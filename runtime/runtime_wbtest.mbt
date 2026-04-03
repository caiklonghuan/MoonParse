///|
// runtime_wbtest.mbt — parse() 端对端表格驱动测试
//
// 流水线：Grammar DSL → parse_from_dsl() → CstNode
// 或：    Grammar DSL → make_table() → parse() → CstNode
//
// 测试分组：
//   表 1：parse 成功 — 根节点 start_byte=0, end_byte, children 数量
//   表 2：parse 失败 — 语法/词法错误时返回 Err
//   表 3：叶节点位置信息 — start_byte / end_byte 精确值
//   表 4：extras 处理 — 空白不影响语义节点

// ─── 辅助 ─────────────────────────────────────────────────────────────────────

///|
/// CstNode 的紧凑摘要（调试输出）
fn node_summary(n : CstNode) -> String {
  "sym=\{n.symbol} [\{n.start_byte},\{n.end_byte}) ch=\{n.children.length()}"
}

// ─── 表 1：parse 成功 ─────────────────────────────────────────────────────────
// (_label, dsl, input, exp_end_byte, exp_children)
// exp_end_byte / exp_children = -1 → 跳过该断言

///|
test "parse 成功 — 根节点属性" {
  let cases : Array[(String, String, String, Int, Int)] = [
    ("单字符 a", "start s\nrule s: \"a\"", "a", 1, 1),
    ("两字符 ab", "start s\nrule s: \"a\" \"b\"", "ab", 2, 2),
    ("选择 a — 匹配 a", "start s\nrule s: \"a\" | \"b\"", "a", 1, 1),
    ("选择 b — 匹配 b", "start s\nrule s: \"a\" | \"b\"", "b", 1, 1),
    ("数字串 regex", "start s\nrule s: /[0-9]+/", "123", 3, 1),
    ("嵌套 atom", "start e\nrule e: e \"+\" t | t\nrule t: \"n\"", "n", 1, -1),
    (
      "嵌套加法", "start e\nrule e: e \"+\" t | t\nrule t: \"n\"", "n+n", 3,
      -1,
    ),
  ]
  for case in cases {
    let (_l, dsl, input, exp_end, exp_ch) = case
    match parse_from_dsl(dsl, input) {
      Err(e) => fail("parse_from_dsl failed for '\{_l}': \{e.message}")
      Ok(root) => {
        inspect(node_summary(root), content=node_summary(root))
        assert_eq(root.start_byte, 0)
        if exp_end >= 0 {
          assert_eq(root.end_byte, exp_end)
        }
        if exp_ch >= 0 {
          assert_eq(root.children.length(), exp_ch)
        }
      }
    }
  }
}

// ─── 表 2：parse 失败 ─────────────────────────────────────────────────────────
// (_label, dsl, input, want_err)

///|
test "parse 失败 — 语法/词法错误返回 Err" {
  let cases : Array[(String, String, String, Bool)] = [
    ("空输入 EOF", "start s\nrule s: \"a\"", "", true),
    ("词法错误 !", "start s\nrule s: \"a\"", "!", true),
    ("多余字符", "start s\nrule s: \"a\"", "ab", true),
    ("期望 a 给 b", "start s\nrule s: \"a\"", "b", true),
    ("正确输入不报错", "start s\nrule s: \"a\"", "a", false),
  ]
  for case in cases {
    let (_l, dsl, input, want_err) = case
    let got_err = match parse_from_dsl(dsl, input) {
      Ok(_) => false
      Err(_) => true
    }
    assert_eq(got_err, want_err)
  }
}

// ─── 表 3：叶节点位置信息 ────────────────────────────────────────────────────
// (_label, dsl, input, leaf_index, exp_start, exp_end)

///|
test "parse 叶节点位置" {
  let cases : Array[(String, String, String, Int, Int, Int)] = [
    ("单叶 a", "start s\nrule s: \"a\"", "a", 0, 0, 1),
    ("双叶 ab — 第0叶", "start s\nrule s: \"a\" \"b\"", "ab", 0, 0, 1),
    ("双叶 ab — 第1叶", "start s\nrule s: \"a\" \"b\"", "ab", 1, 1, 2),
    ("regex 123", "start s\nrule s: /[0-9]+/", "123", 0, 0, 3),
  ]
  for case in cases {
    let (_l, dsl, input, leaf_idx, exp_start, exp_end) = case
    match parse_from_dsl(dsl, input) {
      Err(e) => fail("parse_from_dsl failed for '\{_l}': \{e.message}")
      Ok(root) => {
        if leaf_idx >= root.children.length() {
          fail(
            "'\{_l}': leaf_idx=\{leaf_idx} >= children.len=\{root.children.length()}",
          )
        }
        let leaf = root.children[leaf_idx]
        assert_eq(leaf.start_byte, exp_start)
        assert_eq(leaf.end_byte, exp_end)
      }
    }
  }
}

// ─── 表 4：extras 处理 ────────────────────────────────────────────────────────
// (_label, dsl, input, exp_root_end, exp_non_extra_children)
// exp_non_extra_children = -1 → 跳过

///|
test "parse extras — 空白跳过不影响结构" {
  let cases : Array[(String, String, String, Int, Int)] = [
    ("前置空格", "start s\nrule s: \"a\"\nextras [/\\s+/]", " a", 2, -1),
    ("后置空格", "start s\nrule s: \"a\"\nextras [/\\s+/]", "a ", 1, -1),
    (
      "加法中间空格", "start e\nrule e: e \"+\" t | t\nrule t: \"n\"\nextras [/\\s+/]",
      "n + n", 5, -1,
    ),
    ("无 extras", "start s\nrule s: \"a\"", "a", 1, 1),
  ]
  for case in cases {
    let (_l, dsl, input, exp_end, exp_ne_ch) = case
    match parse_from_dsl(dsl, input) {
      Err(e) => fail("parse_from_dsl failed for '\{_l}': \{e.message}")
      Ok(root) => {
        assert_eq(root.end_byte, exp_end)
        if exp_ne_ch >= 0 {
          let ne = root.children.iter().filter(fn(c) { not(c.extra) }).count()
          assert_eq(ne, exp_ne_ch)
        }
      }
    }
  }
}
