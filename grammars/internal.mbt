///|
// 内置 grammar 模块共享的辅助函数。

///|
fn compile_builtin_grammar(grammar_dsl : String) -> @tablegen.ParseTable {
  let grammar = match @grammar.parse_grammar(grammar_dsl) {
    Success(g) => g
    Error(_) => panic()
  }
  match @tablegen.generate_parse_table(grammar) {
    Ok((table, _)) => table
    Err(_) => panic()
  }
}
