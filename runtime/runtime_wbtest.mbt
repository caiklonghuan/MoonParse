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

// ─── 表 4b：extras 节点出现在 CST children 中 ────────────────────────────────
// GLR 路径下 extras 必须体现在 CST，不能静默丢弃。
// ("label", dsl, input, expected_total_children, expected_extra_children)

///|
test "parse extras — extras 节点出现在 CST children 中" {
  let cases : Array[(String, String, String, Int, Int)] = [
    // s → "a" "b"，输入 "a b"：期望 children = [a, space, b]（共 3 个，1 个 extra）
    (
      "中间空格进 children", "start s\nrule s: \"a\" \"b\"\nextras [/\\s+/]",
      "a b", 3, 1,
    ),
    // s → "a"，输入 " a"：前置空格作为 leading_extras 附到 "a" 的 Shift 边，
    // 归约时进入 s 的 children → [space, a]（共 2 个，1 个 extra）
    (
      "前置空格进 children", "start s\nrule s: \"a\"\nextras [/\\s+/]", " a",
      2, 1,
    ),
    // 无 extras 时 children 数量不变
    (
      "无 extras — children 不变", "start s\nrule s: \"a\" \"b\"", "ab", 2,
      0,
    ),
  ]
  for case in cases {
    let (_l, dsl, input, exp_total, exp_extra) = case
    match parse_from_dsl(dsl, input) {
      Err(e) => fail("parse_from_dsl failed for '\{_l}': \{e.message}")
      Ok(root) => {
        let extra_count = root.children.iter().filter(fn(c) { c.extra }).count()
        assert_eq(root.children.length(), exp_total)
        assert_eq(extra_count, exp_extra)
      }
    }
  }
}

// ─── 表 5：GLR — 左递归左结合 CST 结构 ──────────────────────────────────────
//
// 文法：e → e "+" t | t; t → "n"
// 输入：n+n+n（5 字节）
//
// 期望 CST（左结合）：
//   e (root, 3 children)
//   ├── e (left, 3 children)   ← "n+n"
//   │   ├── e (1 child)        ← e→t→"n"
//   │   ├── "+"
//   │   └── t (1 child)        ← t→"n"
//   ├── "+"
//   └── t (1 child)            ← t→"n"
//
// 若为右结合则 root.children[2] 才是深层节点，children[0].children.length()=1。
// 断言 root.children[0].children.length()==3 验证左结合性。

///|
test "GLR 左递归 — n+n+n 产生左结合 CST" {
  let dsl = "start e\nrule e: e \"+\" t | t\nrule t: \"n\""
  let input = "n+n+n"
  match parse_from_dsl(dsl, input) {
    Err(e) => fail("parse failed: \{e.message}")
    Ok(root) => {
      // 根节点覆盖完整输入
      assert_eq(root.start_byte, 0)
      assert_eq(root.end_byte, 5)
      // 根节点 e → e "+" t：三个子节点
      assert_eq(root.children.length(), 3)
      // 左子树 e 对应 "n+n"：也是三个子节点（左结合）
      assert_eq(root.children[0].children.length(), 3)
      // 左子树的左子树 e 对应 "n"（e→t）：一个子节点
      assert_eq(root.children[0].children[0].children.length(), 1)
      // 最后一个 "+" 的位置
      assert_eq(root.children[1].start_byte, 3)
      assert_eq(root.children[1].end_byte, 4)
    }
  }
}

// ─── 表 6：GLR — S/R 冲突文法（悬挂 else）─────────────────────────────────
//
// 文法：s → "i" s "e" s | "i" s | "x"
// 输入：iixex（= i i x e x，5 字节）
//
// 该文法在 "after i s, lookahead=e" 时有 Shift/Reduce 冲突：
//   · Shift  → else 绑定内层 if（deep binding）
//   · Reduce → else 绑定外层 if（shallow binding）
// GLR 并行探索两条路径，应能成功返回 Ok 而非报错。
// Phase 2b 只返回第一条路径；Phase 2c 可返回两棵树。

///|
test "GLR S/R 冲突 — 悬挂 else 文法可成功解析" {
  let dsl = "start s\nrule s: \"i\" s \"e\" s | \"i\" s | \"x\""
  // i i x e x：外层 if，内层 if-else
  let input = "iixex"
  match parse_from_dsl(dsl, input) {
    Err(e) => fail("parse failed (expected Ok): \{e.message}")
    Ok(root) => {
      // 根节点覆盖完整输入
      assert_eq(root.start_byte, 0)
      assert_eq(root.end_byte, 5)
      // 根节点体积大于 0
      assert_true(root.children.length() > 0)
    }
  }
}

// ─── 表 7：fragile 标记精度 ───────────────────────────────────────────────────
//
// 无歧义文法（确定性 LR）：内部节点不应被标 fragile，以便 Phase 3a 增量复用。
// 有歧义文法（GLR 并行路径）：内部节点必须标 fragile。

///|
test "GLR fragile — 无歧义文法内部节点 fragile=false" {
  // 确定性文法：s → "a" "b"，无任何 S/R 或 R/R 冲突
  let dsl = "start s\nrule s: \"a\" \"b\""
  match parse_from_dsl(dsl, "ab") {
    Err(e) => fail("parse failed: \{e.message}")
    Ok(root) => {
      // 根节点 s 是内部节点，不应被标 fragile
      assert_eq(root.fragile_left, false)
      assert_eq(root.fragile_right, false)
    }
  }
}

///|
test "GLR fragile — S/R 冲突文法内部节点 fragile=true" {
  // 悬挂 else：存在 S/R 冲突，GLR 并行探索 ⟹ 内部节点必须 fragile
  let dsl = "start s\nrule s: \"i\" s \"e\" s | \"i\" s | \"x\""
  match parse_from_dsl(dsl, "iixex") {
    Err(e) => fail("parse failed: \{e.message}")
    Ok(root) => {
      // 根节点由 S/R 冲突路径归约而来，必须 fragile
      assert_eq(root.fragile_left, true)
      assert_eq(root.fragile_right, true)
    }
  }
}
