// items_test.mbt — closure / goto_set / build_item_sets / build_goto_map 的黑盒单元测试

// 辅助函数

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
  items.contains({ prod: prod_id, dot })
}

// closure 测试

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

// goto_set 测试

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

// build_item_sets 测试

// build_item_sets / build_goto_map 表驱动不变式测试

///|
priv struct ItemSetsCase {
  name : String
  dsl : String
  /// 状态数下界（便于快速回归）
  min_states : Int
}

///|
fn get_item_sets_cases() -> Array[ItemSetsCase] {
  [
    { name: "线性单终结符", dsl: "start s\nrule s: \"a\"", min_states: 3 },
    {
      name: "选择文法",
      dsl: "start kw\nrule kw: \"if\" | \"else\"",
      min_states: 4,
    },
    { name: "序列文法", dsl: "start s\nrule s: \"a\" \"b\"", min_states: 4 },
    {
      name: "多规则含共享 NT",
      dsl: "start expr\nrule expr: num \"+\" num | num\nrule num: /d+/",
      min_states: 5,
    },
    {
      name: "ε 与左递归",
      dsl: "start items\nrule items: \"x\"*",
      min_states: 2,
    },
  ]
}

///|
test "build_item_sets / 结构不变式" {
  for case in get_item_sets_cases() {
    let ag = build_ag_i(case.dsl)
    let sets = build_item_sets(ag)

    // 1. 状态数下界
    if sets.length() < case.min_states {
      fail(
        "[\{case.name}] 状态数 \{sets.length()} < 预期下界 \{case.min_states}",
      )
    }

    // 2. state 0 含 $accept 的 dot=0 项目
    let accept_prod = ag.productions[0]
    if !has_item(sets[0], accept_prod.id, 0) {
      fail("[\{case.name}] state 0 缺少 $accept 的 dot=0 项目")
    }

    // 3. 接受状态存在（某个状态含 [$accept → body • ]）
    let accept_len = accept_prod.body.length()
    let mut found_accept = false
    for state in sets {
      if has_item(state, accept_prod.id, accept_len) {
        found_accept = true
      }
    }
    if !found_accept {
      fail("[\{case.name}] 未找到接受状态")
    }

    // 4. 状态无重复（去重正确）
    let seen_keys : Map[String, Bool] = Map::new()
    for state in sets {
      let arr = state.to_array()
      arr.sort_by(fn(a, b) { a.compare(b) })
      let mut key = ""
      for item in arr {
        key = key + "\{item.prod}:\{item.dot},"
      }
      if seen_keys.get(key) is Some(_) {
        fail("[\{case.name}] 发现重复状态：\{key}")
      }
      seen_keys.set(key, true)
    }
  }
}

///|
priv struct GotoMapCase {
  name : String
  dsl : String
  /// 起始规则名，用于验证 goto(0, start_NT) 存在
  start_rule : String
}

///|
fn get_goto_map_cases() -> Array[GotoMapCase] {
  [
    {
      name: "线性单终结符",
      dsl: "start s\nrule s: \"a\"",
      start_rule: "s",
    },
    {
      name: "序列文法",
      dsl: "start s\nrule s: \"a\" \"b\"",
      start_rule: "s",
    },
    {
      name: "选择文法",
      dsl: "start kw\nrule kw: \"if\" | \"else\"",
      start_rule: "kw",
    },
    {
      name: "多规则含共享 NT",
      dsl: "start expr\nrule expr: num \"+\" num | num\nrule num: /d+/",
      start_rule: "expr",
    },
    {
      name: "ε 与左递归",
      dsl: "start items\nrule items: \"x\"*",
      start_rule: "items",
    },
  ]
}

///|
test "build_goto_map / 结构不变式" {
  for case in get_goto_map_cases() {
    let ag = build_ag_i(case.dsl)
    let sets = build_item_sets(ag)
    let n = sets.length()
    let gmap = build_goto_map(ag, sets)

    // 1. 转移表非空
    if gmap.length() < 1 {
      fail("[\{case.name}] goto 表为空")
    }

    // 2. state 0 见到起始 NT 应有跳转
    let start_id = match ag.nonterminals.get(case.start_rule) {
      Some(id) => id
      None => fail("[\{case.name}] NT '\{case.start_rule}' 未找到")
    }
    if gmap.get((0, Symbol::NonTerminal(start_id))) is None {
      fail("[\{case.name}] goto(0, \{case.start_rule}) 不存在")
    }

    // 3. 目标状态范围合法
    for _, to in gmap {
      if to < 0 || to >= n {
        fail("[\{case.name}] goto 目标 \{to} 超出范围 [0, \{n})")
      }
    }

    // 4. 正向一致性：from 状态含 body[dot].symbol == sym 的项目
    for key, _ in gmap {
      let (from, sym) = key
      let from_state = sets[from]
      let mut ok = false
      for item in from_state {
        let prod = ag.productions[item.prod]
        if item.dot < prod.body.length() && prod.body[item.dot].symbol == sym {
          ok = true
        }
      }
      if !ok {
        fail(
          "[\{case.name}] 正向一致性：from=\{from} 中无 body[dot]==\{sym} 的项目",
        )
      }
    }

    // 5. 反向一致性：target 状态含 body[dot-1].symbol == sym 的项目
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
      if !ok {
        fail(
          "[\{case.name}] 反向一致性：goto 目标 \{to} 无 body[dot-1]==\{sym} 的项目",
        )
      }
    }
  }
}

///|
test "closure / 空 kernel 返回空集" {
  let ag = build_ag_i("start s\nrule s: \"a\"")
  let empty : Set[LRItem] = Set::new()
  let cl = closure(ag, empty)
  assert_eq(cl.is_empty(), true)
}

///|
test "goto_set / GOTO(EndOfInput) 越过 $ 到达接受项目" {
  // $accept → s $ 的产生式 body = [NonTerminal(s), EndOfInput]
  // 找到包含 [$accept → s • $]（dot=1）的状态，
  // GOTO(EndOfInput) 应得到含 [$accept → s $ •]（dot=2）的集合
  let ag = build_ag_i("start s\nrule s: \"a\"")
  let accept_prod = ag.productions[0]
  // 构造只含 {dot=1} 的 kernel，closure 不会再展开（dot 处为 EndOfInput）
  let kernel : Set[LRItem] = Set::new()
  kernel.add({ prod: accept_prod.id, dot: 1 })
  let cl = closure(ag, kernel)
  let next = goto_set(ag, cl, Symbol::EndOfInput)
  // 结果应含 [$accept → s $ •]（dot = body.length() = 2，即接受项）
  assert_eq(next.is_empty(), false)
  assert_eq(has_item(next, accept_prod.id, accept_prod.body.length()), true)
}
