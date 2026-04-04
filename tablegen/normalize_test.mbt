// normalize_test.mbt — augment_grammar() 的表格驱动黑盒测试

///|
priv struct NormalizeCase {
  name : String
  dsl : String
  /// 预期用户定义非终结符数量（不含辅助 NT，辅助 NT 以 _ 开头；含 $accept = +1）
  expected_named_nt_count : Int
  /// 预期注册的终结符 key（"lit:x" / "re:re" / "·"）
  expected_terminals : Array[String]
  /// $accept 产生式的体长度（start + $ = 2）
  accept_body_len : Int
  /// 是否含 ε 产生式（body 为空的产生式）
  has_epsilon_prod : Bool
  /// 预期产生式总数下界（至少有这么多条）
  min_prod_count : Int
}

///|
fn get_normalize_cases() -> Array[NormalizeCase] {
  [
    // 最小线性文法
    {
      name: "线性 - 单字面量",
      dsl: "start s\nrule s: \"hello\"",
      expected_named_nt_count: 1,
      expected_terminals: ["lit:hello"],
      accept_body_len: 2,
      has_epsilon_prod: false,
      min_prod_count: 2,
    },
    // 序列
    {
      name: "序列 - 两终结符",
      dsl: "start ab\nrule ab: \"a\" \"b\"",
      expected_named_nt_count: 1,
      expected_terminals: ["lit:a", "lit:b"],
      accept_body_len: 2,
      has_epsilon_prod: false,
      min_prod_count: 2,
    },
    // 选择
    {
      name: "选择 - 两分支",
      dsl: "start kw\nrule kw: \"if\" | \"else\"",
      expected_named_nt_count: 1,
      expected_terminals: ["lit:if", "lit:else"],
      accept_body_len: 2,
      has_epsilon_prod: false,
      min_prod_count: 3,
    },
    // Optional（含 ε 产生式）
    {
      name: "Optional - 产生 ε 产生式",
      dsl: "start s\nrule s: \"a\"?",
      expected_named_nt_count: 1,
      expected_terminals: ["lit:a"],
      accept_body_len: 2,
      has_epsilon_prod: true,
      min_prod_count: 3,
    },
    // Repeat（左递归 + ε）
    {
      name: "Repeat - 左递归",
      dsl: "start items\nrule items: \"x\"*",
      expected_named_nt_count: 1,
      expected_terminals: ["lit:x"],
      accept_body_len: 2,
      has_epsilon_prod: true,
      min_prod_count: 3,
    },
    // Plus
    {
      name: "Plus - 一或多次",
      dsl: "start digits\nrule digits: /\\d/+",
      expected_named_nt_count: 1,
      expected_terminals: ["re:\\d"],
      accept_body_len: 2,
      has_epsilon_prod: false,
      min_prod_count: 3,
    },
    // Regex 终结符
    {
      name: "Regex 终结符",
      dsl: "start id\nrule id: /[a-z]+/",
      expected_named_nt_count: 1,
      expected_terminals: ["re:[a-z]+"],
      accept_body_len: 2,
      has_epsilon_prod: false,
      min_prod_count: 2,
    },
    // AnyChar 终结符
    {
      name: "AnyChar 终结符",
      dsl: "start any\nrule any: .",
      expected_named_nt_count: 1,
      expected_terminals: ["\u00b7"],
      accept_body_len: 2,
      has_epsilon_prod: false,
      min_prod_count: 2,
    },
    // 字段名保留
    {
      name: "Field 元数据保留",
      dsl: "start assign\nrule assign: lhs: /[a-z]+/ \"=\" rhs: /[a-z]+/",
      expected_named_nt_count: 1,
      expected_terminals: ["re:[a-z]+", "lit:="],
      accept_body_len: 2,
      has_epsilon_prod: false,
      min_prod_count: 2,
    },
    // 10. 多规则 + RuleRef
    {
      name: "多规则 - 规则引用",
      dsl: "start expr\nrule expr: num \"+\" num\nrule num: /\\d+/",
      expected_named_nt_count: 2,
      expected_terminals: ["re:\\d+", "lit:+"],
      accept_body_len: 2,
      has_epsilon_prod: false,
      min_prod_count: 3,
    },
    // 11. Prec 标注
    {
      name: "Prec 标注",
      dsl: "start e\nrule e: prec.left(1, \"x\" \"+\" \"y\")",
      expected_named_nt_count: 1,
      expected_terminals: ["lit:x", "lit:+", "lit:y"],
      accept_body_len: 2,
      has_epsilon_prod: false,
      min_prod_count: 2,
    },
    // 12. RepeatRange
    {
      name: "RepeatRange {2,4}",
      dsl: "start hex\nrule hex: /[0-9a-f]/{2,4}",
      expected_named_nt_count: 1,
      expected_terminals: ["re:[0-9a-f]"],
      accept_body_len: 2,
      has_epsilon_prod: true,
      min_prod_count: 3,
    },
  ]
}

// 辅助函数

///|
/// 通过 nonterminals map 逆向查找 NT id 对应的名称（黑盒可访问）
fn nt_name(ag : AugmentedGrammar, id : NonTerminalId) -> String {
  for name, nid in ag.nonterminals {
    if nid == id {
      return name
    }
  }
  "<unknown:\{id}>"
}

///|
fn count_helper_nts(ag : AugmentedGrammar) -> Int {
  let mut n = 0
  for name, _ in ag.nonterminals {
    if name.length() > 0 && name[0] == '_' {
      n = n + 1
    }
  }
  n
}

///|
fn count_user_nts(ag : AugmentedGrammar) -> Int {
  ag.nonterminals.length() - count_helper_nts(ag)
}

///|
fn has_epsilon(ag : AugmentedGrammar) -> Bool {
  for prod in ag.productions {
    if prod.body.length() == 0 {
      return true
    }
  }
  false
}

///|
fn has_terminal_keys(ag : AugmentedGrammar, keys : Array[String]) -> Bool {
  for key in keys {
    if ag.terminals.get(key) is None {
      return false
    }
  }
  true
}

// 测试块

///|
test "augment_grammar / $accept 产生式首位且体末为 EndOfInput" {
  for case in get_normalize_cases() {
    let g = match @grammar.parse_grammar(case.dsl) {
      Success(g) => g
      Error(e) => fail("[\{case.name}] parse failed: \{e.message}")
    }
    let ag = augment_grammar(g)
    if ag.productions.length() == 0 {
      fail("[\{case.name}] productions 为空")
    }
    let first = ag.productions[0]
    let head = nt_name(ag, first.head)
    if head != "$accept" {
      fail("[\{case.name}] 首条产生式 head = \{head}，预期 $accept")
    }
    let last_sym = first.body[first.body.length() - 1].symbol
    if last_sym != Symbol::EndOfInput {
      fail(
        "[\{case.name}] $accept 产生式末尾应为 EndOfInput，实为 \{last_sym}",
      )
    }
  }
}

///|
test "augment_grammar / $accept 体长度" {
  for case in get_normalize_cases() {
    let g = match @grammar.parse_grammar(case.dsl) {
      Success(g) => g
      Error(e) => fail("[\{case.name}] parse failed: \{e.message}")
    }
    let ag = augment_grammar(g)
    let first = ag.productions[0]
    if first.body.length() != case.accept_body_len {
      fail(
        "[\{case.name}] $accept 体长度 = \{first.body.length()}，预期 \{case.accept_body_len}",
      )
    }
  }
}

///|
test "augment_grammar / 终结符注册正确" {
  for case in get_normalize_cases() {
    let g = match @grammar.parse_grammar(case.dsl) {
      Success(g) => g
      Error(e) => fail("[\{case.name}] parse failed: \{e.message}")
    }
    let ag = augment_grammar(g)
    if not(has_terminal_keys(ag, case.expected_terminals)) {
      fail(
        "[\{case.name}] 缺少预期终结符，期望: \{case.expected_terminals}",
      )
    }
  }
}

///|
test "augment_grammar / 命名非终结符数量" {
  for case in get_normalize_cases() {
    let g = match @grammar.parse_grammar(case.dsl) {
      Success(g) => g
      Error(e) => fail("[\{case.name}] parse failed: \{e.message}")
    }
    let ag = augment_grammar(g)
    let expected = case.expected_named_nt_count + 1
    let got = count_user_nts(ag)
    if got != expected {
      fail("[\{case.name}] 用户 NT + $accept = \{got}，预期 \{expected}")
    }
  }
}

///|
test "augment_grammar / ε 产生式存在性" {
  for case in get_normalize_cases() {
    let g = match @grammar.parse_grammar(case.dsl) {
      Success(g) => g
      Error(e) => fail("[\{case.name}] parse failed: \{e.message}")
    }
    let ag = augment_grammar(g)
    let got = has_epsilon(ag)
    if got != case.has_epsilon_prod {
      fail(
        "[\{case.name}] ε 产生式存在性 = \{got}，预期 \{case.has_epsilon_prod}",
      )
    }
  }
}

///|
test "augment_grammar / 产生式总数下界" {
  for case in get_normalize_cases() {
    let g = match @grammar.parse_grammar(case.dsl) {
      Success(g) => g
      Error(e) => fail("[\{case.name}] parse failed: \{e.message}")
    }
    let ag = augment_grammar(g)
    let n = ag.productions.length()
    if n < case.min_prod_count {
      fail(
        "[\{case.name}] 产生式总数 \{n} < 预期下界 \{case.min_prod_count}",
      )
    }
  }
}

///|
test "augment_grammar / Field 元数据保留" {
  let dsl = "start assign\nrule assign: lhs: /[a-z]+/ \"=\" rhs: /[a-z]+/"
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  let assign_id = match ag.nonterminals.get("assign") {
    Some(id) => id
    None => fail("NT assign 未注册")
  }
  let mut found_left = false
  let mut found_right = false
  for prod in ag.productions {
    if prod.head == assign_id {
      for sym in prod.body {
        match sym.field_name {
          Some("lhs") => found_left = true
          Some("rhs") => found_right = true
          _ => ()
        }
      }
    }
  }
  if not(found_left) {
    fail("assign 产生式应含 field_name = \"lhs\"")
  }
  if not(found_right) {
    fail("assign 产生式应含 field_name = \"rhs\"")
  }
}

///|
test "augment_grammar / Prec 标注传递" {
  let dsl = "start e\nrule e: prec.left(5, \"x\" \"+\" \"y\")"
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  let e_id = match ag.nonterminals.get("e") {
    Some(id) => id
    None => fail("NT e 未注册")
  }
  let mut found = false
  for prod in ag.productions {
    if prod.head == e_id {
      match prod.prec {
        Some(5) => found = true
        _ => ()
      }
    }
  }
  if not(found) {
    fail("e 的产生式应携带 prec = 5")
  }
}

///|
test "augment_grammar / Repeat 左递归形态" {
  let dsl = "start items\nrule items: \"x\"*"
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  let mut has_left_rec = false
  for prod in ag.productions {
    if prod.body.length() == 2 {
      match prod.body[0].symbol {
        NonTerminal(id) => if id == prod.head { has_left_rec = true }
        _ => ()
      }
    }
  }
  if not(has_left_rec) {
    fail("Repeat 应生成左递归产生式 (head → head x)")
  }
}

///|
test "augment_grammar / TerminalDef 类型正确" {
  let dsl = "start s\nrule s: \"lit\" | /re+/ | ."
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  match ag.terminals.get("lit:lit") {
    Some(id) =>
      assert_eq(ag.terminal_patterns.get(id), Some(TerminalDef::Literal("lit")))
    None => fail("缺少 Literal terminal")
  }
  match ag.terminals.get("re:re+") {
    Some(id) =>
      assert_eq(ag.terminal_patterns.get(id), Some(TerminalDef::Regex("re+")))
    None => fail("缺少 Regex terminal")
  }
  match ag.terminals.get("\u00b7") {
    Some(id) =>
      assert_eq(ag.terminal_patterns.get(id), Some(TerminalDef::AnyChar))
    None => fail("缺少 AnyChar terminal")
  }
}

///|
test "augment_grammar / extras 透传到 AugmentedGrammar" {
  let dsl = "start s\nrule s: \"a\"\nextras [/\\s+/]"
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  assert_eq(g.extras.length(), 1)
  let ag = augment_grammar(g)
  assert_eq(ag.extras.length(), 1)
  // extras terminal 应被注册到 terminal_patterns
  let tid = ag.extras[0]
  assert_eq(ag.terminal_patterns.get(tid), Some(TerminalDef::Regex("\\s+")))
}

///|
test "augment_grammar / 多个 extras 注册为独立 terminal" {
  let dsl = "start s\nrule s: \"a\"\nextras [/\\s+/, /\\t+/]"
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  assert_eq(ag.extras.length(), 2)
}

///|
test "augment_grammar / extras 不重复注册同一 terminal" {
  // extras 里和 rule 里都用了 /\\s+/，terminal ID 应相同
  let dsl = "start s\nrule s: /\\s+/\nextras [/\\s+/]"
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  // extras[0] 的 ID 应和 rule body 里的 ID 相同（幂等注册）
  let extras_tid = ag.extras[0]
  let rule_tid = match ag.terminals.get("re:\\s+") {
    Some(id) => id
    None => fail("缺少 re:\\s+ terminal")
  }
  assert_eq(extras_tid, rule_tid)
}

// 以下 6 个测试专门验证 expand_into 的核心分支结构正确性

///|
test "augment_grammar / Plus - 无 epsilon、左递归2条产生式" {
  // Plus(inner) 生成恰好 2 条产生式：head→inner 和 head→head inner（左递归）
  // 不含 epsilon（区别于 Repeat）
  let dsl = "start xs\nrule xs: \"x\"+"
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  let digits_id = match ag.nonterminals.get("xs") {
    Some(id) => id
    None => fail("NT xs not found")
  }
  let mut count = 0
  let mut has_eps = false
  let mut has_left_rec = false
  for prod in ag.productions {
    if prod.head == digits_id {
      count = count + 1
      if prod.body.length() == 0 {
        has_eps = true
      }
      if prod.body.length() == 2 &&
        prod.body[0].symbol == Symbol::NonTerminal(digits_id) {
        has_left_rec = true
      }
    }
  }
  assert_eq(count, 2)
  assert_eq(has_eps, false)
  assert_eq(has_left_rec, true)
}

///|
test "augment_grammar / Optional - epsilon + inner 两条产生式" {
  // Optional(inner) 生成恰好 2 条产生式：head→epsilon 和 head→inner
  let dsl = "start maybe\nrule maybe: \"a\"?"
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  let maybe_id = match ag.nonterminals.get("maybe") {
    Some(id) => id
    None => fail("NT maybe not found")
  }
  let mut count = 0
  let mut has_eps = false
  let mut has_nonempty = false
  for prod in ag.productions {
    if prod.head == maybe_id {
      count = count + 1
      if prod.body.length() == 0 {
        has_eps = true
      }
      if prod.body.length() == 1 {
        has_nonempty = true
      }
    }
  }
  assert_eq(count, 2)
  assert_eq(has_eps, true)
  assert_eq(has_nonempty, true)
}

///|
test "augment_grammar / RepeatRange {2,4} - body contains 2 terminals + 2 helper NT refs" {
  // RepeatRange(inner, 2, 4): hex has 1 production, body length = 4
  //   first 2 = Terminal (mandatory), last 2 = NonTerminal (optional helper)
  let dsl = "start hex\nrule hex: /[0-9a-f]/{2,4}"
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  let hex_id = match ag.nonterminals.get("hex") {
    Some(id) => id
    None => fail("NT hex not found")
  }
  let mut hex_prod_count = 0
  let mut body_len = 0
  let mut helper_ref_count = 0
  let mut term_ref_count = 0
  for prod in ag.productions {
    if prod.head == hex_id {
      hex_prod_count = hex_prod_count + 1
      body_len = prod.body.length()
      for sym in prod.body {
        match sym.symbol {
          NonTerminal(_) => helper_ref_count = helper_ref_count + 1
          Terminal(_) => term_ref_count = term_ref_count + 1
          _ => ()
        }
      }
    }
  }
  assert_eq(hex_prod_count, 1)
  assert_eq(body_len, 4)
  assert_eq(term_ref_count, 2)
  assert_eq(helper_ref_count, 2)
}

///|
test "augment_grammar / Tagged - @label propagated to body field_name" {
  // Tagged("lhs", inner) as top-level rule pattern triggers expand_into.Tagged
  // production body[0].field_name should be Some("lhs")
  let dsl = "start s\nrule s: @lhs \"a\""
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  let s_id = match ag.nonterminals.get("s") {
    Some(id) => id
    None => fail("NT s not found")
  }
  let mut found = false
  for prod in ag.productions {
    if prod.head == s_id && prod.body.length() == 1 {
      match prod.body[0].field_name {
        Some("lhs") => found = true
        _ => ()
      }
    }
  }
  assert_true(found)
}

///|
test "augment_grammar / Not in Seq tail - production carries NotFollowedBy constraint" {
  // rule s: "a" !"b" => Seq([Literal("a"), Not(Literal("b"))])
  // expand_into.Seq extracts trailing Not as constraint:
  //   production.lookahead = Some(NotFollowedBy([...]))
  //   production.body = [sym_a]  (Not contributes no symbol)
  let dsl = "start s\nrule s: \"a\" !\"b\""
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  let s_id = match ag.nonterminals.get("s") {
    Some(id) => id
    None => fail("NT s not found")
  }
  let mut found_constraint = false
  for prod in ag.productions {
    if prod.head == s_id {
      match prod.lookahead {
        Some(NotFollowedBy(tids)) => {
          found_constraint = true
          assert_true(tids.length() > 0)
          assert_eq(prod.body.length(), 1)
        }
        _ => ()
      }
    }
  }
  assert_true(found_constraint)
}

///|
test "augment_grammar / And in Seq tail - production carries FollowedBy constraint" {
  // rule s: "a" &"b" => Seq([Literal("a"), And(Literal("b"))])
  // expand_into.Seq extracts trailing And as constraint:
  //   production.lookahead = Some(FollowedBy([...]))
  let dsl = "start s\nrule s: \"a\" &\"b\""
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  let s_id = match ag.nonterminals.get("s") {
    Some(id) => id
    None => fail("NT s not found")
  }
  let mut found_constraint = false
  for prod in ag.productions {
    if prod.head == s_id {
      match prod.lookahead {
        Some(FollowedBy(tids)) => {
          found_constraint = true
          assert_true(tids.length() > 0)
          assert_eq(prod.body.length(), 1)
        }
        _ => ()
      }
    }
  }
  assert_true(found_constraint)
}
