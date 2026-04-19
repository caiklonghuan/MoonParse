///|
// 增量解析
// 增量解析允许在输入发生局部修改后，重用上一次解析结果中未受影响的子树，
// 从而避免完整地重新解析整个文件。

///|
/// 增量解析的旧树快照（包含一次或多次编辑的累积状态）
pub(all) struct OldTree {
  /// 上一次解析的 CST 根节点
  root : CstNode
  /// 该根节点对应的完整输入字符串（用于 lookahead_bytes 比对）
  old_input : String
} derive(Debug)

///|
/// 深度优先遍历，对与 [start, old_end) 相交的节点打 has_changes。
/// 不相交的节点原样返回（共享），相交的节点 copy-on-write。
fn mark_changes(node : CstNode, start : Int, old_end : Int) -> CstNode {
  // 不相交：直接返回原节点（零复制）
  // 节点整体在编辑区间右侧：不相交，直接返回
  if node.start_byte >= old_end {
    return node
  }
  // 节点整体在编辑区间左侧：
  if node.end_byte <= start && node.lookahead_bytes <= start {
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
/// 将 Point 坐标按编辑偏移校正（仅用于位置在 old_end_point 之后的节点）
fn shift_point(
  p : Point,
  old_end_point : Point,
  row_delta : Int,
  col_delta : Int,
) -> Point {
  if row_delta == 0 && col_delta == 0 {
    return p
  }
  if p.row > old_end_point.row {
    { row: p.row + row_delta, column: p.column }
  } else if p.row == old_end_point.row {
    { row: p.row + row_delta, column: p.column + col_delta }
  } else {
    p
  }
}

///|
/// 将节点（及子树）的字节位置和行列坐标按编辑偏移全量校正
fn shift_node(
  node : CstNode,
  byte_delta : Int,
  old_end_point : Point,
  row_delta : Int,
  col_delta : Int,
) -> CstNode {
  if byte_delta == 0 && row_delta == 0 && col_delta == 0 {
    return node
  }
  let new_start = shift_point(
    node.start_point,
    old_end_point,
    row_delta,
    col_delta,
  )
  let new_end = shift_point(node.end_point, old_end_point, row_delta, col_delta)
  if node.children.is_empty() {
    {
      ..node,
      start_byte: node.start_byte + byte_delta,
      end_byte: node.end_byte + byte_delta,
      start_point: new_start,
      end_point: new_end,
    }
  } else {
    let new_children = node.children.map(fn(c) {
      shift_node(c, byte_delta, old_end_point, row_delta, col_delta)
    })
    {
      ..node,
      start_byte: node.start_byte + byte_delta,
      end_byte: node.end_byte + byte_delta,
      start_point: new_start,
      end_point: new_end,
      children: new_children,
    }
  }
}

///|
/// 深度优先搜索旧树，返回第一个满足 is_reusable 的节点
fn search_reusable(
  node : CstNode,
  new_pos : Int,
  lr_state : Int,
  edit_start : Int,
  old_end_byte : Int,
) -> CstNode? {
  // 剪枝：节点整体在 new_pos 之后
  if node.start_byte > new_pos {
    return None
  }
  // 尝试本节点（start_byte == new_pos 时才有可能通过 is_reusable）
  if node.start_byte == new_pos &&
    is_reusable(node, new_pos, lr_state, edit_start, old_end_byte) {
    return Some(node)
  }
  // 递归子节点
  for child in node.children {
    if child.start_byte > new_pos {
      break
    }
    match search_reusable(child, new_pos, lr_state, edit_start, old_end_byte) {
      Some(n) => return Some(n)
      None => ()
    }
  }
  None
}

///|
/// 尝试从旧 CST 中找到可复用的子树。
///
/// old_end_byte：编辑结束字节（旧坐标，= edit.new_end_byte - byte_delta）。
/// 对编辑区间后（new_pos >= old_end_byte）的节点，放宽 lookahead 约束。
pub fn find_reusable_node(
  old_tree : OldTree,
  new_pos : Int,
  lr_state : Int,
  edit_start : Int,
  old_end_byte : Int,
) -> CstNode? {
  search_reusable(old_tree.root, new_pos, lr_state, edit_start, old_end_byte)
}

///|
/// 增量版 GLR 解析（内部入口）
fn glr_parse_incremental(
  table : @tablegen.ParseTable,
  input : String,
  old_tree : OldTree,
  edit : InputEdit,
  config : ParseConfig,
) -> Result[CstNode, ParseError] {
  let marked = apply_edit(old_tree, edit)
  // byte_delta / row_delta / col_delta 均为整次编辑的常数，解析期间不变
  let delta = edit.new_end_byte - edit.old_end_byte
  let row_delta = edit.new_end_point.row - edit.old_end_point.row
  let col_delta = edit.new_end_point.column - edit.old_end_point.column
  let lexer = LexerEngine::new(table.lexer_dfa)
  let engine = {
    ..GlrEngine::new(lexer, config),
    old_tree: Some(marked),
    byte_delta: delta,
    edit_start: edit.start_byte,
    new_end_byte: edit.new_end_byte,
    old_end_point: edit.old_end_point,
    row_delta,
    col_delta,
  }
  engine.run(table, input)
}

///|
/// 增量版解析入口
///
/// 提供旧树和编辑描述时，先 apply_edit 标记 has_changes，
/// 再以 old_tree 作为 reuse pool 调用解析器。
pub fn parse_incremental(
  table : @tablegen.ParseTable,
  input : String,
  old_tree : OldTree?,
  _edit : InputEdit?,
) -> Result[CstNode, ParseError] {
  match (old_tree, _edit) {
    (Some(ot), Some(edit)) =>
      glr_parse_incremental(table, input, ot, edit, ParseConfig::default())
    _ => glr_parse(table, input)
  }
}

///|
/// 带自定义配置的增量解析入口
pub fn parse_incremental_with_config(
  table : @tablegen.ParseTable,
  input : String,
  old_tree : OldTree?,
  edit : InputEdit?,
  config : ParseConfig,
) -> Result[CstNode, ParseError] {
  match (old_tree, edit) {
    (Some(ot), Some(e)) => glr_parse_incremental(table, input, ot, e, config)
    _ => glr_parse_with_config(table, input, config)
  }
}

///|
/// 带外部词法器的增量解析入口
pub fn parse_incremental_with_external_scanner(
  table : @tablegen.ParseTable,
  input : String,
  old_tree : OldTree?,
  edit : InputEdit?,
  scanner : ExternalScanner,
) -> Result[CstNode, ParseError] {
  match (old_tree, edit) {
    (Some(ot), Some(e)) => {
      let marked = apply_edit(ot, e)
      let delta = e.new_end_byte - e.old_end_byte
      let row_delta = e.new_end_point.row - e.old_end_point.row
      let col_delta = e.new_end_point.column - e.old_end_point.column
      let lexer = LexerEngine::new_with_external(table.lexer_dfa, scanner)
      let engine = {
        ..GlrEngine::new(lexer, ParseConfig::default()),
        old_tree: Some(marked),
        byte_delta: delta,
        edit_start: e.start_byte,
        new_end_byte: e.new_end_byte,
        old_end_point: e.old_end_point,
        row_delta,
        col_delta,
      }
      engine.run(table, input)
    }
    _ => glr_parse_with_external_scanner(table, input, scanner)
  }
}

///|
/// 带有状态词法器的增量解析入口
pub fn parse_incremental_with_stateful_scanner(
  table : @tablegen.ParseTable,
  input : String,
  old_tree : OldTree?,
  edit : InputEdit?,
  scanner : &StatefulScanner,
) -> Result[CstNode, ParseError] {
  parse_incremental_with_stateful_scanner_and_config(
    table,
    input,
    old_tree,
    edit,
    scanner,
    ParseConfig::default(),
  )
}

///|
/// 带有状态词法器 + 自定义配置的增量解析入口
pub fn parse_incremental_with_stateful_scanner_and_config(
  table : @tablegen.ParseTable,
  input : String,
  old_tree : OldTree?,
  edit : InputEdit?,
  scanner : &StatefulScanner,
  config : ParseConfig,
) -> Result[CstNode, ParseError] {
  match (old_tree, edit) {
    (Some(ot), Some(e)) => {
      let marked = apply_edit(ot, e)
      let delta = e.new_end_byte - e.old_end_byte
      let row_delta = e.new_end_point.row - e.old_end_point.row
      let col_delta = e.new_end_point.column - e.old_end_point.column
      let lexer = LexerEngine::new_with_stateful(table.lexer_dfa, scanner)
      let engine = {
        ..GlrEngine::new(lexer, config),
        old_tree: Some(marked),
        byte_delta: delta,
        edit_start: e.start_byte,
        new_end_byte: e.new_end_byte,
        old_end_point: e.old_end_point,
        row_delta,
        col_delta,
      }
      // 为初始栈顶（哨兵节点 0）设置初始 scanner 状态
      engine.scanner_states[0] = scanner
      engine.run(table, input)
    }
    _ =>
      glr_parse_with_stateful_scanner_and_config(table, input, scanner, config)
  }
}

///|
/// 判断一个节点在新编辑后是否仍然可复用
///
/// cur_pos     ：在旧树坐标中的搜索位置（= search_pos）
/// edit_start  ：编辑起始字节（旧坐标）
/// old_end_byte：编辑结束字节（旧坐标，= new_end_byte - byte_delta）
///
/// 前瞻规则：
///   · 编辑区间前的节点（cur_pos < old_end_byte）：
///       lookahead_bytes > edit_start 说明词法器"看穿"了编辑起点，不可复用。
///   · 编辑区间后的节点（cur_pos >= old_end_byte）：
///       完全在编辑之后，has_changes=false 即可安全复用（前瞻不做约束）。
pub fn is_reusable(
  node : CstNode,
  cur_pos : Int,
  lr_state : Int,
  edit_start : Int,
  old_end_byte : Int,
) -> Bool {
  // 错误节点和缺失节点不可复用
  if node.is_missing || node.is_error {
    return false
  }
  // extra 节点（空白/注释等）不参与归约，不可复用（parse_state=0 无意义）
  if node.extra {
    return false
  }
  // 位置对齐
  if node.start_byte != cur_pos {
    return false
  }
  // LR 状态一致
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
  // 前瞻边界检查：仅对编辑区间前的节点有效；
  // 编辑区间后（cur_pos >= old_end_byte）的节点不受 edit_start 约束
  if cur_pos < old_end_byte && node.lookahead_bytes > edit_start {
    return false
  }
  true
}
