///|
// ─── §3 LR(0) 项目集构建 ─────────────────────────────────────────────────────
//
// 实现 design.md §3 的四个公开函数：
//   closure(grammar, items)              -> Set[LRItem]
//   goto_set(grammar, items, sym)        -> Set[LRItem]
//   build_item_sets(grammar)             -> Array[Set[LRItem]]
//   build_goto_map(grammar, item_sets)   -> Map[(StateId, Symbol), StateId]
//
// 项目集去重键：将 Set[LRItem] 中的元素排序后转为 Array，作为 Map key 的字符串。
// LRItem 已 derive(Compare)，因此可以排序。

// ─── 辅助：项目集规范化键 ─────────────────────────────────────────────────────

///|
/// 将项目集转为确定性字符串 key，用于 Map 去重。
///
/// 格式：`prod:dot` 对按 LRItem 自然序排序后以 `,` 拼接。
/// 编码无歧义：prod 与 dot 均为非负整数，不含 `:` / `,`，分隔符唯一确定边界。
/// 使用 StringBuilder 避免 O(n²) 字符串拼接。
fn item_set_key(items : Set[LRItem]) -> String {
  let arr = items.to_array()
  arr.sort_by(fn(a, b) { a.compare(b) })
  let buf = StringBuilder::new()
  let mut first = true
  for item in arr {
    if !first {
      buf.write_char(',')
    }
    buf.write_string("\{item.prod}:\{item.dot}")
    first = false
  }
  buf.to_string()
}

// ─── 内部加速辅助 ─────────────────────────────────────────────────────────────

///|
/// 预构建 NonTerminalId → [ProductionId] 索引。
/// build_item_sets / build_goto_map 各构建一次，closure_fast 用它替代 O(P) 全量扫描。
fn build_head_prods_index(grammar : AugmentedGrammar) -> Map[Int, Array[Int]] {
  let idx : Map[Int, Array[Int]] = Map::new()
  for p in grammar.productions {
    match idx.get(p.head) {
      None => idx.set(p.head, [p.id])
      Some(arr) => arr.push(p.id)
    }
  }
  idx
}

///|
/// 使用预构建索引的 closure（O(1) 查 head→prods，省去每次 O(P) 扫描）。
fn closure_fast(
  grammar : AugmentedGrammar,
  items : Set[LRItem],
  head_prods : Map[Int, Array[Int]],
) -> Set[LRItem] {
  let result : Set[LRItem] = Set::new()
  let queue : Array[LRItem] = []
  for item in items {
    if result.add_and_check(item) {
      queue.push(item)
    }
  }
  let mut qi = 0
  while qi < queue.length() {
    let item = queue[qi]
    qi = qi + 1
    let prod = grammar.productions[item.prod]
    if item.dot < prod.body.length() {
      match prod.body[item.dot].symbol {
        NonTerminal(nt) =>
          match head_prods.get(nt) {
            None => ()
            Some(prod_ids) =>
              for pid in prod_ids {
                let new_item = { prod: pid, dot: 0 }
                if result.add_and_check(new_item) {
                  queue.push(new_item)
                }
              }
          }
        _ => ()
      }
    }
  }
  result
}

///|
/// 使用预构建索引的 GOTO(I, X)。
fn goto_set_fast(
  grammar : AugmentedGrammar,
  items : Set[LRItem],
  sym : Symbol,
  head_prods : Map[Int, Array[Int]],
) -> Set[LRItem] {
  let kernel : Set[LRItem] = Set::new()
  for item in items {
    let prod = grammar.productions[item.prod]
    if item.dot < prod.body.length() && prod.body[item.dot].symbol == sym {
      kernel.add({ prod: item.prod, dot: item.dot + 1 })
    }
  }
  if kernel.is_empty() {
    Set::new()
  } else {
    closure_fast(grammar, kernel, head_prods)
  }
}

// ─── 公开 API ─────────────────────────────────────────────────────────────────

///|
/// 项目集闭包：closure(I)。
///
/// 对 I 中所有形如 [A → α • B β] 的项目，将 B 的全部产生式的起始项
/// [B → • γ] 加入集合；重复直至不动点。
pub fn closure(grammar : AugmentedGrammar, items : Set[LRItem]) -> Set[LRItem] {
  let result : Set[LRItem] = Set::new()
  // 工作队列：记录待处理的新增项目
  let queue : Array[LRItem] = []

  // 初始化：将 items 全部加入
  for item in items {
    if result.add_and_check(item) {
      queue.push(item)
    }
  }

  let mut qi = 0
  while qi < queue.length() {
    let item = queue[qi]
    qi = qi + 1
    let prod = grammar.productions[item.prod]
    // 若 dot 未越过产生式末尾，检查 dot 处的符号
    if item.dot < prod.body.length() {
      match prod.body[item.dot].symbol {
        NonTerminal(nt) =>
          // 将 nt 的所有产生式以 dot=0 加入
          for p in grammar.productions {
            if p.head == nt {
              let new_item = { prod: p.id, dot: 0 }
              if result.add_and_check(new_item) {
                queue.push(new_item)
              }
            }
          }
        _ => ()
      }
    }
  }
  result
}

///|
/// GOTO(I, X)：将集合 I 中所有 dot 处为符号 X 的项目的 dot 前进一步，
/// 再取其闭包。若无项目越过 X，返回空集。
pub fn goto_set(
  grammar : AugmentedGrammar,
  items : Set[LRItem],
  sym : Symbol,
) -> Set[LRItem] {
  let kernel : Set[LRItem] = Set::new()
  for item in items {
    let prod = grammar.productions[item.prod]
    if item.dot < prod.body.length() && prod.body[item.dot].symbol == sym {
      kernel.add({ prod: item.prod, dot: item.dot + 1 })
    }
  }
  if kernel.is_empty() {
    Set::new()
  } else {
    closure(grammar, kernel)
  }
}

///|
/// 构建规范 LR(0) 项目集族（所有 DFA 状态）。
///
/// 算法（BFS）：
///   1. 从增广起始产生式 [$accept → • start $] 的闭包作为初始状态
///   2. 对每个状态中所有 dot 处出现的符号，计算 GOTO，得到新状态
///   3. 用规范化 key 去重，新状态入队，直至不动点
///
/// 返回值下标即 StateId（state 0 = 初始状态）。
pub fn build_item_sets(grammar : AugmentedGrammar) -> Array[Set[LRItem]] {
  let states : Array[Set[LRItem]] = []
  // key → StateId，用于去重
  let seen : Map[String, StateId] = Map::new()

  // 预构建 head→productions 索引（只构建一次，供所有 closure_fast 调用共享）
  let head_prods = build_head_prods_index(grammar)

  // 找到增广起始产生式（head == grammar.start，即 $accept）
  let mut start_prod_id : ProductionId = 0
  for p in grammar.productions {
    if p.head == grammar.start {
      start_prod_id = p.id
      break
    }
  }
  let init_item : LRItem = { prod: start_prod_id, dot: 0 }
  let init_set : Set[LRItem] = Set::new()
  init_set.add(init_item)
  let s0 = closure_fast(grammar, init_set, head_prods)
  let s0_key = item_set_key(s0)
  states.push(s0)
  seen.set(s0_key, 0)

  // BFS
  let mut qi = 0
  while qi < states.length() {
    let state = states[qi]
    qi = qi + 1

    // 收集该状态 dot 处出现的所有符号（去重）
    let syms : Set[Symbol] = Set::new()
    for item in state {
      let prod = grammar.productions[item.prod]
      if item.dot < prod.body.length() {
        syms.add(prod.body[item.dot].symbol)
      }
    }

    // 对每个符号计算 GOTO
    for sym in syms {
      let next = goto_set_fast(grammar, state, sym, head_prods)
      if !next.is_empty() {
        let key = item_set_key(next)
        if seen.get(key) is None {
          let new_id = states.length()
          states.push(next)
          seen.set(key, new_id)
        }
      }
    }
  }
  states
}

///|
/// 构建 GOTO 转移表：(StateId, Symbol) → StateId。
///
/// 对每个状态重新计算一次 goto_set，借助 item_set_key 查找目标 StateId。
pub fn build_goto_map(
  grammar : AugmentedGrammar,
  item_sets : Array[Set[LRItem]],
) -> Map[(StateId, Symbol), StateId] {
  // 预构建 head→productions 索引
  let head_prods = build_head_prods_index(grammar)

  // 先建立 key → StateId 索引，O(n)
  let key_to_id : Map[String, StateId] = Map::new()
  let mut sid = 0
  for state in item_sets {
    key_to_id.set(item_set_key(state), sid)
    sid = sid + 1
  }

  let goto_map : Map[(StateId, Symbol), StateId] = Map::new()
  let mut from_id = 0
  for state in item_sets {
    // 收集 dot 处符号
    let syms : Set[Symbol] = Set::new()
    for item in state {
      let prod = grammar.productions[item.prod]
      if item.dot < prod.body.length() {
        syms.add(prod.body[item.dot].symbol)
      }
    }
    // 计算 GOTO 并查表
    for sym in syms {
      let next = goto_set_fast(grammar, state, sym, head_prods)
      if !next.is_empty() {
        let key = item_set_key(next)
        match key_to_id.get(key) {
          Some(to_id) => goto_map.set((from_id, sym), to_id)
          None => ()
        }
      }
    }
    from_id = from_id + 1
  }
  goto_map
}
