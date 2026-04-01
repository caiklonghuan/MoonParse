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
/// 词法器 DFA 状态编号（词法 DFA 的内部状态，与 StateId 是不同的 ID 空间）
/// ⚠️ 注意：LexerDfa.valid_tokens 的 key 是 StateId（LR 状态），不是 DfaStateId
pub type DfaStateId = Int

// ─── §1 增广文法 ──────────────────────────────────────────────────────────────

///|
/// 扁平化 CFG 中的符号
pub(all) enum Symbol {
  Terminal(TerminalId)
  NonTerminal(NonTerminalId)
  EndOfInput
} derive(Eq, Hash, Show)

///|
/// 产生式体中携带字段元数据的符号包装
/// field_name 来自 Pattern::Field("name", p) 或 Pattern::Tagged("tag", p)
pub(all) struct BodySymbol {
  symbol : Symbol
  field_name : String?
} derive(Show)

///|
/// Reduce 时的前瞻约束（由 Not(p) / And(p) 零宽断言产生）
pub(all) enum LookaheadConstraint {
  /// 负向前瞻 !p：当前 lookahead 不得属于此集合
  NotFollowedBy(Array[TerminalId])
  /// 正向前瞻 &p ：当前 lookahead 必须属于此集合
  FollowedBy(Array[TerminalId])
} derive(Show)

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
} derive(Show)

///|
/// 终结符的词法定义
pub(all) enum TerminalDef {
  Literal(String)
  Regex(String)
  AnyChar
} derive(Eq, Show)

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
}

///|
// ─── §3 LR(0) 项目 ───────────────────────────────────────────────────────────

///|
/// LR(0) 项目 [A → α • β]；dot = • 的位置，范围 0..=body.len
pub(all) struct LRItem {
  prod : ProductionId
  dot : Int
} derive(Eq, Hash, Show, Compare)

///|
// ─── §4 解析动作与解析表 ──────────────────────────────────────────────────────

///|
/// LR 解析动作
pub(all) enum Action {
  /// 移进到目标状态
  Shift(StateId)
  /// 用产生式 prod 规约
  Reduce(ProductionId)
  /// 接受（仅用于增广起始产生式的规约）
  Accept
} derive(Eq, Show)

///|
/// 非终结符的 AST 节点元数据（对应 grammar.Rule.is_named）
pub(all) struct SymbolMeta {
  name : String
  /// false = 匿名节点，运行时 AST 不暴露给用户
  is_named : Bool
} derive(Show)

///|
// ─── §6 词法器 DFA ────────────────────────────────────────────────────────────

///|
/// 词法器 DFA 的单个状态（ID 空间：DfaStateId，与 LR 的 StateId 无关）
pub(all) struct DfaState {
  id : DfaStateId
  transitions : Map[Char, DfaStateId]
  /// 若为接受态，记录优先级最高的 terminal
  /// 优先级：Literal > Regex > 声明顺序靠前
  accept : TerminalId?
} derive(Show)

///|
/// 上下文敏感词法器 DFA
///
/// ID 空间说明：
///   · states / start / DfaState.id  — 词法 DFA 内部状态，类型为 DfaStateId
///   · valid_tokens 的 key            — LR 解析器状态，类型为 StateId
/// 两个 ID 空间在底层都是 Int，但语义完全不同，不可混用。
pub(all) struct LexerDfa {
  /// 词法 DFA 的全部状态（按 DfaStateId 索引）
  states : Array[DfaState]
  /// 词法 DFA 的起始状态（DfaStateId）
  start : DfaStateId
  /// LR 状态 → 当前合法 token 列表（key 是 StateId，不是 DfaStateId）
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
}

///|
// ─── §5 冲突 ─────────────────────────────────────────────────────────────────

///|
/// 冲突严重级别
pub(all) enum ConflictSeverity {
  /// 有 prec/assoc 可编译期消解（仅告警）
  Warn(String)
  /// 无优先级，GLR 并行保留全部路径
  Ambiguous(String)
  /// prec.dynamic：编译期无法消解，携带 dynamic prec id 待 runtime/ 比较
  DynamicConflict(Int)
} derive(Show)

///|
/// 单条冲突报告
pub(all) struct ConflictReport {
  state : StateId
  terminal : TerminalId
  actions : Array[Action]
  severity : ConflictSeverity
} derive(Show)
