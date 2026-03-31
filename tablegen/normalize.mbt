///|
// ─── 规范化内部状态 ────────────────────────────────────────────────────────────

priv struct NormCtx {
  mut term_next   : Int
  mut nt_next     : Int
  mut prod_next   : Int
  mut helper_next : Int
  /// "lit:s" / "re:re" / "·" → TerminalId
  terminals        : Map[String, TerminalId]
  /// TerminalId → 词法定义
  term_patterns    : Map[TerminalId, TerminalDef]
  /// 规则名 → NonTerminalId
  nonterminals     : Map[String, NonTerminalId]
  /// 与 nonterminals 同步增长，下标即 NonTerminalId
  nt_metas         : Array[SymbolMeta]
  productions      : Array[Production]
}

///|
fn NormCtx::new() -> NormCtx {
  {
    term_next    : 0,
    nt_next      : 0,
    prod_next    : 0,
    helper_next  : 0,
    terminals    : Map::new(),
    term_patterns: Map::new(),
    nonterminals : Map::new(),
    nt_metas     : [],
    productions  : [],
  }
}

// ─── 分配辅助函数 ─────────────────────────────────────────────────────────────

///|
/// 注册终结符；key 已存在则返回现有 ID（幂等）
fn alloc_terminal(
  ctx : NormCtx,
  key : String,
  def : TerminalDef
) -> TerminalId {
  match ctx.terminals.get(key) {
    Some(id) => id
    None => {
      let id = ctx.term_next
      ctx.term_next = ctx.term_next + 1
      ctx.terminals.set(key, id)
      ctx.term_patterns.set(id, def)
      id
    }
  }
}

///|
/// 注册非终结符；name 已存在则返回现有 ID（幂等）
fn alloc_nt(
  ctx      : NormCtx,
  name     : String,
  is_named : Bool
) -> NonTerminalId {
  match ctx.nonterminals.get(name) {
    Some(id) => id
    None => {
      let id = ctx.nt_next
      ctx.nt_next = ctx.nt_next + 1
      ctx.nonterminals.set(name, id)
      ctx.nt_metas.push({ name: name, is_named: is_named })
      id
    }
  }
}

///|
/// 将一条产生式追加到 ctx
fn add_production(
  ctx       : NormCtx,
  head      : NonTerminalId,
  body      : Array[BodySymbol],
  prec      : Int?,
  assoc     : @grammar.PrecKind?,
  rule_name : String
) -> Unit {
  let id = ctx.prod_next
  ctx.prod_next = ctx.prod_next + 1
  ctx.productions.push({
    id        : id,
    head      : head,
    body      : body,
    prec      : prec,
    assoc     : assoc,
    rule_name : rule_name,
  })
}

///|
/// 分配辅助非终结符（is_named = false），命名带规则来源和类型后缀
fn fresh_helper(
  ctx       : NormCtx,
  rule_name : String,
  suffix    : String
) -> NonTerminalId {
  let n = ctx.helper_next
  ctx.helper_next = ctx.helper_next + 1
  let name = "_\{rule_name}_\{suffix}_\{n}"
  alloc_nt(ctx, name, false)
}

///|
/// 用于生成辅助 NT 名称的后缀
fn pattern_suffix(p : @grammar.Pattern) -> String {
  match p {
    Seq(_)               => "seq"
    Choice(_)            => "choice"
    Repeat(_)            => "rep"
    Plus(_)              => "plus"
    Optional(_)          => "opt"
    RepeatRange(_, n, m) => "r\{n}to\{m}"
    _                    => "aux"
  }
}

// ─── 核心展开函数（三函数互递归） ───────────────────────────────────────────────

///|
/// 将 Pattern 转为单个 BodySymbol。
/// - 原子（Literal/Regex/AnyChar/RuleRef）：直接映射为终结符或非终结符。
/// - 包装（Tagged/Field/Prec/Not/And）：透传并传递元数据。
/// - 复杂（Seq/Choice/Repeat/Plus/Optional/RepeatRange）：创建辅助 NT 并展开。
fn to_symbol(
  ctx        : NormCtx,
  p          : @grammar.Pattern,
  rule_name  : String,
  field_name : String?,
  prec       : Int?,
  assoc      : @grammar.PrecKind?
) -> BodySymbol {
  match p {
    Literal(s) => {
      let id = alloc_terminal(ctx, "lit:\{s}", TerminalDef::Literal(s))
      { symbol: Symbol::Terminal(id), field_name: field_name }
    }
    Regex(re) => {
      let id = alloc_terminal(ctx, "re:\{re}", TerminalDef::Regex(re))
      { symbol: Symbol::Terminal(id), field_name: field_name }
    }
    AnyChar => {
      let id = alloc_terminal(ctx, "\u00b7", TerminalDef::AnyChar)
      { symbol: Symbol::Terminal(id), field_name: field_name }
    }
    RuleRef(name) =>
      // 前向引用在预注册阶段已处理，此处保底自动注册
      match ctx.nonterminals.get(name) {
        Some(id) => { symbol: Symbol::NonTerminal(id), field_name: field_name }
        None => {
          let id = alloc_nt(ctx, name, false)
          { symbol: Symbol::NonTerminal(id), field_name: field_name }
        }
      }
    // 包装类：传递元数据，递归处理内层
    Tagged(tag, inner) =>
      to_symbol(ctx, inner, rule_name, Some(tag), prec, assoc)
    Field(fname, inner) =>
      to_symbol(ctx, inner, rule_name, Some(fname), prec, assoc)
    Prec(level, kind, inner) =>
      to_symbol(ctx, inner, rule_name, field_name, Some(level), Some(kind))
    Not(inner) =>
      // Phase 1：忽略负向前瞻，直接透传
      to_symbol(ctx, inner, rule_name, field_name, prec, assoc)
    And(inner) =>
      // Phase 1：忽略正向前瞻，直接透传
      to_symbol(ctx, inner, rule_name, field_name, prec, assoc)
    _ => {
      // 复杂 Pattern：创建辅助 NT，展开后返回对它的引用
      let fresh_id = fresh_helper(ctx, rule_name, pattern_suffix(p))
      expand_into(ctx, fresh_id, p, rule_name, prec, assoc)
      { symbol: Symbol::NonTerminal(fresh_id), field_name: field_name }
    }
  }
}

///|
/// 将 Pattern 展平为 BodySymbol 序列。
/// Seq 被内联展开（多个符号），其余委托给 to_symbol（单符号）。
fn to_body(
  ctx        : NormCtx,
  p          : @grammar.Pattern,
  rule_name  : String,
  field_name : String?,
  prec       : Int?,
  assoc      : @grammar.PrecKind?
) -> Array[BodySymbol] {
  match p {
    Seq(elems) => {
      let result : Array[BodySymbol] = []
      for elem in elems {
        for sym in to_body(ctx, elem, rule_name, None, prec, assoc) {
          result.push(sym)
        }
      }
      result
    }
    _ => [to_symbol(ctx, p, rule_name, field_name, prec, assoc)]
  }
}

///|
/// 将 Pattern 的全部产生式展开并挂到 head 非终结符。
fn expand_into(
  ctx       : NormCtx,
  head      : NonTerminalId,
  p         : @grammar.Pattern,
  rule_name : String,
  prec      : Int?,
  assoc     : @grammar.PrecKind?
) -> Unit {
  match p {
    Choice(alts) =>
      // 每个分支各自展开成 head 的一条产生式
      for alt in alts {
        expand_into(ctx, head, alt, rule_name, prec, assoc)
      }

    Prec(level, kind, inner) =>
      // 向内传递优先级，更新 prec/assoc
      expand_into(ctx, head, inner, rule_name, Some(level), Some(kind))

    Tagged(tag, inner) => {
      let sym = to_symbol(ctx, inner, rule_name, Some(tag), None, None)
      add_production(ctx, head, [sym], prec, assoc, rule_name)
    }

    Field(fname, inner) => {
      let sym = to_symbol(ctx, inner, rule_name, Some(fname), None, None)
      add_production(ctx, head, [sym], prec, assoc, rule_name)
    }

    Repeat(inner) => {
      let sym = to_symbol(ctx, inner, rule_name, None, None, None)
      // head → ε
      add_production(ctx, head, [], None, None, rule_name)
      // head → head inner  (左递归，GLR 天然处理)
      add_production(
        ctx, head,
        [{ symbol: Symbol::NonTerminal(head), field_name: None }, sym],
        None, None, rule_name,
      )
    }

    Plus(inner) => {
      let sym = to_symbol(ctx, inner, rule_name, None, None, None)
      // head → inner
      add_production(ctx, head, [sym], None, None, rule_name)
      // head → head inner  (左递归)
      add_production(
        ctx, head,
        [{ symbol: Symbol::NonTerminal(head), field_name: None }, sym],
        None, None, rule_name,
      )
    }

    Optional(inner) => {
      let sym = to_symbol(ctx, inner, rule_name, None, None, None)
      // head → ε
      add_production(ctx, head, [], None, None, rule_name)
      // head → inner
      add_production(ctx, head, [sym], None, None, rule_name)
    }

    RepeatRange(inner, n, m) => {
      let sym = to_symbol(ctx, inner, rule_name, None, None, None)
      // 所有可选槽位共享一个辅助 NT：opt_id → ε | inner
      let opt_id = fresh_helper(ctx, rule_name, "opt")
      expand_into(
        ctx, opt_id, @grammar.Pattern::Optional(inner), rule_name, None, None,
      )
      let body : Array[BodySymbol] = []
      for _ in 0..<n {
        body.push(sym)
      }
      for _ in n..<m {
        body.push({ symbol: Symbol::NonTerminal(opt_id), field_name: None })
      }
      add_production(ctx, head, body, prec, assoc, rule_name)
    }

    Not(inner) =>
      // Phase 1：忽略负向前瞻
      expand_into(ctx, head, inner, rule_name, prec, assoc)

    And(inner) =>
      // Phase 1：忽略正向前瞻
      expand_into(ctx, head, inner, rule_name, prec, assoc)

    _ =>
      // Seq / Literal / Regex / AnyChar / RuleRef
      add_production(
        ctx, head,
        to_body(ctx, p, rule_name, None, prec, assoc),
        prec, assoc, rule_name,
      )
  }
}

// ─── 公开入口 ─────────────────────────────────────────────────────────────────

///|
/// 将用户 Grammar 规范化为 LALR/GLR 算法所需的增广 CFG。
///
/// 步骤：
/// 1. 预注册所有规则名为非终结符，保证 RuleRef 可前向查找
/// 2. 确定起始符（grammar.start 优先，否则取规则表中首条）
/// 3. 生成增广产生式 $accept → start $
/// 4. 展开每条规则的 Pattern 为若干产生式
pub fn augment_grammar(grammar : @grammar.Grammar) -> AugmentedGrammar {
  let ctx = NormCtx::new()

  // 1. 预注册所有非终结符
  for name, rule in grammar.rules {
    let _ = alloc_nt(ctx, name, rule.is_named)
  }

  // 2. 确定起始符名称
  let start_name : String = match grammar.start {
    Some(n) => n
    None => {
      // 取规则表首条（Map 按插入顺序迭代）
      let mut found = ""
      for name, _ in grammar.rules {
        if found == "" {
          found = name
        }
      }
      found
    }
  }

  let start_nt_id = match ctx.nonterminals.get(start_name) {
    Some(id) => id
    None => 0 // 空文法兜底；实际使用前应先经过 validate_grammar
  }

  // 3. 创建增广起始符及产生式 $accept → start $
  let accept_id = alloc_nt(ctx, "$accept", false)
  add_production(
    ctx,
    accept_id,
    [
      { symbol: Symbol::NonTerminal(start_nt_id), field_name: None },
      { symbol: Symbol::EndOfInput, field_name: None },
    ],
    None,
    None,
    "$accept",
  )

  // 4. 展开每条用户规则
  for name, rule in grammar.rules {
    let nt_id = match ctx.nonterminals.get(name) {
      Some(id) => id
      None => 0
    }
    expand_into(ctx, nt_id, rule.pattern, name, None, None)
  }

  // 5. 返回增广文法
  // 注：grammar/ 层目前未建模 extras（空白、注释），Phase 1 留空
  {
    start             : accept_id,
    terminals         : ctx.terminals,
    nonterminals      : ctx.nonterminals,
    productions       : ctx.productions,
    terminal_patterns : ctx.term_patterns,
    extras            : [],
  }
}
