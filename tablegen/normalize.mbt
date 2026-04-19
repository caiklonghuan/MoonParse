///|
// 规范化内部状态

priv struct NormCtx {
  mut term_next : Int
  mut nt_next : Int
  mut prod_next : Int
  mut helper_next : Int
  /// "lit:s" / "re:re" / "·" → TerminalId
  terminals : Map[String, TerminalId]
  /// TerminalId → 词法定义
  term_patterns : Map[TerminalId, TerminalDef]
  /// 规则名 → NonTerminalId
  nonterminals : Map[String, NonTerminalId]
  /// 与 nonterminals 同步增长，下标即 NonTerminalId
  nt_metas : Array[SymbolMeta]
  productions : Array[Production]
  /// 模板规则 name → Rule（用于 RuleApp 展开）
  template_rules : Map[String, @grammar.Rule]
  /// RuleApp 实例化缓存：canonical_key → NonTerminalId（防止无限递归）
  rule_app_cache : Map[String, NonTerminalId]
  /// @inline 规则的展开模式（name → Pattern），用于在引用处创建 per-callsite 新 NT
  inline_patterns : Map[String, @grammar.Pattern]
}

///|
fn NormCtx::new() -> NormCtx {
  {
    term_next: 0,
    nt_next: 0,
    prod_next: 0,
    helper_next: 0,
    terminals: Map::new(),
    term_patterns: Map::new(),
    nonterminals: Map::new(),
    nt_metas: [],
    productions: [],
    template_rules: Map::new(),
    rule_app_cache: Map::new(),
    inline_patterns: Map::new(),
  }
}

// 分配辅助函数

///|
/// 注册终结符；key 已存在则返回现有 ID（幂等）
fn alloc_terminal(ctx : NormCtx, key : String, def : TerminalDef) -> TerminalId {
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
fn alloc_nt(ctx : NormCtx, name : String, is_named : Bool) -> NonTerminalId {
  match ctx.nonterminals.get(name) {
    Some(id) => id
    None => {
      let id = ctx.nt_next
      ctx.nt_next = ctx.nt_next + 1
      ctx.nonterminals.set(name, id)
      ctx.nt_metas.push({ name, is_named, is_synthetic: false, field_slots: [] })
      id
    }
  }
}

///|
/// 注册 normalize 阶段生成的辅助非终结符（is_synthetic = true）
fn alloc_nt_synthetic(ctx : NormCtx, name : String) -> NonTerminalId {
  match ctx.nonterminals.get(name) {
    Some(id) => id
    None => {
      let id = ctx.nt_next
      ctx.nt_next = ctx.nt_next + 1
      ctx.nonterminals.set(name, id)
      ctx.nt_metas.push({
        name,
        is_named: false,
        is_synthetic: true,
        field_slots: [],
      })
      id
    }
  }
}

///|
/// 将一条产生式追加到 ctx
fn add_production(
  ctx : NormCtx,
  head : NonTerminalId,
  body : Array[BodySymbol],
  prec : Int?,
  assoc : @grammar.PrecKind?,
  rule_name : String,
) -> Unit {
  let id = ctx.prod_next
  ctx.prod_next = ctx.prod_next + 1
  ctx.productions.push({
    id,
    head,
    body,
    prec,
    assoc,
    rule_name,
    lookahead: None,
    alias_name: None,
  })
}

///|
/// 带前瞻约束的产生式添加（用于 Not / And 断言提取后调用）
fn add_production_with_lookahead(
  ctx : NormCtx,
  head : NonTerminalId,
  body : Array[BodySymbol],
  prec : Int?,
  assoc : @grammar.PrecKind?,
  rule_name : String,
  lookahead : LookaheadConstraint,
) -> Unit {
  let id = ctx.prod_next
  ctx.prod_next = ctx.prod_next + 1
  ctx.productions.push({
    id,
    head,
    body,
    prec,
    assoc,
    rule_name,
    lookahead: Some(lookahead),
    alias_name: None,
  })
}

///|
/// 分配辅助非终结符（is_named = false，is_synthetic = true），命名带规则来源和类型后缀
fn fresh_helper(
  ctx : NormCtx,
  rule_name : String,
  suffix : String,
) -> NonTerminalId {
  let n = ctx.helper_next
  ctx.helper_next = ctx.helper_next + 1
  let name = "_\{rule_name}_\{suffix}_\{n}"
  alloc_nt_synthetic(ctx, name)
}

///|
/// 用于生成辅助 NT 名称的后缀
fn pattern_suffix(p : @grammar.Pattern) -> String {
  match p {
    Seq(_) => "seq"
    Choice(_) => "choice"
    Repeat(_) => "rep"
    Plus(_) => "plus"
    Optional(_) => "opt"
    RepeatRange(_, n, m) => "r\{n}to\{m}"
    Alias(_, _) => "alias"
    _ => "aux"
  }
}

///|
/// 计算 RuleApp 实例化的规范 key（用于缓存查找）
fn ruleapp_cache_key(
  tmpl_name : String,
  args : Array[@grammar.Pattern],
) -> String {
  let arg_strs = args.map(fn(a) { @grammar.pattern_to_string(a) })
  tmpl_name + "[" + arg_strs.join(",") + "]"
}

///|
/// 将模板 Pattern 中的参数名替换为实际 Pattern（类型替换）
fn substitute_pattern(
  params : Array[String],
  args : Array[@grammar.Pattern],
  p : @grammar.Pattern,
) -> @grammar.Pattern {
  match p {
    RuleRef(name) => {
      // 若 name 是模板参数，替换为对应实参
      for i in 0..<params.length() {
        if params[i] == name {
          return args[i]
        }
      }
      RuleRef(name)
    }
    RuleApp(tmpl, as2) =>
      RuleApp(tmpl, as2.map(fn(a) { substitute_pattern(params, args, a) }))
    Choice(ps) => Choice(ps.map(fn(q) { substitute_pattern(params, args, q) }))
    Seq(ps) => Seq(ps.map(fn(q) { substitute_pattern(params, args, q) }))
    Repeat(q) => Repeat(substitute_pattern(params, args, q))
    Plus(q) => Plus(substitute_pattern(params, args, q))
    Optional(q) => Optional(substitute_pattern(params, args, q))
    Tagged(tag, q) => Tagged(tag, substitute_pattern(params, args, q))
    Field(f, q) => Field(f, substitute_pattern(params, args, q))
    Not(q) => Not(substitute_pattern(params, args, q))
    And(q) => And(substitute_pattern(params, args, q))
    RepeatRange(q, n, m) =>
      RepeatRange(substitute_pattern(params, args, q), n, m)
    Prec(n, k, q) => Prec(n, k, substitute_pattern(params, args, q))
    Alias(a, q) => Alias(a, substitute_pattern(params, args, q))
    Literal(_) | Regex(_) | AnyChar => p
  }
}

// 核心展开函数（三函数互递归）

///|
/// 将 Pattern 转为单个 BodySymbol。
/// - 原子（Literal/Regex/AnyChar/RuleRef）：直接映射为终结符或非终结符。
/// - 包装（Tagged/Field/Prec/Not/And）：透传并传递元数据。
/// - 复杂（Seq/Choice/Repeat/Plus/Optional/RepeatRange）：创建辅助 NT 并展开。
fn to_symbol(
  ctx : NormCtx,
  p : @grammar.Pattern,
  rule_name : String,
  field_name : String?,
  prec : Int?,
  assoc : @grammar.PrecKind?,
) -> BodySymbol {
  match p {
    Literal(s) => {
      let id = alloc_terminal(ctx, "lit:\{s}", TerminalDef::Literal(s))
      { symbol: Symbol::Terminal(id), field_name }
    }
    Regex(re) => {
      let id = alloc_terminal(ctx, "re:\{re}", TerminalDef::Regex(re))
      { symbol: Symbol::Terminal(id), field_name }
    }
    AnyChar => {
      let id = alloc_terminal(ctx, "\u00b7", TerminalDef::AnyChar)
      { symbol: Symbol::Terminal(id), field_name }
    }
    RuleRef(name) =>
      // 先检查是否为 @inline 规则（展开到引用处，创建 per-callsite 新 NT）
      match ctx.inline_patterns.get(name) {
        Some(inline_pat) => {
          let fresh_id = fresh_helper(ctx, name, "inl")
          expand_into(ctx, fresh_id, inline_pat, name, prec, assoc)
          { symbol: Symbol::NonTerminal(fresh_id), field_name }
        }
        None =>
          // 先检查是否为外部词法器 token（externals 声明的名称）
          match ctx.terminals.get("ext:\{name}") {
            Some(ext_id) => { symbol: Symbol::Terminal(ext_id), field_name }
            None =>
              // 前向引用在预注册阶段已处理，此处保底自动注册
              match ctx.nonterminals.get(name) {
                Some(id) => { symbol: Symbol::NonTerminal(id), field_name }
                None => {
                  let id = alloc_nt(ctx, name, false)
                  { symbol: Symbol::NonTerminal(id), field_name }
                }
              }
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
    Alias(alias_name, inner) => {
      // 创建新 NT，展开内层 pattern，并对所有直接产生式标记 alias_name
      let fresh_id = fresh_helper(ctx, rule_name, "alias")
      let start_prod_id = ctx.prod_next
      expand_into(ctx, fresh_id, inner, rule_name, prec, assoc)
      let mut i = start_prod_id
      while i < ctx.productions.length() {
        if ctx.productions[i].head == fresh_id {
          ctx.productions[i].alias_name = Some(alias_name)
        }
        i = i + 1
      }
      { symbol: Symbol::NonTerminal(fresh_id), field_name }
    }
    RuleApp(tmpl_name, args) => {
      // 模板规则实例化：查缓存，未命中则展开后缓存
      let key = ruleapp_cache_key(tmpl_name, args)
      let nt_id = match ctx.rule_app_cache.get(key) {
        Some(id) => id
        None =>
          match ctx.template_rules.get(tmpl_name) {
            None => {
              // 验证器已报告，此处仅分配空 NT 作兜底
              let id = alloc_nt_synthetic(ctx, "_ra_\{tmpl_name}_err")
              ctx.rule_app_cache.set(key, id)
              id
            }
            Some(tmpl) => {
              let expanded = substitute_pattern(tmpl.params, args, tmpl.pattern)
              let n = ctx.rule_app_cache.length()
              let concrete_name = "_ra_\{tmpl_name}_\{n}"
              let id = alloc_nt_synthetic(ctx, concrete_name)
              // 先缓存再展开，防止模板递归引用自身时无限循环
              ctx.rule_app_cache.set(key, id)
              expand_into(ctx, id, expanded, rule_name, prec, assoc)
              id
            }
          }
      }
      { symbol: Symbol::NonTerminal(nt_id), field_name }
    }
    _ => {
      // 复杂 Pattern：创建辅助 NT，展开后返回对它的引用
      let fresh_id = fresh_helper(ctx, rule_name, pattern_suffix(p))
      expand_into(ctx, fresh_id, p, rule_name, prec, assoc)
      { symbol: Symbol::NonTerminal(fresh_id), field_name }
    }
  }
}

///|
/// 将 Pattern 展平为 BodySymbol 序列。
/// Seq 被内联展开（多个符号），其余委托给 to_symbol（单符号）。
/// Not / And 均为零宽断言，不向 body 贡献符号（约束由 expand_into 的 Seq 分支提取）。
fn to_body(
  ctx : NormCtx,
  p : @grammar.Pattern,
  rule_name : String,
  field_name : String?,
  prec : Int?,
  assoc : @grammar.PrecKind?,
) -> Array[BodySymbol] {
  match p {
    Seq(elems) => {
      let result : Array[BodySymbol] = []
      for elem in elems {
        match elem {
          Not(_) => () // 零宽断言，不贡献符号
          And(_) => () // 零宽断言，不贡献符号
          _ =>
            for sym in to_body(ctx, elem, rule_name, None, prec, assoc) {
              result.push(sym)
            }
        }
      }
      result
    }
    Not(_) => [] // 零宽断言
    And(_) => [] // 零宽断言
    _ => [to_symbol(ctx, p, rule_name, field_name, prec, assoc)]
  }
}

///|
/// 从原子 pattern 提取约束终结符集合（用于 Not/And 前瞻约束）。
/// 仅处理 Literal / Regex / AnyChar / Choice；复杂 pattern 返回空数组。
fn collect_constraint_tids(
  ctx : NormCtx,
  p : @grammar.Pattern,
) -> Array[TerminalId] {
  match p {
    Literal(s) => [alloc_terminal(ctx, "lit:\{s}", TerminalDef::Literal(s))]
    Regex(re) => [alloc_terminal(ctx, "re:\{re}", TerminalDef::Regex(re))]
    AnyChar => [alloc_terminal(ctx, "\u00b7", TerminalDef::AnyChar)]
    Choice(alts) => {
      let result : Array[TerminalId] = []
      for alt in alts {
        for tid in collect_constraint_tids(ctx, alt) {
          result.push(tid)
        }
      }
      result
    }
    _ => []
  }
}

///|
/// 将 Pattern 的全部产生式展开并挂到 head 非终结符。
fn expand_into(
  ctx : NormCtx,
  head : NonTerminalId,
  p : @grammar.Pattern,
  rule_name : String,
  prec : Int?,
  assoc : @grammar.PrecKind?,
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
      add_production(ctx, head, [], prec, assoc, rule_name)
      // head → head inner  (左递归，GLR 天然处理)
      add_production(
        ctx,
        head,
        [{ symbol: Symbol::NonTerminal(head), field_name: None }, sym],
        prec,
        assoc,
        rule_name,
      )
    }
    Plus(inner) => {
      let sym = to_symbol(ctx, inner, rule_name, None, None, None)
      // head → inner
      add_production(ctx, head, [sym], prec, assoc, rule_name)
      // head → head inner  (左递归)
      add_production(
        ctx,
        head,
        [{ symbol: Symbol::NonTerminal(head), field_name: None }, sym],
        prec,
        assoc,
        rule_name,
      )
    }
    Optional(inner) => {
      let sym = to_symbol(ctx, inner, rule_name, None, None, None)
      // head → ε
      add_production(ctx, head, [], prec, assoc, rule_name)
      // head → inner
      add_production(ctx, head, [sym], prec, assoc, rule_name)
    }
    RepeatRange(inner, n, m) => {
      let sym = to_symbol(ctx, inner, rule_name, None, None, None)
      // 所有可选槽位共享一个辅助 NT：opt_id → ε | inner
      let opt_id = fresh_helper(ctx, rule_name, "opt")
      expand_into(
        ctx,
        opt_id,
        @grammar.Pattern::Optional(inner),
        rule_name,
        None,
        None,
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
    Not(q) => {
      // 负向前瞻（零宽断言）：head → ε [!q]
      let tids = collect_constraint_tids(ctx, q)
      if tids.length() > 0 {
        add_production_with_lookahead(
          ctx,
          head,
          [],
          prec,
          assoc,
          rule_name,
          NotFollowedBy(tids),
        )
      } else {
        // 复杂 pattern：回退到透传（Phase 1 行为）
        expand_into(ctx, head, q, rule_name, prec, assoc)
      }
    }
    And(q) => {
      // 正向前瞻（零宽断言）：head → ε [&q]
      let tids = collect_constraint_tids(ctx, q)
      if tids.length() > 0 {
        add_production_with_lookahead(
          ctx,
          head,
          [],
          prec,
          assoc,
          rule_name,
          FollowedBy(tids),
        )
      } else {
        // 复杂 pattern：回退到透传（Phase 1 行为）
        expand_into(ctx, head, q, rule_name, prec, assoc)
      }
    }
    Alias(alias_name, inner) => {
      // 展开内层 pattern 到 head，并对所有直接产生式标记 alias_name
      let start_prod_id = ctx.prod_next
      expand_into(ctx, head, inner, rule_name, prec, assoc)
      let mut i = start_prod_id
      while i < ctx.productions.length() {
        if ctx.productions[i].head == head {
          ctx.productions[i].alias_name = Some(alias_name)
        }
        i = i + 1
      }
    }
    Seq(elems) => {
      // 向后扫描，收集尾部连续的 Not/And 零宽断言，提取为前瞻约束。
      // 多个同类断言合并（tids 取并集）；And/Not 混存时 FollowedBy 优先（取最内层类型）。
      let mut body_count = elems.length()
      let not_tids : Array[TerminalId] = []
      let and_tids : Array[TerminalId] = []
      let mut scanning = true
      while scanning && body_count > 0 {
        match elems[body_count - 1] {
          Not(q) => {
            let tids = collect_constraint_tids(ctx, q)
            if tids.length() > 0 {
              body_count = body_count - 1
              for t in tids {
                not_tids.push(t)
              }
            } else {
              scanning = false
            }
          }
          And(q) => {
            let tids = collect_constraint_tids(ctx, q)
            if tids.length() > 0 {
              body_count = body_count - 1
              for t in tids {
                and_tids.push(t)
              }
            } else {
              scanning = false
            }
          }
          _ => scanning = false
        }
      }
      // 构造约束：FollowedBy 优先于 NotFollowedBy（LookaheadConstraint 只能携带一种）
      let constraint : LookaheadConstraint? = if and_tids.length() > 0 {
        Some(FollowedBy(and_tids))
      } else if not_tids.length() > 0 {
        Some(NotFollowedBy(not_tids))
      } else {
        None
      }
      let body : Array[BodySymbol] = []
      for i in 0..<body_count {
        for sym in to_body(ctx, elems[i], rule_name, None, prec, assoc) {
          body.push(sym)
        }
      }
      match constraint {
        None => add_production(ctx, head, body, prec, assoc, rule_name)
        Some(c) =>
          add_production_with_lookahead(
            ctx, head, body, prec, assoc, rule_name, c,
          )
      }
    }
    _ =>
      // Literal / Regex / AnyChar / RuleRef
      add_production(
        ctx,
        head,
        to_body(ctx, p, rule_name, None, prec, assoc),
        prec,
        assoc,
        rule_name,
      )
  }
}

// 公开入口

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

  // 收集 @inline 规则的展开模式（引用处展开，不创建命名 NT）
  for name, rule in grammar.rules {
    if rule.attributes.contains(@grammar.RuleAttribute::Inline) {
      ctx.inline_patterns.set(name, rule.pattern)
    }
  }

  // 收集模板规则（params 非空），供 RuleApp 展开使用
  for name, rule in grammar.rules {
    if !rule.params.is_empty() {
      ctx.template_rules.set(name, rule)
    }
  }

  // 预注册所有非终结符（@inline 规则跳过，由引用处按需展开）
  for name, rule in grammar.rules {
    if ctx.inline_patterns.contains(name) {
      continue // @inline 规则不分配命名 NT
    }
    // @hide 规则强制 is_named = false（无论名称是否以 _ 开头）
    let hide_forced = rule.attributes.contains(@grammar.RuleAttribute::Hide)
    let effective_is_named = rule.is_named && !hide_forced
    let _ = alloc_nt(ctx, name, effective_is_named)
  }

  // 确定起始符名称
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

  // 创建增广起始符及产生式 $accept → start $
  let accept_id = alloc_nt_synthetic(ctx, "$accept")
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

  // 预注册外部词法器 token（必须在展开规则前，使 RuleRef 能正确映射为 Terminal）
  let external_ids : Array[TerminalId] = []
  for name in grammar.externals {
    let tid = alloc_terminal(ctx, "ext:\{name}", TerminalDef::External(name))
    external_ids.push(tid)
  }

  // 展开每条用户规则（@inline 规则不展开，由引用处生成 per-callsite NT）
  for name, rule in grammar.rules {
    if ctx.inline_patterns.contains(name) {
      continue
    }
    let nt_id = match ctx.nonterminals.get(name) {
      Some(id) => id
      None => 0
    }
    expand_into(ctx, nt_id, rule.pattern, name, None, None)
  }

  // 从 grammar.precedences 构建 prec_table，并补标产生式的 prec/assoc
  let prec_table : Map[TerminalId, (Int, @grammar.PrecKind)] = Map::new()
  let nt_prec_map : Map[NonTerminalId, (Int, @grammar.PrecKind)] = Map::new()
  for pd in grammar.precedences {
    for rule_name in pd.rules {
      match ctx.nonterminals.get(rule_name) {
        Some(nt_id) => nt_prec_map.set(nt_id, (pd.level, pd.kind))
        None => ()
      }
    }
  }
  // 对含 prec-declared NT 的产生式补标 prec/assoc（取最右出现）
  let n_prods = ctx.productions.length()
  let mut pi = 0
  while pi < n_prods {
    let prod = ctx.productions[pi]
    match prod.prec {
      None => {
        let mut rv : Int? = None
        let mut rk : @grammar.PrecKind? = None
        let mut j = prod.body.length() - 1
        while j >= 0 {
          match prod.body[j].symbol {
            NonTerminal(nt) =>
              match nt_prec_map.get(nt) {
                Some((lv, lk)) => {
                  rv = Some(lv)
                  rk = Some(lk)
                  break
                }
                None => ()
              }
            _ => ()
          }
          j = j - 1
        }
        match rv {
          Some(_) =>
            ctx.productions[pi] = {
              id: prod.id,
              head: prod.head,
              body: prod.body,
              prec: rv,
              assoc: rk,
              rule_name: prod.rule_name,
              lookahead: prod.lookahead,
              alias_name: prod.alias_name,
            }
          None => ()
        }
      }
      Some(_) => ()
    }
    pi = pi + 1
  }
  // 从简单 token 产生式构建 prec_table（nt → [Terminal(t)]，nt ∈ nt_prec_map）
  for prod in ctx.productions {
    match nt_prec_map.get(prod.head) {
      Some((lv, lk)) =>
        if prod.body.length() == 1 {
          match prod.body[0].symbol {
            Terminal(t) => prec_table.set(t, (lv, lk))
            _ => ()
          }
        }
      None => ()
    }
  }

  // 处理 extras：将每个 extras Pattern 注册为 terminal，收集 TerminalId
  let extras : Array[TerminalId] = []
  for pat in grammar.extras {
    let tid = match pat {
      Literal(s) => alloc_terminal(ctx, "lit:\{s}", TerminalDef::Literal(s))
      Regex(re) => alloc_terminal(ctx, "re:\{re}", TerminalDef::Regex(re))
      AnyChar => alloc_terminal(ctx, "·", TerminalDef::AnyChar)
      _ => continue // 复杂 pattern 作 extras 不支持，忽略
    }
    extras.push(tid)
  }

  // 处理 word：找到 word 规则对应的 TerminalId（通过产生式 body 间接查找）
  let word_token : TerminalId? = match grammar.word {
    None => None
    Some(word_name) =>
      match ctx.nonterminals.get(word_name) {
        None => None
        Some(nt_id) => {
          // word 规则是 token rule，其产生式 body 只含一个 Terminal
          let mut found : TerminalId? = None
          for prod in ctx.productions {
            if prod.head == nt_id && prod.body.length() == 1 {
              match prod.body[0].symbol {
                Terminal(tid) => {
                  found = Some(tid)
                  break
                }
                _ => ()
              }
            }
          }
          found
        }
      }
  }

  // 后处理：扫描产生式，为每个非终结符收集字段名（来自 Field / Tagged），
  // 然后重建 nt_metas，使 field_slots 填充就位，供 runtime 和其他上层工具读取。
  let nt_field_names : Array[Array[String]] = []
  for _ in 0..<ctx.nt_metas.length() {
    nt_field_names.push([])
  }
  for prod in ctx.productions {
    let head_id = prod.head
    if head_id < nt_field_names.length() {
      for sym in prod.body {
        match sym.field_name {
          None => ()
          Some(fname) =>
            if !nt_field_names[head_id].contains(fname) {
              nt_field_names[head_id].push(fname)
            }
        }
      }
    }
  }
  let final_metas : Array[SymbolMeta] = []
  for i in 0..<ctx.nt_metas.length() {
    let old = ctx.nt_metas[i]
    final_metas.push({
      name: old.name,
      is_named: old.is_named,
      is_synthetic: old.is_synthetic,
      field_slots: nt_field_names[i],
    })
  }

  // 返回增广文法
  {
    start: accept_id,
    terminals: ctx.terminals,
    nonterminals: ctx.nonterminals,
    productions: ctx.productions,
    terminal_patterns: ctx.term_patterns,
    extras,
    prec_table,
    nt_metas: final_metas,
    external_ids,
    word_token,
    declared_conflicts: grammar.conflicts,
  }
}
