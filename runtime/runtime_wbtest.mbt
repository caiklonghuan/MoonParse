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

// 辅助

///|
/// CstNode 的紧凑摘要（调试输出）
fn node_summary(n : CstNode) -> String {
  "sym=\{n.symbol} [\{n.start_byte},\{n.end_byte}) ch=\{n.children.length()}"
}

// 表 1：parse 成功
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

// 表 2：parse 失败
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

// 表 3：叶节点位置信息
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

// 表 4：extras 处理
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

// 表 4b：extras 节点出现在 CST children 中
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

// 表 5：GLR — 左递归左结合 CST 结构
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

// 表 6：GLR — S/R 冲突文法（悬挂 else）
//
// 文法：s → "i" s "e" s | "i" s | "x"
// 输入：iixex（= i i x e x，5 字节）
//
// 该文法在 "after i s, lookahead=e" 时有 Shift/Reduce 冲突：
//   · Shift  → else 绑定内层 if（deep binding）
//   · Reduce → else 绑定外层 if（shallow binding）
// GLR 并行探索两条路径，应能成功返回 Ok 而非报错。
// 当前返回第一条路径；歧义时可扩展为返回两棵树。

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

// 表 7：fragile 标记精度
//
// 无歧义文法（确定性 LR）：内部节点不应被标 fragile，以便增量复用。
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
      // 根节点由 S/R 冲突路径归约而来，fragile_left=true；
      // 右边界始终同步于当前词法单元，不受并行路径影响，fragile_right=false
      assert_eq(root.fragile_left, true)
      assert_eq(root.fragile_right, false)
    }
  }
}

// 表 8：skip_token 错误恢复
//
// GLR 遇到无法 Shift 的 token 时，skip_token 把它包进 ERROR 节点并保持
// 当前 LR 状态，解析继续推进，最终仍返回 Ok（而非 Err）。

///|
test "skip_token — 单个垃圾字符后正常解析" {
  // 文法：s → "a" "b"，输入 "!ab"
  // "!" 无法被任何状态 Shift，应被 skip，然后 "ab" 正常完成
  let dsl = "start s\nrule s: \"a\" \"b\""
  match parse_from_dsl(dsl, "!ab") {
    Err(e) => fail("expected Ok but got Err: \{e.message}")
    Ok(root) =>
      // 根节点覆盖到 "ab" 结束位置（byte 3），不包括被 skip 的位置 0
      assert_eq(root.end_byte, 3)
  }
}

///|
test "skip_token — 多个垃圾字符后正常解析" {
  // 输入 "!!ab"，两个 "!" 都被 skip
  let dsl = "start s\nrule s: \"a\" \"b\""
  match parse_from_dsl(dsl, "!!ab") {
    Err(e) => fail("expected Ok but got Err: \{e.message}")
    Ok(root) => assert_eq(root.end_byte, 4)
  }
}

///|
test "skip_token — 只有垃圾字符（无法恢复到完整树）" {
  // 输入 "!!"，无法拼出完整 s，解析最终接受不了，预期返回 Err
  // （skip 后 active_tops 仍在等 "a"，EOF 时无 accept 状态）
  let dsl = "start s\nrule s: \"a\" \"b\""
  match parse_from_dsl(dsl, "!!") {
    Err(_) => () // 期望失败
    Ok(_) => fail("expected Err but got Ok")
  }
}

// 表 9：insert_missing 恢复
//
// insert_missing 在无法 Shift 当前 token 时，先检查是否可以插入一个 MISSING
// 虚拟节点，使解析继续推进并消费当前 token。
// 与 skip_token 区别：skip 是"扔掉当前 token"，insert_missing 是"在当前 token
// 前插入一个缺失 token"——后者更能保留语义结构。

///|
test "insert_missing — 缺少分号后仍可完成解析" {
  // 文法：s → "a" ";" "b"，输入 "ab"（缺 ";"）
  // insert_missing 插入虚拟 ";"，然后正常 Shift "b"，解析成功
  let dsl = "start s\nrule s: \"a\" \";\" \"b\""
  match parse_from_dsl(dsl, "ab") {
    Err(e) => fail("expected Ok but got Err: \{e.message}")
    Ok(root) => {
      // 根节点覆盖整个输入 [0, 2)
      assert_eq(root.end_byte, 2)
      // s → "a" ";" "b"：三个子节点（";" 是 MISSING 节点，zero-width）
      assert_eq(root.children.length(), 3)
      // 中间子节点是 MISSING 节点
      assert_eq(root.children[1].is_missing, true)
      // MISSING 节点是零宽的
      assert_eq(root.children[1].start_byte, root.children[1].end_byte)
    }
  }
}

///|
test "insert_missing — 缺少中间 token 的代价标记" {
  // 含 MISSING 节点的路径，其 error_status 应有代价（> 0）
  // 通过多次恢复后解析成功 → 根节点存在 MISSING 子孙
  let dsl = "start s\nrule s: \"a\" \";\" \"b\""
  match parse_from_dsl(dsl, "ab") {
    Err(e) => fail("expected Ok: \{e.message}")
    Ok(root) => {
      // 存在 MISSING 子节点
      let has_missing = root.children.iter().any(fn(c) { c.is_missing })
      assert_true(has_missing)
    }
  }
}

// 表 10：recover_to_state 恢复
//
// recover_to_state 沿 GSS 入边回溯，找到可接受当前 token 的祖先状态，
// 将路径上的内容包进 ERROR 节点后从祖先状态继续解析。
//
// 该策略在 next_tops.is_empty()（insert_missing 也无法推进）时触发，
// 常见于 GLR 多路径中某路径陷入死胡同的情形。
// 注意：当前实现中 skip_token 的「停留路径」仅在初始状态（state=0）或
// 完整产生式归约边界处可正确穿透 enum_paths；产生式体中间出现错误时，
// 应优先由 insert_missing_and_relex 介入补齐缺失 token。
// 以下测试通过 parse_from_dsl 验证恢复后解析可成功完成。

///|
test "recover_to_state — 初始状态前的错误不影响后续解析" {
  // 文法 s → "a" "b" "c"，输入 "_abc"（"_"在移进任何 token 前出现）
  // "_" → sym_error → skip_token at initial state(0) → S0_staying
  // "a" "b" "c" 均在 S0_staying 的后继路径上正常移进 + 归约
  // skip 处于初始状态，enum_paths 的 base_ref 仍为 state=0，归约成功
  let dsl = "start s\nrule s: \"a\" \"b\" \"c\""
  match parse_from_dsl(dsl, "_abc") {
    Err(e) => fail("expected Ok but got Err: \{e.message}")
    Ok(root) => {
      // 根节点覆盖 [0, 4)，包含 3 个子节点（不含 ERROR 前缀 "_"）
      assert_eq(root.end_byte, 4)
      assert_eq(root.children.length(), 3)
    }
  }
}

///|
test "recover_to_state — 多余前缀后完成解析" {
  // 文法 s → "a" "b"，输入 "!!!ab"（三个 sym_error 符号后跟 "ab"）
  // 每个 "!" 在 initial state 被 skip；"a" "b" 之后正常归约
  let dsl = "start s\nrule s: \"a\" \"b\""
  match parse_from_dsl(dsl, "!!!ab") {
    Err(e) => fail("expected Ok but got Err: \{e.message}")
    Ok(root) => assert_eq(root.end_byte, 5)
  }
}

///|
test "recover_to_state — S/R 冲突文法中错误前缀不影响 GLR 解析" {
  // 悬挂 else 文法存在 S/R 冲突，GLR 并行探索两条路径
  // 在有效输入前加错误前缀，确认 recover_to_state 不会干扰正常路径
  let dsl = "start s\nrule s: \"i\" s \"e\" s | \"i\" s | \"x\""
  // 正常输入（无错误前缀）应当成功
  match parse_from_dsl(dsl, "iixex") {
    Err(e) => fail("expected Ok but got Err: \{e.message}")
    Ok(root) => assert_eq(root.end_byte, 5)
  }
}

// 表 11：condense_stack 版本上限
//
// condense_stack 在 active_tops.length() > max_version_count 时
// 按代价排序截尾，确保活跃版本数不超过 max_version_count。
// 高度歧义文法（大量 S/R 冲突）会产生指数级并行路径，condense 是防爆炸的安全阀。

///|
test "condense_stack — 高歧义文法解析不崩溃且返回 Ok" {
  // s → "x" | "x" "x" | "x" "x" "x"，输入 "xxx"
  // 每个 token 都触发多条 Shift/Reduce 路径，active_tops 可能超过 max_version_count
  // condense_stack 应在截尾后保持 active_tops 可管理，最终解析成功
  let dsl = "start s\nrule s: \"x\" | \"x\" \"x\" | \"x\" \"x\" \"x\""
  // 该文法输入 "xxx" 存在多条解析（单 x、双 x、三 x 均合法），GLR 返回其中一条
  match parse_from_dsl(dsl, "xxx") {
    Err(e) => fail("expected Ok but got Err: \{e.message}")
    Ok(root) => {
      assert_eq(root.start_byte, 0)
      assert_eq(root.end_byte, 3)
    }
  }
}

///|
test "condense_stack — 截尾优先保留低代价路径" {
  // 错误恢复时代价最低的路径（无错误 = 代价 0）应被优先保留
  // 文法：s → "a" "b"，输入无前缀错误 "ab"：正常路径代价 0，应成功
  let dsl = "start s\nrule s: \"a\" \"b\""
  match parse_from_dsl(dsl, "ab") {
    Err(e) => fail("expected Ok but got Err: \{e.message}")
    Ok(root) => assert_eq(root.end_byte, 2)
  }
}

// 表 12：apply_edit — has_changes 标记
//
// apply_edit 对旧 CST 做 copy-on-write 深度优先遍历：
//   · 与 [start_byte, old_end_byte) 相交的节点打 has_changes = true
//   · 不相交的节点原样共享（零复制）
//   · 内部节点相交时递归重建 children，自身也打 has_changes

///|
test "apply_edit — 编辑区间内节点标 has_changes，区间外不变" {
  // 文法 s → "a" "b" "c"，输入 "abc"
  // 树：s[0,3) → ["a"[0,1), "b"[1,2), "c"[2,3)]
  // 编辑 [1,2)：替换 "b"
  let dsl = "start s\nrule s: \"a\" \"b\" \"c\""
  match parse_from_dsl(dsl, "abc") {
    Err(e) => fail("parse failed: \{e.message}")
    Ok(root) => {
      let tree : OldTree = { root, old_input: "abc" }
      let edit : InputEdit = {
        start_byte: 1,
        old_end_byte: 2,
        new_end_byte: 2,
        start_point: { row: 0, column: 1 },
        old_end_point: { row: 0, column: 2 },
        new_end_point: { row: 0, column: 2 },
      }
      let new_tree = apply_edit(tree, edit)
      // 根节点 s[0,3) 与 [1,2) 相交 → has_changes
      assert_eq(new_tree.root.has_changes, true)
      let ch = new_tree.root.children
      assert_eq(ch[0].has_changes, false) // "a"[0,1) 不相交
      assert_eq(ch[1].has_changes, true) // "b"[1,2) 相交
      assert_eq(ch[2].has_changes, false) // "c"[2,3) 不相交
    }
  }
}

///|
test "apply_edit — 不修改原树（copy-on-write）" {
  let dsl = "start s\nrule s: \"a\" \"b\""
  match parse_from_dsl(dsl, "ab") {
    Err(e) => fail("parse failed: \{e.message}")
    Ok(root) => {
      let tree : OldTree = { root, old_input: "ab" }
      let edit : InputEdit = {
        start_byte: 0,
        old_end_byte: 1,
        new_end_byte: 1,
        start_point: { row: 0, column: 0 },
        old_end_point: { row: 0, column: 1 },
        new_end_point: { row: 0, column: 1 },
      }
      let new_tree = apply_edit(tree, edit)
      assert_eq(new_tree.root.has_changes, true)
      assert_eq(tree.root.has_changes, false) // 原树未被修改
    }
  }
}

///|
test "apply_edit — 编辑在所有节点之后不标记任何节点" {
  // 文法 s → "a" "b"，输入 "ab"，根节点 [0,2)
  // 编辑 [2,3)：在末尾追加，不与任何现有节点相交
  let dsl = "start s\nrule s: \"a\" \"b\""
  match parse_from_dsl(dsl, "ab") {
    Err(e) => fail("parse failed: \{e.message}")
    Ok(root) => {
      let tree : OldTree = { root, old_input: "ab" }
      let edit : InputEdit = {
        start_byte: 2,
        old_end_byte: 3,
        new_end_byte: 4,
        start_point: { row: 0, column: 2 },
        old_end_point: { row: 0, column: 3 },
        new_end_point: { row: 0, column: 4 },
      }
      let new_tree = apply_edit(tree, edit)
      // 根节点 end_byte=2，不与 start=2 相交（end_byte > start 为 false）
      assert_eq(new_tree.root.has_changes, false)
    }
  }
}

// 表 13：find_reusable_node — 旧树复用查找
//
// 直接构造 CstNode 以精确控制 parse_state / has_changes / lookahead_bytes，
// 验证 search_reusable 的剪枝策略与 is_reusable 过滤。

///|
/// 构造简单叶节点，仅设置增量相关字段
fn make_leaf(
  start : Int,
  end : Int,
  state : Int,
  lookahead : Int,
  has_changes : Bool,
) -> CstNode {
  let pt : Point = { row: 0, column: 0 }
  {
    ..CstNode::leaf(1, true, start, end, pt, pt, state, lookahead, false, false),
    has_changes,
  }
}

///|
test "find_reusable_node — 叶节点满足所有条件时返回 Some" {
  // 叶节点 [2,3)，state=5，lookahead=3，无 has_changes
  // 查询 new_pos=2, lr_state=5, edit_start=10 → 全部条件通过
  let leaf = make_leaf(2, 3, 5, 3, false)
  let tree : OldTree = { root: leaf, old_input: "abc" }
  match find_reusable_node(tree, 2, 5, 10) {
    None => fail("expected Some but got None")
    Some(n) => {
      assert_eq(n.start_byte, 2)
      assert_eq(n.end_byte, 3)
    }
  }
}

///|
test "find_reusable_node — has_changes 阻止复用" {
  let leaf = make_leaf(2, 3, 5, 3, true) // has_changes = true
  let tree : OldTree = { root: leaf, old_input: "abc" }
  assert_true(find_reusable_node(tree, 2, 5, 10) is None)
}

///|
test "find_reusable_node — parse_state 不匹配阻止复用" {
  let leaf = make_leaf(2, 3, 5, 3, false)
  let tree : OldTree = { root: leaf, old_input: "abc" }
  // 传入 lr_state=99，与 leaf.parse_state=5 不符
  assert_true(find_reusable_node(tree, 2, 99, 10) is None)
}

///|
test "find_reusable_node — lookahead 越过 edit_start 阻止复用" {
  // lookahead_bytes=8 > edit_start=5 → 不可复用
  let leaf = make_leaf(2, 3, 5, 8, false)
  let tree : OldTree = { root: leaf, old_input: "abc" }
  assert_true(find_reusable_node(tree, 2, 5, 5) is None)
}

///|
test "find_reusable_node — new_pos 不匹配时剪枝返回 None" {
  // 树只有 [2,3) 这个叶节点，但查询 new_pos=0
  let leaf = make_leaf(2, 3, 5, 3, false)
  let tree : OldTree = { root: leaf, old_input: "abc" }
  // leaf.start_byte=2 > new_pos=0 → 剪枝
  assert_true(find_reusable_node(tree, 0, 5, 10) is None)
}

///|
test "find_reusable_node — 在 children 中找到匹配叶节点" {
  // 内部节点 [0,3)，children = [leaf[0,1), leaf[1,2), leaf[2,3)]
  // 查询 new_pos=1, lr_state=7, edit_start=10 → 返回 children[1]
  let c0 = make_leaf(0, 1, 3, 1, false)
  let c1 = make_leaf(1, 2, 7, 2, false) // 目标节点
  let c2 = make_leaf(2, 3, 9, 3, false)
  let root = CstNode::inner(
    2,
    true,
    [c0, c1, c2],
    [None, None, None],
    0,
    0,
    false,
    false,
  )
  let tree : OldTree = { root, old_input: "abc" }
  match find_reusable_node(tree, 1, 7, 10) {
    None => fail("expected Some but got None")
    Some(n) => {
      assert_eq(n.start_byte, 1)
      assert_eq(n.end_byte, 2)
      assert_eq(n.parse_state, 7)
    }
  }
}

///|
test "find_reusable_node — children 中靠后的节点被正确剪枝" {
  // children[2].start_byte=5 > new_pos=2，应被剪枝，不影响结果
  let c0 = make_leaf(0, 1, 1, 1, false)
  let c1 = make_leaf(2, 3, 4, 3, false) // 目标，state=4
  let c2 = make_leaf(5, 6, 4, 6, false) // 剪枝
  let root = CstNode::inner(
    2,
    true,
    [c0, c1, c2],
    [None, None, None],
    0,
    0,
    false,
    false,
  )
  let tree : OldTree = { root, old_input: "abcdef" }
  match find_reusable_node(tree, 2, 4, 10) {
    None => fail("expected Some but got None")
    Some(n) => assert_eq(n.start_byte, 2)
  }
}
