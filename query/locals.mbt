///|
// 局部变量作用域解析

///|
/// 局部变量解析结果。
///
/// 以节点 start_byte 为 key 区分：一个字节偏移可以唯一定位一个引用节点。
pub(all) struct LocalResolution {
  /// start_byte → true：该字节处的节点是一个已被本地定义绑定的引用。
  local_refs : Map[Int, Bool]
} derive(Debug)

///|
/// 查询节点是否被识别为局部变量引用（在某个祖先作用域内有对应定义）。
pub fn LocalResolution::is_local_ref(
  self : LocalResolution,
  start_byte : Int,
) -> Bool {
  match self.local_refs.get(start_byte) {
    Some(true) => true
    _ => false
  }
}

///|
// 内部辅助

///|
/// 给定一组 scope 区间（start_byte, end_byte），找出包含字节偏移 [nb_start..nb_end)
/// 的所有 scope 索引，按"最内层优先"（start_byte 最大者优先）排序返回。
// 旧辅助函数，P4 起由 bindings.mbt 替代，保留以兼容老测试
fn _find_containing_scopes(
  scopes : Array[(Int, Int)],
  node_start : Int,
  node_end : Int,
) -> Array[Int] {
  let result : Array[Int] = []
  for i in 0..<scopes.length() {
    let (ss, se) = scopes[i]
    if ss <= node_start && node_end <= se {
      result.push(i)
    }
  }
  // 按 start_byte 降序排列（最内层 scope 的 start_byte 最大）
  let n = result.length()
  for i in 1..<n {
    let key = result[i]
    let (key_ss, _) = scopes[key]
    let mut j = i - 1
    while j >= 0 {
      let (r_ss, _) = scopes[result[j]]
      if r_ss < key_ss {
        result[j + 1] = result[j]
        j = j - 1
      } else {
        break
      }
    }
    result[j + 1] = key
  }
  result
}

///|
/// 判断 capture_name 是否属于 local.definition 系列。
// 旧辅助函数，P4 起由 bindings.capture_role 替代
fn _is_local_def_capture(name : String) -> Bool {
  name == "local.definition" || str_starts_with(name, "local.definition.")
}

///|
/// 在 CST 上运行 locals_query 并解析作用域与定义关系，返回 LocalResolution。
///
/// 内部委托给 bindings.build_binding_graph，将 BindingGraph.edges 中
/// 成功绑定的引用映射回 LocalResolution.local_refs。
/// 旧的 @local.scope / @local.definition / @local.reference capture
/// 由 bindings.capture_role 自动兼容。
pub fn resolve_locals(
  root : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
  locals_query : CompiledQuery,
) -> LocalResolution {
  let graph = build_binding_graph(root, input, table, locals_query)
  let local_refs : Map[Int, Bool] = {}
  for edge in graph.edges {
    let ref_node = graph.references[edge.reference_id]
    local_refs[ref_node.start_byte] = true
  }
  { local_refs, }
}
