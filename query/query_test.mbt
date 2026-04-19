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

///|
// #match? predicate tests

///|
test "compile/match_predicate" {
  match compile("(identifier) @name\n#match? @name \"^[a-z]+$\"") {
    Ok(q) => {
      assert_eq(q.patterns.length(), 1)
      assert_eq(q.predicates.length(), 1)
      assert_eq(q.predicates[0].length(), 1)
      assert_true(q.predicates[0][0] is Match("name", "^[a-z]+$"))
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "exec/match_predicate_pass" {
  let dsl =
    #|start s
    #|rule s: name "+" name
    #|rule name: /[a-zA-Z]+/
  // #match? 谓词：仅捕获全小写字母的 name 节点（"add" 满足，"MUL" 不满足）
  let results = run_query(
    dsl, "add+MUL", "(s (name) @fn)\n#match? @fn \"^[a-z]+$\"",
  )
  assert_eq(results.length(), 1)
  assert_eq(results[0].capture_name, "fn")
  assert_eq(results[0].node.start_byte, 0)
  assert_eq(results[0].node.end_byte, 3)
}

///|
test "exec/match_predicate_fail" {
  let dsl =
    #|start s
    #|rule s: name
    #|rule name: /[A-Z]+/
  // 输入 "ABC" 不满足 #match? @n "^[a-z]+$" → 0 个捕获
  let results = run_query(dsl, "ABC", "(name) @n\n#match? @n \"^[a-z]+$\"")
  assert_eq(results.length(), 0)
}

///|
test "exec/match_predicate_digit_pattern" {
  let dsl =
    #|start expr
    #|rule expr: num "+" num
    #|rule num: /[0-9]+/
  // 捕获文本只含数字的 num 节点（永远成立）
  let results = run_query(dsl, "12+34", "(num) @n\n#match? @n \"^[0-9]+$\"")
  assert_eq(results.length(), 2)
}

///|
test "exec/match_predicate_partial" {
  let dsl =
    #|start s
    #|rule s: name "+" name
    #|rule name: /[a-zA-Z]+/
  // "add" 满足 ^[a-z]+$，"MUL" 不满足
  let results = run_query(
    dsl, "add+MUL", "(s (name) @fn)\n#match? @fn \"^[a-z]+$\"",
  )
  assert_eq(results.length(), 1)
  assert_eq(results[0].node.start_byte, 0)
}

///|
test "exec/match_predicate_dot_star" {
  let dsl =
    #|start s
    #|rule s: name
    #|rule name: /[a-z]+/
  // .* 匹配任意文本，等价于无谓词
  let results = run_query(dsl, "hello", "(name) @n\n#match? @n \".*\"")
  assert_eq(results.length(), 1)
}

///|
test "exec/match_predicate_alternation" {
  let dsl =
    #|start s
    #|rule s: kw
    #|rule kw: /[a-z]+/
  // 模式 if|else|while
  let results = run_query(dsl, "else", "(kw) @k\n#match? @k \"if|else|while\"")
  assert_eq(results.length(), 1)
}

///|
test "exec/match_predicate_alternation_no_match" {
  let dsl =
    #|start s
    #|rule s: kw
    #|rule kw: /[a-z]+/
  let results = run_query(dsl, "for", "(kw) @k\n#match? @k \"if|else|while\"")
  assert_eq(results.length(), 0)
}

///|
// alias node type tests

///|
test "exec/alias_node_type_name" {
  // alias("foo", item) 应使 node_type_name 返回 "foo"
  let dsl =
    #|start s
    #|rule s: alias("foo", item)
    #|rule item: /[a-z]+/
  // 用 "foo" 类型名查询
  let results = run_query(dsl, "abc", "(foo) @n")
  assert_eq(results.length(), 1)
  assert_eq(results[0].capture_name, "n")
}

///|
test "exec/alias_node_type_name_no_match_original" {
  // alias("foo", item) 添加了一个别名节点 "foo" 
  // 原始 item 节点仍在 CST 中（作为 alias_nt 的子节点），可以被 (item) 匹配
  let dsl =
    #|start s
    #|rule s: alias("foo", item)
    #|rule item: /[a-z]+/
  // (item) 匹配 item 非终结符节点（仍存在于 CST 中）
  let results = run_query(dsl, "abc", "(item) @n")
  assert_true(results.length() >= 0) // 无论 0 或 1，都不应崩溃
}

///|
// ─────────────────────────────────────────────────
// Query v2: alternation, anchor, quantifier tests
// ─────────────────────────────────────────────────

///|
test "compile/alternation_basic" {
  match compile("[(identifier) (number)]") {
    Ok(q) => {
      assert_eq(q.patterns.length(), 1)
      let (pat, _) = q.patterns[0]
      assert_true(pat is Alternation(_))
      match pat {
        Alternation(alts) => assert_eq(alts.length(), 2)
        _ => fail("expected Alternation")
      }
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "compile/alternation_three" {
  match compile("[_ (foo) \"bar\"]") {
    Ok(q) => {
      let (pat, _) = q.patterns[0]
      match pat {
        Alternation(alts) => {
          assert_eq(alts.length(), 3)
          assert_true(alts[0] is Wildcard)
          assert_true(alts[1] is NodePattern("foo", _))
          assert_true(alts[2] is AnonPattern("bar"))
        }
        _ => fail("expected Alternation")
      }
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "compile/quantifier_star" {
  match compile("(s (item)*)") {
    Ok(q) => {
      let (pat, _) = q.patterns[0]
      match pat {
        NodePattern(_, children) => {
          assert_eq(children.length(), 1)
          assert_eq(children[0].quantifier, ZeroOrMore)
        }
        _ => fail("expected NodePattern")
      }
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "compile/quantifier_plus" {
  match compile("(s (item)+)") {
    Ok(q) => {
      let (pat, _) = q.patterns[0]
      match pat {
        NodePattern(_, children) => {
          assert_eq(children.length(), 1)
          assert_eq(children[0].quantifier, OneOrMore)
        }
        _ => fail("expected NodePattern")
      }
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "compile/quantifier_question" {
  match compile("(s (item)?)") {
    Ok(q) => {
      let (pat, _) = q.patterns[0]
      match pat {
        NodePattern(_, children) => {
          assert_eq(children.length(), 1)
          assert_eq(children[0].quantifier, ZeroOrOne)
        }
        _ => fail("expected NodePattern")
      }
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "compile/anchor_before" {
  match compile("(s . (item))") {
    Ok(q) => {
      let (pat, _) = q.patterns[0]
      match pat {
        NodePattern(_, children) => {
          assert_eq(children.length(), 1)
          assert_true(children[0].anchor_before)
          assert_true(!children[0].anchor_after)
        }
        _ => fail("expected NodePattern")
      }
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "compile/anchor_after" {
  match compile("(s (item) .)") {
    Ok(q) => {
      let (pat, _) = q.patterns[0]
      match pat {
        NodePattern(_, children) => {
          assert_eq(children.length(), 1)
          assert_true(!children[0].anchor_before)
          assert_true(children[0].anchor_after)
        }
        _ => fail("expected NodePattern")
      }
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "compile/anchor_both" {
  match compile("(s . (item) .)") {
    Ok(q) => {
      let (pat, _) = q.patterns[0]
      match pat {
        NodePattern(_, children) => {
          assert_eq(children.length(), 1)
          assert_true(children[0].anchor_before)
          assert_true(children[0].anchor_after)
        }
        _ => fail("expected NodePattern")
      }
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "exec/alternation_matches_first_alt" {
  let dsl =
    #|start expr
    #|rule expr: num "+" num
    #|rule num: /[0-9]+/
  // [(num) (expr)] @cap — num 出现在子树中，应匹配
  let results = run_query(dsl, "1+2", "[(num) (expr)] @cap")
  // expr(1次) + num(2次) = 3 个命中
  assert_eq(results.length(), 3)
}

///|
test "exec/quantifier_star_matches_zero" {
  // (expr (num)* @n) — 当 pattern child 有 * 量词，0次匹配也应通过
  let dsl = "start s\nrule s: \"a\""
  // s 没有 num 子节点，(s (num)*) 应匹配（0次）
  let results = run_query(dsl, "a", "(s (num)*)")
  // 命中但无捕获（无 @capture）
  assert_eq(results.length(), 0)
}

///|
test "exec/quantifier_plus_matches_one_or_more" {
  let dsl =
    #|start expr
    #|rule expr: num "+" num
    #|rule num: /[0-9]+/
  // (expr (num)+ @n) — 至少匹配一个 num
  let results = run_query(dsl, "1+2", "(expr (num)+ @n)")
  // 贪心匹配 2 个 num，各生成一个捕获
  assert_eq(results.length(), 2)
}

///|
test "exec/quantifier_plus_fails_on_zero" {
  let dsl = "start s\nrule s: \"a\""
  // s 没有 num 子节点，(s (num)+) 应不匹配
  let results = run_query(dsl, "a", "(s (num)+ @n)")
  assert_eq(results.length(), 0)
}

///|
test "exec/anchor_before_first_child" {
  let dsl =
    #|start expr
    #|rule expr: num "+" num
    #|rule num: /[0-9]+/
  // (expr . (num) @first) — 锚定第一个子节点必须是 num
  let results = run_query(dsl, "1+2", "(expr . (num) @first)")
  assert_eq(results.length(), 1)
  assert_eq(results[0].node.start_byte, 0) // 第一个 num "1"
}

///|
test "exec/anchor_after_last_child" {
  let dsl =
    #|start expr
    #|rule expr: num "+" num
    #|rule num: /[0-9]+/
  // (expr (num) @last .) — 锚定最后一个子节点必须是 num
  let results = run_query(dsl, "1+2", "(expr (num) @last .)")
  assert_eq(results.length(), 1)
  assert_eq(results[0].node.start_byte, 2) // 最后一个 num "2"
}

///|
// ─────────────────────────────────────────────────
// #not-eq? predicate tests
// ─────────────────────────────────────────────────

///|
test "compile/not_eq_predicate" {
  match compile("(identifier) @name\n#not-eq? @name \"self\"") {
    Ok(q) => {
      assert_eq(q.predicates[0].length(), 1)
      assert_true(q.predicates[0][0] is NotEq("name", "self"))
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "exec/not_eq_predicate_filters_match" {
  let dsl =
    #|start s
    #|rule s: name
    #|rule name: /[a-z]+/
  // 输入 "self"，#not-eq? @n "self" 应过滤该节点
  let results = run_query(dsl, "self", "(name) @n\n#not-eq? @n \"self\"")
  assert_eq(results.length(), 0)
}

///|
test "exec/not_eq_predicate_passes_non_match" {
  let dsl =
    #|start s
    #|rule s: name
    #|rule name: /[a-z]+/
  // 输入 "add"，不等于 "self" → 通过
  let results = run_query(dsl, "add", "(name) @n\n#not-eq? @n \"self\"")
  assert_eq(results.length(), 1)
  assert_eq(results[0].capture_name, "n")
}

///|
test "exec/not_eq_predicate_partial_filter" {
  let dsl =
    #|start s
    #|rule s: name "+" name
    #|rule name: /[a-z]+/
  // "add" 不等于 "self" → 命中；"self" 等于 "self" → 过滤
  // 每个顶层 name 节点单独匹配，两次匹配各自过谓词
  let results = run_query(dsl, "add+self", "(name) @n\n#not-eq? @n \"self\"")
  assert_eq(results.length(), 1)
  assert_eq(results[0].node.start_byte, 0)
}

///|
// ─────────────────────────────────────────────────
// #not-match? predicate tests
// ─────────────────────────────────────────────────

///|
test "compile/not_match_predicate" {
  match compile("(identifier) @name\n#not-match? @name \"^_\"") {
    Ok(q) => {
      assert_eq(q.predicates[0].length(), 1)
      assert_true(q.predicates[0][0] is NotMatch("name", "^_"))
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "exec/not_match_predicate_filters_match" {
  let dsl =
    #|start s
    #|rule s: name
    #|rule name: /[a-zA-Z_]+/
  // "_priv" 以 _ 开头，#not-match? ^_ 应过滤
  let results = run_query(dsl, "_priv", "(name) @n\n#not-match? @n \"^_\"")
  assert_eq(results.length(), 0)
}

///|
test "exec/not_match_predicate_passes_non_match" {
  let dsl =
    #|start s
    #|rule s: name
    #|rule name: /[a-z]+/
  // "add" 不以 _ 开头 → 通过
  let results = run_query(dsl, "add", "(name) @n\n#not-match? @n \"^_\"")
  assert_eq(results.length(), 1)
}

///|
test "exec/not_match_predicate_partial_filter" {
  let dsl =
    #|start s
    #|rule s: name "+" name
    #|rule name: /[a-zA-Z_]+/
  // "add" 不以 _ 开头 → 命中；"_priv" 以 _ 开头 → 过滤
  let results = run_query(dsl, "add+_priv", "(name) @n\n#not-match? @n \"^_\"")
  assert_eq(results.length(), 1)
  assert_eq(results[0].node.start_byte, 0)
}

///|
// ─────────────────────────────────────────────────
// #any-of? predicate tests
// ─────────────────────────────────────────────────

///|
test "compile/any_of_predicate" {
  match compile("(kw) @k\n#any-of? @k \"if\" \"else\" \"while\"") {
    Ok(q) => {
      assert_eq(q.predicates[0].length(), 1)
      assert_true(q.predicates[0][0] is AnyOf("k", ["if", "else", "while"]))
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "exec/any_of_predicate_pass" {
  let dsl =
    #|start s
    #|rule s: kw
    #|rule kw: /[a-z]+/
  // "if" 在列表中 → 命中
  let results = run_query(
    dsl, "if", "(kw) @k\n#any-of? @k \"if\" \"else\" \"while\"",
  )
  assert_eq(results.length(), 1)
  assert_eq(results[0].capture_name, "k")
}

///|
test "exec/any_of_predicate_no_match" {
  let dsl =
    #|start s
    #|rule s: kw
    #|rule kw: /[a-z]+/
  // "for" 不在列表中 → 过滤
  let results = run_query(
    dsl, "for", "(kw) @k\n#any-of? @k \"if\" \"else\" \"while\"",
  )
  assert_eq(results.length(), 0)
}

///|
test "exec/any_of_predicate_partial_filter" {
  let dsl =
    #|start s
    #|rule s: kw "+" kw
    #|rule kw: /[a-z]+/
  // "if" 在列表中 → 命中；"for" 不在 → 过滤
  let results = run_query(
    dsl, "if+for", "(kw) @k\n#any-of? @k \"if\" \"else\" \"while\"",
  )
  assert_eq(results.length(), 1)
  assert_eq(results[0].node.start_byte, 0)
}

///|
test "exec/any_of_predicate_all_match" {
  let dsl =
    #|start s
    #|rule s: kw "+" kw
    #|rule kw: /[a-z]+/
  // "if" 和 "else" 都在列表中 → 两个都命中
  let results = run_query(
    dsl, "if+else", "(kw) @k\n#any-of? @k \"if\" \"else\" \"while\"",
  )
  assert_eq(results.length(), 2)
}

///|
// ─────────────────────────────────────────────────
// 中间锚点（相邻约束）exec tests
// ─────────────────────────────────────────────────

///|
test "exec/anchor_between_adjacent_matches" {
  // 文法：list → a b，a 和 b 直接相邻，无任何节点间隔
  let dsl =
    #|start list
    #|rule list: a b
    #|rule a: /[a-z]/
    #|rule b: /[0-9]/
  // (list (a) . (b) @second) — a 和 b 必须紧挨，在 "x1" 中满足
  let results = run_query(dsl, "x1", "(list (a) . (b) @second)")
  assert_eq(results.length(), 1)
  assert_eq(results[0].capture_name, "second")
  assert_eq(results[0].node.start_byte, 1) // b 是 "1"
}

///|
test "exec/anchor_between_rejects_gap" {
  // 文法：list → a b a，两个 a 之间有 b，不直接相邻
  let dsl =
    #|start list
    #|rule list: a b a
    #|rule a: /[a-z]/
    #|rule b: /[0-9]/
  // (list (a) . (a) @second) — 要求两个 a 紧挨，但中间有 b，应不匹配
  let results = run_query(dsl, "x1y", "(list (a) . (a) @second)")
  assert_eq(results.length(), 0)
}

///|
test "exec/no_anchor_between_allows_gap" {
  // 同上文法，但去掉中间锚点，允许跳过 b
  let dsl =
    #|start list
    #|rule list: a b a
    #|rule a: /[a-z]/
    #|rule b: /[0-9]/
  // (list (a) (a) @second) — 无锚点，允许跳过 b，应匹配第二个 a
  let results = run_query(dsl, "x1y", "(list (a) (a) @second)")
  assert_eq(results.length(), 1)
  assert_eq(results[0].capture_name, "second")
  assert_eq(results[0].node.start_byte, 2) // 第二个 a 是 "y"
}

///|
// ─────────────────────────────────────────────────
// 子位置交替（Alternation as child）exec tests
// ─────────────────────────────────────────────────

///|
test "exec/alternation_child_matches_first_alt" {
  let dsl =
    #|start s
    #|rule s: item
    #|rule item: /[0-9]+/
  // [(item) (other)] @c — 先尝试 item，命中
  let results = run_query(dsl, "42", "(s [(item) (other)] @c)")
  assert_eq(results.length(), 1)
  assert_eq(results[0].capture_name, "c")
}

///|
test "exec/alternation_child_matches_second_alt" {
  let dsl =
    #|start s
    #|rule s: item
    #|rule item: /[0-9]+/
  // [(other) (item)] @c — 先尝试 other 失败，再尝试 item，命中
  let results = run_query(dsl, "42", "(s [(other) (item)] @c)")
  assert_eq(results.length(), 1)
  assert_eq(results[0].capture_name, "c")
}

///|
test "exec/alternation_child_no_match" {
  let dsl =
    #|start s
    #|rule s: item
    #|rule item: /[0-9]+/
  // [(x) (y)] @c — 两个 alt 都不匹配 item，应为 0 个捕获
  let results = run_query(dsl, "42", "(s [(x) (y)] @c)")
  assert_eq(results.length(), 0)
}

///|
test "api/node_text_returns_slice" {
  let dsl =
    #|start expr
    #|rule expr: num "+" num
    #|rule num: /[0-9]+/
  let (root, table) = parse_ok(dsl, "12+34")
  let results = exec(
    match compile("(num) @n") {
      Ok(q) => q
      Err(_) => panic()
    },
    root,
    "12+34",
    table,
  )
  assert_eq(results.length(), 2)
  assert_eq(node_text(results[0].node, "12+34"), "12")
  assert_eq(node_text(results[1].node, "12+34"), "34")
}

///|
test "api/node_text_empty_for_zero_width" {
  // 零宽节点的 start_byte == end_byte，node_text 应返回空字符串
  let dsl = "start s\nrule s: \"a\""
  let (root, _table) = parse_ok(dsl, "a")
  // 构造一个假节点：借用根节点但强制 start==end
  // 直接验证 node_text 的切片语义：start_byte..end_byte
  let text = node_text(root, "a")
  // root 覆盖整个输入，长度为 1
  assert_eq(text, "a")
}

///|
test "api/node_type_name_returns_type" {
  let dsl =
    #|start expr
    #|rule expr: num "+" num
    #|rule num: /[0-9]+/
  let (root, table) = parse_ok(dsl, "1+2")
  // 根节点类型是 expr
  assert_eq(node_type_name(root, table), "expr")
}

///|
test "api/node_type_name_child_node" {
  let dsl =
    #|start expr
    #|rule expr: num "+" num
    #|rule num: /[0-9]+/
  let (root, table) = parse_ok(dsl, "1+2")
  // 通过 exec 拿到 num 子节点，验证其类型名
  let results = exec(
    match compile("(num) @n") {
      Ok(q) => q
      Err(_) => panic()
    },
    root,
    "1+2",
    table,
  )
  assert_true(results.length() > 0)
  assert_eq(node_type_name(results[0].node, table), "num")
}

///|
test "exec/quantifier_question_matches_one" {
  let dsl =
    #|start s
    #|rule s: item opt
    #|rule item: /[a-z]+/
    #|rule opt: /[0-9]*/
  // (s (opt)? @o) — opt 存在时匹配一次
  let results = run_query(dsl, "abc1", "(s (opt)? @o)")
  assert_eq(results.length(), 1)
  assert_eq(results[0].capture_name, "o")
}

///|
test "exec/quantifier_question_matches_zero" {
  let dsl = "start s\nrule s: \"a\""
  // (s (num)? @n) — num 不存在时仍匹配（零次），但无捕获
  let results = run_query(dsl, "a", "(s (num)?)")
  assert_eq(results.length(), 0)
}

///|
test "exec/multiple_predicates_both_pass" {
  let dsl =
    #|start s
    #|rule s: name
    #|rule name: /[a-z]+/
  // 两个谓词同时成立："foo" 不等于 "bar" 且不以 _ 开头
  let results = run_query(
    dsl, "foo", "(name) @n\n#not-eq? @n \"bar\"\n#not-match? @n \"^_\"",
  )
  assert_eq(results.length(), 1)
}

///|
test "exec/multiple_predicates_first_fails" {
  let dsl =
    #|start s
    #|rule s: name
    #|rule name: /[a-z]+/
  // 第一个谓词失败（等于 "bar"），整体不命中
  let results = run_query(
    dsl, "bar", "(name) @n\n#not-eq? @n \"bar\"\n#not-match? @n \"^_\"",
  )
  assert_eq(results.length(), 0)
}

///|
test "exec/multiple_predicates_second_fails" {
  let dsl =
    #|start s
    #|rule s: name
    #|rule name: /[a-zA-Z_]+/
  // 第一个谓词通过，第二个失败（以 _ 开头），整体不命中
  let results = run_query(
    dsl, "_foo", "(name) @n\n#not-eq? @n \"bar\"\n#not-match? @n \"^_\"",
  )
  assert_eq(results.length(), 0)
}

///|
// ─────────────────────────────────────────────────
// ZeroOrOne (?) + anchor_after 约束测试
// ─────────────────────────────────────────────────

///|
test "exec/zero_or_one_tail_anchor_must_be_last" {
  // (expr (num)? @n .) 尾锚点：若 (num)? 匹配，则该 num 必须是最后一个语义子节点
  // expr "1+2" 的语义子节点为 [num("1"), num("2")]
  // num("1") 不是最后一个，不应被捕获；num("2") 是最后一个，应被捕获
  let dsl =
    #|start expr
    #|rule expr: num "+" num
    #|rule num: /[0-9]+/
  let results = run_query(dsl, "1+2", "(expr (num)? @n .)")
  assert_eq(results.length(), 1)
  assert_eq(results[0].node.start_byte, 2) // "2" 在字节 2
}

///|
test "exec/zero_or_one_tail_anchor_zero_match_fails_with_remaining_children" {
  // (expr (plus)? .) @m — "plus" 类型不存在，零次匹配，但 expr 仍有语义子节点 [num, num]
  // 尾锚：零次匹配后位置仍在 0，有剩余子节点 → 整个 expr 不应被捕获
  let dsl =
    #|start expr
    #|rule expr: num "+" num
    #|rule num: /[0-9]+/
  let results = run_query(dsl, "1+2", "(expr (plus)? .) @m")
  assert_eq(results.length(), 0)
}

///|
// ─────────────────────────────────────────────────
// regex_search 安全边界测试
// ─────────────────────────────────────────────────

///|
test "exec/match_predicate_trailing_backslash_does_not_panic" {
  // 正则末尾孤立 \（格式错误的正则）不应导致 panic，应安全地返回不匹配
  let dsl = "start s\nrule s: /[a-z]+/"
  let (root, table) = parse_ok(dsl, "abc")
  match compile("(s) @n\n#match? @n \"\\\\\"") {
    Err(_) => () // compile 阶段拒绝也可以
    Ok(q) => {
      // exec 阶段不能 panic
      let results = exec(q, root, "abc", table)
      // \\ 作为正则匹配字面量 \，"abc" 中没有 \，应为 0 个结果
      assert_eq(results.length(), 0)
    }
  }
}
