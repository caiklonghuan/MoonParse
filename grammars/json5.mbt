///|
// JSON5 语法定义。
//
// 覆盖最常用的 JSON5 特性：
//   - 单引号 / 双引号字符串
//   - 注释与尾随逗号
//   - 未加引号的对象 key
//   - 十六进制数字、Infinity、NaN

///|
pub let json5_grammar : String =
  #|start json5
  #|extras [/[ \t\n\r]+/, /[ \t]*\/\/[^\n\r]*(\r\n|\n|\r)?/, /\/\*([^*]|\*+[^*/])*\*+\//]
  #|rule json5: value
  #|rule value: object | array | string | number | "true" | "false" | "null" | "Infinity" | "NaN" | "+Infinity" | "-Infinity"
  #|rule object: "{" members? ","? "}"
  #|rule members: member ("," member)*
  #|rule member: property_name ":" value
  #|rule property_name: string | identifier
  #|rule array: "[" elements? ","? "]"
  #|rule elements: value ("," value)*
  #|rule string: dstring | sstring
  #|rule dstring: /"([^"\\]|\\.)*"/
  #|rule sstring: /'([^'\\]|\\.)*'/
  #|rule number: /[-+]?(0[xX][0-9a-fA-F]+|([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?)/
  #|rule identifier: /[$A-Za-z_][$0-9A-Za-z_]*/

///|
let json5_table : @tablegen.ParseTable = compile_builtin_grammar(json5_grammar)

///|
pub fn parse_json5(
  source : String,
) -> Result[@runtime.CstNode, @runtime.ParseError] {
  @runtime.parse(json5_table, source)
}

///|
pub fn json5_sexp(source : String) -> String {
  match @runtime.parse(json5_table, source) {
    Ok(root) => cst_to_sexp(root, source, json5_table)
    Err(_) => "(ERROR)"
  }
}
