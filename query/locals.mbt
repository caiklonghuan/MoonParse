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
fn find_containing_scopes(
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
fn is_local_def_capture(name : String) -> Bool {
  name == "local.definition" || str_starts_with(name, "local.definition.")
}

///|
/// 在 CST 上运行 locals_query 并解析作用域与定义关系，返回 LocalResolution。
pub fn resolve_locals(
  root : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
  locals_query : CompiledQuery,
) -> LocalResolution {
  let captures = exec(locals_query, root, input, table)
  // ── 分拣捕获 ─────────────────────────────────────────────────
  // scope 区间列表：(start_byte, end_byte)
  let scopes : Array[(Int, Int)] = []
  // def 节点列表
  let def_nodes : Array[@runtime.CstNode] = []
  // ref 节点列表
  let ref_nodes : Array[@runtime.CstNode] = []
  for c in captures {
    if c.capture_name == "local.scope" {
      let n = c.node
      scopes.push((n.start_byte, n.end_byte))
    } else if is_local_def_capture(c.capture_name) {
      def_nodes.push(c.node)
    } else if c.capture_name == "local.reference" {
      ref_nodes.push(c.node)
    }
  }
  // ── 构建 scope → defs 映射 ───────────────────────────────────
  // scope_defs[i] 是 scopes[i] 内所有定义的文本集合
  let scope_defs : Array[Array[String]] = scopes.map(fn(_) { [] })
  for def in def_nodes {
    let text = node_text(def, input)
    if text.is_empty() {
      continue
    }
    // 找最内层包含该 def 的 scope
    let containing = find_containing_scopes(
      scopes,
      def.start_byte,
      def.end_byte,
    )
    if !containing.is_empty() {
      let innermost = containing[0]
      scope_defs[innermost].push(text)
    }
  }
  // ── 解析 refs ────────────────────────────────────────────────
  let local_refs : Map[Int, Bool] = {}
  for ref_node in ref_nodes {
    let text = node_text(ref_node, input)
    if text.is_empty() {
      continue
    }
    let containing = find_containing_scopes(
      scopes,
      ref_node.start_byte,
      ref_node.end_byte,
    )
    // 由内到外逐 scope 搜索同名定义
    let mut found = false
    for scope_idx in containing {
      for def_text in scope_defs[scope_idx] {
        if def_text == text {
          found = true
          break
        }
      }
      if found {
        break
      }
    }
    if found {
      local_refs[ref_node.start_byte] = true
    }
  }
  { local_refs, }
}
