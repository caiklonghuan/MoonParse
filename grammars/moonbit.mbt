///|
// MoonBit 语法定义（覆盖绝大部分常用语法特性）。
//
// 覆盖：
//   - fn / let / const / type / struct / enum / trait / impl / test / suberror
//   - if / match / guard / for / for..in / while / loop / return / raise / try-catch / defer
//   - 管道 |> / 级联 .. / is 表达式 / 箭头函数
//   - 位运算 & | ^ << >> / 范围 .. ..< ..=
//   - 带标签参数 label~ / 可选参数 label?
//   - 记录字面量、struct update { ..e, f: v }、数组、调用、索引、成员访问
//   - or-pattern (|) / as-pattern / rest-pattern (..) / range pattern
//   - 泛型约束 fn[T : Trait] / raise 签名 / nobreak 子句
//   - 基于 newline 的语句分隔

///|
pub let moonbit_grammar : String = builtin_moonbit_pack.grammar_source

///|
let moonbit_table : @tablegen.ParseTable = builtin_moonbit_bundle.table

///|
pub fn parse_moonbit(
  source : String,
) -> Result[@runtime.CstNode, @runtime.ParseError] {
  @runtime.parse(moonbit_table, source)
}

///|
pub fn moonbit_sexp(source : String) -> String {
  match @runtime.parse(moonbit_table, source) {
    Ok(root) => cst_to_sexp(root, source, moonbit_table)
    Err(_) => "(ERROR)"
  }
}
