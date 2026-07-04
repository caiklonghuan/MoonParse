///|
fn enriched_reports(dsl : String) -> (ParseTable, Array[ConflictReport]) {
  match @grammar.parse_grammar(dsl) {
    @grammar.Error(_) => panic()
    @grammar.Success(grammar) =>
      match generate_parse_table(grammar) {
        Err(_) => panic()
        Ok(result) => result
      }
  }
}

///|
test "conflict diagnostics retain LR items and deterministic state paths" {
  let (_, first) = enriched_reports("start e\nrule e: e \"+\" e | \"n\"")
  let (_, second) = enriched_reports("start e\nrule e: e \"+\" e | \"n\"")
  assert_true(first.length() > 0)
  assert_eq(first.length(), second.length())
  for index in 0..<first.length() {
    let report = first[index]
    assert_true(report.items.length() > 0)
    for item_index in 1..<report.items.length() {
      let previous = report.items[item_index - 1]
      let current = report.items[item_index]
      assert_true(
        previous.prod < current.prod ||
        (previous.prod == current.prod && previous.dot <= current.dot),
      )
    }
    if report.state == 0 {
      assert_eq(report.state_path.length(), 0)
    } else {
      assert_true(report.state_path.length() > 0)
      assert_eq(report.state_path[0].from_state, 0)
      assert_eq(
        report.state_path[report.state_path.length() - 1].to_state,
        report.state,
      )
      for step_index in 1..<report.state_path.length() {
        assert_eq(
          report.state_path[step_index - 1].to_state,
          report.state_path[step_index].from_state,
        )
      }
    }
    assert_true(report.state_path == second[index].state_path)
  }
}

///|
test "conflict diagnostics retain resolved and runtime branches" {
  let (_, warns) = enriched_reports(
    "start e\nrule e: prec.left(1, e \"+\" e) | \"n\"",
  )
  assert_true(
    warns.any(fn(report) {
      match report.severity {
        Warn(_) => report.resolved_actions.length() < report.actions.length()
        _ => false
      }
    }),
  )
  let (_, dynamic) = enriched_reports(
    "start e\nrule e: prec.dynamic(1, e \"+\" e) | \"n\"",
  )
  assert_true(
    dynamic.any(fn(report) {
      match report.severity {
        DynamicConflict(_) => report.resolved_actions == report.actions
        _ => false
      }
    }),
  )
  let (_, declared) = enriched_reports(
    "start s\nconflicts [[a, b]]\nrule s: a \"e\" | b \"e\"\nrule a: \"d\"\nrule b: \"d\"",
  )
  assert_true(
    declared.any(fn(report) {
      match report.severity {
        Declared(_) => report.resolved_actions == report.actions
        _ => false
      }
    }),
  )
}
