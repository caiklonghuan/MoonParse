///|
// 匹配引擎

///|
// 极简正则匹配引擎（#match? 谓词专用）

///|
fn re_is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn re_is_word(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///|
fn re_is_space(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
/// 跳过字符类 `[...]` 内容，pi_start 指向 `[` 后第一个字符。
/// 返回 `]` 之后的位置。
fn re_skip_class(pat : Array[Char], pi_start : Int) -> Int {
  let mut pi = pi_start
  if pi < pat.length() && pat[pi] == '^' {
    pi = pi + 1
  }
  // 第一个 `]` 字符是类成员（如 []a] 匹配 ] 或 a）
  if pi < pat.length() && pat[pi] == ']' {
    pi = pi + 1
  }
  while pi < pat.length() && pat[pi] != ']' {
    if pat[pi] == '\\' {
      pi = pi + 1 // 跳过转义后字符
    }
    pi = pi + 1
  }
  if pi < pat.length() {
    pi = pi + 1 // 跳过 ']'
  }
  pi
}

///|
/// 跳过分组 `(...)` 内容，pi_start 指向 `(` 后第一个字符。
/// 返回 `)` 之后的位置。
fn re_skip_group(pat : Array[Char], pi_start : Int) -> Int {
  let mut pi = pi_start
  let mut depth = 1
  while pi < pat.length() && depth > 0 {
    match pat[pi] {
      '(' => {
        depth = depth + 1
        pi = pi + 1
      }
      ')' => {
        depth = depth - 1
        pi = pi + 1
      }
      '[' => pi = re_skip_class(pat, pi + 1)
      '\\' => pi = pi + 2
      _ => pi = pi + 1
    }
  }
  pi
}

///|
/// 跳过一个原子（不含量词），返回原子结尾之后的位置。
fn re_skip_atom(pat : Array[Char], pi : Int) -> Int {
  if pi >= pat.length() {
    return pi
  }
  match pat[pi] {
    '[' => re_skip_class(pat, pi + 1)
    '(' => re_skip_group(pat, pi + 1)
    '\\' => pi + 2
    _ => pi + 1
  }
}

///|
/// 在 pat[pi_start..pi_end) 中找到顶层 `|` 的位置（不在括号或字符类内）。
/// 未找到则返回 pi_end。
fn re_find_alt(pat : Array[Char], pi_start : Int, pi_end : Int) -> Int {
  let mut pi = pi_start
  while pi < pi_end {
    match pat[pi] {
      '|' => return pi
      '[' => pi = re_skip_class(pat, pi + 1)
      '(' => pi = re_skip_group(pat, pi + 1)
      '\\' => pi = pi + 2
      _ => pi = pi + 1
    }
  }
  pi_end
}

///|
/// 判断 tc 是否匹配字符类 `[...]`。
/// pi_start 指向 `[` 后第一个字符，pi_after 指向 `]` 之后的位置。
fn re_class_matches(
  pat : Array[Char],
  pi_start : Int,
  pi_after : Int,
  tc : Char,
) -> Bool {
  let mut pi = pi_start
  let negate = if pi < pi_after && pat[pi] == '^' {
    pi = pi + 1
    true
  } else {
    false
  }
  let pi_end = pi_after - 1 // `]` 的位置
  // 首字符为 `]` 时按字面量处理
  if pi < pi_end && pat[pi] == ']' {
    if tc == ']' {
      return not(negate)
    }
    pi = pi + 1
  }
  let mut matched = false
  while pi < pi_end {
    if pat[pi] == '\\' && pi + 1 < pi_end {
      let esc = pat[pi + 1]
      let ok = match esc {
        'd' => re_is_digit(tc)
        'D' => not(re_is_digit(tc))
        'w' => re_is_word(tc)
        'W' => not(re_is_word(tc))
        's' => re_is_space(tc)
        'S' => not(re_is_space(tc))
        'n' => tc == '\n'
        't' => tc == '\t'
        'r' => tc == '\r'
        _ => tc == esc
      }
      if ok {
        matched = true
      }
      pi = pi + 2
    } else if pi + 2 < pi_end && pat[pi + 1] == '-' {
      // 范围 [c1-c2]
      let lo = pat[pi]
      let hi = pat[pi + 2]
      if tc >= lo && tc <= hi {
        matched = true
      }
      pi = pi + 3
    } else {
      if tc == pat[pi] {
        matched = true
      }
      pi = pi + 1
    }
  }
  if negate {
    not(matched)
  } else {
    matched
  }
}

///|
/// 在 text[ti] 处匹配原子 pat[atom_start..atom_end)。
/// 返回匹配后的新 ti，失败返回 -1。
fn re_match_one_atom(
  pat : Array[Char],
  atom_start : Int,
  atom_end : Int,
  text : Array[Char],
  ti : Int,
  ti_end : Int,
) -> Int {
  if atom_start >= atom_end {
    return -1
  }
  match pat[atom_start] {
    '.' => if ti >= ti_end || text[ti] == '\n' { -1 } else { ti + 1 }
    '[' => {
      if ti >= ti_end {
        return -1
      }
      if re_class_matches(pat, atom_start + 1, atom_end, text[ti]) {
        ti + 1
      } else {
        -1
      }
    }
    '(' =>
      // 分组内容 pat[atom_start+1..atom_end-1)
      re_match_seq(pat, atom_start + 1, atom_end - 1, text, ti, ti_end)
    '\\' => {
      if atom_start + 1 >= atom_end || ti >= ti_end {
        return -1
      }
      let esc = pat[atom_start + 1]
      let tc = text[ti]
      let ok = match esc {
        'd' => re_is_digit(tc)
        'D' => not(re_is_digit(tc))
        'w' => re_is_word(tc)
        'W' => not(re_is_word(tc))
        's' => re_is_space(tc)
        'S' => not(re_is_space(tc))
        'n' => tc == '\n'
        't' => tc == '\t'
        'r' => tc == '\r'
        _ => tc == esc
      }
      if ok {
        ti + 1
      } else {
        -1
      }
    }
    c => if ti >= ti_end || text[ti] != c { -1 } else { ti + 1 }
  }
}

///|
/// 贪心量词匹配：尽量多地重复匹配原子 pat[atom_start..atom_end)，
/// 然后从最长到最短尝试，直到后续 pat[next_pi..pi_end) 匹配成功。
/// min_count：最少重复次数（`+` 为 1，`*`/`?` 为 0）。
fn re_match_greedy(
  pat : Array[Char],
  atom_start : Int,
  atom_end : Int,
  next_pi : Int,
  pi_end : Int,
  text : Array[Char],
  ti_start : Int,
  ti_end : Int,
  min_count : Int,
) -> Int {
  let positions : Array[Int] = [ti_start]
  let mut cur = ti_start
  while cur < ti_end {
    let next = re_match_one_atom(pat, atom_start, atom_end, text, cur, ti_end)
    if next < 0 || next == cur {
      break
    }
    positions.push(next)
    cur = next
  }
  let mut i = positions.length() - 1
  while i >= min_count {
    let rest = re_match_atoms(pat, next_pi, pi_end, text, positions[i], ti_end)
    if rest >= 0 {
      return rest
    }
    i = i - 1
  }
  -1
}

///|
/// 匹配 pat[pi_in..pi_end) 中的原子序列（无顶层交替）。
/// 返回匹配后的新 ti，失败返回 -1。
fn re_match_atoms(
  pat : Array[Char],
  pi_in : Int,
  pi_end : Int,
  text : Array[Char],
  ti_in : Int,
  ti_end : Int,
) -> Int {
  let mut pi = pi_in
  let mut ti_cur = ti_in
  while pi < pi_end {
    // 行尾锚点 $（仅在模式末尾有效）
    if pat[pi] == '$' && pi + 1 == pi_end {
      return if ti_cur == ti_end { ti_cur } else { -1 }
    }
    let atom_start = pi
    let atom_end = re_skip_atom(pat, pi)
    // 量词检查
    if atom_end < pi_end {
      let q = pat[atom_end]
      if q == '*' || q == '+' || q == '?' {
        let next_pi = atom_end + 1
        let min_count = if q == '+' { 1 } else { 0 }
        return re_match_greedy(
          pat, atom_start, atom_end, next_pi, pi_end, text, ti_cur, ti_end, min_count,
        )
      }
    }
    // 无量词：匹配一个原子并继续
    let new_ti = re_match_one_atom(
      pat, atom_start, atom_end, text, ti_cur, ti_end,
    )
    if new_ti < 0 {
      return -1
    }
    ti_cur = new_ti
    pi = atom_end
  }
  ti_cur
}

///|
/// 匹配 pat[pi..pi_end) 对 text（支持顶层交替）。
/// 返回匹配后的新 ti，失败返回 -1。
fn re_match_seq(
  pat : Array[Char],
  pi : Int,
  pi_end : Int,
  text : Array[Char],
  ti : Int,
  ti_end : Int,
) -> Int {
  let alt_pos = re_find_alt(pat, pi, pi_end)
  if alt_pos < pi_end {
    let left = re_match_atoms(pat, pi, alt_pos, text, ti, ti_end)
    if left >= 0 {
      return left
    }
    return re_match_seq(pat, alt_pos + 1, pi_end, text, ti, ti_end)
  }
  re_match_atoms(pat, pi, pi_end, text, ti, ti_end)
}

///|
/// 在 text 中搜索 pattern（部分匹配）。
/// 若 pattern 以 `^` 开头，仅从位置 0 尝试；否则从每个位置尝试。
fn regex_search(pattern : String, text : String) -> Bool {
  let pat : Array[Char] = []
  for c in pattern {
    pat.push(c)
  }
  let txt : Array[Char] = []
  for c in text {
    txt.push(c)
  }
  let pi_end = pat.length()
  let ti_end = txt.length()
  if pi_end == 0 {
    return true
  }
  let (anchor_start, pi_start) = if pat[0] == '^' {
    (true, 1)
  } else {
    (false, 0)
  }
  if anchor_start {
    re_match_seq(pat, pi_start, pi_end, txt, 0, ti_end) >= 0
  } else {
    let mut ti = 0
    while ti <= ti_end {
      if re_match_seq(pat, pi_start, pi_end, txt, ti, ti_end) >= 0 {
        return true
      }
      ti = ti + 1
    }
    false
  }
}

///|
/// 从 node + field_names 数组中取 child_idx 处的字段名
fn get_field(field_names : Array[String?], child_idx : Int) -> String? {
  if child_idx < field_names.length() {
    field_names[child_idx]
  } else {
    None
  }
}

///|
// 子节点匹配

///|
/// match_children 的回溯递归核心。
///
/// 从 pattern_children[pc_idx] 开始，在 semantic[sem_idx..] 中寻找匹配位置。
/// 对每个候选位置先做字段约束和模式匹配，再递归匹配剩余模式；
/// 若递归失败则回退并尝试下一个候选位置（回溯）。
/// 成功时将本次捕获追加到 captures，返回 true；穷举所有候选后仍失败返回 false。
fn match_children_from(
  pattern_children : Array[PatternChild],
  pc_idx : Int,
  semantic : Array[(Int, @runtime.CstNode)],
  sem_idx : Int,
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
  match_id : Int,
  captures : Array[CaptureResult],
) -> Bool {
  // 所有模式均已匹配成功
  if pc_idx >= pattern_children.length() {
    return true
  }
  let pc = pattern_children[pc_idx]
  let mut i = sem_idx
  while i < semantic.length() {
    let (real_idx, child) = semantic[i]
    // 字段约束检查
    let field_ok = match pc.field {
      None => true
      Some(f) =>
        match get_field(node.field_names, real_idx) {
          Some(cf) => cf == f
          None => false
        }
    }
    if field_ok {
      // 模式匹配（捕获写入临时缓冲）
      let this_captures : Array[CaptureResult] = []
      if try_match(pc.pattern, child, input, table, match_id, this_captures) {
        match pc.capture {
          Some(name) =>
            this_captures.push({ match_id, capture_name: name, node: child })
          None => ()
        }
        // 递归匹配剩余模式；失败时回溯，尝试下一个 sem_idx
        let rest_captures : Array[CaptureResult] = []
        if match_children_from(
            pattern_children,
            pc_idx + 1,
            semantic,
            i + 1,
            node,
            input,
            table,
            match_id,
            rest_captures,
          ) {
          for c in this_captures {
            captures.push(c)
          }
          for c in rest_captures {
            captures.push(c)
          }
          return true
        }
        // 回溯：当前位置不行，继续尝试下一个候选
      }
    }
    i = i + 1
  }
  false
}

///|
/// 在 node.children 中按顺序匹配 pattern_children 列表（有序子集匹配，带回溯）。
fn match_children(
  pattern_children : Array[PatternChild],
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
  match_id : Int,
  captures : Array[CaptureResult],
) -> Bool {
  // 收集语义子节点（排除 extra）
  let semantic : Array[(Int, @runtime.CstNode)] = []
  for i in 0..<node.children.length() {
    let child = node.children[i]
    if not(child.extra) {
      semantic.push((i, child))
    }
  }
  if pattern_children.length() > semantic.length() {
    return false
  }
  let sub_captures : Array[CaptureResult] = []
  if match_children_from(
      pattern_children, 0, semantic, 0, node, input, table, match_id, sub_captures,
    ) {
    for c in sub_captures {
      captures.push(c)
    }
    return true
  }
  false
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
  captures : Array[CaptureResult],
) -> Bool {
  match pattern {
    Wildcard => true
    AnonPattern(s) =>
      // 叶节点，原文与字面量相等
      node.children.is_empty() && node_text(node, input) == s
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
  top_capture : String?,
  predicates : Array[Array[Predicate]],
  node : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
  match_id : Int,
  results : Array[CaptureResult],
) -> Bool {
  let captures : Array[CaptureResult] = []
  if not(try_match(pattern, node, input, table, match_id, captures)) {
    return false
  }
  // 顶层 @capture 标注：将 node 本身加入捕获
  match top_capture {
    Some(name) => captures.push({ match_id, capture_name: name, node })
    None => ()
  }
  // 谓词后置过滤：直接索引当前模式的谓词列表，无需全表扫描
  if pat_idx < predicates.length() {
    for p in predicates[pat_idx] {
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
        Match(cap_name, pattern_str) => {
          let mut ok = false
          for c in captures {
            if c.capture_name == cap_name {
              if regex_search(pattern_str, node_text(c.node, input)) {
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
  results : Array[CaptureResult],
) -> Unit {
  for i in 0..<query.patterns.length() {
    let (pat, top_capture) = query.patterns[i]
    let mid = match_counter[0]
    if try_match_top(
        i,
        pat,
        top_capture,
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
pub fn exec(
  query : CompiledQuery,
  root : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
) -> Array[CaptureResult] {
  let results : Array[CaptureResult] = []
  let counter = [0]
  walk(root, query, input, table, counter, results)
  results
}
