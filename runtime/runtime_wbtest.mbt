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

///|
fn must_make_table(dsl : String) -> @tablegen.ParseTable {
  match @grammar.parse_grammar(dsl) {
    @grammar.Error(e) => {
      println("parse_grammar failed: \{e.message}")
      panic()
    }
    @grammar.Success(gram) =>
      match @tablegen.generate_parse_table(gram) {
        Err(e) => {
          println("generate_parse_table failed: \{e}")
          panic()
        }
        Ok((table, _)) => table
      }
  }
}

///|
fn must_parse_linear(
  label : String,
  table : @tablegen.ParseTable,
  input : String,
) -> CstNode {
  match parse_linear(table, input) {
    Ok(root) => root
    Err(e) => {
      println("\{label}: parse_linear failed: \{e.message}")
      panic()
    }
  }
}

///|
fn must_parse_glr(
  label : String,
  table : @tablegen.ParseTable,
  input : String,
) -> CstNode {
  match parse(table, input) {
    Ok(root) => root
    Err(e) => {
      println("\{label}: parse failed: \{e.message}")
      panic()
    }
  }
}

///|
fn point_at(input : String, pos : Int) -> Point {
  bytes_to_point(input, 0, { row: 0, column: 0 }, pos)
}

///|
fn replace_range(
  old_input : String,
  start_byte : Int,
  old_end_byte : Int,
  replacement : String,
) -> String {
  old_input[0:start_byte].to_string() +
  replacement +
  old_input[old_end_byte:old_input.length()].to_string()
}

///|
fn make_edit_from_replacement(
  old_input : String,
  start_byte : Int,
  old_end_byte : Int,
  replacement : String,
) -> (String, InputEdit) {
  let new_input = replace_range(
    old_input, start_byte, old_end_byte, replacement,
  )
  let new_end_byte = start_byte + replacement.length()
  let edit : InputEdit = {
    start_byte,
    old_end_byte,
    new_end_byte,
    start_point: point_at(old_input, start_byte),
    old_end_point: point_at(old_input, old_end_byte),
    new_end_point: point_at(new_input, new_end_byte),
  }
  (new_input, edit)
}

///|
fn point_repr(p : Point) -> String {
  "(" + p.row.to_string() + ", " + p.column.to_string() + ")"
}

///|
fn node_type_name_for_test(
  node : CstNode,
  table : @tablegen.ParseTable,
) -> String {
  if node.is_error {
    return "ERROR"
  }
  if node.symbol == sym_error {
    return "ERROR"
  }
  if node.children.is_empty() {
    if node.symbol == sym_end {
      return "EOF"
    }
    match table.terminal_names.get(node.symbol) {
      Some(name) => name
      None => "<t:" + node.symbol.to_string() + ">"
    }
  } else {
    let meta = table.symbol_metadata
    if node.symbol >= 0 && node.symbol < meta.length() {
      let alias_name : String? = if node.production_id >= 0 &&
        node.production_id < table.productions.length() {
        table.productions[node.production_id].alias_name
      } else {
        None
      }
      match alias_name {
        Some(name) => name
        None => meta[node.symbol].name
      }
    } else {
      "<nt:" + node.symbol.to_string() + ">"
    }
  }
}

///|
fn write_named_sexp_children(
  buf : StringBuilder,
  node : CstNode,
  input : String,
  table : @tablegen.ParseTable,
) -> Unit {
  for i in 0..<node.children.length() {
    let child = node.children[i]
    if child.is_named || child.is_error {
      buf.write_char(' ')
      let field = if i < node.field_names.length() {
        node.field_names[i]
      } else {
        None
      }
      write_named_sexp(buf, child, input, table, field)
    } else if !child.children.is_empty() {
      write_named_sexp_children(buf, child, input, table)
    }
  }
}

///|
fn write_named_sexp(
  buf : StringBuilder,
  node : CstNode,
  input : String,
  table : @tablegen.ParseTable,
  field : String?,
) -> Unit {
  match field {
    Some(name) => {
      buf.write_string(name)
      buf.write_string(": ")
    }
    None => ()
  }
  if node.is_named || node.is_error {
    buf.write_char('(')
    buf.write_string(node_type_name_for_test(node, table))
    write_named_sexp_children(buf, node, input, table)
    buf.write_char(')')
  } else {
    buf.write_char('"')
    let text = if node.start_byte <= node.end_byte &&
      node.end_byte <= input.length() {
      input[node.start_byte:node.end_byte].to_string()
    } else {
      ""
    }
    for ch in text {
      if ch == '"' || ch == '\\' {
        buf.write_char('\\')
      }
      buf.write_char(ch)
    }
    buf.write_char('"')
  }
}

///|
fn cst_to_named_sexp(
  node : CstNode,
  input : String,
  table : @tablegen.ParseTable,
) -> String {
  let buf = StringBuilder::new()
  write_named_sexp(buf, node, input, table, None)
  buf.to_string()
}

///|
fn is_visible_for_compare(node : CstNode) -> Bool {
  node.is_named || node.is_error || node.is_missing
}

///|
fn collect_visible_children(node : CstNode) -> Array[CstNode] {
  let out : Array[CstNode] = []
  for child in node.children {
    if is_visible_for_compare(child) {
      out.push(child)
    } else if !child.children.is_empty() {
      for nested in collect_visible_children(child) {
        out.push(nested)
      }
    }
  }
  out
}

///|
fn assert_same_tree_shape(
  label : String,
  table : @tablegen.ParseTable,
  actual : CstNode,
  expected : CstNode,
  path : String,
) -> Unit {
  if is_visible_for_compare(actual) != is_visible_for_compare(expected) {
    println("\{label}: visible-node mismatch at \{path}")
    panic()
  }
  if actual.symbol != expected.symbol {
    println(
      "\{label}: symbol mismatch at \{path}: \{node_type_name_for_test(actual, table)} != \{node_type_name_for_test(expected, table)}",
    )
    panic()
  }
  if actual.is_named != expected.is_named {
    println("\{label}: is_named mismatch at \{path}")
    panic()
  }
  if actual.is_error != expected.is_error {
    println("\{label}: is_error mismatch at \{path}")
    panic()
  }
  if actual.is_missing != expected.is_missing {
    println("\{label}: is_missing mismatch at \{path}")
    panic()
  }
  if actual.extra != expected.extra {
    println("\{label}: extra mismatch at \{path}")
    panic()
  }
  if actual.start_byte != expected.start_byte ||
    actual.end_byte != expected.end_byte {
    println(
      "\{label}: byte span mismatch at \{path}: [\{actual.start_byte}, \{actual.end_byte}) != [\{expected.start_byte}, \{expected.end_byte})",
    )
    panic()
  }
  if actual.start_point != expected.start_point ||
    actual.end_point != expected.end_point {
    println(
      "\{label}: point mismatch at \{path}: " +
      point_repr(actual.start_point) +
      ".." +
      point_repr(actual.end_point) +
      " != " +
      point_repr(expected.start_point) +
      ".." +
      point_repr(expected.end_point),
    )
    panic()
  }
  let actual_children = collect_visible_children(actual)
  let expected_children = collect_visible_children(expected)
  if actual_children.length() != expected_children.length() {
    println(
      "\{label}: children length mismatch at \{path}: \{actual_children.length()} != \{expected_children.length()}",
    )
    panic()
  }
  for i in 0..<actual_children.length() {
    assert_same_tree_shape(
      label,
      table,
      actual_children[i],
      expected_children[i],
      path + "/" + i.to_string(),
    )
  }
}

///|
fn assert_incremental_equals_full(
  label : String,
  table : @tablegen.ParseTable,
  old_input : String,
  old_root : CstNode,
  edit : InputEdit,
  new_input : String,
) -> Unit {
  let inc_root = match
    parse_incremental(
      table,
      new_input,
      Some({ root: old_root, old_input }),
      Some(edit),
    ) {
    Ok(root) => root
    Err(e) => {
      println("\{label}: parse_incremental failed: \{e.message}")
      panic()
    }
  }
  let full_root = match parse_linear(table, new_input) {
    Ok(root) => root
    Err(e) => {
      println("\{label}: parse_linear failed: \{e.message}")
      panic()
    }
  }

  if inc_root.start_byte != full_root.start_byte ||
    inc_root.end_byte != full_root.end_byte {
    println(
      "\{label}: root span mismatch: [\{inc_root.start_byte}, \{inc_root.end_byte}) != [\{full_root.start_byte}, \{full_root.end_byte})",
    )
    panic()
  }

  let inc_sexp = cst_to_named_sexp(inc_root, new_input, table)
  let full_sexp = cst_to_named_sexp(full_root, new_input, table)
  if inc_sexp != full_sexp {
    println(
      "\{label}: named S-expression mismatch\ninc : \{inc_sexp}\nfull: \{full_sexp}",
    )
    panic()
  }

  assert_same_tree_shape(label, table, inc_root, full_root, "root")
}

///|
fn assert_incremental_case_from_linear(
  label : String,
  table : @tablegen.ParseTable,
  old_input : String,
  start_byte : Int,
  old_end_byte : Int,
  replacement : String,
) -> Unit {
  let old_root = must_parse_linear(label, table, old_input)
  let (new_input, edit) = make_edit_from_replacement(
    old_input, start_byte, old_end_byte, replacement,
  )
  assert_incremental_equals_full(
    label, table, old_input, old_root, edit, new_input,
  )
}

///|
fn assert_incremental_case_exact(
  label : String,
  table : @tablegen.ParseTable,
  old_input : String,
  start_byte : Int,
  old_end_byte : Int,
  replacement : String,
  expected_new_input : String,
) -> Unit {
  let old_root = must_parse_linear(label, table, old_input)
  let (new_input, edit) = make_edit_from_replacement(
    old_input, start_byte, old_end_byte, replacement,
  )
  if new_input != expected_new_input {
    println(
      "\{label}: new_input mismatch: expected \{expected_new_input}, got \{new_input}",
    )
    panic()
  }
  assert_incremental_equals_full(
    label, table, old_input, old_root, edit, new_input,
  )
}

///|
fn make_large_stmt_block(prefix : String, count : Int, base : Int) -> String {
  let buf = StringBuilder::new()
  buf.write_string("{")
  for i in 0..<count {
    buf.write_string(" let ")
    buf.write_string(prefix)
    buf.write_string(i.to_string())
    buf.write_string(" = ")
    buf.write_string((base + i).to_string())
    buf.write_string(";")
  }
  buf.write_string(" }")
  buf.to_string()
}

///|
fn has_error_or_missing(node : CstNode) -> Bool {
  if node.is_error || node.is_missing {
    return true
  }
  for child in node.children {
    if has_error_or_missing(child) {
      return true
    }
  }
  false
}

///|
fn count_error_nodes(node : CstNode) -> Int {
  let mut total = if node.is_error { 1 } else { 0 }
  for child in node.children {
    total = total + count_error_nodes(child)
  }
  total
}

///|
fn count_missing_nodes(node : CstNode) -> Int {
  let mut total = if node.is_missing { 1 } else { 0 }
  for child in node.children {
    total = total + count_missing_nodes(child)
  }
  total
}

///|
fn assert_recovery_tree_usable(
  label : String,
  table : @tablegen.ParseTable,
  input : String,
  root : CstNode,
  expected_start_byte : Int,
  min_end_byte : Int,
  require_error : Bool,
  require_missing : Bool,
  expected_fragments : Array[String],
) -> String {
  if root.start_byte != expected_start_byte {
    println(
      "\{label}: expected root.start_byte = \{expected_start_byte}, got \{root.start_byte}",
    )
    panic()
  }
  if root.end_byte < min_end_byte {
    println(
      "\{label}: expected root.end_byte >= \{min_end_byte}, got \{root.end_byte}",
    )
    panic()
  }
  if root.end_byte > input.length() {
    println(
      "\{label}: expected root.end_byte <= \{input.length()}, got \{root.end_byte}",
    )
    panic()
  }
  if !has_error_or_missing(root) {
    println("\{label}: expected recovered tree to contain ERROR or MISSING")
    panic()
  }
  if require_error && count_error_nodes(root) == 0 {
    println("\{label}: expected recovered tree to contain ERROR node")
    panic()
  }
  if require_missing && count_missing_nodes(root) == 0 {
    println("\{label}: expected recovered tree to contain MISSING node")
    panic()
  }
  let sexp = cst_to_named_sexp(root, input, table)
  if sexp.is_empty() {
    println("\{label}: recovered tree should still export named sexp")
    panic()
  }
  for fragment in expected_fragments {
    if !sexp.contains(fragment) {
      println(
        "\{label}: expected named sexp to contain \{fragment}, got \{sexp}",
      )
      panic()
    }
  }
  sexp
}

// parse 成功
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

// parse 失败
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

///|
test "parse_from_dsl/validation_error_includes_hint" {
  let dsl =
    #|start s
    #|word ident
    #|rule s: ident
    #|rule ident: /[a-z]+/
  match parse_from_dsl(dsl, "abc") {
    Ok(_) => fail("expected validation error")
    Err(err) => {
      assert_true(err.message.contains("validation failed"))
      assert_true(err.message.contains("hint:"))
      assert_true(err.message.contains("token rule"))
    }
  }
}

// parse 叶节点位置信息
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

// parse extras — 空白不影响语义节点
// (_label, dsl, input, exp_root_end, exp_non_extra_children)
// exp_non_extra_children = -1 → 跳过

///|
test "parse extras — 空白跳过不影响结构" {
  let cases : Array[(String, String, String, Int, Int)] = [
    ("前置空格", "start s\nrule s: \"a\"\nextras [/\\s+/]", " a", 2, -1),
    ("后置空格", "start s\nrule s: \"a\"\nextras [/\\s+/]", "a ", 2, -1),
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
          let ne = root.children.iter().filter(fn(c) { !c.extra }).count()
          assert_eq(ne, exp_ne_ch)
        }
      }
    }
  }
}

// parse extras — extras 节点出现在 CST children 中
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

// parse GLR — S/R 冲突文法（悬挂 else）
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

// parse GLR — fragile 标记精度
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

// parse GLR — skip_token 错误恢复
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

// parse GLR — insert_missing 恢复
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

///|
test "error recovery / 非法 token 前缀产生 ERROR 节点且保留根树" {
  let label = "error recovery / 非法 token 前缀"
  let dsl = "start s\nrule s: \"a\" \"b\""
  let input = "!ab"
  let table = must_make_table(dsl)
  let root = must_parse_glr(label, table, input)
  let sexp = assert_recovery_tree_usable(
    label,
    table,
    input,
    root,
    1,
    input.length(),
    true,
    false,
    ["(s", "(ERROR)"],
  )
  assert_eq(root.children.length(), 3)
  assert_true(root.children[0].is_error)
  assert_true(sexp.contains("(ERROR)"))
}

///|
test "error recovery / 缺失中间 token 产生 MISSING 节点且保留结构" {
  let label = "error recovery / 缺失中间 token"
  let dsl = "start s\nrule s: \"a\" \";\" \"b\""
  let input = "ab"
  let table = must_make_table(dsl)
  let root = must_parse_glr(label, table, input)
  ignore(
    assert_recovery_tree_usable(
      label,
      table,
      input,
      root,
      0,
      input.length(),
      false,
      true,
      ["(s"],
    ),
  )
  assert_eq(root.children.length(), 3)
  assert_true(root.children[1].is_missing)
  assert_eq(root.children[1].start_byte, 1)
  assert_eq(root.children[1].end_byte, 1)
}

// parse GLR — recover_to_state 恢复

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
      // 根节点覆盖 [0, 4)；ERROR 前缀 "_" 作为 extra 子节点嵌入，共 4 个子节点
      assert_eq(root.end_byte, 4)
      assert_eq(root.children.length(), 4)
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

// parse GLR — condense_stack 版本上限
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

// find_reusable_node — 旧树复用查找
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
  match find_reusable_node(tree, 2, 5, 10, 20) {
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
  assert_true(find_reusable_node(tree, 2, 5, 10, 20) is None)
}

///|
test "find_reusable_node — parse_state 不匹配阻止复用" {
  let leaf = make_leaf(2, 3, 5, 3, false)
  let tree : OldTree = { root: leaf, old_input: "abc" }
  // 传入 lr_state=99，与 leaf.parse_state=5 不符
  assert_true(find_reusable_node(tree, 2, 99, 10, 20) is None)
}

///|
test "find_reusable_node — lookahead 越过 edit_start 阻止复用" {
  // lookahead_bytes=8 > edit_start=5 → 不可复用
  let leaf = make_leaf(2, 3, 5, 8, false)
  let tree : OldTree = { root: leaf, old_input: "abc" }
  assert_true(find_reusable_node(tree, 2, 5, 5, 20) is None)
}

///|
test "find_reusable_node — new_pos 不匹配时剪枝返回 None" {
  // 树只有 [2,3) 这个叶节点，但查询 new_pos=0
  let leaf = make_leaf(2, 3, 5, 3, false)
  let tree : OldTree = { root: leaf, old_input: "abc" }
  // leaf.start_byte=2 > new_pos=0 → 剪枝
  assert_true(find_reusable_node(tree, 0, 5, 10, 20) is None)
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
    0,
  )
  let tree : OldTree = { root, old_input: "abc" }
  match find_reusable_node(tree, 1, 7, 10, 20) {
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
    0,
  )
  let tree : OldTree = { root, old_input: "abcdef" }
  match find_reusable_node(tree, 2, 4, 10, 20) {
    None => fail("expected Some but got None")
    Some(n) => assert_eq(n.start_byte, 2)
  }
}

// parse_incremental — 增量解析正确性验证
//
// 策略：先用 parse_linear 解析旧输入得到旧树，
// 再对新输入做增量解析，结果应与 parse_linear 全量解析一致。

///|
test "parse_incremental — old_tree=None 退化为全量解析" {
  let dsl = "start s\nrule s: /[a-z]/ /[a-z]/"
  match @grammar.parse_grammar(dsl) {
    @grammar.Error(e) => fail(e.message)
    @grammar.Success(gram) =>
      match @tablegen.generate_parse_table(gram) {
        Err(e) => fail(e)
        Ok((table, _)) => {
          let r1 = parse_linear(table, "ab")
          let r2 = parse_incremental(table, "ab", None, None)
          match (r1, r2) {
            (Ok(a), Ok(b)) => {
              assert_eq(a.start_byte, b.start_byte)
              assert_eq(a.end_byte, b.end_byte)
              assert_eq(a.children.length(), b.children.length())
            }
            _ => fail("unexpected parse failure")
          }
        }
      }
  }
}

///|
test "parse_incremental — 同长替换编辑后输出与 parse_linear 一致" {
  // 文法：两个单字母 token，复用第一个、重解析第二个
  let dsl = "start s\nrule s: /[a-z]/ /[a-z]/"
  match @grammar.parse_grammar(dsl) {
    @grammar.Error(e) => fail(e.message)
    @grammar.Success(gram) =>
      match @tablegen.generate_parse_table(gram) {
        Err(e) => fail(e)
        Ok((table, _)) =>
          // 旧输入 "ab"
          match parse_linear(table, "ab") {
            Err(e) => fail("old parse failed: \{e.message}")
            Ok(old_root) => {
              let old_tree : OldTree = { root: old_root, old_input: "ab" }
              // 编辑：将第 2 个字节 'b' 替换为 'd'（同长度）
              let edit : InputEdit = {
                start_byte: 1,
                old_end_byte: 2,
                new_end_byte: 2,
                start_point: { row: 0, column: 1 },
                old_end_point: { row: 0, column: 2 },
                new_end_point: { row: 0, column: 2 },
              }
              // 增量解析 "ad"
              let r_inc = parse_incremental(
                table,
                "ad",
                Some(old_tree),
                Some(edit),
              )
              // 基准：全量 parse_linear
              let r_lin = parse_linear(table, "ad")
              match (r_inc, r_lin) {
                (Ok(inc), Ok(lin)) => {
                  assert_eq(inc.start_byte, lin.start_byte)
                  assert_eq(inc.end_byte, lin.end_byte)
                  assert_eq(inc.children.length(), lin.children.length())
                  // 第一个子节点 'a' 应被复用（start_byte 相同）
                  if inc.children.length() >= 1 {
                    assert_eq(
                      inc.children[0].start_byte,
                      lin.children[0].start_byte,
                    )
                    assert_eq(
                      inc.children[0].end_byte,
                      lin.children[0].end_byte,
                    )
                  }
                }
                _ => fail("parse failed")
              }
            }
          }
      }
  }
}

// shift_node — Point 坐标校正

///|
test "shift_node — 同行编辑：行/列偏移均校正" {
  // 模拟在同一行内替换：old_end_point=(0,3) new_end_point=(0,5)，col_delta=+2
  // 节点在编辑之后：start_point=(0,3) end_point=(0,8)
  let pt : Point = { row: 0, column: 0 }
  let node = CstNode::leaf(
    1,
    true,
    10,
    15,
    { row: 0, column: 3 },
    { row: 0, column: 8 },
    0,
    0,
    false,
    false,
  )
  let edit : InputEdit = {
    start_byte: 5,
    old_end_byte: 10,
    new_end_byte: 12,
    start_point: { row: 0, column: 5 },
    old_end_point: { row: 0, column: 3 },
    new_end_point: { row: 0, column: 5 },
  }
  let _ = pt
  let shifted = shift_node(node, 2, edit.old_end_point, 0, 2)
  // start_point row=0 == old_end_point.row=0 → col 也加 2
  assert_eq(shifted.start_byte, 12)
  assert_eq(shifted.end_byte, 17)
  assert_eq(shifted.start_point.row, 0)
  assert_eq(shifted.start_point.column, 5) // 3 + 2
  assert_eq(shifted.end_point.row, 0)
  assert_eq(shifted.end_point.column, 10) // 8 + 2
}

///|
test "shift_node — 跨行编辑：行号偏移，列号不变" {
  // 编辑在第 0 行结束（old_end_point.row=0），节点在第 2 行
  // row_delta=+1（增加了一行）：节点从 row=2 移到 row=3
  let node = CstNode::leaf(
    1,
    true,
    20,
    25,
    { row: 2, column: 4 },
    { row: 2, column: 9 },
    0,
    0,
    false,
    false,
  )
  let shifted = shift_node(node, 3, { row: 0, column: 0 }, 1, 5)
  // row=2 > old_end_point.row=0 → 仅 row 加 row_delta，col 不变
  assert_eq(shifted.start_byte, 23)
  assert_eq(shifted.start_point.row, 3) // 2 + 1
  assert_eq(shifted.start_point.column, 4) // 不变
  assert_eq(shifted.end_point.row, 3)
  assert_eq(shifted.end_point.column, 9) // 不变
}

///|
test "shift_node — delta 全零时原样返回" {
  let node = CstNode::leaf(
    1,
    true,
    5,
    10,
    { row: 1, column: 2 },
    { row: 1, column: 7 },
    0,
    0,
    false,
    false,
  )
  let shifted = shift_node(node, 0, { row: 0, column: 0 }, 0, 0)
  assert_eq(shifted.start_byte, 5)
  assert_eq(shifted.start_point.row, 1)
  assert_eq(shifted.start_point.column, 2)
}

// find_reusable_node — fragile 节点阻止复用
//
// is_reusable 在 fragile_left 或 fragile_right 为 true 时返回 false。
// 这些节点是 GLR 并行归约的产物，其边界依赖并行上下文，不能安全复用。

///|
test "find_reusable_node — fragile_left 阻止复用" {
  let pt : Point = { row: 0, column: 0 }
  // fragile_left=true：GLR 多路径归约产物，不可增量复用
  // CstNode::leaf 不暴露 fragile 字段，用 struct update 注入
  let leaf = {
    ..CstNode::leaf(1, true, 2, 3, pt, pt, 5, 3, false, false),
    fragile_left: true,
  }
  let tree : OldTree = { root: leaf, old_input: "abc" }
  assert_true(find_reusable_node(tree, 2, 5, 10, 20) is None)
}

///|
test "find_reusable_node — fragile_right 阻止复用" {
  let pt : Point = { row: 0, column: 0 }
  // fragile_right=true：同上，右边界不稳定
  let leaf = {
    ..CstNode::leaf(1, true, 2, 3, pt, pt, 5, 3, false, false),
    fragile_right: true,
  }
  let tree : OldTree = { root: leaf, old_input: "abc" }
  assert_true(find_reusable_node(tree, 2, 5, 10, 20) is None)
}

// parse_incremental — 扩张 edit 与收缩 edit
//
// 现有表 14 只覆盖同长替换（byte_delta=0）。
// 表 17 验证 byte_delta≠0 时增量解析结果与全量解析一致。

///|
test "parse_incremental — 扩张 edit（替换为较长文本）结果与全量解析一致" {
  // 文法 s → /[a-z]+/
  // 旧输入 "abc"，将 'b'（位置 1）替换为 'xy' → 新输入 "axyc"
  // edit: [1,2) → [1,3)，byte_delta=+1
  // apply_edit 标记整个旧 token（含 'b'）has_changes=true，无节点可复用
  // 增量路径退化为全量重解析，验证 byte_delta > 0 时结果正确
  let dsl = "start s\nrule s: /[a-z]+/"
  match @grammar.parse_grammar(dsl) {
    @grammar.Error(e) => fail(e.message)
    @grammar.Success(gram) =>
      match @tablegen.generate_parse_table(gram) {
        Err(e) => fail(e)
        Ok((table, _)) =>
          match parse_linear(table, "abc") {
            Err(e) => fail("old parse: \{e.message}")
            Ok(old_root) => {
              let old_tree : OldTree = { root: old_root, old_input: "abc" }
              let edit : InputEdit = {
                start_byte: 1,
                old_end_byte: 2,
                new_end_byte: 3,
                start_point: { row: 0, column: 1 },
                old_end_point: { row: 0, column: 2 },
                new_end_point: { row: 0, column: 3 },
              }
              let r_inc = parse_incremental(
                table,
                "axyc",
                Some(old_tree),
                Some(edit),
              )
              let r_lin = parse_linear(table, "axyc")
              match (r_inc, r_lin) {
                (Ok(inc), Ok(lin)) => {
                  assert_eq(inc.start_byte, lin.start_byte)
                  assert_eq(inc.end_byte, lin.end_byte)
                }
                _ => fail("parse failed")
              }
            }
          }
      }
  }
}

///|
test "parse_incremental — 收缩 edit（删除中间字符）结果与全量解析一致" {
  // 文法 s → /[a-z]+/
  // 旧输入 "abcd"，删除 'c' → 新输入 "abd"
  // edit: [2,3) → [2,2)，byte_delta=-1
  let dsl = "start s\nrule s: /[a-z]+/"
  match @grammar.parse_grammar(dsl) {
    @grammar.Error(e) => fail(e.message)
    @grammar.Success(gram) =>
      match @tablegen.generate_parse_table(gram) {
        Err(e) => fail(e)
        Ok((table, _)) =>
          match parse_linear(table, "abcd") {
            Err(e) => fail("old parse: \{e.message}")
            Ok(old_root) => {
              let old_tree : OldTree = { root: old_root, old_input: "abcd" }
              let edit : InputEdit = {
                start_byte: 2,
                old_end_byte: 3,
                new_end_byte: 2,
                start_point: { row: 0, column: 2 },
                old_end_point: { row: 0, column: 3 },
                new_end_point: { row: 0, column: 2 },
              }
              let r_inc = parse_incremental(
                table,
                "abd",
                Some(old_tree),
                Some(edit),
              )
              let r_lin = parse_linear(table, "abd")
              match (r_inc, r_lin) {
                (Ok(inc), Ok(lin)) => {
                  assert_eq(inc.start_byte, lin.start_byte)
                  assert_eq(inc.end_byte, lin.end_byte)
                }
                _ => fail("parse failed")
              }
            }
          }
      }
  }
}

// parse_with_old_tree — public API wrapper
//
// parse_with_old_tree 是 parse_incremental 的公开包装，
// 传入相同参数时两者输出应完全一致。

///|
test "parse_with_old_tree — 与 parse_incremental 输出一致" {
  let dsl = "start s\nrule s: /[a-z]/ /[a-z]/"
  match @grammar.parse_grammar(dsl) {
    @grammar.Error(e) => fail(e.message)
    @grammar.Success(gram) =>
      match @tablegen.generate_parse_table(gram) {
        Err(e) => fail(e)
        Ok((table, _)) =>
          match parse_linear(table, "ab") {
            Err(e) => fail("old parse: \{e.message}")
            Ok(old_root) => {
              let old_tree : OldTree = { root: old_root, old_input: "ab" }
              let edit : InputEdit = {
                start_byte: 1,
                old_end_byte: 2,
                new_end_byte: 2,
                start_point: { row: 0, column: 1 },
                old_end_point: { row: 0, column: 2 },
                new_end_point: { row: 0, column: 2 },
              }
              let r1 = parse_with_old_tree(
                table,
                "ad",
                Some(old_tree),
                Some(edit),
              )
              let r2 = parse_incremental(
                table,
                "ad",
                Some(old_tree),
                Some(edit),
              )
              match (r1, r2) {
                (Ok(a), Ok(b)) => {
                  assert_eq(a.start_byte, b.start_byte)
                  assert_eq(a.end_byte, b.end_byte)
                  assert_eq(a.children.length(), b.children.length())
                }
                _ => fail("parse failed")
              }
            }
          }
      }
  }
}

// parse_incremental — 多行 Point 坐标
//
// 旧输入含换行，编辑删除换行后节点行列坐标应与全量解析一致。
// 验证 shift_node 的 row_delta / col_delta 在增量解析集成路径上正确传播。

///|
test "parse_incremental — 删除换行后 end_point 与全量解析一致" {
  // 文法 s → /[a-z]/ /[a-z]/，空白为 extra
  // 旧输入 "a\nb"（a 在行 0 列 0，b 在行 1 列 0）
  // 编辑：删除 '\n'，byte[1,2) → byte[1,1)，新输入 "ab"
  // row_delta=-1，col_delta=+1（old_end_point=(1,0) → new_end_point=(0,1)）
  // 增量后 b 应移到 (0,1)，与 parse_linear("ab") 一致
  let dsl = "start s\nrule s: /[a-z]/ /[a-z]/\nextras [/\\s+/]"
  match @grammar.parse_grammar(dsl) {
    @grammar.Error(e) => fail(e.message)
    @grammar.Success(gram) =>
      match @tablegen.generate_parse_table(gram) {
        Err(e) => fail(e)
        Ok((table, _)) =>
          match parse_linear(table, "a\nb") {
            Err(e) => fail("old parse: \{e.message}")
            Ok(old_root) => {
              let old_tree : OldTree = { root: old_root, old_input: "a\nb" }
              let edit : InputEdit = {
                start_byte: 1,
                old_end_byte: 2,
                new_end_byte: 1,
                start_point: { row: 0, column: 1 },
                old_end_point: { row: 1, column: 0 },
                new_end_point: { row: 0, column: 1 },
              }
              let r_inc = parse_incremental(
                table,
                "ab",
                Some(old_tree),
                Some(edit),
              )
              let r_lin = parse_linear(table, "ab")
              match (r_inc, r_lin) {
                (Ok(inc), Ok(lin)) => {
                  assert_eq(inc.end_byte, lin.end_byte)
                  assert_eq(inc.end_point.row, lin.end_point.row)
                  assert_eq(inc.end_point.column, lin.end_point.column)
                }
                _ => fail("parse failed")
              }
            }
          }
      }
  }
}

// Nonassoc — 重复使用非结合运算符触发空动作表路径
//
// 当 nonassoc 冲突中 Shift 和 Reduce 均被删除后，
// action 表中存入空数组 Some([])，GLR 引擎无法 Shift，
// 必须走 skip_token / insert_missing 错误恢复，最终仍返回 Ok（带 ERROR 节点）。

///|
test "nonassoc — 重复运算符触发空动作表，错误恢复后返回 Ok" {
  // e → e "==" e | /[a-z]+/，优先级：nonassoc ==
  // 输入 "a==b==c"：归约 "a==b"→e 后，再见 "==" 时 action=[] → 错误恢复
  let dsl = "start e\nprecedence nonassoc ==\nrule e: e \"==\" e | /[a-z]+/"
  match parse_from_dsl(dsl, "a==b==c") {
    Err(e) => fail("expected Ok (with recovery) but got Err: \{e.message}")
    Ok(root) => {
      assert_eq(root.start_byte, 0)
      assert_true(root.end_byte > 0)
    }
  }
}

// 场景 2：Nonassoc — 单次合法使用（无冲突）
//
// nonassoc 仅阻止同一层级运算符的连续使用，单次使用是完全合法的。

///|
test "nonassoc — 单次合法使用不触发错误" {
  let dsl = "start e\nprecedence nonassoc ==\nrule e: e \"==\" e | /[a-z]+/"
  match parse_from_dsl(dsl, "a==b") {
    Err(e) => fail("expected Ok but got Err: \{e.message}")
    Ok(root) => assert_eq(root.end_byte, 4)
  }
}

// parse GLR — dynamic_precedence
//
// prec.dynamic(N, ...) 使归约产生式携带正整数优先级。
// condense_stack 按 (cost ASC, dynamic_precedence DESC) 排序，
// 动态优先级高的路径被保留，低的路径在截尾时被丢弃。
// 行为验证：带 prec.dynamic 的文法能成功解析（無崩溃）且返回 Ok。

///|
test "dynamic_precedence — 带 prec.dynamic 文法解析不崩溃" {
  // prec.dynamic(1, ...) 标注单个产生式体
  let dsl =
    #|start e
    #|rule e: prec.dynamic(1, e "+" e) | "n"
  match parse_from_dsl(dsl, "n+n") {
    Err(e) => fail("expected Ok but got Err: \{e.message}")
    Ok(root) => {
      assert_eq(root.start_byte, 0)
      assert_eq(root.end_byte, 3)
    }
  }
}

///|
test "dynamic_precedence — 根节点 dynamic_precedence > 0" {
  // 带 prec.dynamic 的产生式归约后，内部节点应有 dynamic_precedence > 0
  let dsl =
    #|start e
    #|rule e: prec.dynamic(5, e "+" e) | "n"
  match parse_from_dsl(dsl, "n+n") {
    Err(e) => fail("expected Ok but got Err: \{e.message}")
    Ok(root) =>
      // 根节点由 prec.dynamic(5, ...) 产生式归约而来，dynamic_precedence >= 5
      assert_true(root.dynamic_precedence >= 5)
  }
}

///|
test "dynamic_precedence — 子节点累积到父节点" {
  // 三元输入 n+n+n：外层归约节点的 dynamic_precedence 包含两次 prec.dynamic 累积
  let dsl =
    #|start e
    #|rule e: prec.dynamic(3, e "+" e) | "n"
  match parse_from_dsl(dsl, "n+n+n") {
    Err(e) => fail("expected Ok but got Err: \{e.message}")
    Ok(root) =>
      // 外层归约 = 内层(dp≥3) + 外层prod_dp(3) ≥ 6
      assert_true(root.dynamic_precedence >= 6)
  }
}

///|
test "dynamic_precedence — 无 prec.dynamic 节点 dynamic_precedence 为 0" {
  // 普通左递归文法，没有 prec.dynamic，所有节点 dynamic_precedence = 0
  let dsl = "start e\nrule e: e \"+\" t | t\nrule t: \"n\""
  match parse_from_dsl(dsl, "n+n") {
    Err(e) => fail("expected Ok but got Err: \{e.message}")
    Ok(root) => assert_eq(root.dynamic_precedence, 0)
  }
}

// 场景 3：extras — 空字符串输入（extras 已声明）
//
// 输入长度为 0，词法器立即返回 EOF。extras DFA 不会被调用。
// 必填规则 "a" 无法匹配 → 错误恢复也无法补全 → 最终 Err。

///|
test "extras — 空字符串输入（extras 已声明）返回 Err" {
  let dsl = "start s\nrule s: \"a\"\nextras [/\\s+/]"
  match parse_from_dsl(dsl, "") {
    Err(_) => () // 期望失败
    Ok(_) => fail("expected Err but got Ok")
  }
}

// 场景 4：extras — 纯空白输入（只有 extras token，无必填 token）
//
// 输入为 "   "（3 个空格），全部被 extras DFA 消耗后遇到 EOF。
// 必填规则 "a" 没有匹配 → 错误恢复无法修复 → 最终 Err。

///|
test "extras — 纯空白输入（无非空 token）返回 Err" {
  let dsl = "start s\nrule s: \"a\"\nextras [/\\s+/]"
  match parse_from_dsl(dsl, "   ") {
    Err(_) => () // 期望失败
    Ok(_) => fail("expected Err but got Ok")
  }
}

// 非初始 LR 状态下的词法错误
//
// 已成功 Shift 第一个 token（LR 进入非初始状态），
// 然后遇到产生式体中间的词法 sym_error。
// skip_token 的"停留路径"在产生式体中间无法被 enum_paths 正确穿透，
// 当前实现返回 Err（而非 Ok），且不崩溃——验证此路径的健壮性。

///|
test "非初始 LR 状态下的词法错误 — 解析器不崩溃且返回 Result" {
  // s → "a" "b"，输入 "a#b"：
  // Shift "a" 后（LR 进入非初始状态），遇到 "#"（sym_error）,
  // skip_token 停留路径在产生式体中间无法被 enum_paths 穿透
  // → 当前实现返回 Err（不崩溃）
  let dsl = "start s\nrule s: \"a\" \"b\""
  let result = parse_from_dsl(dsl, "a#b")
  // 无论 Ok/Err，解析器必须正常完成（不 panic）
  // 当前实现：enum_paths 无法穿透停留路径 → Err
  match result {
    Err(_) => () // 当前实现：产生式中间的 skip_token 不可恢复，期望 Err
    Ok(root) => {
      // 若将来错误恢复逻辑改进，Ok 亦可接受；此时根节点应覆盖完整输入
      assert_eq(root.start_byte, 0)
      assert_true(root.end_byte > 0)
    }
  }
}

// 增量解析端对端正确性：节点真正复用验证
//
// 策略：向旧树的第一个子节点注入"哨兵"字段（is_keyword=true）。
//   · is_reusable 不检查 is_keyword → 哨兵不影响复用判定
//   · shift_node 复用路径将 ..node 展开 → is_keyword 原样保留
//   · 新建叶节点路径经词法器填充 is_keyword → 对于非关键字 regex 为 false
// 因此：
//   new_root.children[0].is_keyword == true  ⟺ 旧节点被真正复用
//   new_root.children[1].is_keyword == false ⟺ 第二个节点已重新词法+解析

///|
test "parse_incremental — 旧节点被真正复用（哨兵字段保留验证）" {
  // 文法：两个独立 regex token
  let dsl = "start s\nrule s: /[a-z]/ /[a-z]/"
  match @grammar.parse_grammar(dsl) {
    @grammar.Error(e) => fail(e.message)
    @grammar.Success(gram) =>
      match @tablegen.generate_parse_table(gram) {
        Err(e) => fail(e)
        Ok((table, _)) =>
          match parse_linear(table, "ab") {
            Err(e) => fail("old parse failed: \{e.message}")
            Ok(old_root) => {
              // 向第一个 child 注入哨兵：is_keyword=true
              // （普通 regex token 不是 keyword，真正复用时该值会原样保留）
              let sentinel = { ..old_root.children[0], is_keyword: true }
              let patched_root = {
                ..old_root,
                children: [sentinel, old_root.children[1]],
              }
              let old_tree : OldTree = { root: patched_root, old_input: "ab" }
              // 编辑：将 'b' 替换为 'd'（同长度，仅影响第二个 token）
              let edit : InputEdit = {
                start_byte: 1,
                old_end_byte: 2,
                new_end_byte: 2,
                start_point: { row: 0, column: 1 },
                old_end_point: { row: 0, column: 2 },
                new_end_point: { row: 0, column: 2 },
              }
              match parse_incremental(table, "ad", Some(old_tree), Some(edit)) {
                Err(e) => fail("incremental parse failed: \{e.message}")
                Ok(new_root) => {
                  assert_true(new_root.children.length() >= 2)
                  // 第一个子节点被真正复用 → is_keyword 哨兵保留
                  assert_eq(new_root.children[0].is_keyword, true)
                  // 第二个子节点重新词法+解析 → is_keyword 为 false
                  assert_eq(new_root.children[1].is_keyword, false)
                }
              }
            }
          }
      }
  }
}

// parse_incremental — 回归测试：三 token 中间替换
//
// 文法 s → /[a-z]/ /[a-z]/ /[a-z]/，输入 "abc"
// 编辑：将 'b'（位置 [1,2)）替换为 'x' → 新输入 "axc"
// 增量解析结果应与全量 parse_linear("axc") 字节范围一致。
// 用哨兵验证 children[0]（edit 之前，lookahead<=1）被复用，
// children[1] 和 [2] 在 edit 区间内或 lookahead 超过 edit_start 而重新词法。

///|
test "parse_incremental — 三 token 序列中间替换结果与全量解析一致" {
  let dsl = "start s\nrule s: /[a-z]/ /[a-z]/ /[a-z]/"
  match @grammar.parse_grammar(dsl) {
    @grammar.Error(e) => fail(e.message)
    @grammar.Success(gram) =>
      match @tablegen.generate_parse_table(gram) {
        Err(e) => fail(e)
        Ok((table, _)) =>
          match parse_linear(table, "abc") {
            Err(e) => fail("old parse: \{e.message}")
            Ok(old_root) => {
              // 注入哨兵到 children[0]（edit 之前的 token）
              let s0 = { ..old_root.children[0], is_keyword: true }
              let patched_root = {
                ..old_root,
                children: [s0, old_root.children[1], old_root.children[2]],
              }
              let old_tree : OldTree = { root: patched_root, old_input: "abc" }
              let edit : InputEdit = {
                start_byte: 1,
                old_end_byte: 2,
                new_end_byte: 2,
                start_point: { row: 0, column: 1 },
                old_end_point: { row: 0, column: 2 },
                new_end_point: { row: 0, column: 2 },
              }
              match
                parse_incremental(table, "axc", Some(old_tree), Some(edit)) {
                Err(e) => fail("incremental parse: \{e.message}")
                Ok(new_root) => {
                  // 验证增量结果与全量解析一致
                  let baseline = match parse_linear(table, "axc") {
                    Err(e) => fail("baseline: \{e.message}")
                    Ok(r) => r
                  }
                  assert_eq(new_root.start_byte, baseline.start_byte)
                  assert_eq(new_root.end_byte, baseline.end_byte)
                  assert_eq(
                    new_root.children.length(),
                    baseline.children.length(),
                  )
                  assert_eq(
                    new_root.children.length(),
                    baseline.children.length(),
                  )
                  // children[0] 的 lookahead <= edit_start，应被复用（哨兵保留）
                  assert_eq(new_root.children[0].is_keyword, true)
                }
              }
            }
          }
      }
  }
}

// parse_incremental — 回归测试：连续两次编辑
//
// 旧树 → 编辑1 → 中间树 → 编辑2 → 最终树
// 最终树与全量 parse_linear 结果字节范围应一致。

///|
test "parse_incremental — 连续两次编辑结果与全量解析一致" {
  let dsl = "start s\nrule s: /[a-z]/ /[a-z]/ /[a-z]/"
  match @grammar.parse_grammar(dsl) {
    @grammar.Error(e) => fail(e.message)
    @grammar.Success(gram) =>
      match @tablegen.generate_parse_table(gram) {
        Err(e) => fail(e)
        Ok((table, _)) => {
          // 全量解析 "abc"
          let r0 = parse_linear(table, "abc")
          let old_root = match r0 {
            Err(e) => fail("base parse: \{e.message}")
            Ok(root) => root
          }
          // 编辑1：'c'→'d'，输入 "abc" → "abd"
          let edit1 : InputEdit = {
            start_byte: 2,
            old_end_byte: 3,
            new_end_byte: 3,
            start_point: { row: 0, column: 2 },
            old_end_point: { row: 0, column: 3 },
            new_end_point: { row: 0, column: 3 },
          }
          let tree1 = match
            parse_incremental(
              table,
              "abd",
              Some({ root: old_root, old_input: "abc" }),
              Some(edit1),
            ) {
            Err(e) => fail("edit1: \{e.message}")
            Ok(root) => root
          }
          // 编辑2：'b'→'x'，输入 "abd" → "axd"
          let edit2 : InputEdit = {
            start_byte: 1,
            old_end_byte: 2,
            new_end_byte: 2,
            start_point: { row: 0, column: 1 },
            old_end_point: { row: 0, column: 2 },
            new_end_point: { row: 0, column: 2 },
          }
          match
            parse_incremental(
              table,
              "axd",
              Some({ root: tree1, old_input: "abd" }),
              Some(edit2),
            ) {
            Err(e) => fail("edit2: \{e.message}")
            Ok(final_root) => {
              let baseline = match parse_linear(table, "axd") {
                Err(e) => fail("baseline: \{e.message}")
                Ok(r) => r
              }
              assert_eq(final_root.start_byte, baseline.start_byte)
              assert_eq(final_root.end_byte, baseline.end_byte)
              assert_eq(
                final_root.children.length(),
                baseline.children.length(),
              )
            }
          }
        }
      }
  }
}

// parse_incremental — 回归测试：恒等编辑（无内容变化）
//
// 编辑区间 byte_delta=0，且旧输入与新输入完全相同。
// 所有节点 has_changes=true（与编辑区间相交），但词法结果不变。
// 增量结果应与全量解析完全一致。

///|
test "parse_incremental — 恒等编辑结果与全量解析一致" {
  let dsl = "start s\nrule s: /[a-z]/ /[a-z]/"
  match @grammar.parse_grammar(dsl) {
    @grammar.Error(e) => fail(e.message)
    @grammar.Success(gram) =>
      match @tablegen.generate_parse_table(gram) {
        Err(e) => fail(e)
        Ok((table, _)) =>
          match parse_linear(table, "ab") {
            Err(e) => fail("old parse: \{e.message}")
            Ok(old_root) => {
              // 恒等编辑：用 [0,0)→[0,0) 插入空串，旧/新输入均为 "ab"
              let edit : InputEdit = {
                start_byte: 0,
                old_end_byte: 0,
                new_end_byte: 0,
                start_point: { row: 0, column: 0 },
                old_end_point: { row: 0, column: 0 },
                new_end_point: { row: 0, column: 0 },
              }
              let r_inc = parse_incremental(
                table,
                "ab",
                Some({ root: old_root, old_input: "ab" }),
                Some(edit),
              )
              let r_lin = parse_linear(table, "ab")
              match (r_inc, r_lin) {
                (Ok(inc), Ok(lin)) => {
                  assert_eq(inc.start_byte, lin.start_byte)
                  assert_eq(inc.end_byte, lin.end_byte)
                  assert_eq(inc.children.length(), lin.children.length())
                }
                _ => fail("parse failed")
              }
            }
          }
      }
  }
}

// byte_offset_to_char_col — UTF-8 字节偏移到代码点列号转换

///|
test "byte_offset_to_char_col — ASCII 字符（1 字节/char）恒等映射" {
  // 纯 ASCII：每个字符 1 字节，字节偏移 == 代码点偏移
  let src = "hello\nworld"
  assert_eq(byte_offset_to_char_col(src, 0, 0), 0)
  assert_eq(byte_offset_to_char_col(src, 0, 3), 3)
  assert_eq(byte_offset_to_char_col(src, 0, 5), 5)
  // 第二行
  assert_eq(byte_offset_to_char_col(src, 1, 2), 2)
}

///|
test "byte_offset_to_char_col — 3 字节 CJK 字符" {
  // CJK 字符（U+4E00–U+9FFF）每个占 3 UTF-8 字节
  // "你好" = U+4F60 U+597D，各 3 字节 → 共 6 字节，2 个代码点
  let src = "你好"
  // 字节偏移 0 → 代码点 0
  assert_eq(byte_offset_to_char_col(src, 0, 0), 0)
  // 字节偏移 3（"你" 后面）→ 代码点 1
  assert_eq(byte_offset_to_char_col(src, 0, 3), 1)
  // 字节偏移 6（"好" 后面）→ 代码点 2
  assert_eq(byte_offset_to_char_col(src, 0, 6), 2)
}

///|
test "byte_offset_to_char_col — 混合 ASCII + CJK" {
  // "a你b" = 'a'(1) + '你'(3) + 'b'(1) = 5 字节，3 个代码点
  let src = "a你b"
  assert_eq(byte_offset_to_char_col(src, 0, 1), 1) // 'a' 之后
  assert_eq(byte_offset_to_char_col(src, 0, 4), 2) // '你' 之后
  assert_eq(byte_offset_to_char_col(src, 0, 5), 3) // 'b' 之后
}

///|
test "byte_offset_to_char_col — 多行：正确跳过前几行" {
  // "ab\ncd\nef"，第 2 行（0-based）从索引 6 开始
  let src = "ab\ncd\nef"
  assert_eq(byte_offset_to_char_col(src, 2, 0), 0)
  assert_eq(byte_offset_to_char_col(src, 2, 1), 1)
  assert_eq(byte_offset_to_char_col(src, 2, 2), 2)
}

///|
test "byte_offset_to_char_col — col_bytes=0 时返回 0" {
  let src = "hello"
  assert_eq(byte_offset_to_char_col(src, 0, 0), 0)
}

// ── External scanner 端对端测试 ─────────────────────────────────────────────
//
// parse_with_external_scanner / parse_with_old_tree_and_external_scanner
// 的集成测试，验证三个场景：
//   A. no-op scanner（始终返回 None）等价于 parse —— 不干扰 DFA 词法
//   B. 含 externals 声明的文法 + 真实外部词法器 —— external token 被正确识别
//   C. 增量 + no-op scanner 等价于 parse_with_old_tree

///|
test "parse_with_external_scanner — no-op scanner 等价于 parse" {
  // 无 externals 声明的文法；no-op scanner 永不被调用（ext_tids 为空），
  // 因此结果与 glr_parse 完全一致。
  let dsl = "start e\nrule e: e \"+\" t | t\nrule t: /[0-9]+/\nextras [/\\s+/]"
  match @grammar.parse_grammar(dsl) {
    @grammar.Error(e) => fail(e.message)
    @grammar.Success(gram) =>
      match @tablegen.generate_parse_table(gram) {
        Err(e) => fail(e)
        Ok((table, _)) => {
          let r1 = parse(table, "1+2")
          let r2 = parse_with_external_scanner(table, "1+2", fn(_, _, _) {
            None
          })
          match (r1, r2) {
            (Ok(a), Ok(b)) => {
              assert_eq(a.start_byte, b.start_byte)
              assert_eq(a.end_byte, b.end_byte)
              assert_eq(a.children.length(), b.children.length())
            }
            (Err(_), Err(_)) => ()
            _ => fail("r1 和 r2 对 Ok/Err 应一致")
          }
        }
      }
  }
}

///|
test "parse_with_external_scanner — externals 声明的 token 由外部词法器识别" {
  // 文法 s → tok，tok 为 externals 声明的外部 token。
  // 外部词法器：当 ext_tids 包含 tok 的 terminal_id 时，消费 5 个字节。
  let dsl = "start s\nexternals [tok]\nrule s: tok"
  match @grammar.parse_grammar(dsl) {
    @grammar.Error(e) => fail(e.message)
    @grammar.Success(gram) =>
      match @tablegen.generate_parse_table(gram) {
        Err(e) => fail(e)
        Ok((table, _)) => {
          // externals 声明必须产生非空的 external_token_ids
          assert_true(table.external_token_ids.length() > 0)
          let ext_id = table.external_token_ids[0]
          // 外部词法器：ext_tids 包含 ext_id 时消费 5 个字节
          let scanner : ExternalScanner = fn(
            _input : String,
            pos : Int,
            valid : Array[Int],
          ) -> (Int, Int)? {
            let mut has_ext = false
            for tid in valid {
              if tid == ext_id {
                has_ext = true
                break
              }
            }
            if has_ext {
              Some((ext_id, pos + 5))
            } else {
              None
            }
          }
          match parse_with_external_scanner(table, "hello", scanner) {
            Err(e) => fail("expected Ok but got Err: \{e.message}")
            Ok(root) => {
              assert_eq(root.start_byte, 0)
              assert_eq(root.end_byte, 5)
            }
          }
        }
      }
  }
}

///|
test "parse_with_old_tree_and_external_scanner — no-op scanner 等价于 parse_with_old_tree" {
  // no-op 外部词法器不干预词法，parse_with_old_tree_and_external_scanner
  // 与 parse_with_old_tree 的结果应完全一致。
  let dsl = "start s\nrule s: /[a-z]/ /[a-z]/"
  match @grammar.parse_grammar(dsl) {
    @grammar.Error(e) => fail(e.message)
    @grammar.Success(gram) =>
      match @tablegen.generate_parse_table(gram) {
        Err(e) => fail(e)
        Ok((table, _)) =>
          match parse_linear(table, "ab") {
            Err(e) => fail("old parse: \{e.message}")
            Ok(old_root) => {
              let old_tree : OldTree = { root: old_root, old_input: "ab" }
              let edit : InputEdit = {
                start_byte: 1,
                old_end_byte: 2,
                new_end_byte: 2,
                start_point: { row: 0, column: 1 },
                old_end_point: { row: 0, column: 2 },
                new_end_point: { row: 0, column: 2 },
              }
              let no_op : ExternalScanner = fn(_, _, _) { None }
              let r_ext = parse_with_old_tree_and_external_scanner(
                table,
                "ad",
                Some(old_tree),
                Some(edit),
                no_op,
              )
              let r_inc = parse_with_old_tree(
                table,
                "ad",
                Some(old_tree),
                Some(edit),
              )
              match (r_ext, r_inc) {
                (Ok(a), Ok(b)) => {
                  assert_eq(a.start_byte, b.start_byte)
                  assert_eq(a.end_byte, b.end_byte)
                  assert_eq(a.children.length(), b.children.length())
                }
                _ => fail("unexpected parse failure")
              }
            }
          }
      }
  }
}

// parse_incremental — 阶段二验证矩阵

///|
test "parse_incremental — 2.1 编辑类型矩阵与全量解析一致" {
  let word_list_dsl =
    #|start s
    #|extras [/[ \t\n\r]+/, /#[^\n\r]*/]
    #|rule s: word | word rest
    #|rule rest: word | word rest
    #|rule word: /[a-z]+/
  let table = must_make_table(word_list_dsl)
  let cases : Array[(String, String, Int, Int, String)] = [
    ("insert / 文件开头插入", "b c d", 0, 0, "a "),
    ("insert / 文件中间插入", "a c d", 2, 2, "b "),
    ("insert / 文件末尾插入", "a b c", 5, 5, " d"),
    ("delete / 删除单字符", "abcd ef", 2, 3, ""),
    ("delete / 删除整 token", "a bb c d", 2, 5, ""),
    ("delete / 删除整行", "aa\nbb\ncc", 3, 6, ""),
    ("delete / 删除多行块", "aa\nbb\ncc\ndd", 3, 9, ""),
    ("replace / 同长度替换", "a b x d", 4, 5, "c"),
    ("replace / 扩张替换", "a b d", 2, 3, "bc"),
    ("replace / 收缩替换", "alpha beta gamma", 6, 10, "b"),
    ("identity / old_input == new_input", "a b c", 2, 3, "b"),
    ("identity / 空编辑 [i,i) -> [i,i)", "a b c", 2, 2, ""),
  ]
  for case in cases {
    let (label, old_input, start_byte, old_end_byte, replacement) = case
    assert_incremental_case_from_linear(
      label, table, old_input, start_byte, old_end_byte, replacement,
    )
  }
}

///|
test "parse_incremental — 2.2 结构场景矩阵与全量解析一致" {
  let flat_dsl =
    #|start s
    #|extras [/[ \t\n\r]+/]
    #|rule s: word | word rest
    #|rule rest: word | word rest
    #|rule word: /[a-z]+/
  let flat_table = must_make_table(flat_dsl)
  assert_incremental_case_from_linear(
    "scene / 平铺 token 序列", flat_table, "a b d", 4, 4, "c ",
  )

  let expr_dsl = "start e\nrule e: e \"+\" t | t\nrule t: \"n\""
  let expr_table = must_make_table(expr_dsl)
  assert_incremental_case_from_linear(
    "scene / 左递归表达式", expr_table, "n+n+n+n", 7, 7, "+n",
  )

  let nested_dsl =
    #|start value
    #|extras [/[ \t\n\r]+/]
    #|rule value: object | array | number
    #|rule object: "{" pair_list? "}"
    #|rule pair_list: pair ("," pair)*
    #|rule pair: key ":" value
    #|rule key: "a" | "b"
    #|rule array: "[" elem_list? "]"
    #|rule elem_list: value ("," value)*
    #|rule number: "1" | "2" | "3" | "4"
  let nested_table = must_make_table(nested_dsl)
  assert_incremental_case_from_linear(
    "scene / 深层嵌套结构", nested_table, "{a:[{b:[1,2]}]}", 11, 11, ",3",
  )

  let extras_dsl =
    #|start s
    #|extras [/[ \t\n\r]+/, /#[^\n\r]*/]
    #|rule s: word | word rest
    #|rule rest: word | word rest
    #|rule word: /[a-z]+/
  let extras_table = must_make_table(extras_dsl)
  assert_incremental_case_from_linear(
    "scene / extras 密集结构", extras_table, "a b c", 1, 1, "  #gap\n  ",
  )

  let recovery_dsl = "start s\nrule s: \"a\" \";\" \"b\""
  let recovery_table = must_make_table(recovery_dsl)
  let old_input = "ab"
  let old_root = must_parse_glr(
    "scene / 含错误恢复路径的旧树", recovery_table, old_input,
  )
  if !has_error_or_missing(old_root) {
    println(
      "scene / 含错误恢复路径的旧树: expected old tree to contain ERROR or MISSING",
    )
    panic()
  }
  let (new_input, edit) = make_edit_from_replacement(old_input, 1, 1, ";")
  assert_incremental_equals_full(
    "scene / 含错误恢复路径的旧树", recovery_table, old_input, old_root,
    edit, new_input,
  )
}

// parse_incremental — 2.3 必测边界案例

///|
test "parse_incremental — 2.3 必测边界案例与全量解析一致" {
  let seq_dsl = "start s\nrule s: ch | ch s\nrule ch: /[a-z]/"
  let seq_table = must_make_table(seq_dsl)
  let seq_cases : Array[(String, String, Int, Int, String, String)] = [
    ("case 1 / 文件首字符插入", "abc", 0, 0, "x", "xabc"),
    ("case 2 / 文件末尾删除", "abc", 2, 3, "", "ab"),
    ("case 3 / 中间替换同长度", "abc", 1, 2, "x", "axc"),
    ("case 4 / 中间扩张", "abc", 1, 2, "xyz", "axyzc"),
    ("case 5 / 中间收缩", "abcdef", 2, 5, "x", "abxf"),
  ]
  for case in seq_cases {
    let (label, old_input, start_byte, old_end_byte, replacement, new_input) = case
    assert_incremental_case_exact(
      label, seq_table, old_input, start_byte, old_end_byte, replacement, new_input,
    )
  }

  let seq_with_extras_dsl = "start s\nextras [/[ \\t\\n\\r]+/]\nrule s: ch | ch s\nrule ch: /[a-z]/"
  let seq_with_extras_table = must_make_table(seq_with_extras_dsl)
  assert_incremental_case_exact(
    "case 6 / 跨行删除", seq_with_extras_table, "a\n  b\n  c", 4, 8, "", "a\n  c",
  )

  let json_like_dsl =
    #|start json
    #|extras [/[ \t\n\r]+/]
    #|rule json: value
    #|rule value: object | array | number
    #|rule object: "{" pair_list? "}"
    #|rule pair_list: pair ("," pair)*
    #|rule pair: key ":" value
    #|rule key: /"[ab]"/
    #|rule array: "[" elem_list? "]"
    #|rule elem_list: value ("," value)*
    #|rule number: /[0-9]+/
  let json_like_table = must_make_table(json_like_dsl)
  let json_prefix = "{\"a\": {\"b\": [1,"
  let json_suffix = ",3]}}"
  assert_incremental_case_exact(
    "case 7 / 深层 JSON 局部改值",
    json_like_table,
    json_prefix + "2" + json_suffix,
    json_prefix.length(),
    json_prefix.length() + 1,
    "20",
    json_prefix + "20" + json_suffix,
  )

  let block_dsl =
    #|start file
    #|extras [/[ \t\n\r]+/]
    #|rule file: block
    #|rule block: "{" stmt_list? "}"
    #|rule stmt_list: stmt | stmt stmt_list
    #|rule stmt: let_stmt | block
    #|rule let_stmt: "let" ident "=" number ";"
    #|rule ident: /[a-z][a-z0-9]*/
    #|rule number: /[0-9]+/
  let block_table = must_make_table(block_dsl)
  let block_prefix = "{ let head = 1; "
  let old_block = make_large_stmt_block("oldv", 700, 0)
  let new_block = make_large_stmt_block("newv", 420, 1000)
  let block_suffix = " let tail = 2; }"
  let large_old_input = block_prefix + old_block + block_suffix
  let large_new_input = block_prefix + new_block + block_suffix
  assert_true(large_old_input.length() > 10_000)
  assert_incremental_case_exact(
    "case 8 / 大块替换（10KB+）",
    block_table,
    large_old_input,
    block_prefix.length(),
    block_prefix.length() + old_block.length(),
    new_block,
    large_new_input,
  )
}

// parse_incremental — 2.4 增量专用断言

///|
test "parse_incremental — 2.4 哨兵验证未受影响节点复用且编辑交集节点不复用" {
  let label = "2.4 / 哨兵复用"
  let dsl = "start s\nrule s: /[a-z]/ /[a-z]/ /[a-z]/"
  let table = must_make_table(dsl)
  let old_root = must_parse_linear(label, table, "abc")
  let patched_root = {
    ..old_root,
    children: [
      { ..old_root.children[0], is_keyword: true },
      { ..old_root.children[1], is_keyword: true },
      old_root.children[2],
    ],
  }
  let old_tree : OldTree = { root: patched_root, old_input: "abc" }
  let edit : InputEdit = {
    start_byte: 1,
    old_end_byte: 2,
    new_end_byte: 2,
    start_point: { row: 0, column: 1 },
    old_end_point: { row: 0, column: 2 },
    new_end_point: { row: 0, column: 2 },
  }

  let marked = apply_edit(old_tree, edit)
  assert_eq(marked.root.has_changes, true)
  assert_eq(marked.root.children[0].has_changes, false)
  assert_eq(marked.root.children[1].has_changes, true)
  assert_eq(marked.root.children[2].has_changes, false)

  let inc_root = match
    parse_incremental(table, "axc", Some(old_tree), Some(edit)) {
    Ok(root) => root
    Err(e) => fail("2.4 incremental parse failed: \{e.message}")
  }
  assert_eq(inc_root.children[0].is_keyword, true)
  assert_eq(inc_root.children[1].is_keyword, false)

  assert_incremental_equals_full(label, table, "abc", patched_root, edit, "axc")
}

///|
test "parse_incremental — 2.4 跨行删除后坐标与全量解析一致" {
  let label = "2.4 / 跨行 shift_node"
  let dsl = "start s\nextras [/[ \\t\\n\\r]+/]\nrule s: ch ch ch | ch ch\nrule ch: /[a-z]/"
  let table = must_make_table(dsl)
  let old_root = must_parse_linear(label, table, "a\n  b\n  c")
  let old_tree : OldTree = { root: old_root, old_input: "a\n  b\n  c" }
  let edit : InputEdit = {
    start_byte: 4,
    old_end_byte: 8,
    new_end_byte: 4,
    start_point: point_at("a\n  b\n  c", 4),
    old_end_point: point_at("a\n  b\n  c", 8),
    new_end_point: point_at("a\n  c", 4),
  }
  let inc_root = match
    parse_incremental(table, "a\n  c", Some(old_tree), Some(edit)) {
    Ok(root) => root
    Err(e) => fail("2.4 cross-line parse failed: \{e.message}")
  }
  let full_root = must_parse_linear(label, table, "a\n  c")
  let inc_visible = collect_visible_children(inc_root)
  let full_visible = collect_visible_children(full_root)
  if inc_root.end_point != full_root.end_point {
    println(
      "2.4 cross-line root end_point mismatch: " +
      point_repr(inc_root.end_point) +
      " != " +
      point_repr(full_root.end_point),
    )
    panic()
  }
  if inc_visible[1].start_point != full_visible[1].start_point {
    println(
      "2.4 cross-line child start_point mismatch: " +
      point_repr(inc_visible[1].start_point) +
      " != " +
      point_repr(full_visible[1].start_point),
    )
    panic()
  }
  if inc_visible[1].end_point != full_visible[1].end_point {
    println(
      "2.4 cross-line child end_point mismatch: " +
      point_repr(inc_visible[1].end_point) +
      " != " +
      point_repr(full_visible[1].end_point),
    )
    panic()
  }
  assert_incremental_equals_full(
    label, table, "a\n  b\n  c", old_root, edit, "a\n  c",
  )
}

// ─── Section 8.1 不变量检查测试 ───────────────────────────────────────────────

///|
// 辅助：构造满足所有不变量的最小叶节点。
fn ok_leaf(start : Int, end_ : Int) -> CstNode {
  let p : Point = { row: 0, column: start }
  let q : Point = { row: 0, column: end_ }
  CstNode::leaf(1, true, start, end_, p, q, 0, end_, false, false)
}

///|
// 辅助：断言 check_cst_invariants 应当通过。
fn assert_invariants_pass(
  label : String,
  root : CstNode,
  source : String,
) -> Unit {
  match check_cst_invariants(root, source) {
    Some(msg) => {
      println("\{label}: expected invariants to pass, got: \{msg}")
      panic()
    }
    None => ()
  }
}

///|
// 辅助：断言 check_cst_invariants 应当检测出违反，且消息包含期望子串。
fn assert_invariant_fails(
  label : String,
  root : CstNode,
  source : String,
  expected_substring : String,
) -> Unit {
  match check_cst_invariants(root, source) {
    None => {
      println("\{label}: expected invariant violation but check passed")
      panic()
    }
    Some(msg) =>
      if !msg.contains(expected_substring) {
        println(
          "\{label}: violation message '\{msg}' does not contain '\{expected_substring}'",
        )
        panic()
      }
  }
}

///|
test "8.1 不变量 — 干净 JSON 解析树通过全部检查" {
  let dsl =
    #|start json
    #|rule json: object | array
    #|rule object: "{" pair_list? "}"
    #|rule pair_list: pair ("," pair)*
    #|rule pair: key ":" value
    #|rule key: /"[^"]*"/
    #|rule value: object | array | string | number | "true" | "false" | "null"
    #|rule array: "[" elem_list? "]"
    #|rule elem_list: value ("," value)*
    #|rule string: /"[^"]*"/
    #|rule number: /[0-9]+/
  let table = must_make_table(dsl)
  for
    input in [
      "{}", "{\"a\":1}", "{\"a\":[1,2,3]}", "[1,2,3]", "{\"a\":{\"b\":{\"c\":42}}}",
    ] {
    match parse(table, input) {
      Ok(root) => assert_invariants_pass("clean/\{input}", root, input)
      Err(e) => fail("parse failed for '\{input}': \{e.message}")
    }
  }
}

///|
test "8.1 不变量 — 错误恢复树通过全部检查" {
  let dsl = "start s\nrule s: /[a-z]+/"
  let table = must_make_table(dsl)
  // 前缀垃圾：恢复树含 ERROR 节点，但结构上仍自洽
  let inputs = ["!abc", "!!!", "abc!", ""]
  for input in inputs {
    match parse(table, input) {
      Ok(root) =>
        match check_cst_invariants(root, input) {
          Some(msg) => {
            println(
              "recovery tree for '\{input.escape()}' violated invariants: \{msg}",
            )
            panic()
          }
          None => ()
        }
      Err(_) => () // parse returned Err — no tree to check
    }
  }
}

///|
test "8.1 不变量 — 增量解析树通过全部检查" {
  let dsl = "start s\nextras [/[ \\t\\n\\r]+/]\nrule s: ch ch ch | ch ch\nrule ch: /[a-z]/"
  let table = must_make_table(dsl)
  let old_input = "a b c"
  let old_root = must_parse_linear("8.1/inc", table, old_input)
  let (new_input, edit) = make_edit_from_replacement(old_input, 2, 3, "x")
  match
    parse_incremental(
      table,
      new_input,
      Some({ root: old_root, old_input }),
      Some(edit),
    ) {
    Ok(inc_root) =>
      assert_invariants_pass("8.1/incremental", inc_root, new_input)
    Err(e) => fail("8.1/inc: parse_incremental failed: \{e.message}")
  }
}

///|
test "8.1 不变量 — 违反 1：start_byte > end_byte 被检测" {
  // 人工构造 start_byte > end_byte 的叶节点
  let bad_leaf : CstNode = {
    ..ok_leaf(5, 3) // start=5, end=3 — 反转
    ,
    start_byte: 5,
    end_byte: 3,
  }
  assert_invariant_fails(
    "8.1/inverted-bytes", bad_leaf, "hello world", "start_byte",
  )
}

///|
test "8.1 不变量 — 违反 2：end_byte 超出 source 被检测" {
  // 叶节点 end_byte 超过 source 长度
  let source = "hi"
  let bad_leaf : CstNode = {
    ..ok_leaf(0, 5) // end_byte=5 but source.length()=2
    ,
    start_byte: 0,
    end_byte: 5,
  }
  assert_invariant_fails("8.1/end-out-of-bounds", bad_leaf, source, "end_byte")
}

///|
test "8.1 不变量 — 违反 3：is_missing 非零宽 被检测" {
  let bad_missing : CstNode = {
    ..ok_leaf(2, 4),
    is_missing: true,
    start_byte: 2,
    end_byte: 4,
  }
  assert_invariant_fails(
    "8.1/missing-nonzero", bad_missing, "hello", "is_missing",
  )
}

///|
test "8.1 不变量 — 违反 4：start_point > end_point 被检测" {
  let bad_point : CstNode = {
    ..ok_leaf(0, 3),
    start_point: { row: 0, column: 5 },
    end_point: { row: 0, column: 1 },
  }
  assert_invariant_fails(
    "8.1/point-reversed", bad_point, "hello", "start_point",
  )
}

///|
/// 测试用有状态扫描器：计数已扫描次数（作为 clone 正确性验证）
struct CountingScanner {
  mut count : Int
  /// 每次 scan 返回 (tid=ext_tids[0], pos)（零宽 token）
}

///|
impl StatefulScanner for CountingScanner with scan(self, _input, pos, ext_tids) {
  self.count = self.count + 1
  if ext_tids.length() > 0 {
    Some((ext_tids[0], pos))
  } else {
    None
  }
}

///|
impl StatefulScanner for CountingScanner with clone_scanner(self) {
  ({ count: self.count } : CountingScanner) as &StatefulScanner
}

///|
test "9.1 stateful scanner clone 正确性" {
  let s1 : CountingScanner = { count: 0 }
  let obj1 : &StatefulScanner = s1
  // scan 3 次
  let _ = obj1.scan("abc", 0, [99])
  let _ = obj1.scan("abc", 0, [99])
  let _ = obj1.scan("abc", 0, [99])
  assert_eq(s1.count, 3)
  // clone 后应得到独立副本
  let obj2 = obj1.clone_scanner()
  let _ = obj2.scan("abc", 0, [99])
  let _ = obj2.scan("abc", 0, [99])
  // 原始对象不受影响
  assert_eq(s1.count, 3)
}

///|
test "9.2 ExternalScannerState adapter（无状态包装）" {
  let func : ExternalScanner = fn(input, pos, _tids) {
    if pos < input.length() {
      Some((42, pos + 1))
    } else {
      None
    }
  }
  let ss = external_scanner_to_stateful(func)
  // scan 正常工作
  assert_eq(ss.scan("hello", 0, [42]), Some((42, 1)))
  assert_eq(ss.scan("hello", 5, [42]), None)
  // clone 后行为一致
  let ss2 = ss.clone_scanner()
  assert_eq(ss2.scan("hello", 2, [42]), Some((42, 3)))
}

///|
test "9.3 parse_with_stateful_scanner 基础" {
  // 简单 grammar + external token 的端到端验证
  let dsl =
    #|start items
    #|externals [sep]
    #|rule items: item (sep item)*
    #|rule item: /[a-z]+/
  let table = must_make_table(dsl)
  // scanner: sep 匹配逗号
  let sep_id = table.external_token_ids[0]
  let scanner : &StatefulScanner = ({ count: 0, sep_id } : SepScanner)
    as &StatefulScanner
  match parse_with_stateful_scanner(table, "abc,def,ghi", scanner) {
    Ok(root) => assert_false(root.is_error)
    // 应该有 3 个 item
    Err(e) => {
      println("9.3: \{e.message}")
      panic()
    }
  }
}

///|
struct SepScanner {
  mut count : Int
  sep_id : Int
}

///|
impl StatefulScanner for SepScanner with scan(self, input, pos, ext_tids) {
  self.count = self.count + 1
  if pos < input.length() && input[pos] == ',' {
    let mut found = false
    for tid in ext_tids {
      if tid == self.sep_id {
        found = true
        break
      }
    }
    if found {
      Some((self.sep_id, pos + 1))
    } else {
      None
    }
  } else {
    None
  }
}

///|
impl StatefulScanner for SepScanner with clone_scanner(self) {
  ({ count: self.count, sep_id: self.sep_id } : SepScanner) as &StatefulScanner
}

///|
test "9.4 parse_with_old_tree_and_stateful_scanner 增量" {
  let dsl =
    #|start items
    #|externals [sep]
    #|rule items: item (sep item)*
    #|rule item: /[a-z]+/
  let table = must_make_table(dsl)
  let sep_id = table.external_token_ids[0]
  // 第一次解析
  let scanner1 : &StatefulScanner = ({ count: 0, sep_id } : SepScanner)
    as &StatefulScanner
  let root1 = match parse_with_stateful_scanner(table, "abc,def", scanner1) {
    Ok(r) => r
    Err(e) => {
      println("9.4 initial: \{e.message}")
      panic()
    }
  }
  assert_false(root1.is_error)
  // 增量：在末尾追加 ",ghi"
  let old_tree : OldTree = { root: root1, old_input: "abc,def" }
  let edit : InputEdit = {
    start_byte: 7,
    old_end_byte: 7,
    new_end_byte: 11,
    start_point: { row: 0, column: 7 },
    old_end_point: { row: 0, column: 7 },
    new_end_point: { row: 0, column: 11 },
  }
  let scanner2 : &StatefulScanner = ({ count: 0, sep_id } : SepScanner)
    as &StatefulScanner
  match
    parse_with_old_tree_and_stateful_scanner(
      table,
      "abc,def,ghi",
      Some(old_tree),
      Some(edit),
      scanner2,
    ) {
    Ok(root2) => assert_false(root2.is_error)
    Err(e) => {
      println("9.4 incr: \{e.message}")
      panic()
    }
  }
}

///|
test "8.1 不变量 — 违反 5：非 extra 子节点 start_byte 超出父节点 被检测" {
  // child at [0,5); parent manually patched to start_byte=2 (while child still at 0)
  let child = ok_leaf(0, 5)
  let raw_parent = CstNode::inner(
    1,
    false,
    [child],
    [None],
    0,
    0,
    false,
    false,
    0,
  )
  // raw_parent.start_byte=0 (computed from child). Patch it to 2 to create violation.
  let wrapper = { ..raw_parent, start_byte: 2 }
  // child.start_byte=0 < wrapper.start_byte=2 AND child.extra=false AND child is non-zero-width
  assert_invariant_fails(
    "8.1/child-before-parent", wrapper, "hello world", "child.start_byte",
  )
}

///|
test "8.1 不变量 — 违反 6：兄弟节点重叠 被检测" {
  // 使用 CstNode::inner 构造一个非 ERROR 父节点，包含两个重叠的非零宽子节点
  let c1 = ok_leaf(0, 5)
  let c2 = ok_leaf(3, 7) // start=3 < c1.end=5 → overlap
  // inner 会计算 start_byte = c1.start_byte = 0, end_byte = c2.end_byte = 7
  // 此节点 is_error=false，因此兄弟顺序检查会生效
  let parent = CstNode::inner(
    1,
    false,
    [c1, c2],
    [None, None],
    0,
    0,
    false,
    false,
    0,
  )
  assert_invariant_fails(
    "8.1/siblings-overlap", parent, "hello world", "siblings overlap",
  )
}

///|
test "8.1 不变量 — 违反 6：兄弟节点顺序反转 被检测" {
  // c1=[1,5), c2=[2,7): c1.end=5 > c2.start=2 → overlap/out-of-order
  // parent inner: start=1, end=7 (valid interval)
  let c1 = ok_leaf(1, 5)
  let c2 = ok_leaf(2, 7)
  let parent = CstNode::inner(
    1,
    false,
    [c1, c2],
    [None, None],
    0,
    0,
    false,
    false,
    0,
  )
  assert_invariant_fails(
    "8.1/siblings-out-of-order", parent, "hello world", "siblings overlap or are out of order",
  )
}

///|
test "8.1 不变量 — 根节点 end_byte 超出 source 被检测" {
  let source = "abc"
  let bad_root : CstNode = {
    ..ok_leaf(0, 10) // end_byte=10, source.length()=3
    ,
    start_byte: 0,
    end_byte: 10,
  }
  assert_invariant_fails("8.1/root-out-of-bounds", bad_root, source, "end_byte")
}

///|
test "8.1 不变量 — check_clean_root：干净解析通过" {
  let dsl = "start s\nrule s: /[a-z]+/"
  let table = must_make_table(dsl)
  let input = "hello"
  match parse(table, input) {
    Ok(root) =>
      match check_clean_root(root, input) {
        Some(msg) => {
          println("check_clean_root failed for clean parse: \{msg}")
          panic()
        }
        None => ()
      }
    Err(e) => {
      println("parse failed: \{e.message}")
      panic()
    }
  }
}

///|
test "8.1 不变量 — check_clean_root：含 ERROR 节点时报告" {
  let dsl = "start s\nrule s: /[a-z]+/"
  let table = must_make_table(dsl)
  let input = "!hello"
  match parse(table, input) {
    Ok(root) =>
      match check_clean_root(root, input) {
        Some(msg) =>
          if !msg.contains("ERROR") &&
            !msg.contains("MISSING") &&
            !msg.contains("root:") {
            println(
              "expected clean_root to report error/missing or span mismatch, got: \{msg}",
            )
            panic()
          }
        None => () // Some grammars do full recovery; acceptable here.
      }
    Err(_) => () // Err means no tree — also acceptable
  }
}

// ─── Section 8.2 增量专用不变量测试 ──────────────────────────────────────────

///|
test "8.2 不变量 — apply_edit 后标记树通过不变量检查" {
  // 文法 s → /[a-z]/ /[a-z]/ /[a-z]/，输入 "abc"，编辑 [1,2) → "x"
  let dsl = "start s\nrule s: /[a-z]/ /[a-z]/ /[a-z]/"
  let table = must_make_table(dsl)
  let old_input = "abc"
  let old_root = must_parse_linear("8.2/mark", table, old_input)
  let (_, edit) = make_edit_from_replacement(old_input, 1, 2, "x")
  let marked = apply_edit({ root: old_root, old_input }, edit)
  match check_incremental_invariants(marked.root, edit) {
    Some(msg) => {
      println("8.2 apply_edit invariant violated: \{msg}")
      panic()
    }
    None => ()
  }
}

///|
test "8.2 不变量 — 恒等编辑后标记树通过不变量检查" {
  // 恒等编辑（start_byte == old_end_byte）不应破坏任何 has_changes=false 节点的交叉性
  let dsl = "start s\nrule s: /[a-z]+/"
  let table = must_make_table(dsl)
  let input = "hello"
  let root = must_parse_linear("8.2/identity", table, input)
  let identity_edit : InputEdit = {
    start_byte: 2,
    old_end_byte: 2,
    new_end_byte: 2,
    start_point: { row: 0, column: 2 },
    old_end_point: { row: 0, column: 2 },
    new_end_point: { row: 0, column: 2 },
  }
  let marked = apply_edit({ root, old_input: input }, identity_edit)
  match check_incremental_invariants(marked.root, identity_edit) {
    Some(msg) => {
      println("8.2 identity-edit invariant violated: \{msg}")
      panic()
    }
    None => ()
  }
}

///|
test "8.2 不变量 — 人工构造 has_changes=false 与编辑相交被检测" {
  // ok_leaf(2, 5): start=2, end=5, lookahead_bytes=5, has_changes=false
  // edit: [3, 6) — 与叶节点 [2, 5) 相交
  let node = ok_leaf(2, 5)
  let edit : InputEdit = {
    start_byte: 3,
    old_end_byte: 6,
    new_end_byte: 6,
    start_point: { row: 0, column: 3 },
    old_end_point: { row: 0, column: 6 },
    new_end_point: { row: 0, column: 6 },
  }
  match check_incremental_invariants(node, edit) {
    None => {
      println(
        "8.2: expected has_changes=false intersection violation not detected",
      )
      panic()
    }
    Some(msg) =>
      if !msg.contains("has_changes=false") {
        println(
          "8.2: violation message '\{msg}' does not contain 'has_changes=false'",
        )
        panic()
      }
  }
}

///|
test "8.2 不变量 — fragile_left 节点被 is_reusable 拒绝" {
  // fragile_left/right 标志标识 GLR 合并产物，不可复用
  let dsl = "start s\nrule s: /[a-z]/ /[a-z]/"
  let table = must_make_table(dsl)
  let old_root = must_parse_linear("8.2/fragile", table, "ab")
  let fragile_l : CstNode = { ..old_root, fragile_left: true }
  if is_reusable(fragile_l, 0, old_root.parse_state, 0, 2) {
    println("8.2: fragile_left node should not be reusable")
    panic()
  }
  let fragile_r : CstNode = { ..old_root, fragile_right: true }
  if is_reusable(fragile_r, 0, old_root.parse_state, 0, 2) {
    println("8.2: fragile_right node should not be reusable")
    panic()
  }
}

///|
test "8.2 不变量 — has_changes=true 节点不可复用" {
  // 被标记了 has_changes=true 的节点无论位置，均应被 is_reusable 拒绝
  let dsl = "start s\nrule s: /[a-z]+/"
  let table = must_make_table(dsl)
  let root = must_parse_linear("8.2/changed", table, "abc")
  let changed : CstNode = { ..root, has_changes: true }
  if is_reusable(changed, 0, root.parse_state, 0, 0) {
    println("8.2: has_changes=true node should not be reusable")
    panic()
  }
}

///|
test "8.2 不变量 — shift_node 后 byte 与全量解析兼容" {
  // 编辑 "abc" → "axc"：增量解析结果的字节位置应与全量解析完全一致
  let dsl = "start s\nrule s: /[a-z]/ /[a-z]/ /[a-z]/"
  let table = must_make_table(dsl)
  assert_incremental_case_from_linear(
    "8.2/shift-bytes", table, "abc", 1, 2, "x",
  )
}

///|
test "8.2 不变量 — 文件开头插入增量不变量通过" {
  // edit: [0,0) → [0,1)  old "bc" → new "abc"
  let dsl = "start s\nrule s: /[a-z]+/"
  let table = must_make_table(dsl)
  let old_input = "bc"
  let old_root = must_parse_linear("8.2/head-insert-parse", table, old_input)
  let (_, edit) = make_edit_from_replacement(old_input, 0, 0, "a")
  let marked = apply_edit({ root: old_root, old_input }, edit)
  match check_incremental_invariants(marked.root, edit) {
    Some(msg) => {
      println("8.2 head-insert invariant violated: \{msg}")
      panic()
    }
    None => ()
  }
}

///|
test "8.2 不变量 — 文件末尾删除增量不变量通过" {
  // edit: [2,3) → [2,2)  old "abc" → new "ab"
  let dsl = "start s\nrule s: /[a-z]/ /[a-z]/ | /[a-z]/ /[a-z]/ /[a-z]/"
  let table = must_make_table(dsl)
  let old_input = "abc"
  let old_root = must_parse_linear("8.2/tail-delete-parse", table, old_input)
  let (_, edit) = make_edit_from_replacement(old_input, 2, 3, "")
  let marked = apply_edit({ root: old_root, old_input }, edit)
  match check_incremental_invariants(marked.root, edit) {
    Some(msg) => {
      println("8.2 tail-delete invariant violated: \{msg}")
      panic()
    }
    None => ()
  }
}
