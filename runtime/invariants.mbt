///|
// runtime/invariants.mbt 
// 通用 CST 不变量检查器

///|
/// 检查从 `root` 出发的整棵 CST 树是否满足结构不变量。
/// 返回 None 表示通过；返回 Some(msg) 表示首个违反的描述。
pub fn check_cst_invariants(root : CstNode, source : String) -> String? {
  // 根节点的 end_byte 不得超出 source — 会导致切片越界
  if root.end_byte > source.length() {
    return Some(
      "root: end_byte (\{root.end_byte}) > source.length() (\{source.length()})",
    )
  }
  check_node(root, source, "root", None, false)
}

///|
/// 检查一棵 CST 是否为合法的**干净**解析结果：
/// 通过所有结构不变量 + 根节点覆盖整个输入 + 不含 ERROR/MISSING 节点。
/// 返回 None 表示通过；返回 Some(msg) 表示首个违反描述。
pub fn check_clean_root(root : CstNode, source : String) -> String? {
  match check_cst_invariants(root, source) {
    Some(msg) => return Some(msg)
    None => ()
  }
  if root.start_byte != 0 || root.end_byte != source.length() {
    return Some(
      "root: expected span [0, \{source.length()}) but got [\{root.start_byte}, \{root.end_byte})",
    )
  }
  if collect_first_error_or_missing(root) is Some(path) {
    return Some("root: unexpected ERROR/MISSING at \{path}")
  }
  None
}

///|
fn point_le(a : Point, b : Point) -> Bool {
  a.row < b.row || (a.row == b.row && a.column <= b.column)
}

///|
fn fmt_point(p : Point) -> String {
  "(" + p.row.to_string() + "," + p.column.to_string() + ")"
}

///|
// 递归检查单节点及其子树。
// parent = None 仅用于根节点（跳过父子包含检查）。
// parent_is_error = true 时，豁免父子包含检查（错误恢复树）。
fn check_node(
  node : CstNode,
  source : String,
  path : String,
  parent : CstNode?,
  parent_is_error : Bool,
) -> String? {
  let has_end_at_zero = !node.children.is_empty() &&
    node.end_byte == 0 &&
    node.start_byte > 0
  if !node.is_error && !has_end_at_zero && node.start_byte > node.end_byte {
    return Some(
      "\{path}: start_byte (\{node.start_byte}) > end_byte (\{node.end_byte})",
    )
  }

  // 源码绝对边界（ERROR 节点豁免：其字节范围可能超出 source）
  if !node.is_error {
    if node.start_byte < 0 {
      return Some("\{path}: start_byte (\{node.start_byte}) < 0")
    }
    if node.end_byte > source.length() {
      return Some(
        "\{path}: end_byte (\{node.end_byte}) > source.length() (\{source.length()})",
      )
    }
  }

  // is_missing 必须零宽
  if node.is_missing && node.start_byte != node.end_byte {
    return Some(
      "\{path}: is_missing=true but not zero-width [\{node.start_byte}, \{node.end_byte})",
    )
  }

  // 点位单调性（ERROR 节点豁免；has_end_at_zero 节点豁免：同一原因导致 end_point=(0,0)）
  if !node.is_error &&
    !has_end_at_zero &&
    !point_le(node.start_point, node.end_point) {
    return Some(
      "\{path}: start_point \{fmt_point(node.start_point)} > end_point \{fmt_point(node.end_point)}",
    )
  }

  match parent {
    Some(p) => {
      let parent_end_unreliable = p.end_byte == 0 && p.start_byte > 0
      // ERROR 子节点、ERROR 父节点、或父节点 end 不可靠：完全豁免包含检查
      if !node.is_error && !parent_is_error && !parent_end_unreliable {
        // 所有非 ERROR 子节点的 end_byte 不得超出父节点
        if node.end_byte > p.end_byte {
          return Some(
            "\{path}: child.end_byte (\{node.end_byte}) > parent.end_byte (\{p.end_byte})",
          )
        }
        // 零宽节点（start==end）豁免起始端检查（ε 产生式节点固定在 0）
        // 非叶内部节点 start_byte=0 豁免：左递归 ε 基传导的不可靠起始位置
        // 非 extra、非零宽、非 ε-unpositioned 子节点的 start_byte 不得在父节点之前
        let child_unpositioned_inner = node.start_byte == 0 &&
          !node.children.is_empty()
        if !node.extra &&
          node.start_byte != node.end_byte &&
          !child_unpositioned_inner &&
          node.start_byte < p.start_byte {
          return Some(
            "\{path}: non-extra child.start_byte (\{node.start_byte}) < parent.start_byte (\{p.start_byte})",
          )
        }
      }
    }
    None => ()
  }

  // 兄弟有序不重叠（零宽节点豁免；ERROR 直接兄弟豁免；当前节点为 ERROR 时豁免全部）
  let children = node.children
  if !node.is_error {
    for i in 0..<(children.length() - 1) {
      let ci = children[i]
      let cj = children[i + 1]
      let ci_zero_width = ci.start_byte == ci.end_byte
      let cj_zero_width = cj.start_byte == cj.end_byte
      // 非叶内部节点若 start_byte=0，可能是左递归 ε 基传导的不可靠位置，豁免
      let cj_unpositioned_inner = cj.start_byte == 0 && !cj.children.is_empty()
      if !ci_zero_width &&
        !cj_zero_width &&
        !ci.is_error &&
        !cj.is_error &&
        !cj_unpositioned_inner &&
        ci.end_byte > cj.start_byte {
        return Some(
          "\{path}: children[\{i}].end_byte (\{ci.end_byte}) > children[\{i + 1}].start_byte (\{cj.start_byte}) — siblings overlap or are out of order",
        )
      }
    }
  }

  // 递归子节点
  let this_is_error = node.is_error
  for i in 0..<children.length() {
    match
      check_node(
        children[i],
        source,
        path + "/children[" + i.to_string() + "]",
        Some(node),
        this_is_error,
      ) {
      Some(msg) => return Some(msg)
      None => ()
    }
  }
  None
}

///|
// 前序遍历找到第一个 ERROR 或 MISSING 节点，返回其路径。
fn collect_first_error_or_missing(node : CstNode) -> String? {
  collect_first_error_or_missing_at(node, "root")
}

///|
fn collect_first_error_or_missing_at(node : CstNode, path : String) -> String? {
  if node.is_error || node.is_missing {
    return Some(path)
  }
  for i in 0..<node.children.length() {
    match
      collect_first_error_or_missing_at(
        node.children[i],
        path + "/children[" + i.to_string() + "]",
      ) {
      Some(p) => return Some(p)
      None => ()
    }
  }
  None
}

///|

///|
/// 检查增量解析专用不变量
pub fn check_incremental_invariants(
  marked_root : CstNode,
  edit : InputEdit,
) -> String? {
  check_inc_node(marked_root, edit, "root")
}

///|
fn check_inc_node(node : CstNode, edit : InputEdit, path : String) -> String? {
  let es = edit.start_byte
  let ee = edit.old_end_byte
  // 对 has_changes=false 的节点，验证它确实不与编辑区间相交
  if !node.has_changes {
    // 完全在编辑区间右侧（含紧接）
    let right_of_edit = node.start_byte >= ee
    // 完全在编辑区间左侧（end_byte 及 lookahead 均不越入 es）
    let left_of_edit = node.end_byte <= es && node.lookahead_bytes <= es
    if !right_of_edit && !left_of_edit {
      return Some(
        "\{path}: has_changes=false but node [\{node.start_byte}, \{node.end_byte}) (lookahead=\{node.lookahead_bytes}) intersects edit [\{es}, \{ee})",
      )
    }
  }
  for i in 0..<node.children.length() {
    match
      check_inc_node(
        node.children[i],
        edit,
        path + "/children[" + i.to_string() + "]",
      ) {
      Some(msg) => return Some(msg)
      None => ()
    }
  }
  None
}
