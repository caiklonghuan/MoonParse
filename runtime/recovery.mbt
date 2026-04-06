///|
// 错误恢复辅助函数
//
// 错误恢复三策略（recover_to_state / insert_missing / skip_token）
// 已在 glr.mbt 中作为 GlrEngine 方法实现。
// 代价常量在 types.mbt 中定义（error_cost_per_* 系列）。

///|
/// 计算跳过一个 CstNode 的错误代价
fn error_cost_for_skipped_node(node : CstNode, config : ParseConfig) -> Int {
  let char_cost = (node.end_byte - node.start_byte) *
    config.error_cost_per_skipped_char
  let line_cost = (node.end_point.row - node.start_point.row) *
    config.error_cost_per_skipped_line
  let tree_cost = config.error_cost_per_skipped_tree
  // 取字符代价与行代价中较大者，再加上树代价
  let body_cost = if char_cost > line_cost { char_cost } else { line_cost }
  tree_cost + body_cost
}
