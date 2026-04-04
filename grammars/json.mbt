///|
// JSON 语法定义
//
// 覆盖标准 JSON（RFC 8259）的完整子集：
//   - 对象 {}，数组 []，字符串，数字，true/false/null
//   - 忽略空白（extras）
// 限制：字符串转义序列简化为 /\"[^\"]*\"/（不处理 \uXXXX 转义）

///|
/// JSON Grammar DSL 字符串
pub let json_grammar : String =
  #|start json
  #|extras [/[ \t\n\r]+/]
  #|rule json: value
  #|rule value: object | array | jstring | number | "true" | "false" | "null"
  #|rule object: "{" pairs? "}"
  #|rule pairs:  pair ("," pair)*
  #|rule pair:   jstring ":" value
  #|rule array:    "[" elements? "]"
  #|rule elements: value ("," value)*
  #|rule jstring: /"[ -!#-~]*"/
  #|rule number:  /-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?/

///|
// 预编译 ParseTable（模块加载时编译一次，后续复用）

///|
fn make_json_table() -> @tablegen.ParseTable {
  let g = match @grammar.parse_grammar(json_grammar) {
    Success(g) => g
    Error(_) => panic()
  }
  match @tablegen.generate_parse_table(g) {
    Ok((t, _)) => t
    Err(_) => panic()
  }
}

///|
let json_table : @tablegen.ParseTable = make_json_table()

///|
// 公开解析接口

///|
/// 用内置 JSON 语法解析 source，返回 CST 根节点。
///
/// 解析结果始终为 Ok（语法错误以 ERROR 节点形式嵌入 CST）。
pub fn parse_json(source : String) -> Result[@runtime.CstNode, @runtime.ParseError] {
  @runtime.parse(json_table, source)
}
