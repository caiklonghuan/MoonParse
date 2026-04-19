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
    if !has_terminal_keys(ag, case.expected_terminals) {
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
  if !found_left {
    fail("assign 产生式应含 field_name = \"lhs\"")
  }
  if !found_right {
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
  if !found {
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
  if !has_left_rec {
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
  let xs_id = match ag.nonterminals.get("xs") {
    Some(id) => id
    None => fail("NT xs not found")
  }
  let mut count = 0
  let mut has_eps = false
  let mut has_left_rec = false
  for prod in ag.productions {
    if prod.head == xs_id {
      count = count + 1
      if prod.body.length() == 0 {
        has_eps = true
      }
      if prod.body.length() == 2 &&
        prod.body[0].symbol == Symbol::NonTerminal(xs_id) {
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

// @hide 属性测试

///|
test "augment_grammar / @hide 规则的 NT 元数据 is_named = false" {
  // @hide rule hidden: "x" — 规则名不以 _ 开头但有 @hide，应强制 is_named = false
  let dsl = "start s\n@hide rule hidden: \"x\"\nrule s: hidden"
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  let mut found_is_named : Bool? = None
  for m in ag.nt_metas {
    if m.name == "hidden" {
      found_is_named = Some(m.is_named)
      break
    }
  }
  match found_is_named {
    Some(v) => assert_eq(v, false)
    None => fail("NT 'hidden' not found in nt_metas")
  }
}

///|
test "augment_grammar / @hide 规则仍生成产生式（正常参与文法）" {
  let dsl = "start s\n@hide rule hidden: \"x\"\nrule s: hidden"
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  let hidden_id = match ag.nonterminals.get("hidden") {
    Some(id) => id
    None => fail("NT 'hidden' not found")
  }
  let mut has_prod = false
  for prod in ag.productions {
    if prod.head == hidden_id {
      has_prod = true
      break
    }
  }
  assert_true(has_prod)
}

///|
test "augment_grammar / 普通规则 is_named 不受 @hide 影响" {
  let dsl = "start s\n@hide rule hidden: \"x\"\nrule s: hidden"
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  let mut found_is_named : Bool? = None
  for m in ag.nt_metas {
    if m.name == "s" {
      found_is_named = Some(m.is_named)
      break
    }
  }
  match found_is_named {
    Some(v) => assert_eq(v, true)
    None => fail("NT 's' not found in nt_metas")
  }
}

// @inline 属性测试

///|
test "augment_grammar / @inline 规则不创建命名 NT" {
  // @inline rule kw: "if" | "else" — 引用处展开，kw 本身不注册为命名 NT
  let dsl = "start s\n@inline rule kw: \"if\" | \"else\"\nrule s: kw"
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  assert_eq(ag.nonterminals.contains("kw"), false)
}

///|
test "augment_grammar / @inline 规则引用处生成辅助 NT" {
  let dsl = "start s\n@inline rule kw: \"a\" | \"b\"\nrule s: kw"
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  let s_id = match ag.nonterminals.get("s") {
    Some(id) => id
    None => fail("NT 's' not found")
  }
  let mut body_has_nt = false
  for prod in ag.productions {
    if prod.head == s_id {
      for bs in prod.body {
        match bs.symbol {
          NonTerminal(_) => body_has_nt = true
          _ => ()
        }
      }
    }
  }
  assert_true(body_has_nt)
}

///|
test "augment_grammar / @inline 规则两处引用各自生成独立辅助 NT（不共享）" {
  let dsl = "start s\n@inline rule op: \"+\" | \"-\"\nrule s: op op"
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  let s_id = match ag.nonterminals.get("s") {
    Some(id) => id
    None => fail("NT 's' not found")
  }
  let mut nt_count = 0
  for prod in ag.productions {
    if prod.head == s_id {
      for bs in prod.body {
        match bs.symbol {
          NonTerminal(_) => nt_count = nt_count + 1
          _ => ()
        }
      }
    }
  }
  assert_eq(nt_count, 2)
}

///|
test "augment_grammar / declared_conflicts 字段透传" {
  // conflicts 声明放在 rules 之前，避免 parse_sequence 将 "conflicts [[" 误读为模板实例化
  let dsl = "start s\nconflicts [[a, b]]\nrule s: a | b\nrule a: \"x\"\nrule b: \"x\""
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  assert_eq(ag.declared_conflicts.length(), 1)
  assert_eq(ag.declared_conflicts[0].contains("a"), true)
  assert_eq(ag.declared_conflicts[0].contains("b"), true)
}

// ── field_slots 字段布局元数据测试 ─────────────────────────────────────────────

///|
test "augment_grammar / field_slots - Seq 含 Field 时收集字段名" {
  let dsl =
    #|start binary_expr
    #|rule expr: binary_expr | number
    #|rule number: /[0-9]+/
    #|rule binary_expr: lhs: expr "+" rhs: expr
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  let mut slots : Array[String] = []
  for m in ag.nt_metas {
    if m.name == "binary_expr" {
      slots = m.field_slots
      break
    }
  }
  assert_true(slots.contains("lhs"))
  assert_true(slots.contains("rhs"))
  assert_eq(slots.length(), 2)
}

///|
test "augment_grammar / field_slots - 无字段规则 field_slots 为空" {
  let dsl = "start s\nrule s: \"hello\" \"world\""
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  let mut slots : Array[String]? = None
  for m in ag.nt_metas {
    if m.name == "s" {
      slots = Some(m.field_slots)
      break
    }
  }
  match slots {
    None => fail("NT 's' not found")
    Some(s) => assert_eq(s.length(), 0)
  }
}

///|
test "augment_grammar / field_slots - 同名字段只出现一次（去重）" {
  let dsl =
    #|start list
    #|rule item: /[a-z]+/
    #|rule list: items: item | list items: item
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  let mut slots : Array[String]? = None
  for m in ag.nt_metas {
    if m.name == "list" {
      slots = Some(m.field_slots)
      break
    }
  }
  match slots {
    None => fail("NT 'list' not found")
    Some(s) => {
      assert_true(s.contains("items"))
      let count = s.fold(
        fn(acc, x) { if x == "items" { acc + 1 } else { acc } },
        init=0,
      )
      assert_eq(count, 1)
    }
  }
}

///|
test "augment_grammar / field_slots - 合成 NT field_slots 为空" {
  // Repeat 出现在 Seq 内部时，to_symbol 会创建辅助合成 NT（is_synthetic = true）
  // 辅助 NT 没有 Field/Tagged，field_slots 应为空
  let dsl = "start s\nrule item: /[a-z]/\nrule s: \"a\" item* \"b\""
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  let mut synthetic_count = 0
  for m in ag.nt_metas {
    if m.is_synthetic {
      synthetic_count = synthetic_count + 1
      assert_eq(m.field_slots.length(), 0)
    }
  }
  // 至少有 $accept 和 Repeat 辅助 NT 两个合成 NT
  assert_true(synthetic_count >= 2)
}

///|
test "augment_grammar / 独立 Not 规则体 - 生成 ε 产生式带 NotFollowedBy 约束" {
  // rule s: !"b"  →  expand_into.Not 分支  →  s → ε [NotFollowedBy([lit:b])]
  let dsl = "start s\nrule s: !\"b\""
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
    if prod.head == s_id {
      match prod.lookahead {
        Some(NotFollowedBy(tids)) => {
          assert_eq(prod.body.length(), 0)
          assert_true(tids.length() > 0)
          found = true
        }
        _ => ()
      }
    }
  }
  assert_true(found)
}

///|
test "augment_grammar / 独立 And 规则体 - 生成 ε 产生式带 FollowedBy 约束" {
  // rule s: &"b"  →  expand_into.And 分支  →  s → ε [FollowedBy([lit:b])]
  let dsl = "start s\nrule s: &\"b\""
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
    if prod.head == s_id {
      match prod.lookahead {
        Some(FollowedBy(tids)) => {
          assert_eq(prod.body.length(), 0)
          assert_true(tids.length() > 0)
          found = true
        }
        _ => ()
      }
    }
  }
  assert_true(found)
}

///|
test "augment_grammar / Alias - alias_name 透传到产生式" {
  // rule s: alias("foo", "x" | "y")
  // expand_into.Alias 展开内层 Choice 到辅助 NT，并对辅助 NT 的每条产生式标记 alias_name = "foo"
  let dsl = "start s\nrule s: alias(\"foo\", \"x\" | \"y\")"
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  let s_id = match ag.nonterminals.get("s") {
    Some(id) => id
    None => fail("NT s not found")
  }
  // s 的两条产生式（Choice 展开）各自应携带 alias_name = Some("foo")
  let mut alias_count = 0
  for prod in ag.productions {
    if prod.head == s_id {
      match prod.alias_name {
        Some("foo") => alias_count = alias_count + 1
        _ => ()
      }
    }
  }
  assert_eq(alias_count, 2)
}

///|
test "augment_grammar / 混用 & 和 ! 时 normalize 保留 FollowedBy" {
  // rule s: "a" &"b" !"c"  →  Seq 尾部同时有 And 和 Not
  // expand_into.Seq 中 FollowedBy 优先：约束应为 FollowedBy([lit:b])，
  // NotFollowedBy 被丢弃（对应 validator 中 LookaheadMixedAssertions 的行为说明）
  let dsl = "start s\nrule s: \"a\" &\"b\" !\"c\""
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  let s_id = match ag.nonterminals.get("s") {
    Some(id) => id
    None => fail("NT s not found")
  }
  let mut constraint_kind : String = "none"
  for prod in ag.productions {
    if prod.head == s_id {
      match prod.lookahead {
        Some(FollowedBy(_)) => constraint_kind = "followed_by"
        Some(NotFollowedBy(_)) => constraint_kind = "not_followed_by"
        None => ()
      }
    }
  }
  assert_eq(constraint_kind, "followed_by")
}

///|
test "augment_grammar / externals 声明名称在规则体内映射为 Terminal" {
  // externals 中声明 indent，在 rule 体内引用 indent 时，
  // to_symbol.RuleRef 走 ext: 路径，返回 Terminal 而非 NonTerminal
  let dsl = "start s\nexternals [indent]\nrule s: indent"
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(e) => fail("parse failed: \{e.message}")
  }
  let ag = augment_grammar(g)
  let s_id = match ag.nonterminals.get("s") {
    Some(id) => id
    None => fail("NT s not found")
  }
  // indent 的 ext: terminal 必须存在
  let ext_tid = match ag.terminals.get("ext:indent") {
    Some(id) => id
    None => fail("terminal ext:indent not registered")
  }
  // s 的产生式 body 中应包含 Terminal(ext_tid)，而不是 NonTerminal
  let mut mapped_as_terminal = false
  for prod in ag.productions {
    if prod.head == s_id {
      for bs in prod.body {
        match bs.symbol {
          Terminal(tid) => if tid == ext_tid { mapped_as_terminal = true }
          _ => ()
        }
      }
    }
  }
  assert_true(mapped_as_terminal)
}
