///|
// viz_wbtest.mbt — AST 可视化函数单元测试
//
// 测试三种可视化格式：
//   1. ASCII 树形打印 (tree_to_ascii_tree)
//   2. Graphviz DOT 导出 (tree_to_dot)
//   3. HTML 树可视化 (tree_to_html)


///|
test "ascii_tree — 单节点叶子含原文" {
  let pid = parser_create_from_dsl("start s\nrule s: \"a\"")
  assert_true(pid >= 0)
  let tid = parse_full(pid, "a")
  assert_true(tid >= 0)
  let out = tree_to_ascii_tree(tid)
  // 根行应含节点类型 "s"
  assert_true(out.contains("s"))
  // 应含字节区间
  assert_true(out.contains("(0-"))
  // 叶节点应含原文
  assert_true(out.contains("\"a\""))
  tree_free(tid)
  parser_free(pid)
}

///|
test "ascii_tree — 嵌套树含连接线符号" {
  let pid = parser_create_from_dsl(
    "start e\nrule e: e \"+\" t | t\nrule t: \"n\"",
  )
  let tid = parse_full(pid, "n+n")
  let out = tree_to_ascii_tree(tid)
  // 多级树应含 ├── 或 └──
  assert_true(out.contains("├──") || out.contains("└──"))
  // 含叶节点原文 "n"
  assert_true(out.contains("\"n\""))
  tree_free(tid)
  parser_free(pid)
}

///|
test "ascii_tree — 无效 tree_id 返回空串" {
  assert_eq(tree_to_ascii_tree(9999), "")
}

///|
test "ascii_tree — 多词法单元各在独立行" {
  let pid = parser_create_from_dsl("start s\nrule s: \"a\" \"b\"")
  let tid = parse_full(pid, "ab")
  let out = tree_to_ascii_tree(tid)
  // 应有多行（至少 3 行：根节点 + 2 个叶子）
  let mut newlines = 0
  for ch in out {
    if ch == '\n' {
      newlines = newlines + 1
    }
  }
  assert_true(newlines >= 2)
  tree_free(tid)
  parser_free(pid)
}

// ── Graphviz DOT 导出 ─────────────────────────────────────────────

///|
test "dot — 输出以 digraph CST 开头" {
  let pid = parser_create_from_dsl("start s\nrule s: \"a\"")
  let tid = parse_full(pid, "a")
  let out = tree_to_dot(tid)
  assert_true(out.contains("digraph CST {"))
  assert_true(out.contains("->"))
  assert_true(out.contains("}"))
  tree_free(tid)
  parser_free(pid)
}

///|
test "dot — 包含节点定义和边" {
  let pid = parser_create_from_dsl(
    "start e\nrule e: e \"+\" t | t\nrule t: \"n\"",
  )
  let tid = parse_full(pid, "n+n")
  let out = tree_to_dot(tid)
  // 节点定义：nX [label=...]
  assert_true(out.contains("n0 ["))
  assert_true(out.contains("label="))
  // 边：nX -> nY
  assert_true(out.contains("-> n"))
  tree_free(tid)
  parser_free(pid)
}

///|
test "dot — 节点颜色标注存在" {
  let pid = parser_create_from_dsl(
    "start e\nrule e: e \"+\" t | t\nrule t: \"n\"",
  )
  let tid = parse_full(pid, "n+n")
  let out = tree_to_dot(tid)
  // 内部节点填充蓝色，叶节点填充绿色
  assert_true(out.contains("#cce5ff") || out.contains("#d4edda"))
  tree_free(tid)
  parser_free(pid)
}

///|
test "dot — 无效 tree_id 返回空串" {
  assert_eq(tree_to_dot(9999), "")
}

// ── HTML 树可视化 ─────────────────────────────────────────────────

///|
test "html — 输出为有效 HTML 结构" {
  let pid = parser_create_from_dsl("start s\nrule s: \"a\"")
  let tid = parse_full(pid, "a")
  let out = tree_to_html(tid)
  assert_true(out.contains("<!DOCTYPE html>"))
  assert_true(out.contains("<html"))
  assert_true(out.contains("</html>"))
  assert_true(out.contains("<style>"))
  tree_free(tid)
  parser_free(pid)
}

///|
test "html — 嵌套树使用 details/summary" {
  let pid = parser_create_from_dsl(
    "start e\nrule e: e \"+\" t | t\nrule t: \"n\"",
  )
  let tid = parse_full(pid, "n+n")
  let out = tree_to_html(tid)
  assert_true(out.contains("<details"))
  assert_true(out.contains("<summary"))
  assert_true(out.contains("</details>"))
  tree_free(tid)
  parser_free(pid)
}

///|
test "html — 叶节点原文在 text span 中" {
  let pid = parser_create_from_dsl("start s\nrule s: \"hello\"")
  let tid = parse_full(pid, "hello")
  let out = tree_to_html(tid)
  assert_true(out.contains("hello"))
  assert_true(out.contains("class=\"text\""))
  tree_free(tid)
  parser_free(pid)
}

///|
test "html — 无效 tree_id 返回空串" {
  assert_eq(tree_to_html(9999), "")
}

///|
test "html — CSS 类名：命名节点用 named，匿名用 anon" {
  let pid = parser_create_from_dsl("start s\nrule s: \"a\" \"b\"")
  let tid = parse_full(pid, "ab")
  let out = tree_to_html(tid)
  assert_true(out.contains("class=\"named\"") || out.contains("class=\"anon\""))
  tree_free(tid)
  parser_free(pid)
}

///|
test "html — 正则词法节点" {
  let pid = parser_create_from_dsl("start s\nrule s: /[0-9]+/")
  let tid = parse_full(pid, "42")
  assert_true(tid >= 0)
  let out = tree_to_html(tid)
  assert_true(out.contains("42"))
  tree_free(tid)
  parser_free(pid)
}
