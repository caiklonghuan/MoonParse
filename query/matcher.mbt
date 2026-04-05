///|
// 匹配引擎
//
// 公开 API：
//   exec(query, root, input, table) -> Array[CaptureResult]
//
// 算法概述：
//   外层 DFS（walk）先序遍历整棵 CST，对每个节点依次尝试所有顶层模式。
//   try_match 对单个 (pattern, node) 做递归匹配，成功时把捕获写入临时缓冲。
//   子节点列表匹配（match_children）跳过 extra 节点，按顺序逐一配对。
//   谓词（#eq?）在整条顶层模式完全命中后做后置过滤；过滤不通过则丢弃本次捕获。
// 子节点匹配策略：
//   Pattern 子节点列表有序，CST children 可能夹杂 extra 节点（空白/注释）。
//   匹配时跳过 is_extra==true 的节点，只对语义子节点按顺序配对。
//   若模式有字段约束（field: Some(f)），则同时校验 field_names[child_idx]。
// match_id：同一次顶层模式命中产生的所有捕获共享同一 match_id，
//   全局单调递增（match_counter 值在 exec 内传递）。

///|
// 内部辅助

///|
/// 从 node + field_names 数组中取 child_idx 处的字段名
fn get_field(
  field_names : Array[String?],
  child_idx : Int
) -> String? {
  if child_idx < field_names.length() {
    field_names[child_idx]
  } else {
    None
  }
}

///|
// 子节点匹配

///|
/// 在 node.children 中按顺序匹配 pattern_children 列表。
///
/// 跳过 extra 节点；若模式有字段约束，则同时校验字段名。
/// 成功时将本次捕获写入 captures，返回 true；任一子模式失败返回 false。
fn match_children(
  pattern_children : Array[PatternChild],
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
  match_id : Int,
  captures : Array[CaptureResult]
) -> Bool {
  // 收集语义子节点（排除 extra）
  let semantic : Array[(Int, @runtime.CstNode)] = []
  for i in 0..<node.children.length() {
    let child = node.children[i]
    if not(child.extra) {
      semantic.push((i, child))
    }
  }

  // 模式子节点必须完全匹配（pattern 数量 <= 语义子节点数）
  if pattern_children.length() > semantic.length() {
    return false
  }

  // 尝试从 semantic 中顺序匹配每个 PatternChild
  let sub_captures : Array[CaptureResult] = []
  let mut sem_idx = 0
  for pc in pattern_children {
    // 找到下一个满足字段约束（若有）的语义子节点
    let mut found = false
    while sem_idx < semantic.length() {
      let (real_idx, child) = semantic[sem_idx]
      sem_idx = sem_idx + 1
      // 字段约束检查
      let field_ok = match pc.field {
        None => true
        Some(f) =>
          match get_field(node.field_names, real_idx) {
            Some(cf) => cf == f
            None => false
          }
      }
      if not(field_ok) {
        continue
      }
      // 模式匹配
      if try_match(pc.pattern, child, input, table, match_id, sub_captures) {
        // 捕获标注
        match pc.capture {
          Some(name) =>
            sub_captures.push({ match_id, capture_name: name, node: child })
          None => ()
        }
        found = true
        break
      }
    }
    if not(found) {
      return false
    }
  }
  // 全部匹配成功，提交 sub_captures
  for c in sub_captures {
    captures.push(c)
  }
  true
}

///|
/// 尝试将 pattern 与 node 匹配。
///
/// 成功时将本次产生的捕获追加到 captures，返回 true；失败返回 false（captures 不变）。
fn try_match(
  pattern : QueryPattern,
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
  match_id : Int,
  captures : Array[CaptureResult]
) -> Bool {
  match pattern {
    Wildcard => true
    AnonPattern(s) => {
      // 叶节点，原文与字面量相等
      node.children.is_empty() && node_text(node, input) == s
    }
    NodePattern(type_name, children) => {
      // 类型名校验
      if node_type_name(node, table) != type_name {
        return false
      }
      // 无子节点约束时只匹配类型名
      if children.is_empty() {
        return true
      }
      // 有子节点约束则递归匹配
      match_children(children, node, input, table, match_id, captures)
    }
  }
}

///|
/// 对一条顶层模式（pattern_index）在 node 上做完整匹配：
/// 包括 try_match + 谓词后置过滤。
///
/// 匹配成功且通过谓词时，将捕获追加到 results 并返回 true。
fn try_match_top(
  pat_idx : Int,
  pattern : QueryPattern,
  predicates : Array[(Int, Predicate)],
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
  match_id : Int,
  results : Array[CaptureResult]
) -> Bool {
  let captures : Array[CaptureResult] = []
  if not(try_match(pattern, node, input, table, match_id, captures)) {
    return false
  }
  // 谓词后置过滤
  for pred in predicates {
    let (pidx, p) = pred
    if pidx != pat_idx {
      continue
    }
    match p {
      Eq(cap_name, expected) => {
        let mut ok = false
        for c in captures {
          if c.capture_name == cap_name {
            if node_text(c.node, input) == expected {
              ok = true
            }
            break
          }
        }
        if not(ok) {
          return false
        }
      }
    }
  }
  for c in captures {
    results.push(c)
  }
  true
}

///|
// 外层 DFS

///|
/// 先序 DFS 遍历 CST，对每个节点尝试所有顶层模式。
/// match_counter 单调递增，每次顶层模式命中后自增。
fn walk(
  node : @runtime.CstNode,
  query : CompiledQuery,
  input : String,
  table : @tablegen.ParseTable,
  match_counter : Array[Int],
  results : Array[CaptureResult]
) -> Unit {
  for i in 0..<query.patterns.length() {
    let pat = query.patterns[i]
    let mid = match_counter[0]
    if try_match_top(
      i,
      pat,
      query.predicates,
      node,
      input,
      table,
      mid,
      results,
    ) {
      match_counter[0] = mid + 1
    }
  }
  // 递归子节点
  for child in node.children {
    walk(child, query, input, table, match_counter, results)
  }
}

///|
// 公开 API

///|
/// 在 CST 树上执行编译好的查询，返回所有捕获结果。
///
/// 参数：
/// - query  : 由 `compile` 生成的 CompiledQuery
/// - root   : CST 根节点（来自 @runtime.parse）
/// - input  : 解析时使用的原始输入字符串（用于 AnonPattern 原文比较和捕获文本）
/// - table  : 对应的 ParseTable（用于节点类型名反查）
///
/// 返回值按 match_id 升序排列，同一 match_id 内按捕获出现顺序排列。
pub fn exec(
  query : CompiledQuery,
  root : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable
) -> Array[CaptureResult] {
  let results : Array[CaptureResult] = []
  let counter = [0]
  walk(root, query, input, table, counter, results)
  results
}
