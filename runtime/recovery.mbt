///|
// 错误恢复存根
//
// 错误恢复采用 tree-sitter 的三策略混合：
//
//   recover_to_state：
//     · 回退栈，寻找存在错误产生式 [X → • error β] 的状态
//     · 丢弃 error → β 之间的 token（代价 = skipped_tree×100 + skipped_char×1）
//     · 产生 ERROR 节点包裹被丢弃内容
//
//   insert_missing：
//     · 模拟插入一个缺失 token（代价 = missing_tree×110）
//     · 仅当插入后可以继续推进解析时有效
//
//   skip_token：
//     · 丢弃当前前瞻 token，继续尝试
//     · 代价 = skipped_char×1（字符级）或 skipped_line×30（行级）
//
// 多策略并行展开（GLR 框架），选代价最低的版本继续。
// 代价常量在 types.mbt 中定义（error_cost_per_* 系列）。
//
// 注：三个策略函数（recover_to_state / insert_missing / skip_token）
// 已在 glr.mbt 中作为 GlrEngine 方法实现，以下为独立存根（暂未接入）。

///|
/// 错误恢复结果
pub(all) enum RecoveryResult {
  /// 成功恢复，返回包含 ERROR 节点的解析状态更新
  Recovered(Array[CstNode])
  /// 无法恢复（整个输入无法解析）
  Failed
} derive(Show)

///|
/// 错误恢复上下文（触发恢复时由 parser 传入）
struct RecoveryContext {
  /// 当前解析位置（字节偏移）
  position : Int
  /// 当前行列坐标
  point : Point
  /// 当前 LR 状态栈快照（深度从底到顶）
  state_stack : Array[Int]
  /// 当前 CST 节点栈快照
  node_stack : Array[CstNode]
  /// 前瞻 token（触发错误的 token）
  lookahead : Token?
} derive(Show)

///|
/// StackSummary：错误恢复用的历史状态摘要
///
/// 从当前栈顶向下记录若干帧，每帧包含：
///   · state      — LR 状态
///   · position   — 该状态推入时对应的字节位置
///   · row        — 推入时的行号（快速行跳跃代价计算）
///   · depth      — 距当前栈顶的距离（0 = 顶部，depth+1 = 该帧以下的帧数）
struct StackSummary {
  entries : Array[StackSummaryEntry]
}

///|
fn StackSummary::new() -> StackSummary {
  { entries: [] }
}

///|
fn StackSummary::push(
  self : StackSummary,
  state : Int,
  position : Int,
  row : Int,
  depth : Int,
) -> Unit {
  self.entries.push({ state, position, row, depth })
}

///|
/// 策略 1：回退到可接受 error token 的状态，包裹跳过内容为 ERROR 节点
///
/// TODO: 实现后替换此 stub
pub fn recover_to_state(
  _ctx : RecoveryContext,
  _table : @tablegen.ParseTable,
  _input : String,
) -> RecoveryResult {
  // TODO: 向下遍历 state_stack，找到存在 error 产生式的状态
  //       跳过 token 直到 error 产生式的 FOLLOW 集中的 token
  //       构造 ERROR 节点，更新栈
  RecoveryResult::Failed
}

///|
/// 策略 2：插入缺失 token
///
/// TODO: 实现后替换此 stub
pub fn insert_missing_token(
  _ctx : RecoveryContext,
  _table : @tablegen.ParseTable,
  _tid : @tablegen.TerminalId,
) -> RecoveryResult {
  // TODO: 对每个 valid_tokens[state] 中的 terminal，
  //       模拟插入并检查是否可以继续解析
  //       选代价最低的
  RecoveryResult::Failed
}

///|
/// 策略 3：跳过当前前瞻 token（字符/行级代价）
///
/// TODO: 实现后替换此 stub
pub fn skip_lookahead(
  _ctx : RecoveryContext,
  _table : @tablegen.ParseTable,
) -> RecoveryResult {
  // TODO: 计算跳过当前 token 的代价（行内 vs 换行）
  //       更新 position 并继续
  RecoveryResult::Failed
}

///|
/// 计算跳过一个 CstNode 的错误代价
fn error_cost_for_skipped_node(node : CstNode) -> Int {
  let char_cost = (node.end_byte - node.start_byte) *
    error_cost_per_skipped_char
  let line_cost = (node.end_point.row - node.start_point.row) *
    error_cost_per_skipped_line
  let tree_cost = error_cost_per_skipped_tree
  // 取字符代价与行代价中较大者，再加上树代价
  let body_cost = if char_cost > line_cost { char_cost } else { line_cost }
  tree_cost + body_cost
}
