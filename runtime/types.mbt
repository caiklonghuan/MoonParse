///|
// 基础坐标类型

///|
/// 行列坐标（0-based）
/// column 是 Unicode 代码点偏移（codepoint offset），不是 UTF-8 字节偏移。
pub(all) struct Point {
  row : Int
  column : Int
} derive(Eq, Show)

///|
/// 将 UTF-8 字节偏移列号转换为 Unicode 代码点列号（LSP UTF-8 位置编码集成用）。
///
/// LSP 客户端在"utf-8 position encoding"模式下传入的 `character` 是该行的
/// UTF-8 字节偏移，而 MoonParse 内部 `Point.column` 存储的是代码点偏移。
/// 本函数完成从"外部字节偏移"到"内部代码点偏移"的转换。
///
/// 参数：
///   `source`    — 完整的 UTF-8 输入字符串（MoonBit String，按代码点索引）
///   `line`      — 目标行（0-based，以 '\n' 为分隔符）
///   `col_bytes` — 该行内的 UTF-8 字节偏移
///
/// 返回值：UTF-8 字节偏移 `col_bytes` 对应的代码点数（0-based）。
/// 若 `line` 超出范围或 `col_bytes` 超出行长度，安全退化为返回 `col_bytes`。
pub fn byte_offset_to_char_col(
  source : String,
  line : Int,
  col_bytes : Int,
) -> Int {
  if col_bytes <= 0 {
    return 0
  }
  let n = source.length()
  // 步骤 1：定位目标行的起始代码点下标
  let mut line_start = 0
  let mut cur_line = 0
  while cur_line < line && line_start < n {
    if source[line_start].to_int().to_char().unwrap() == '\n' {
      cur_line = cur_line + 1
    }
    line_start = line_start + 1
  }
  if cur_line < line {
    return col_bytes // 行超出范围，退化
  }
  // 步骤 2：自行首逐代码点累加 UTF-8 字节数，直至消耗满 col_bytes
  let mut char_count = 0
  let mut byte_acc = 0
  let mut i = line_start
  while i < n && byte_acc < col_bytes {
    let c = source[i].to_int().to_char().unwrap()
    if c == '\n' {
      break // 不越过行边界
    }
    let cp = c.to_int()
    let bytes = if cp < 0x80 {
      1
    } else if cp < 0x800 {
      2
    } else if cp < 0x10000 {
      3
    } else {
      4
    }
    byte_acc = byte_acc + bytes
    if byte_acc <= col_bytes {
      char_count = char_count + 1
    }
    i = i + 1
  }
  char_count
}

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
// CST 节点

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
  // 标识
  /// TerminalId（叶）或 NonTerminalId（内部节点）
  /// 负值为特殊节点：sym_error / sym_error_repeat
  symbol : Int
  /// true = 命名节点（对应 is_named=true 的规则）；false = 匿名/标点节点
  is_named : Bool

  // 位置
  start_byte : Int
  end_byte : Int
  start_point : Point
  end_point : Point

  // 叶节点字段（children 为空时有效）
  /// 创建该叶节点时的 LR 状态（增量复用判断用，暂置零）
  parse_state : Int
  /// 词法器实际读到的末尾字节偏移（>= end_byte，增量边界检查用，暂置零）
  lookahead_bytes : Int
  /// 该 token 是关键字（两阶段词法用，暂置 false）
  is_keyword : Bool

  // 内部节点字段（children 非空时有效）
  children : Array[CstNode]
  /// 与 children 等长，记录每个子节点对应的字段名（来自 BodySymbol.field_name）
  field_names : Array[String?]
  /// 产生式编号（alias 和字段名查表用，暂置零）
  production_id : Int
  /// 各级 Reduce 累积的动态优先级（GLR 歧义消解用，暂置零）
  dynamic_precedence : Int

  // 状态标记
  /// true = extras token（空白/注释），标记后不改变 LR 状态
  extra : Bool
  /// true = 错误恢复插入的虚拟缺失 token
  is_missing : Bool
  /// true = ERROR 节点（包含无法解析的内容）
  is_error : Bool
  /// true = 在增量编辑区间内，不可复用
  has_changes : Bool
  /// true = GLR 多路径合并产物，不可增量复用
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
  fragile_left : Bool,
  fragile_right : Bool,
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
    fragile_left,
    fragile_right,
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
/// 构造缺失叶节点（内部用）
///
/// 错误恢复策略 2（insert_missing）使用：在解析器期望某个 token 但未找到时，
/// 插入一个虚拟的零宽节点，使解析可以继续推进。
/// · start_byte == end_byte（零宽，不消费任何输入）
/// · is_missing = true，is_named 与真实 token 保持一致
pub fn CstNode::missing_leaf(
  symbol : Int,
  is_named : Bool,
  byte_pos : Int,
  point : Point,
) -> CstNode {
  {
    symbol,
    is_named,
    start_byte: byte_pos,
    end_byte: byte_pos,
    start_point: point,
    end_point: point,
    parse_state: 0,
    lookahead_bytes: byte_pos,
    is_keyword: false,
    children: [],
    field_names: [],
    production_id: 0,
    dynamic_precedence: 0,
    extra: false,
    is_missing: true,
    is_error: false,
    has_changes: false,
    fragile_left: false,
    fragile_right: false,
  }
}

///|
// 词法内部类型

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
// 解析错误（公开）

///|
/// 公开错误类型：只在 table 损坏等极端情况下返回
/// 对于语法错误，parse() 始终返回带 ERROR 节点的完整 CST
pub(all) struct ParseError {
  position : Int
  point : Point
  message : String
} derive(Show)

///|
// GLR / 错误恢复内部类型

///|
/// 栈帧（单 version 线性 LR 用，GLR 时每个 version 独立持有）
struct StackFrame {
  state : Int // StateId
  node : CstNode? // None 仅用于底部哨兵帧
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
/// 每次进入恢复模式本身的固定惩罚（叠加到 per-token 代价之上）
/// 防止解析器频繁触发恢复导致不稳定
let error_cost_per_recovery : Int = 500

///|
/// GLR 并行版本的代价描述（condense_stack 用）
///
/// 代价存在版本级 ErrorStatus 而不是 CstNode 上，原因：
///   condense_stack 比较的是每条 GssRef（版本）的累积代价，
///   与子树结构无关，GlrEngine 维护 Map[GssRef, ErrorStatus] 即可。
///   tree-sitter 把 error_cost 放在 SubtreeHeapData 是为了后解析阶段
///   O(1) 查询子树代价，MoonParse 目前无此 API 需求，故 CstNode 不加该字段。
///   增量复用所需的"是否含错误"判断由 is_error / fragile_left / fragile_right 覆盖。
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
