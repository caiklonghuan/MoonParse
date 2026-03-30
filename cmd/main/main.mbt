///|
/// Entry point for the CLI or runnable program in this template.
/// Keep main focused; move logic into the library package.
/// Run with `moon run cmd/main` from the project root.
fn main {
  let test_dsl =
    #|start expr
    #|precedence left plus
    #|rule expr: expr "+" term | term
    #|rule term: /\d+/ | "(" expr ")"
    #|rule plus: "+"
  match @grammar.parse_grammar(test_dsl) {
    Success(grammar) => {
      println(
        "── 校验 ──────────────────────────────",
      )
      let errors = @grammar.validate_grammar(grammar)
      if errors.length() == 0 {
        println("校验通过，无错误。")
      } else {
        println("发现 \{errors.length()} 个问题：")
        for e in errors {
          println("  - \{e.to_string()}")
        }
      }
      println("")
      println(
        "── DSL 序列化 ────────────────────────",
      )
      println(@grammar.grammar_to_string(grammar))
      println("")
      println(
        "── JSON 序列化 ───────────────────────",
      )
      println(@grammar.grammar_to_json(grammar))
    }
    Error(err) =>
      println(
        "解析失败: \{err.message} at line \{err.location.line}, col \{err.location.column}",
      )
  }
}
