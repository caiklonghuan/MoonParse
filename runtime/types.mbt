///|
// ─── §1 基础坐标类型 ──────────────────────────────────────────────────────────

///|
/// 行列坐标（0-based）
/// column 是字节偏移，不是字符数。
pub(all) struct Point {
  row : Int
  column : Int
} derive(Eq, Show)

///|
/// 编辑描述：描述输入的一次原地修改（用于增量解析）
pub(all) struct InputEdit {
  start_byte : Int
  old_end_byte : Int
  new_end_byte : Int
  start_point : Point
  old_end_point : Point
  new_end_point : Point
} derive(Show)

///|
// ─── §2 CST 节点 ──────────────────────────────────────────────────────────────

///|
/// 特殊 SymbolId 常量
pub let sym_end : Int = 0 // EOF

///|
pub let sym_error : Int = -1 // ERROR 节点

///|
pub let sym_error_repeat : Int = -2 // 错误恢复中间节点（内部用）

///|
/// CST 节点（叶节点和内部节点共用同一结构体）
///
/// 叶节点：children 为空，symbol 是 TerminalId
/// 内部节点：children 非空，symbol 是 NonTerminalId
pub(all) struct CstNode {
  // ─── 标识 ────────────────────────────────────────────────────────
  /// TerminalId（叶）或 NonTerminalId（内部节点）
  /// 负值为特殊节点：sym_error / sym_error_repeat
  symbol : Int
  /// true = 命名节点（对应 is_named=true 的规则）；false = 匿名/标点节点
  is_named : Bool

  // ─── 位置 ────────────────────────────────────────────────────────
  start_byte : Int
  end_byte : Int
  start_point : Point
  end_point : Point

  // ─── 叶节点字段（children 为空时有效） ───────────────────────────
  /// 创建该叶节点时的 LR 状态（增量复用判断用，Phase 3a 前置零）
  parse_state : Int
  /// 词法器实际读到的末尾字节偏移（>= end_byte，增量边界检查用，Phase 3a 前置零）
  lookahead_bytes : Int
  /// 该 token 是关键字（两阶段词法用，Phase 3b 前置 false）
  is_keyword : Bool

  // ─── 内部节点字段（children 非空时有效） ─────────────────────────
  children : Array[CstNode]
  /// 与 children 等长，记录每个子节点对应的字段名（来自 BodySymbol.field_name）
  field_names : Array[String?]
  /// 产生式编号（alias 和字段名查表用，Phase 2a 前置零）
  production_id : Int
  /// 各级 Reduce 累积的动态优先级（GLR 歧义消解用，Phase 2c 前置零）
  dynamic_precedence : Int

  // ─── 状态标记 ────────────────────────────────────────────────────
  /// true = extras token（空白/注释），标记后不改变 LR 状态
  extra : Bool
  /// true = 错误恢复插入的虚拟缺失 token（Phase 2b）
  is_missing : Bool
  /// true = ERROR 节点（包含无法解析的内容）（Phase 2b）
  is_error : Bool
  /// true = 在增量编辑区间内，不可复用（Phase 3a）
  has_changes : Bool
  /// true = GLR 多路径合并产物，不可增量复用（Phase 2c）
  fragile_left : Bool
  fragile_right : Bool
} derive(Show)

///|
/// 构造叶节点（内部用）
pub fn CstNode::leaf(
  symbol : Int,
  is_named : Bool,
  start_byte : Int,
  end_byte : Int,
  start_point : Point,
  end_point : Point,
  parse_state : Int,
  lookahead_bytes : Int,
  is_keyword : Bool,
  extra : Bool,
) -> CstNode {
  {
    symbol,
    is_named,
    start_byte,
    end_byte,
    start_point,
    end_point,
    parse_state,
    lookahead_bytes,
    is_keyword,
    children: [],
    field_names: [],
    production_id: 0,
    dynamic_precedence: 0,
    extra,
    is_missing: false,
    is_error: false,
    has_changes: false,
    fragile_left: false,
    fragile_right: false,
  }
}

///|
/// 构造内部节点（内部用）
pub fn CstNode::inner(
  symbol : Int,
  is_named : Bool,
  children : Array[CstNode],
  field_names : Array[String?],
  production_id : Int,
  dynamic_precedence : Int,
  fragile : Bool,
) -> CstNode {
  let start_byte = if children.is_empty() { 0 } else { children[0].start_byte }
  let end_byte = if children.is_empty() {
    0
  } else {
    children[children.length() - 1].end_byte
  }
  let start_point = if children.is_empty() {
    { row: 0, column: 0 }
  } else {
    children[0].start_point
  }
  let end_point = if children.is_empty() {
    { row: 0, column: 0 }
  } else {
    children[children.length() - 1].end_point
  }
  {
    symbol,
    is_named,
    start_byte,
    end_byte,
    start_point,
    end_point,
    parse_state: 0,
    lookahead_bytes: 0,
    is_keyword: false,
    children,
    field_names,
    production_id,
    dynamic_precedence,
    extra: false,
    is_missing: false,
    is_error: false,
    has_changes: false,
    fragile_left: fragile,
    fragile_right: fragile,
  }
}

///|
/// 构造 ERROR 节点（内部用）
pub fn CstNode::error_node(
  children : Array[CstNode],
  start_byte : Int,
  end_byte : Int,
  start_point : Point,
  end_point : Point,
) -> CstNode {
  {
    symbol: sym_error,
    is_named: false,
    start_byte,
    end_byte,
    start_point,
    end_point,
    parse_state: 0,
    lookahead_bytes: 0,
    is_keyword: false,
    children,
    field_names: Array::make(children.length(), None),
    production_id: 0,
    dynamic_precedence: 0,
    extra: false,
    is_missing: false,
    is_error: true,
    has_changes: false,
    fragile_left: false,
    fragile_right: false,
  }
}

///|
// ─── §3 词法内部类型 ──────────────────────────────────────────────────────────

///|
/// 词法阶段的临时类型（不进入最终 CST）
struct Token {
  terminal_id : Int // TerminalId
  start_byte : Int
  end_byte : Int
  lookahead_bytes : Int // 词法器实际读到的末尾（>= end_byte）
  is_keyword : Bool
  is_extra : Bool // true = 属于 extras
} derive(Show)

///|
// ─── §4 解析错误（公开） ──────────────────────────────────────────────────────

///|
/// 公开错误类型：只在 table 损坏等极端情况下返回
/// 对于语法错误，parse() 始终返回带 ERROR 节点的完整 CST
pub(all) struct ParseError {
  position : Int
  point : Point
  message : String
} derive(Show)

///|
// ─── §5 GLR / 错误恢复内部类型 ────────────────────────────────────────────────
// 这些类型 Phase 2a 不用，但先在此声明，让其他文件可前向引用。

///|
/// 栈帧（单 version 线性 LR 用，GLR 时每个 version 独立持有）
struct StackFrame {
  state : Int // StateId
  node : CstNode? // None 仅用于底部哨兵帧
} derive(Show)

///|
/// 错误恢复用的历史状态记录项
struct StackSummaryEntry {
  state : Int // StateId
  position : Int // 字节偏移
  row : Int // 行号
  depth : Int // 距当前栈顶的距离
} derive(Show)

///|
/// 错误代价常量
let error_cost_per_skipped_tree : Int = 100

///|
let error_cost_per_skipped_char : Int = 1

///|
let error_cost_per_skipped_line : Int = 30

///|
let error_cost_per_missing_tree : Int = 110

///|
/// GLR 并行版本的代价描述（condense_stack 用）
struct ErrorStatus {
  cost : Int
  node_count : Int // 自上次错误以来推入的节点数
  dynamic_precedence : Int
  is_in_error : Bool
} derive(Show)

///|
/// GLR 版本上限常量
let max_version_count : Int = 6

///|
let max_version_count_overflow : Int = 4
