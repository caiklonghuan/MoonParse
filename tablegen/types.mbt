// 用于区分语义

///|
/// LALR 解析器状态编号（LR 自动机的状态，与 DfaStateId 是不同的 ID 空间）
pub type StateId = Int

///|
/// 终结符编号（含扫描器 token）
pub type TerminalId = Int

///|
/// 非终结符编号
pub type NonTerminalId = Int

///|
/// 产生式编号
pub type ProductionId = Int

///|
/// 词法器 DFA 状态编号
pub type DfaStateId = Int

// 增广文法

///|
/// 扁平化 CFG 中的符号
pub(all) enum Symbol {
  Terminal(TerminalId)
  NonTerminal(NonTerminalId)
  EndOfInput
} derive(Eq, Hash, Debug)

///|
pub impl Show for Symbol with output(self, logger) {
  match self {
    Terminal(id) => logger.write_string("Terminal(\{id})")
    NonTerminal(id) => logger.write_string("NonTerminal(\{id})")
    EndOfInput => logger.write_string("EndOfInput")
  }
}

///|
/// 产生式体中携带字段元数据的符号包装
/// field_name 来自 Pattern::Field("name", p) 或 Pattern::Tagged("tag", p)
pub(all) struct BodySymbol {
  symbol : Symbol
  field_name : String?
} derive(Debug)

///|
/// Reduce 时的前瞻约束（由 Not(p) / And(p) 零宽断言产生）
pub(all) enum LookaheadConstraint {
  /// 负向前瞻 !p：当前 lookahead 不得属于此集合
  NotFollowedBy(Array[TerminalId])
  /// 正向前瞻 &p ：当前 lookahead 必须属于此集合
  FollowedBy(Array[TerminalId])
} derive(Debug)

///|
/// 扁平化产生式：A → β
pub(all) struct Production {
  id : ProductionId
  head : NonTerminalId
  body : Array[BodySymbol]
  /// 继承自 Pattern::Prec 或顶层 precedences 声明
  prec : Int?
  /// 结合性（Left / Right / Nonassoc / Dynamic）
  assoc : @grammar.PrecKind?
  /// 来源规则名，调试 / 错误信息用
  rule_name : String
  /// Reduce 前瞻约束（由 Not/And 断言提取；None = 无约束）
  lookahead : LookaheadConstraint?
  /// 别名（来自 Pattern::Alias；None = 无别名，使用规则名）
  mut alias_name : String?
} derive(Debug)

///|
/// 终结符的词法定义
pub(all) enum TerminalDef {
  Literal(String)
  Regex(String)
  AnyChar
  /// 由外部词法器（external scanner）处理的 token，不进入 DFA
  External(String)
} derive(Eq, Debug)

///|
pub impl Show for TerminalDef with output(self, logger) {
  match self {
    Literal(s) => logger.write_string("Literal(\{s})")
    Regex(s) => logger.write_string("Regex(\{s})")
    AnyChar => logger.write_string("AnyChar")
    External(s) => logger.write_string("External(\{s})")
  }
}

///|
/// Grammar 规范化后的增广文法（S' → Start $）
pub(all) struct AugmentedGrammar {
  /// 增广起始符 S' 的编号
  start : NonTerminalId
  /// 终结符文本 → 编号
  terminals : Map[String, TerminalId]
  /// 非终结符名称 → 编号
  nonterminals : Map[String, NonTerminalId]
  /// 按 ProductionId 排列的全部产生式
  productions : Array[Production]
  /// TerminalId → 词法定义（Literal / Regex / AnyChar）
  terminal_patterns : Map[TerminalId, TerminalDef]
  /// Extras token（空白、注释等），可出现在任意 LR 状态
  extras : Array[TerminalId]
  /// 终结符优先级表，从顶层 precedence 声明提取（TerminalId → (level, kind)）
  prec_table : Map[TerminalId, (Int, @grammar.PrecKind)]
  /// 非终结符元数据，下标即 NonTerminalId（从 normalize 的 NormCtx.nt_metas 填入）
  nt_metas : Array[SymbolMeta]
  /// 外部词法器 token 的 TerminalId 列表（对应 DSL externals 声明）
  external_ids : Array[TerminalId]
  /// word 关键字规则对应的 TerminalId（若文法声明了 `word`，否则为 None）
  /// 该 token 是所有字面量关键字的"通用标识符"模式；字面量在 DFA 中优先级更高
  word_token : TerminalId?
  /// 显式声明的 GLR 冲突规则组（来自 DSL conflicts 声明）
  /// 若某冲突涉及的规则名均属同一组，则按已知歧义处理（Declared 级别），不产生 Ambiguous 报告
  declared_conflicts : Array[Array[String]]
}

///|
// LR(0) 项目

///|
/// LR(0) 项目 [A → α • β]；dot = • 的位置，范围 0..=body.len
pub(all) struct LRItem {
  prod : ProductionId
  dot : Int
} derive(Eq, Hash, Debug, Compare)

///|
// 解析动作与解析表

///|
/// LR 解析动作
pub(all) enum Action {
  /// 移进到目标状态
  Shift(StateId)
  /// 用产生式 prod 规约
  Reduce(ProductionId)
  /// 接受（仅用于增广起始产生式的规约）
  Accept
} derive(Eq, Debug)

///|
pub impl Show for Action with output(self, logger) {
  match self {
    Shift(state) => logger.write_string("Shift(\{state})")
    Reduce(prod) => logger.write_string("Reduce(\{prod})")
    Accept => logger.write_string("Accept")
  }
}

///|
/// 非终结符的 AST 节点元数据（对应 grammar.Rule.is_named）
pub(all) struct SymbolMeta {
  name : String
  /// false = 匿名节点，运行时 AST 不暴露给用户
  is_named : Bool
  /// true = normalize 阶段生成的辅助非终结符（_rulename_suffix_n / _ra_xxx 等），
  /// 不对应用户声明的规则，应被上层代码生成或分析工具跳过。
  is_synthetic : Bool
  /// 该非终结符的产生式中出现的字段名列表（有序、去重）。
  /// 来自 Pattern::Field / Pattern::Tagged；Token 和无字段规则为空。
  /// 供运行时按名定位子节点，也供其他上层工具读取字段布局。
  field_slots : Array[String]
} derive(Debug)

///|
// 词法器 DFA

///|
/// 词法器 DFA 的单个状态（ID 空间：DfaStateId，与 LR 的 StateId 无关）
pub(all) struct DfaState {
  id : DfaStateId
  transitions : Map[Char, DfaStateId]
  /// 若为接受态，记录优先级最高的 terminal
  /// 优先级：Literal > Regex > 声明顺序靠前
  accept : TerminalId?
} derive(Debug)

///|
/// 上下文敏感词法器 DFA
pub(all) struct LexerDfa {
  /// 词法 DFA 的全部状态（按 DfaStateId 索引）
  states : Array[DfaState]
  /// 词法 DFA 的起始状态（DfaStateId）
  start : DfaStateId
  /// LR 状态 → 当前合法 token 列表
  /// valid_tokens[s] = { t | action[(s,t)] ≠ ∅ } ∪ extras_set
  valid_tokens : Map[StateId, Array[TerminalId]]
}

///|
/// LALR(1) 解析表（含 GLR 冲突保留）
pub(all) struct ParseTable {
  /// 状态总数
  states : Int
  /// action[(state, terminal)]：多个动作 = GLR 冲突
  action : Map[(StateId, TerminalId), Array[Action]]
  /// goto[(state, nt)] → 目标状态
  goto_table : Map[(StateId, NonTerminalId), StateId]
  /// 解析表中的完整产生式列表
  productions : Array[Production]
  /// 词法器 DFA（随解析表一并生成）
  lexer_dfa : LexerDfa
  /// 非终结符元数据，下标即 NonTerminalId
  symbol_metadata : Array[SymbolMeta]
  /// 终结符词法定义（TerminalId → 词法规则），供 serialize 输出和 lexer 构建
  terminal_patterns : Map[TerminalId, TerminalDef]
  /// 终结符名称反查表（TerminalId → 显示名称），runtime 错误信息用
  /// 例：expected `+` or `)` 需要靠此表把 TerminalId 还原为可读字符串
  terminal_names : Map[TerminalId, String]
  /// Extras token 列表（空白、注释等），runtime 识别后直接跳过不推 LR 栈
  /// 与 LexerDfa.valid_tokens 里的 extras union 对应，语义层的权威来源
  extras : Array[TerminalId]
  /// 外部词法器 token 的 TerminalId 列表（来自 externals 声明），runtime 调用外部扫描器用
  external_token_ids : Array[TerminalId]
  /// word 关键字规则对应的 TerminalId（若文法声明了 `word`，否则为 None）
  /// 仅当 best_tid == word_token 时，lexer 才尝试 keyword 提升。
  word_token : TerminalId?
  /// 全文法 Literal 终结符的字符串 → TerminalId 映射（O(1) 关键字查表）
  /// 由 generate_parse_table 从 terminal_patterns 中提取所有 Literal 条目构建。
  keyword_map : Map[String, TerminalId]
}

///|
// 冲突

///|
/// 冲突严重级别
pub(all) enum ConflictSeverity {
  /// 有 prec/assoc 可在编译期消解（Shift-Reduce 或 Reduce-Reduce 均可由优先级解决）。
  /// 携带描述字符串，说明采用了哪条规则（如 "left-assoc shift preference"）。
  /// 仍会输出告警，但不阻止生成。
  Warn(String)
  /// 无优先级信息可消解：GLR 并行保留全部冲突路径。
  /// 携带描述字符串，说明具体冲突（如 "shift/reduce on '+'"）。
  /// 除非使用 --force，否则阻止生成。
  Ambiguous(String)
  /// prec.dynamic 标记的冲突：编译期无法消解，在 runtime 根据 dynamic_precedence
  /// 字段比较两棵子树的动态优先级来选择路径。携带 dynamic prec id（来自 grammar DSL）。
  DynamicConflict(Int)
  /// 该冲突由 DSL 的 conflicts 声明显式标注；runtime 通过 GLR 并行处理。
  /// 与 Ambiguous 不同，Declared 是预期歧义，不阻止解析表生成。
  Declared(String)
} derive(Debug)

///|
/// 单条冲突报告（由 tablegen 在构建 LALR 表时生成，每个 (state, terminal) 冲突点一条）
pub(all) struct ConflictReport {
  /// 发生冲突的 LR 解析器状态编号（StateId）。
  /// 可结合 --diagnostic 输出的 GOTO 表定位到具体项目集。
  state : StateId
  /// 触发冲突的前瞻终结符编号（TerminalId）。
  /// 可通过 ParseTable.terminal_names 还原为可读字符串。
  terminal : TerminalId
  /// 该 (state, terminal) 对应的全部冲突 Action（至少 2 条）。
  /// 例如 [Shift(s), Reduce(p)] 表示经典 Shift-Reduce 冲突；
  /// [Reduce(p1), Reduce(p2)] 表示 Reduce-Reduce 冲突。
  actions : Array[Action]
  /// 冲突的严重程度与消解策略，见 ConflictSeverity。
  severity : ConflictSeverity
} derive(Debug)
