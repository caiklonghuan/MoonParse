// items_test.mbt — closure / goto_set / build_item_sets / build_goto_map 的黑盒单元测试

// ─── 辅助函数 ─────────────────────────────────────────────────────────────────

///|
fn build_ag_i(dsl : String) -> AugmentedGrammar {
  match @grammar.parse_grammar(dsl) {
    Success(g) => augment_grammar(g)
    Error(_) => panic()
  }
}

///|
/// 在项目集中查找 dot 位于指定位置的项目数量
fn count_items_with_dot(items : Set[LRItem], dot : Int) -> Int {
  let mut n = 0
  for item in items {
    if item.dot == dot {
      n = n + 1
    }
  }
  n
}

///|
/// 检查项目集中是否含指定 (prod_id, dot) 的项目
fn has_item(items : Set[LRItem], prod_id : ProductionId, dot : Int) -> Bool {
  items.contains({ prod: prod_id, dot: dot })
}

// ─── closure 测试 ─────────────────────────────────────────────────────────────

///|
test "closure / 单条产生式、dot 在末尾时不扩展" {
  // s → "a"，$accept → s $
  // kernel = {[$accept → s • $]}（dot 在末尾前一个没有 NT）
  // → 不应展开出新项目（dot 处为 EndOfInput）
  let ag = build_ag_i("start s\nrule s: \"a\"")
  // 找 $accept 产生式
  let accept_prod = ag.productions[0]
  // kernel: dot = 1（dot 处为 EndOfInput）
  let kernel : Set[LRItem] = Set::new()
  kernel.add({ prod: accept_prod.id, dot: 1 })
  let cl = closure(ag, kernel)
  // 无 NT 在 dot 处，所以 closure 不增加项目
  assert_eq(cl.length(), 1)
}

///|
test "closure / dot 处为 NT 时展开出该 NT 的所有产生式" {
  // s → "a"，$accept → • s $（dot=0，dot 处是 NonTerminal(s)）
  // closure 应包含 [s → • "a"]
  let ag = build_ag_i("start s\nrule s: \"a\"")
  let accept_prod = ag.productions[0]
  let kernel : Set[LRItem] = Set::new()
  kernel.add({ prod: accept_prod.id, dot: 0 })
  let cl = closure(ag, kernel)
  // 应含 [$accept → • s $] 和 [s → • "a"]
  assert_eq(cl.length() >= 2, true)
  // 所有新增项目 dot = 0
  assert_eq(count_items_with_dot(cl, 0) >= 2, true)
}

///|
test "closure / Choice NT 展开出所有分支的 dot=0 项目" {
  // kw → "if" | "else"（两条产生式），
  // $accept → • kw $，closure 应含 [kw→•"if"] 和 [kw→•"else"]
  let ag = build_ag_i("start kw\nrule kw: \"if\" | \"else\"")
  let accept_prod = ag.productions[0]
  let kernel : Set[LRItem] = Set::new()
  kernel.add({ prod: accept_prod.id, dot: 0 })
  let cl = closure(ag, kernel)
  // $accept 自身 + kw 的两条产生式
  assert_eq(cl.length() >= 3, true)
}

///|
test "closure / 传递闭包：NT 引用链" {
  // expr → num，num → /d+/
  // $accept → • expr $
  // closure 应链式展开：[$accept→•expr $] → [expr→•num] → [num→•/d+/]
  let ag = build_ag_i("start expr\nrule expr: num\nrule num: /d+/")
  let accept_prod = ag.productions[0]
  let kernel : Set[LRItem] = Set::new()
  kernel.add({ prod: accept_prod.id, dot: 0 })
  let cl = closure(ag, kernel)
  // 至少 3 个 dot=0 的项目
  assert_eq(count_items_with_dot(cl, 0) >= 3, true)
}

///|
test "closure / Repeat 左递归：闭包包含递归项目本身" {
  // items → ε | items "x"（左递归）
  // $accept → • items $
  // closure 应含 [items→•] 和 [items→•items "x"]
  let ag = build_ag_i("start items\nrule items: \"x\"*")
  let accept_prod = ag.productions[0]
  let kernel : Set[LRItem] = Set::new()
  kernel.add({ prod: accept_prod.id, dot: 0 })
  let cl = closure(ag, kernel)
  // items 有两条产生式（ε 和左递归），都应出现 dot=0
  assert_eq(cl.length() >= 3, true)
}

// ─── goto_set 测试 ────────────────────────────────────────────────────────────

///|
test "goto_set / dot 越过终结符后前进一步" {
  // s → "a"，$accept → s $
  // 先取初始闭包，再 GOTO(sym = Terminal(a)) → s → "a" •
  let ag = build_ag_i("start s\nrule s: \"a\"")
  // 找 s 的产生式（第一条 head == s 的产生式）
  let s_id = match ag.nonterminals.get("s") {
    Some(id) => id
    None => fail("NT s 未找到")
  }
  let mut s_prod_id = 0
  for prod in ag.productions {
    if prod.head == s_id {
      s_prod_id = prod.id
    }
  }
  let t = match ag.terminals.get("lit:a") {
    Some(t) => t
    None => fail("terminal lit:a 未找到")
  }
  let kernel : Set[LRItem] = Set::new()
  kernel.add({ prod: s_prod_id, dot: 0 })
  let cl = closure(ag, kernel)
  let next = goto_set(ag, cl, Symbol::Terminal(t))
  // 应得到 [s → "a" •]，dot = 1
  assert_eq(next.length(), 1)
  assert_eq(has_item(next, s_prod_id, 1), true)
}

///|
test "goto_set / 符号不在 dot 处时返回空集" {
  let ag = build_ag_i("start s\nrule s: \"a\"")
  let kernel : Set[LRItem] = Set::new()
  kernel.add({ prod: ag.productions[0].id, dot: 0 })
  let cl = closure(ag, kernel)
  // 用 "b"（不存在）来 GOTO，应返回空集
  let next = goto_set(ag, cl, Symbol::Terminal(999))
  assert_eq(next.is_empty(), true)
}

///|
test "goto_set / GOTO(NT) 越过非终结符" {
  // $accept → • s $，GOTO(s) 应得到 [$accept → s • $]
  let ag = build_ag_i("start s\nrule s: \"a\"")
  let accept_prod = ag.productions[0]
  let kernel : Set[LRItem] = Set::new()
  kernel.add({ prod: accept_prod.id, dot: 0 })
  let cl = closure(ag, kernel)
  let s_id = match ag.nonterminals.get("s") {
    Some(id) => id
    None => fail("NT s 未找到")
  }
  let next = goto_set(ag, cl, Symbol::NonTerminal(s_id))
  // 应含 [$accept → s • $]
  assert_eq(has_item(next, accept_prod.id, 1), true)
}

// ─── build_item_sets 测试 ────────────────────────────────────────────────────

///|
test "build_item_sets / 最小文法至少有 2 个状态" {
  // s → "a"：state0（初始），state1（见到 "a" 后）
  let ag = build_ag_i("start s\nrule s: \"a\"")
  let sets = build_item_sets(ag)
  assert_eq(sets.length() >= 2, true)
}

///|
test "build_item_sets / 初始状态（state 0）含 $accept 的 dot=0 项目" {
  let ag = build_ag_i("start s\nrule s: \"a\"")
  let sets = build_item_sets(ag)
  let accept_prod_id = ag.productions[0].id
  assert_eq(has_item(sets[0], accept_prod_id, 0), true)
}

///|
test "build_item_sets / 状态不重复（去重正确）" {
  // 文法中存在多条路径，但相同 kernel 应合并为同一状态
  let ag = build_ag_i("start expr\nrule expr: num \"+\" num | num\nrule num: /d+/")
  let sets = build_item_sets(ag)
  // 验证无重复 key
  let seen : Map[String, Bool] = Map::new()
  for state in sets {
    let arr = state.to_array()
    arr.sort_by(fn(a, b) { a.compare(b) })
    let mut key = ""
    for item in arr {
      key = key + "\{item.prod}:\{item.dot},"
    }
    if seen.get(key) is Some(_) {
      fail("发现重复状态：\{key}")
    }
    seen.set(key, true)
  }
}

///|
test "build_item_sets / 接受状态存在（含 dot=body.len 的 $accept 项目）" {
  let ag = build_ag_i("start s\nrule s: \"a\"")
  let sets = build_item_sets(ag)
  let accept_prod = ag.productions[0]
  let accept_len = accept_prod.body.length()
  let mut found = false
  for state in sets {
    if has_item(state, accept_prod.id, accept_len) {
      found = true
    }
  }
  assert_eq(found, true)
}

///|
test "build_item_sets / 左递归文法可正常构建（无死循环）" {
  // items → ε | items "x"（左递归）
  let ag = build_ag_i("start items\nrule items: \"x\"*")
  let sets = build_item_sets(ag)
  assert_eq(sets.length() >= 2, true)
}

// ─── build_goto_map 测试 ─────────────────────────────────────────────────────

///|
test "build_goto_map / 转移表非空" {
  let ag = build_ag_i("start s\nrule s: \"a\"")
  let sets = build_item_sets(ag)
  let gmap = build_goto_map(ag, sets)
  assert_eq(gmap.length() >= 1, true)
}

///|
test "build_goto_map / state 0 见到起始 NT 应跳转到另一状态" {
  // state 0 含 [$accept → • s $]，GOTO(0, s) 应有目标状态
  let ag = build_ag_i("start s\nrule s: \"a\"")
  let sets = build_item_sets(ag)
  let gmap = build_goto_map(ag, sets)
  let s_id = match ag.nonterminals.get("s") {
    Some(id) => id
    None => fail("NT s 未找到")
  }
  let target = gmap.get((0, Symbol::NonTerminal(s_id)))
  assert_eq(target is Some(_), true)
}

///|
test "build_goto_map / 转移目标与 item_sets 下标一致" {
  // 验证 goto_map 中所有目标 StateId 都在 [0, states.length) 范围内
  let ag = build_ag_i("start expr\nrule expr: num \"+\" num | num\nrule num: /d+/")
  let sets = build_item_sets(ag)
  let n = sets.length()
  let gmap = build_goto_map(ag, sets)
  for _, target in gmap {
    if target < 0 || target >= n {
      fail("goto 目标 \{target} 超出状态范围 [0, \{n})")
    }
  }
}

///|
test "build_goto_map / 双向一致性：goto(s, sym) = t 则 t 含该 item" {
  // 对每条 (from, sym) → to 的 goto，
  // 验证 sets[to] 含至少一个 dot > 0 且 body[dot-1].symbol == sym 的项目
  let ag = build_ag_i("start s\nrule s: \"a\" \"b\"")
  let sets = build_item_sets(ag)
  let gmap = build_goto_map(ag, sets)
  for key, to in gmap {
    let (_, sym) = key
    let target_state = sets[to]
    let mut ok = false
    for item in target_state {
      if item.dot > 0 {
        let prod = ag.productions[item.prod]
        if prod.body[item.dot - 1].symbol == sym {
          ok = true
        }
      }
    }
    if not(ok) {
      fail("goto 目标状态无对应 dot-1 项目，sym=\{sym}")
    }
  }
}

///|
test "build_goto_map / 双向一致性：goto(s, sym) = t 则 t 含该项目" {
  // 对每条 (from, sym) → to 的 goto，
  // 验证 sets[to] 含至少一个 dot > 0 的对应产生式项目
  let ag = build_ag_i("start s\nrule s: \"a\" \"b\"")
  let sets = build_item_sets(ag)
  let gmap = build_goto_map(ag, sets)
  for key, to in gmap {
    let (_, sym) = key
    // sets[to] 中应该有某个 item，其 prod 在 dot-1 处的 symbol == sym
    let target_state = sets[to]
    let mut ok = false
    for item in target_state {
      if item.dot > 0 {
        let prod = ag.productions[item.prod]
        if prod.body[item.dot - 1].symbol == sym {
          ok = true
        }
      }
    }
    if not(ok) {
      fail("goto 目标状态无对应 dot-1 项目")
    }
  }
}
