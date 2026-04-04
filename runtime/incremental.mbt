///|
// 增量解析
//
// 增量解析允许在输入发生局部修改后，重用上一次解析结果中未受影响的子树，
// 从而避免完整地重新解析整个文件。
//
// 核心思路（对标 tree-sitter）：
// 用户提供 InputEdit（start_byte, old_end_byte, new_end_byte）
// 遍历旧 CST，对每个节点打上 has_changes = true（如果在编辑区间内）
// 解析新输入时：
//      · 在 Shift 前，先尝试从旧 CST 中找到一个可复用节点（reuse_node）
//      · 复用条件：
//          - node.start_byte == cur_pos（位置对齐）
//          - node.parse_state == cur_lr_state（LR 状态一致）
//          - not node.has_changes（不在编辑区间内）
//          - not node.fragile_left / fragile_right（非 GLR 产物）
//          - node.lookahead_bytes <= new_edit_start（前瞻不越过编辑边界）
//      · 复用时直接将旧节点推栈，跳过重新词法/语法分析
// 非复用节点正常走 glr_parse 路径

///|
/// 增量解析的旧树快照（包含一次或多次编辑的累积状态）
pub(all) struct OldTree {
  /// 上一次解析的 CST 根节点
  root : CstNode
  /// 该根节点对应的完整输入字符串（用于 lookahead_bytes 比对）
  old_input : String
} derive(Show)

///|
/// 深度优先遍历，对与 [start, old_end) 相交的节点打 has_changes。
/// 不相交的节点原样返回（共享），相交的节点 copy-on-write。
fn mark_changes(node : CstNode, start : Int, old_end : Int) -> CstNode {
  // 不相交：直接返回原节点（零复制）
  if node.start_byte >= old_end || node.end_byte <= start {
    return node
  }
  // 叶节点：标记 has_changes
  if node.children.is_empty() {
    return { ..node, has_changes: true }
  }
  // 内部节点：递归处理子节点，重建 children 数组
  let new_children : Array[CstNode] = Array::new(
    capacity=node.children.length(),
  )
  for child in node.children {
    new_children.push(mark_changes(child, start, old_end))
  }
  { ..node, children: new_children, has_changes: true }
}

///|
/// 应用一个 InputEdit，返回标记了 has_changes 的新旧树副本
pub fn apply_edit(tree : OldTree, edit : InputEdit) -> OldTree {
  let new_root = mark_changes(tree.root, edit.start_byte, edit.old_end_byte)
  { root: new_root, old_input: tree.old_input }
}

///|
/// 尝试从旧 CST 中找到可复用的子树
///
/// 返回 Some(node) 表示找到可直接复用的子树；None 表示不可复用。
///
/// TODO: 实现后替换此 stub
pub fn find_reusable_node(
  old_tree : OldTree,
  new_pos : Int,
  lr_state : Int,
  edit_start : Int,
) -> CstNode? {
  // TODO: 在 old_tree.root 中从 new_pos 开始做深度优先搜索
  //       找满足复用条件的节点（见  注释中的复用条件）
  let _ = (old_tree, new_pos, lr_state, edit_start)
  None
}

///|
/// 增量版解析入口
///
/// 提供旧树和编辑描述时，先 apply_edit 标记 has_changes，
/// 再以 old_tree 作为 reuse pool 调用解析器。
///
/// TODO: 实现后替换此 stub
pub fn parse_incremental(
  table : @tablegen.ParseTable,
  input : String,
  old_tree : OldTree?,
  _edit : InputEdit?,
) -> Result[CstNode, ParseError] {
  // TODO:
  // match old_tree, edit → apply_edit
  // 构造带 reuse_lookup 的解析器
  // 在 Shift 前先查 find_reusable_node
  // 复用成功则跳过词法，直接推栈
  let _ = old_tree
  parse_linear(table, input)
}

///|
/// 判断一个节点在新编辑后是否仍然可复用
///
/// 外部调用（Parser 内部在 Shift 前调用）
pub fn is_reusable(
  node : CstNode,
  cur_pos : Int,
  lr_state : Int,
  edit_start : Int,
) -> Bool {
  // 位置对齐
  if node.start_byte != cur_pos {
    return false
  }
  // LR 状态一致（parse_state 当前置 0，条件永远通过，实现时需填入实际状态）
  if node.parse_state != lr_state {
    return false
  }
  // 不在编辑区间内
  if node.has_changes {
    return false
  }
  // 非 GLR 合并产物
  if node.fragile_left || node.fragile_right {
    return false
  }
  // 前瞻不越过编辑起点
  if node.lookahead_bytes > edit_start {
    return false
  }
  true
}
