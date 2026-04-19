///|
// JSON 语法定义
//
// 覆盖标准 JSON 规范：
//   - 对象 {}，数组 []，字符串，数字，true/false/null
//   - 忽略空白（extras）
//   - 字符串支持转义序列：\" \\ \b \f \n \r \t 以及 \uXXXX

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
  #|rule jstring: /"([^"\\]|\\["\\bfnrt]|\\u[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])*"/
  #|rule number:  /-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?/

///|
// 预编译 ParseTable（模块加载时编译一次，后续复用）

///|
let json_table : @tablegen.ParseTable = compile_builtin_grammar(json_grammar)

///|
pub fn parse_json(
  source : String,
) -> Result[@runtime.CstNode, @runtime.ParseError] {
  @runtime.parse(json_table, source)
}

///|
/// 解析 JSON 并返回 S-expression 树结构字符串，用于结构 snapshot 测试。
pub fn json_sexp(source : String) -> String {
  match @runtime.parse(json_table, source) {
    Ok(root) => cst_to_sexp(root, source, json_table)
    Err(e) => "ERROR: " + e.message
  }
}
