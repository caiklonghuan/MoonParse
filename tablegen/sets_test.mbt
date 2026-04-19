// sets_test.mbt — nullable / first_set / first_seq / follow_set 的黑盒单元测试
//
// 测试文法通过 @grammar.parse_grammar + augment_grammar 构建，
// 保证测试自洽，无需手工构造 AugmentedGrammar。

// 辅助函数

///|
/// 从 AugmentedGrammar 的 nonterminals map 中逆向查找名称
fn nt_id(ag : AugmentedGrammar, name : String) -> NonTerminalId {
  match ag.nonterminals.get(name) {
    Some(id) => id
    None => panic()
  }
}

///|
/// 从 AugmentedGrammar 的 terminals map 中查找终结符 ID（key 格式 "lit:x" / "re:re"）
fn term_id(ag : AugmentedGrammar, key : String) -> TerminalId {
  match ag.terminals.get(key) {
    Some(id) => id
    None => panic()
  }
}

///|
/// 解析 DSL 并增广
fn build_ag(dsl : String) -> AugmentedGrammar {
  match @grammar.parse_grammar(dsl) {
    Success(g) => augment_grammar(g)
    Error(_) => panic()
  }
}

// nullable 测试

///|
test "nullable / 表驱动" {
  let cases : Array[(String, (AugmentedGrammar) -> Array[Symbol], Bool)] = [
    // 空序列恒为 true
    ("start s\nrule s: \"a\"", fn(_ag) { [] }, true),
    // 含终结符序列为 false
    (
      "start s\nrule s: \"a\"",
      fn(ag) { [Symbol::Terminal(term_id(ag, "lit:a"))] },
      false,
    ),
    // 不可 nullable 的 NT 序列为 false（s → "a" 无 ε 产生式）
    (
      "start s\nrule s: \"a\"",
      fn(ag) { [Symbol::NonTerminal(nt_id(ag, "s"))] },
      false,
    ),
    // Optional 展开后 NT 可 nullable
    (
      "start s\nrule s: \"a\"?",
      fn(ag) { [Symbol::NonTerminal(nt_id(ag, "s"))] },
      true,
    ),
    // Repeat 展开后 NT 可 nullable
    (
      "start items\nrule items: \"x\"*",
      fn(ag) { [Symbol::NonTerminal(nt_id(ag, "items"))] },
      true,
    ),
    // Plus 展开后 NT 不可 nullable
    (
      "start digits\nrule digits: /d/+",
      fn(ag) { [Symbol::NonTerminal(nt_id(ag, "digits"))] },
      false,
    ),
    // 含可 nullable NT 的混合序列（s → "a"? "b"? 的二元体）
    (
      "start s\nrule s: \"a\"? \"b\"?",
      fn(ag) {
        let s = nt_id(ag, "s")
        let mut found : Array[Symbol] = []
        for prod in ag.productions {
          if prod.head == s && prod.body.length() == 2 {
            found = prod.body.map(fn(bs) { bs.symbol })
          }
        }
        found
      },
      true,
    ),
  ]
  for item in cases {
    let ag = build_ag(item.0)
    assert_eq(nullable(ag, (item.1)(ag)), item.2)
  }
}

// first_set 测试

///|
test "first_set / Terminal 返回自身" {
  let ag = build_ag("start s\nrule s: \"x\"")
  let t = term_id(ag, "lit:x")
  let fs = first_set(ag, Symbol::Terminal(t))
  assert_eq(fs.contains(t), true)
  assert_eq(fs.length(), 1)
}

///|
test "first_set / EndOfInput 返回 eoi_id" {
  let ag = build_ag("start s\nrule s: \"x\"")
  let fs = first_set(ag, Symbol::EndOfInput)
  assert_eq(fs.contains(eoi_id), true)
  assert_eq(fs.length(), 1)
}

///|
test "first_set / 直接引用终结符的 NT" {
  // s → "ab"，FIRST(s) = {"ab"}
  let ag = build_ag("start s\nrule s: \"ab\"")
  let t = term_id(ag, "lit:ab")
  let s = nt_id(ag, "s")
  let fs = first_set(ag, Symbol::NonTerminal(s))
  assert_eq(fs.contains(t), true)
}

///|
test "first_set / Choice NT 包含所有分支首终结符" {
  // kw → "if" | "else"，FIRST(kw) = {"if", "else"}
  let ag = build_ag("start kw\nrule kw: \"if\" | \"else\"")
  let t_if = term_id(ag, "lit:if")
  let t_else = term_id(ag, "lit:else")
  let kw = nt_id(ag, "kw")
  let fs = first_set(ag, Symbol::NonTerminal(kw))
  assert_eq(fs.contains(t_if), true)
  assert_eq(fs.contains(t_else), true)
}

///|
test "first_set / Repeat NT 包含内部符号首终结符" {
  // items → "x"*，FIRST(items) 含 "x"（也含 nullable，但 FIRST 不含 ε 标记）
  let ag = build_ag("start items\nrule items: \"x\"*")
  let t = term_id(ag, "lit:x")
  let items = nt_id(ag, "items")
  let fs = first_set(ag, Symbol::NonTerminal(items))
  assert_eq(fs.contains(t), true)
}

///|
test "first_set / 链式 NT 传递" {
  // expr → num，num → /d+/，FIRST(expr) 应含 /d+/ 的终结符
  let ag = build_ag("start expr\nrule expr: num\nrule num: /d+/")
  let t = term_id(ag, "re:d+")
  let expr = nt_id(ag, "expr")
  let fs = first_set(ag, Symbol::NonTerminal(expr))
  assert_eq(fs.contains(t), true)
}

// first_seq 测试

///|
test "first_seq / 空序列返回空集" {
  let ag = build_ag("start s\nrule s: \"a\"")
  let fs = first_seq(ag, [])
  assert_eq(fs.length(), 0)
}

///|
test "first_seq / 序列首为终结符" {
  let ag = build_ag("start s\nrule s: \"a\" \"b\"")
  let t_a = term_id(ag, "lit:a")
  let t_b = term_id(ag, "lit:b")
  let fs = first_seq(ag, [Symbol::Terminal(t_a), Symbol::Terminal(t_b)])
  // FIRST("a" "b") = {"a"}，因为 "a" 不可 nullable
  assert_eq(fs.contains(t_a), true)
  assert_eq(fs.contains(t_b), false)
}

///|
test "first_seq / 首 NT 可 nullable 时继续传播" {
  // opt → "a"?，FIRST([opt, "b"]) 应含 "a" 和 "b"
  let ag = build_ag("start s\nrule s: \"a\"? \"b\"")
  let t_a = term_id(ag, "lit:a")
  let t_b = term_id(ag, "lit:b")
  // 构造 opt NT id（辅助 NT，名称以 _ 开头）
  let mut opt_id : NonTerminalId = 0
  for name, id in ag.nonterminals {
    if name.length() > 0 && name[0] == '_' {
      opt_id = id
    }
  }
  let fs = first_seq(ag, [Symbol::NonTerminal(opt_id), Symbol::Terminal(t_b)])
  assert_eq(fs.contains(t_a), true)
  assert_eq(fs.contains(t_b), true)
}

///|
test "first_seq / EndOfInput 符号处理" {
  let ag = build_ag("start s\nrule s: \"a\"")
  let fs = first_seq(ag, [Symbol::EndOfInput])
  assert_eq(fs.contains(eoi_id), true)
}

// follow_set 测试

///|
test "follow_set / $accept.start 的 FOLLOW 含 eoi_id" {
  // $accept → s $，故 FOLLOW(s) ⊇ {eoi_id}
  let ag = build_ag("start s\nrule s: \"a\"")
  let s = nt_id(ag, "s")
  let fow = follow_set(ag, s)
  assert_eq(fow.contains(eoi_id), true)
}

///|
test "follow_set / A → α B t 使 FOLLOW(B) ∋ t" {
  // expr → num "+" num，FOLLOW(num) 应含 "+"
  let ag = build_ag("start expr\nrule expr: num \"+\" num\nrule num: /d+/")
  let num = nt_id(ag, "num")
  let t_plus = term_id(ag, "lit:+")
  let fow = follow_set(ag, num)
  assert_eq(fow.contains(t_plus), true)
}

///|
test "follow_set / A → α B 时 FOLLOW(A) ⊆ FOLLOW(B)" {
  // s → A，A 在尾部 → FOLLOW(A) ⊇ FOLLOW(s) ⊇ {eoi_id}
  let ag = build_ag("start s\nrule s: a_nt\nrule a_nt: \"a\"")
  let a_nt = nt_id(ag, "a_nt")
  let fow = follow_set(ag, a_nt)
  assert_eq(fow.contains(eoi_id), true)
}

///|
test "follow_set / A → α B C 且 C nullable 时 FOLLOW(A) ⊆ FOLLOW(B)" {
  // s → main opt，opt → "c"? → opt 可 nullable
  // 故 FOLLOW(main) ⊇ FOLLOW(s) ⊇ {eoi_id}，且 ∋ FIRST(opt) = {"c"}
  let ag = build_ag(
    "start s\nrule s: main opt\nrule main: \"m\"\nrule opt: \"c\"?",
  )
  let main_nt = nt_id(ag, "main")
  let t_c = term_id(ag, "lit:c")
  let fow = follow_set(ag, main_nt)
  // FIRST(opt) = {"c"} 应在 FOLLOW(main)
  assert_eq(fow.contains(t_c), true)
  // opt nullable，故 FOLLOW(s) 即 eoi 也应传播到 FOLLOW(main)
  assert_eq(fow.contains(eoi_id), true)
}

///|
test "follow_set / 互递归 NT 的 FOLLOW 通过不动点正确传播" {
  // a_nt → b_nt | "a"，b_nt → a_nt | "b"
  // s → a_nt，故 FOLLOW(a_nt) ⊇ {eoi_id}
  // a_nt → b_nt（b_nt 在尾部）→ FOLLOW(b_nt) ⊇ FOLLOW(a_nt) ⊇ {eoi_id}
  // b_nt → a_nt（a_nt 在尾部）→ FOLLOW(a_nt) ⊇ FOLLOW(b_nt) ⊇ {eoi_id}
  // 不动点收敛后两者均含 eoi_id
  let ag = build_ag(
    "start s\nrule s: a_nt\nrule a_nt: b_nt | \"a\"\nrule b_nt: a_nt | \"b\"",
  )
  let a = nt_id(ag, "a_nt")
  let b = nt_id(ag, "b_nt")
  let fow_a = follow_set(ag, a)
  let fow_b = follow_set(ag, b)
  assert_eq(fow_a.contains(eoi_id), true)
  assert_eq(fow_b.contains(eoi_id), true)
}

///|
test "follow_set / 多次出现的 NT 合并所有 lookahead" {
  // expr → num "+" num | num，num 出现在不同位置
  // FOLLOW(num) 应含 "+" 和 eoi_id
  let ag = build_ag(
    "start expr\nrule expr: num \"+\" num | num\nrule num: /d+/",
  )
  let num = nt_id(ag, "num")
  let t_plus = term_id(ag, "lit:+")
  let fow = follow_set(ag, num)
  assert_eq(fow.contains(t_plus), true)
  assert_eq(fow.contains(eoi_id), true)
}
