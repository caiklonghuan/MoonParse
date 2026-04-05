///|
// 游标 API
//
//
// 用法示例（JS 伪代码）：
//   const cid = cursor_new(tree_id);
//   cursor_goto_first_child(cid);         // 进入根的第一个子节点
//   while (cursor_goto_next_sibling(cid)) { ... }  // 遍历兄弟
//   cursor_goto_parent(cid);              // 返回父节点
//   cursor_free(cid);
//
// 约定：
//   - 导航函数（goto_*）返回 Int：1 = 成功移动，0 = 已到边界或游标无效
//   - 查询函数（node_*）游标无效时返回空串 "" / 0 / -1

///|
// 生命周期

///|
/// 在语法树根节点处创建游标，返回游标句柄 ID。
/// tree_id 无效时返回 -1。
pub fn cursor_new(tree_id : Int) -> Int {
  match tree_registry.get(tree_id) {
    None => -1
    Some(te) =>
      cursor_registry.register({
        tree_id,
        current: te.root,
        current_index: -1,
        current_field: None,
        parent_nodes: [],
        parent_indices: [],
        parent_fields: [],
      })
  }
}

///|
/// 释放游标句柄（从注册表移除；GC 最终回收内存）。
pub fn cursor_free(cursor_id : Int) -> Unit {
  let _ = cursor_registry.remove(cursor_id)
}

///|
// 导航

///|
/// 移动到当前节点的第一个子节点。
/// 有子节点时返回 1；无子节点或游标无效时返回 0。
pub fn cursor_goto_first_child(cursor_id : Int) -> Int {
  match cursor_registry.get(cursor_id) {
    None => 0
    Some(cursor) => {
      let parent = cursor.current
      if parent.children.is_empty() {
        0
      } else {
        cursor.parent_nodes.push(parent)
        cursor.parent_indices.push(cursor.current_index)
        cursor.parent_fields.push(cursor.current_field)
        cursor.current = parent.children[0]
        cursor.current_index = 0
        cursor.current_field = if parent.field_names.length() > 0 {
          parent.field_names[0]
        } else {
          None
        }
        1
      }
    }
  }
}

///|
/// 移动到当前节点的下一个兄弟节点。
/// 存在下一兄弟时返回 1；已是最后一个子节点或游标在根节点时返回 0。
pub fn cursor_goto_next_sibling(cursor_id : Int) -> Int {
  match cursor_registry.get(cursor_id) {
    None => 0
    Some(cursor) => {
      if cursor.parent_nodes.is_empty() {
        return 0
      }
      let parent = cursor.parent_nodes[cursor.parent_nodes.length() - 1]
      let next_index = cursor.current_index + 1
      if next_index >= parent.children.length() {
        0
      } else {
        cursor.current = parent.children[next_index]
        cursor.current_index = next_index
        cursor.current_field = if next_index < parent.field_names.length() {
          parent.field_names[next_index]
        } else {
          None
        }
        1
      }
    }
  }
}

///|
/// 移动到当前节点的父节点。
/// 成功时返回 1；已在根节点或游标无效时返回 0。
pub fn cursor_goto_parent(cursor_id : Int) -> Int {
  match cursor_registry.get(cursor_id) {
    None => 0
    Some(cursor) => {
      if cursor.parent_nodes.is_empty() {
        0
      } else {
        let last = cursor.parent_nodes.length() - 1
        cursor.current = cursor.parent_nodes[last]
        cursor.current_index = cursor.parent_indices[last]
        cursor.current_field = cursor.parent_fields[last]
        let _ = cursor.parent_nodes.pop()
        let _ = cursor.parent_indices.pop()
        let _ = cursor.parent_fields.pop()
        1
      }
    }
  }
}

///|
// 节点属性查询

///|
/// 当前节点的类型名称字符串（如 "expression"、"+" 等）。
/// 游标无效时返回 ""。
pub fn cursor_node_type(cursor_id : Int) -> String {
  match cursor_registry.get(cursor_id) {
    None => ""
    Some(cursor) =>
      match parser_registry_for_tree(cursor.tree_id) {
        None => ""
        Some(table) => node_type_name(cursor.current, table)
      }
  }
}

///|
/// 当前节点是否为命名节点（非匿名叶节点）。1 = 是，0 = 否。游标无效时返回 0。
pub fn cursor_node_is_named(cursor_id : Int) -> Int {
  match cursor_registry.get(cursor_id) {
    None => 0
    Some(cursor) => if cursor.current.is_named { 1 } else { 0 }
  }
}

///|
/// 当前节点是否为 ERROR 节点（包含无法解析的内容）。1 = 是，0 = 否。
pub fn cursor_node_is_error(cursor_id : Int) -> Int {
  match cursor_registry.get(cursor_id) {
    None => 0
    Some(cursor) => if cursor.current.is_error { 1 } else { 0 }
  }
}

///|
/// 当前节点是否为缺失节点（错误恢复插入的虚拟 token）。1 = 是，0 = 否。
pub fn cursor_node_is_missing(cursor_id : Int) -> Int {
  match cursor_registry.get(cursor_id) {
    None => 0
    Some(cursor) => if cursor.current.is_missing { 1 } else { 0 }
  }
}

///|
/// 当前节点是否为额外节点（空白/注释等不推栈的 token）。1 = 是，0 = 否。
pub fn cursor_node_extra(cursor_id : Int) -> Int {
  match cursor_registry.get(cursor_id) {
    None => 0
    Some(cursor) => if cursor.current.extra { 1 } else { 0 }
  }
}

///|
/// 当前节点的起始字节偏移（0-based，inclusive）。游标无效时返回 -1。
pub fn cursor_node_start_byte(cursor_id : Int) -> Int {
  match cursor_registry.get(cursor_id) {
    None => -1
    Some(cursor) => cursor.current.start_byte
  }
}

///|
/// 当前节点的终止字节偏移（0-based，exclusive）。游标无效时返回 -1。
pub fn cursor_node_end_byte(cursor_id : Int) -> Int {
  match cursor_registry.get(cursor_id) {
    None => -1
    Some(cursor) => cursor.current.end_byte
  }
}

///|
/// 当前节点起始位置的行号（0-based）。游标无效时返回 -1。
pub fn cursor_node_start_row(cursor_id : Int) -> Int {
  match cursor_registry.get(cursor_id) {
    None => -1
    Some(cursor) => cursor.current.start_point.row
  }
}

///|
/// 当前节点起始位置的列号（0-based，字节偏移）。游标无效时返回 -1。
pub fn cursor_node_start_col(cursor_id : Int) -> Int {
  match cursor_registry.get(cursor_id) {
    None => -1
    Some(cursor) => cursor.current.start_point.column
  }
}

///|
/// 当前节点终止位置的行号（0-based）。游标无效时返回 -1。
pub fn cursor_node_end_row(cursor_id : Int) -> Int {
  match cursor_registry.get(cursor_id) {
    None => -1
    Some(cursor) => cursor.current.end_point.row
  }
}

///|
/// 当前节点终止位置的列号（0-based，字节偏移）。游标无效时返回 -1。
pub fn cursor_node_end_col(cursor_id : Int) -> Int {
  match cursor_registry.get(cursor_id) {
    None => -1
    Some(cursor) => cursor.current.end_point.column
  }
}

///|
/// 当前节点对应的原始源文本（start_byte..end_byte 的切片）。
/// 游标无效或范围越界时返回 ""。
pub fn cursor_node_text(cursor_id : Int) -> String {
  match cursor_registry.get(cursor_id) {
    None => ""
    Some(cursor) =>
      match tree_registry.get(cursor.tree_id) {
        None => ""
        Some(te) => {
          let node = cursor.current
          if node.start_byte <= node.end_byte &&
            node.end_byte <= te.input.length() {
            te.input[node.start_byte:node.end_byte].to_string()
          } else {
            ""
          }
        }
      }
  }
}

///|
/// 当前节点在父节点中的字段名（如 "left"、"right"），无字段名时返回 ""。
pub fn cursor_node_field(cursor_id : Int) -> String {
  match cursor_registry.get(cursor_id) {
    None => ""
    Some(cursor) =>
      match cursor.current_field {
        Some(f) => f
        None => ""
      }
  }
}

///|
/// 当前节点的子节点总数（含匿名/标点节点）。游标无效时返回 0。
pub fn cursor_node_child_count(cursor_id : Int) -> Int {
  match cursor_registry.get(cursor_id) {
    None => 0
    Some(cursor) => cursor.current.children.length()
  }
}

///|
/// 当前节点的命名子节点数（is_named = true）。游标无效时返回 0。
pub fn cursor_node_named_child_count(cursor_id : Int) -> Int {
  match cursor_registry.get(cursor_id) {
    None => 0
    Some(cursor) => {
      let mut count = 0
      for child in cursor.current.children {
        if child.is_named {
          count = count + 1
        }
      }
      count
    }
  }
}
