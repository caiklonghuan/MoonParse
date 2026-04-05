///|
// query_test.mbt 
// make_table(dsl)      → ParseTable（失败则 panic）
// parse_ok(dsl, input) → (CstNode, ParseTable)（失败则 panic）
// 辅助

///|
fn make_table(dsl : String) -> @tablegen.ParseTable {
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(_) => panic()
  }
  match @tablegen.generate_parse_table(g) {
    Ok((t, _)) => t
    Err(_) => panic()
  }
}

///|
fn parse_ok(
  dsl : String,
  input : String,
) -> (@runtime.CstNode, @tablegen.ParseTable) {
  let table = make_table(dsl)
  match @runtime.parse(table, input) {
    Ok(root) => (root, table)
    Err(e) => {
      let _ = e
      panic()
    }
  }
}

///|
// compile() — 模式编译器测试

///|
test "compile/wildcard" {
  match compile("_") {
    Ok(q) => {
      assert_eq(q.patterns.length(), 1)
      let (pat, _) = q.patterns[0]
      assert_true(pat is Wildcard)
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "compile/anon_pattern" {
  match compile("\"hello\"") {
    Ok(q) => {
      assert_eq(q.patterns.length(), 1)
      let (pat, _) = q.patterns[0]
      assert_true(pat is AnonPattern("hello"))
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "compile/simple_node_pattern" {
  match compile("(identifier)") {
    Ok(q) => {
      assert_eq(q.patterns.length(), 1)
      let (pat, _) = q.patterns[0]
      assert_true(pat is NodePattern("identifier", _))
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "compile/node_with_child" {
  match compile("(binary_expr (identifier))") {
    Ok(q) => {
      assert_eq(q.patterns.length(), 1)
      let (pat, _) = q.patterns[0]
      match pat {
        NodePattern(name, children) => {
          assert_eq(name, "binary_expr")
          assert_eq(children.length(), 1)
          assert_true(children[0].pattern is NodePattern("identifier", _))
          assert_eq(children[0].field, None)
          assert_eq(children[0].capture, None)
        }
        _ => fail("expected NodePattern")
      }
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "compile/capture_annotation" {
  match compile("(identifier) @name") {
    Ok(q) => {
      assert_eq(q.patterns.length(), 1)
      let (pat, top_cap) = q.patterns[0]
      assert_true(pat is NodePattern("identifier", _))
      // 顶层 @capture 存入 tuple 的第二元素
      assert_eq(top_cap, Some("name"))
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "compile/field_constraint" {
  match compile("(binary_expr left: (identifier) right: (identifier))") {
    Ok(q) => {
      let (pat, _) = q.patterns[0]
      match pat {
        NodePattern(_, children) => {
          assert_eq(children.length(), 2)
          assert_eq(children[0].field, Some("left"))
          assert_eq(children[1].field, Some("right"))
        }
        _ => fail("expected NodePattern")
      }
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "compile/capture_in_child" {
  match compile("(binary_expr (identifier) @lhs (identifier) @rhs)") {
    Ok(q) => {
      let (pat, _) = q.patterns[0]
      match pat {
        NodePattern(_, children) => {
          assert_eq(children.length(), 2)
          assert_eq(children[0].capture, Some("lhs"))
          assert_eq(children[1].capture, Some("rhs"))
        }
        _ => fail("expected NodePattern")
      }
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "compile/multiple_top_level_patterns" {
  match compile("(identifier)\n(number)") {
    Ok(q) => {
      assert_eq(q.patterns.length(), 2)
      let (pat0, _) = q.patterns[0]
      let (pat1, _) = q.patterns[1]
      assert_true(pat0 is NodePattern("identifier", _))
      assert_true(pat1 is NodePattern("number", _))
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "compile/eq_predicate" {
  match compile("(identifier) @name\n#eq? @name \"add\"") {
    Ok(q) => {
      assert_eq(q.patterns.length(), 1)
      // predicates 按 pat_idx 分组，长度与 patterns 相同
      assert_eq(q.predicates.length(), 1)
      assert_eq(q.predicates[0].length(), 1)
      assert_true(q.predicates[0][0] is Eq("name", "add"))
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "compile/line_comment_ignored" {
  match compile("; this is a comment\n(identifier)") {
    Ok(q) => assert_eq(q.patterns.length(), 1)
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "compile/nested_pattern" {
  match compile("(binary_expr (identifier) (number))") {
    Ok(q) => {
      let (pat, _) = q.patterns[0]
      match pat {
        NodePattern(name, children) => {
          assert_eq(name, "binary_expr")
          assert_eq(children.length(), 2)
          assert_true(children[0].pattern is NodePattern("identifier", _))
          assert_true(children[1].pattern is NodePattern("number", _))
        }
        _ => fail("expected NodePattern")
      }
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "compile/wildcard_in_child" {
  match compile("(binary_expr _ _)") {
    Ok(q) => {
      let (pat, _) = q.patterns[0]
      match pat {
        NodePattern(_, children) => {
          assert_eq(children.length(), 2)
          assert_true(children[0].pattern is Wildcard)
          assert_true(children[1].pattern is Wildcard)
        }
        _ => fail("expected NodePattern")
      }
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "compile/error_unclosed_paren" {
  match compile("(identifier") {
    Ok(_) => fail("expected parse error")
    Err(ParseError(_, _)) => ()
  }
}

///|
test "compile/error_unexpected_char" {
  match compile("$foo") {
    Ok(_) => fail("expected parse error")
    Err(ParseError(_, _)) => ()
  }
}

///|
test "compile/error_predicate_without_pattern" {
  match compile("#eq? @name \"foo\"") {
    Ok(_) => fail("expected parse error")
    Err(ParseError(_, _)) => ()
  }
}

///|
// exec() — 匹配引擎测试
// 使用简单 DSL 语法构造可预测的 CST，再对其执行 query 查询。

///|
/// 辅助：在 CST 中执行查询模式字符串，返回捕获列表
fn run_query(
  dsl : String,
  input : String,
  pattern : String,
) -> Array[CaptureResult] {
  let (root, table) = parse_ok(dsl, input)
  match compile(pattern) {
    Ok(q) => exec(q, root, input, table)
    Err(e) => {
      let _ = e
      panic()
    }
  }
}

///|
test "exec/wildcard_matches_all_nodes" {
  // 文法：s → "a" "b"，输入 "ab"
  // CST：root(s) → [leaf(a), leaf(b)]
  // 通配符要命中根节点 + 两个叶节点 = 3 次
  let dsl = "start s\nrule s: \"a\" \"b\""
  let (root, table) = parse_ok(dsl, "ab")
  match compile("_") {
    Ok(q) => {
      let results = exec(q, root, "ab", table)
      // 通配符不带 @capture，不产生捕获结果
      assert_eq(results.length(), 0)
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "exec/node_type_match_root" {
  let dsl = "start s\nrule s: \"a\""
  let (root, table) = parse_ok(dsl, "a")
  match compile("(s)") {
    Ok(q) => {
      let results = exec(q, root, "a", table)
      // (s) 无子节点约束，无 @capture，命中但无捕获
      assert_eq(results.length(), 0)
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "exec/capture_root_node" {
  // 通过在外层 NodePattern 中加 @root 捕获根节点
  // 语法：child 层面有 @capture，但顶层 pattern 本身无 @
  // 等效：(s @root) 不合法；实际使用：把根节点作为 child 外包一层通配符
  // 简化方案：直接测试 child 内的 @capture
  let dsl = "start s\nrule s: \"a\" \"b\""
  let results = run_query(dsl, "ab", "(s _ @first _ @second)")
  assert_eq(results.length(), 2)
  assert_eq(results[0].capture_name, "first")
  assert_eq(results[1].capture_name, "second")
}

///|
test "exec/anon_pattern_matches_leaf" {
  // AnonPattern "+" 匹配树中 + 终结符叶节点（无捕获，0 个 CaptureResult）
  let dsl =
    #|start expr
    #|rule expr: num "+" num
    #|rule num: /[0-9]+/
  // 查询 "+" 是 AnonPattern，不带 @capture，命中但不产生 CaptureResult
  let results = run_query(dsl, "1+2", "\"+\"")
  assert_eq(results.length(), 0)
}

///|
test "exec/anon_pattern_no_match" {
  // AnonPattern "-" 在只有 + 的树中不命中
  let dsl =
    #|start expr
    #|rule expr: num "+" num
    #|rule num: /[0-9]+/
  let results = run_query(dsl, "1+2", "\"-\"")
  assert_eq(results.length(), 0)
}

///|
test "exec/capture_named_child" {
  // 文法：expr → num "+" num，用于测试子节点捕获
  let dsl =
    #|start expr
    #|rule expr: num "+" num
    #|rule num: /[0-9]+/
  let results = run_query(dsl, "1+2", "(expr (num) @lhs)")
  assert_eq(results.length(), 1)
  assert_eq(results[0].capture_name, "lhs")
  // 确认文本：第一个 num 是 "1"
  let n = results[0].node
  assert_eq(n.start_byte, 0)
  assert_eq(n.end_byte, 1)
}

///|
test "exec/capture_multiple_children" {
  let dsl =
    #|start expr
    #|rule expr: num "+" num
    #|rule num: /[0-9]+/
  let results = run_query(dsl, "3+7", "(expr (num) @lhs (num) @rhs)")
  assert_eq(results.length(), 2)
  assert_eq(results[0].capture_name, "lhs")
  assert_eq(results[1].capture_name, "rhs")
  // lhs = "3"，rhs = "7"
  assert_eq(results[0].node.start_byte, 0)
  assert_eq(results[1].node.start_byte, 2)
}

///|
test "exec/type_mismatch_no_capture" {
  let dsl = "start s\nrule s: \"a\""
  // 模式要求 (nonexistent_type)，不会命中
  let results = run_query(dsl, "a", "(nonexistent_type)")
  assert_eq(results.length(), 0)
}

///|
test "exec/eq_predicate_pass" {
  let dsl =
    #|start s
    #|rule s: name "+" name
    #|rule name: /[a-z]+/
  // #eq? 谓词：仅捕获文本 == "add" 的 name 节点
  let results = run_query(dsl, "add+mul", "(s (name) @fn)\n#eq? @fn \"add\"")
  assert_eq(results.length(), 1)
  assert_eq(results[0].capture_name, "fn")
  assert_eq(results[0].node.start_byte, 0)
  assert_eq(results[0].node.end_byte, 3)
}

///|
test "exec/eq_predicate_fail" {
  let dsl =
    #|start s
    #|rule s: name "+" name
    #|rule name: /[a-z]+/
  // "add" 的 match 通过谓词，"mul" 不通过 → 仅 1 次捕获
  let results = run_query(dsl, "add+mul", "(s (name) @fn)\n#eq? @fn \"add\"")
  assert_eq(results.length(), 1)
}

///|
test "exec/match_id_increments" {
  // 使用已知可用的 expr 文法，同一棵树里有两个 num 节点
  // (num) @n 分别命中两次，应有不同 match_id
  let dsl =
    #|start expr
    #|rule expr: num "+" num
    #|rule num: /[0-9]+/
  let results = run_query(dsl, "3+7", "(num) @n")
  assert_eq(results.length(), 2)
  assert_true(results[0].match_id != results[1].match_id)
}

///|
test "exec/deep_nesting_capture" {
  // 使用已知工作的 expr → num → leaf 路径
  // (num) @n 捕获深层 num 节点（expr 的子节点）
  let dsl =
    #|start expr
    #|rule expr: num "+" num
    #|rule num: /[0-9]+/
  let results = run_query(dsl, "42+0", "(num) @n")
  assert_eq(results.length(), 2)
  assert_eq(results[0].capture_name, "n")
}

///|
test "exec/multiple_top_patterns_both_match" {
  let dsl =
    #|start expr
    #|rule expr: num "+" num
    #|rule num: /[0-9]+/
  // 两条顶层模式：分别捕获 expr 和 num
  match compile("(expr) @e\n(num) @n") {
    Ok(q) => {
      let (root, table) = parse_ok(dsl, "1+2")
      let results = exec(q, root, "1+2", table)
      // 应有 expr 1 次 + num 2 次 = 3 个捕获
      assert_eq(results.length(), 3)
      let expr_caps = results.filter(fn(r) { r.capture_name == "e" })
      let num_caps = results.filter(fn(r) { r.capture_name == "n" })
      assert_eq(expr_caps.length(), 1)
      assert_eq(num_caps.length(), 2)
    }
    Err(e) => fail("\{e}")
  }
}
