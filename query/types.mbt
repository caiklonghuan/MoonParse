///|
// Query 类型定义
// QueryPattern  — 从 S-表达式字符串编译得到的模式 AST
// CompiledQuery — 一个查询文件编译的结果（多条顶层模式 + 谓词）
// CaptureResult — 执行查询后返回的命中项

///|
/// 查询模式 AST
///
/// 对应 S-表达式语法：
pub(all) enum QueryPattern {
  /// 命名节点类型匹配，children 为有序子节点约束列表
  /// e.g. `(function_definition name: (identifier) @fn)`
  NodePattern(String, Array[PatternChild])
  /// 匿名字面量匹配（与终结符原文比较）
  /// e.g. `"+"` `"return"`
  AnonPattern(String)
  /// 通配符：匹配任意单节点，不约束类型
  /// e.g. `_`
  Wildcard
} derive(Show)

///|
/// 子节点位置的包装：携带可选字段约束和捕获标注
///
/// 对应语法成分：`field: pattern @capture`
/// - `field`   = Some("name") 时要求该子节点来自父节点 field_names 中的对应字段
/// - `capture` = Some("func.name") 时命中后记录捕获
pub(all) struct PatternChild {
  /// 字段约束（`name:` 前缀），无字段时为 None
  field : String?
  /// 子模式
  pattern : QueryPattern
  /// 捕获标注（`@capture_name`），不捕获时为 None
  capture : String?
} derive(Show)

///|
/// 谓词（对捕获结果的后置过滤条件）
///
/// v1 仅支持 `#eq?`，后续可扩展 `#match?` 正则谓词等。
pub(all) enum Predicate {
  /// `#eq? @capture_name "expected_text"`
  /// 要求命名捕获的节点文本等于给定字面量
  Eq(String, String)
} derive(Show)

///|
/// 完整编译后的查询结果
///
/// 一个查询字符串可包含多条并列的顶层模式，每条独立匹配、独立编号 match_id。
pub(all) struct CompiledQuery {
  /// 顶层模式列表（顺序对应模式在字符串中的出现顺序）
  patterns : Array[QueryPattern]
  /// 谓词列表：`(pattern_index, predicate)`
  /// pattern_index 指向 `patterns` 中对应的顶层模式
  predicates : Array[(Int, Predicate)]
  /// 顶层模式自身的捕获标注：`(node_pattern) @capture_name`
  /// top_captures[i] 对应 patterns[i] 的顶层 @capture，无则为 None
  top_captures : Array[String?]
} derive(Show)

///|
/// 查询执行后的一次捕获命中
pub(all) struct CaptureResult {
  /// 顶层模式命中的序号（从 0 开始，同一次完整匹配的所有捕获共享同一 match_id）
  match_id : Int
  /// 捕获名称（`@func.name` 去掉 `@` 前缀后的字符串）
  capture_name : String
  /// 命中的 CST 节点（只读引用，来自原始语法树）
  node : @runtime.CstNode
} derive(Show)

///|
/// 查询编译 / 执行的错误
pub(all) enum QueryError {
  /// 模式字符串语法错误（偏移 + 描述）
  ParseError(Int, String)
  /// 执行时内部错误（理论上不应发生）
  ExecError(String)
} derive(Show)

///|
// 内部辅助：从 CstNode + ParseTable 取节点类型名称字符串
// （与 wasm/cst_json.mbt 中的 node_type_name 逻辑一致，但 query 包不依赖 wasm）

///|
/// 返回节点的类型名称：ERROR 节点 → "ERROR"；叶节点查 terminal_names；内部节点查 symbol_metadata
pub fn node_type_name(
  node : @runtime.CstNode,
  table : @tablegen.ParseTable,
) -> String {
  if node.is_error {
    return "ERROR"
  }
  if node.symbol == @runtime.sym_error ||
    node.symbol == @runtime.sym_error_repeat {
    return "ERROR"
  }
  if node.children.is_empty() {
    if node.symbol == @runtime.sym_end {
      return "EOF"
    }
    match table.terminal_names.get(node.symbol) {
      Some(name) => name
      None => "<terminal:\{node.symbol}>"
    }
  } else {
    let meta = table.symbol_metadata
    if node.symbol >= 0 && node.symbol < meta.length() {
      meta[node.symbol].name
    } else {
      "<nonterminal:\{node.symbol}>"
    }
  }
}

///|
/// 从原始输入字符串中切取节点对应的文本
pub fn node_text(node : @runtime.CstNode, input : String) -> String {
  if node.start_byte <= node.end_byte && node.end_byte <= input.length() {
    input[node.start_byte:node.end_byte].to_string()
  } else {
    ""
  }
}
