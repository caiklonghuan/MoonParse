///|
// 统一测试断言工具（结构、文本、位置）
//
// 供各文法黑盒测试文件通过 @grammars.* 调用。
// 不依赖 inspect，因此在 moon test --update 之外也能以
// 确定性方式失败并报告期望值 / 实际值。

///|
/// 断言节点在 source 中对应的原始文本等于 expected。
pub fn assert_node_text_eq(
  node : @runtime.CstNode,
  source : String,
  expected : String,
) -> Unit {
  let actual = source[node.start_byte:node.end_byte].to_string()
  if actual != expected {
    println(
      "assert_node_text_eq: expected \{expected.escape()} got \{actual.escape()}",
    )
    panic()
  }
}

///|
/// 断言节点的字节区间恰好为 [expected_start, expected_end)。
pub fn assert_span_eq(
  node : @runtime.CstNode,
  expected_start : Int,
  expected_end : Int,
) -> Unit {
  if node.start_byte != expected_start || node.end_byte != expected_end {
    println(
      "assert_span_eq: expected [\{expected_start}, \{expected_end}) got [\{node.start_byte}, \{node.end_byte})",
    )
    panic()
  }
}

///|
/// 断言点的行列等于 expected_row / expected_col（均基于 codepoint 计数）。
pub fn assert_point_eq(
  point : @runtime.Point,
  expected_row : Int,
  expected_col : Int,
) -> Unit {
  if point.row != expected_row || point.column != expected_col {
    println(
      "assert_point_eq: expected (\{expected_row}, \{expected_col}) got (\{point.row}, \{point.column})",
    )
    panic()
  }
}

///|
/// 断言 actual_sexp（由 *_sexp 函数产生）等于 expected_sexp。
///
/// 与 `inspect` 的区别：此函数始终强断言，不支持 `--update` 自动更新；
/// 用于已知稳定的结构测试。对于尚在探索的快照，请继续使用 `inspect`。
pub fn assert_tree_shape_eq(
  actual_sexp : String,
  expected_sexp : String,
) -> Unit {
  if actual_sexp != expected_sexp {
    println(
      "assert_tree_shape_eq:\n  expected: \{expected_sexp}\n  actual:   \{actual_sexp}",
    )
    panic()
  }
}

///|
/// 断言 CST 树满足基本结构不变量（与错误恢复兼容的轻量检查）：
///   · `is_missing` 节点必须零宽（`start_byte == end_byte`）
///
/// 注意：此函数对错误恢复树保持宽容。若需完整的 Section 8.1 结构检查，
/// 请直接调用 `@runtime.check_cst_invariants`（适用于已知干净的解析结果）。
pub fn assert_cst_invariants(
  node : @runtime.CstNode,
  source : String,
  path : String,
) -> Unit {
  ignore(source)
  if node.is_missing && node.start_byte != node.end_byte {
    println(
      "assert_cst_invariants [\{path}]: is_missing but not zero-width [\{node.start_byte}, \{node.end_byte})",
    )
    panic()
  }
  for i in 0..<node.children.length() {
    let child = node.children[i]
    let cp = path + "/" + i.to_string()
    assert_cst_invariants(child, source, cp)
  }
}
