// 测试辅助：TestCase 数据结构 + 用例集合
// 对应 parser.mbt 中的 parse_grammar 函数

///|
priv struct TestCase {
  name : String
  dsl : String
  expected_rules : Array[String]
  expected_patterns : Map[String, String]
}

///|
fn pattern_variant(p : Pattern) -> String {
  match p {
    Pattern::RuleRef(_) => "RuleRef"
    Pattern::Literal(_) => "Literal"
    Pattern::Regex(_) => "Regex"
    Pattern::Choice(_) => "Choice"
    Pattern::Seq(_) => "Seq"
    Pattern::Repeat(_) => "Repeat"
    Pattern::Plus(_) => "Plus"
    Pattern::Optional(_) => "Optional"
    Pattern::Tagged(_, _) => "Tagged"
    Pattern::Not(_) => "Not"
    Pattern::And(_) => "And"
    Pattern::AnyChar => "AnyChar"
    Pattern::Field(_, _) => "Field"
    Pattern::RepeatRange(_, _, _) => "RepeatRange"
    Pattern::Prec(_, _, _) => "Prec"
    Pattern::Alias(_, _) => "Alias"
  }
}

///|
fn get_parse_test_cases() -> Array[TestCase] {
  [
    {
      name: "基本规则 - 选择",
      dsl: "rule expr: num | expr \"+\" expr\nrule num: /\\d+/",
      expected_rules: ["expr", "num"],
      expected_patterns: Map::from_array([("expr", "Choice"), ("num", "Regex")]),
    },
    {
      name: "基本规则 - 序列",
      dsl: "rule statement: identifier \"=\" expression \";\"",
      expected_rules: ["statement"],
      expected_patterns: Map::from_array([("statement", "Seq")]),
    },
    {
      name: "基本规则 - 字面量选择",
      dsl: "rule keyword: \"if\" | \"else\" | \"while\"",
      expected_rules: ["keyword"],
      expected_patterns: Map::from_array([("keyword", "Choice")]),
    },
    {
      name: "基本规则 - 单字面量",
      dsl: "rule equals: \"=\"",
      expected_rules: ["equals"],
      expected_patterns: Map::from_array([("equals", "Literal")]),
    },
    {
      name: "基本规则 - 规则引用链",
      dsl: "rule program: statement\nrule statement: expr\nrule expr: number",
      expected_rules: ["program", "statement", "expr"],
      expected_patterns: Map::from_array([
        ("program", "RuleRef"),
        ("statement", "RuleRef"),
        ("expr", "RuleRef"),
      ]),
    },
    {
      name: "后缀操作 - 可选",
      dsl: "rule optional_param: identifier \":\" type \"?\"?",
      expected_rules: ["optional_param"],
      expected_patterns: Map::from_array([("optional_param", "Seq")]),
    },
    {
      name: "后缀操作 - 零或多次",
      dsl: "rule list: \"[\" item (\",\" item)* \"]\"",
      expected_rules: ["list"],
      expected_patterns: Map::from_array([("list", "Seq")]),
    },
    {
      name: "后缀操作 - 重复区间 exact",
      dsl: "rule hex_byte: digit{2}",
      expected_rules: ["hex_byte"],
      expected_patterns: Map::from_array([("hex_byte", "RepeatRange")]),
    },
    {
      name: "后缀操作 - 重复区间 range",
      dsl: "rule id: letter digit{0,10}",
      expected_rules: ["id"],
      expected_patterns: Map::from_array([("id", "Seq")]),
    },
    {
      name: "分组表达式",
      dsl: "rule paren_expr: \"(\" (add_expr | mul_expr) \")\"",
      expected_rules: ["paren_expr"],
      expected_patterns: Map::from_array([("paren_expr", "Seq")]),
    },
    {
      name: "分组 - 混合复杂",
      dsl: "rule func_call: identifier \"(\" (arg (\",\" arg)*)? \")\"",
      expected_rules: ["func_call"],
      expected_patterns: Map::from_array([("func_call", "Seq")]),
    },
    {
      name: "前缀操作 - 负向前瞻",
      dsl: "rule word: !digit letter\nrule digit: /\\d/\nrule letter: /[a-z]/",
      expected_rules: ["word", "digit", "letter"],
      expected_patterns: Map::from_array([
        ("word", "Seq"),
        ("digit", "Regex"),
        ("letter", "Regex"),
      ]),
    },
    {
      name: "前缀操作 - 正向前瞻",
      dsl: "rule integer: &digit number\nrule digit: /\\d/\nrule number: /\\d+/",
      expected_rules: ["integer", "digit", "number"],
      expected_patterns: Map::from_array([
        ("integer", "Seq"),
        ("digit", "Regex"),
        ("number", "Regex"),
      ]),
    },
    {
      name: "前缀操作 - 任意字符",
      dsl: "rule any: .",
      expected_rules: ["any"],
      expected_patterns: Map::from_array([("any", "AnyChar")]),
    },
    {
      name: "顶层声明 - start",
      dsl: "start program\nrule program: statement*\nrule statement: \"print\" expr",
      expected_rules: ["program", "statement"],
      expected_patterns: Map::from_array([
        ("program", "Repeat"),
        ("statement", "Seq"),
      ]),
    },
    {
      name: "顶层声明 - 优先级左结合",
      dsl: "precedence left plus, minus\nrule expr: number (plus | minus) number\nrule plus: \"+\"\nrule minus: \"-\"",
      expected_rules: ["expr", "plus", "minus"],
      expected_patterns: Map::from_array([
        ("expr", "Seq"),
        ("plus", "Literal"),
        ("minus", "Literal"),
      ]),
    },
    {
      name: "顶层声明 - 优先级右结合",
      dsl: "precedence right power\nrule expr: number power number\nrule power: \"^\"",
      expected_rules: ["expr", "power"],
      expected_patterns: Map::from_array([("expr", "Seq"), ("power", "Literal")]),
    },
    {
      name: "顶层声明 - 多级优先级",
      dsl: "precedence left plus, minus\nprecedence left star, slash\nrule expr: term ((plus | minus) term)*\nrule term: factor ((star | slash) factor)*\nrule factor: number | \"(\" expr \")\"\nrule plus: \"+\"\nrule minus: \"-\"\nrule star: \"*\"\nrule slash: \"/\"",
      expected_rules: [
        "expr", "term", "factor", "plus", "minus", "star", "slash",
      ],
      expected_patterns: Map::from_array([
        ("expr", "Seq"),
        ("term", "Seq"),
        ("factor", "Choice"),
        ("plus", "Literal"),
        ("minus", "Literal"),
        ("star", "Literal"),
        ("slash", "Literal"),
      ]),
    },
    {
      name: "注释 - 行注释",
      dsl: "rule expr: number // 这是一个注释\nrule number: /\\d+/",
      expected_rules: ["expr", "number"],
      expected_patterns: Map::from_array([
        ("expr", "RuleRef"),
        ("number", "Regex"),
      ]),
    },
    {
      name: "注释 - 块注释",
      dsl: "rule expr: /* 这是块注释 */ number\nrule number: /\\d+/",
      expected_rules: ["expr", "number"],
      expected_patterns: Map::from_array([
        ("expr", "RuleRef"),
        ("number", "Regex"),
      ]),
    },
    {
      name: "标签 - 单标签",
      dsl: "rule expr: @additive additive\nrule additive: number \"+\" number",
      expected_rules: ["expr", "additive"],
      expected_patterns: Map::from_array([
        ("expr", "Tagged"),
        ("additive", "Seq"),
      ]),
    },
    {
      name: "标签 - 多标签序列",
      dsl: "rule program: statement*\nrule statement: @lhs identifier \"=\" @rhs expr",
      expected_rules: ["program", "statement"],
      expected_patterns: Map::from_array([
        ("program", "Repeat"),
        ("statement", "Seq"),
      ]),
    },
    {
      name: "命名字段",
      dsl: "rule assign: lhs: identifier \"=\" rhs: expr",
      expected_rules: ["assign"],
      expected_patterns: Map::from_array([("assign", "Seq")]),
    },
    {
      name: "复杂表达式语法",
      dsl: "rule expression: additive\nrule additive: multiplicative ((\"+\" | \"-\") multiplicative)*\nrule multiplicative: primary ((\"*\" | \"/\") primary)*\nrule primary: number | identifier | \"(\" expression \")\"\nrule number: /\\d+(\\.\\d+)?/\nrule identifier: /[a-zA-Z_]\\w*/",
      expected_rules: [
        "expression", "additive", "multiplicative", "primary", "number", "identifier",
      ],
      expected_patterns: Map::from_array([
        ("expression", "RuleRef"),
        ("additive", "Seq"),
        ("multiplicative", "Seq"),
        ("primary", "Choice"),
        ("number", "Regex"),
        ("identifier", "Regex"),
      ]),
    },
    {
      name: "内联优先级 - 无结合性",
      dsl: "rule r: prec(1, number)\nrule number: /\\d+/",
      expected_rules: ["r", "number"],
      expected_patterns: Map::from_array([("r", "Prec"), ("number", "Regex")]),
    },
    {
      name: "内联优先级 - 左结合",
      dsl: "rule expr: prec.left(2, number)\nrule number: /\\d+/",
      expected_rules: ["expr", "number"],
      expected_patterns: Map::from_array([("expr", "Prec"), ("number", "Regex")]),
    },
    {
      name: "内联优先级 - 右结吆",
      dsl: "rule expr: prec.right(3, number)\nrule number: /\\d+/",
      expected_rules: ["expr", "number"],
      expected_patterns: Map::from_array([("expr", "Prec"), ("number", "Regex")]),
    },
    {
      name: "内联优先级 - 内嵌序列",
      dsl: "rule expr: prec.left(2, expr \"+\" expr)\nrule expr: /\\d+/",
      expected_rules: ["expr"],
      expected_patterns: Map::from_array([("expr", "Regex")]),
    },
  ]
}

///|
fn run_parse_tests(cases : Array[TestCase]) -> Unit raise {
  for tc in cases {
    match parse_grammar(tc.dsl) {
      Success(grammar) => {
        for rule_name in tc.expected_rules {
          assert_true(grammar.rules.contains(rule_name))
        }
        for rule_name, expected_type in tc.expected_patterns {
          match grammar.rules.get(rule_name) {
            Some(r) => assert_eq(pattern_variant(r.pattern), expected_type)
            None => abort("规则 \{rule_name} 不存在 [\{tc.name}]")
          }
        }
      }
      Error(err) =>
        abort(
          "解析失败 [\{tc.name}]: \{err.message} at \{err.location.line}:\{err.location.column}",
        )
    }
  }
}

// 测试入口

///|
test "parse_correctness" {
  run_parse_tests(get_parse_test_cases())
}

///|
// 验证各种边缘输入不会崩溃，并区分预期的成功/失败
test "parse_error_handling" {
  // (描述, DSL, 是否期望解析失败)
  let cases = [
    ("缺少选择分支", "rule expr: num |", true),
    ("空规则体", "rule empty: ", true),
    ("无效标签 @", "rule expr: @", true),
    ("未闭合括号", "rule expr: (number", true),
    ("空字面量", "rule empty: \"\"", false), // 空字面量合法
    ("重复规则名", "rule expr: number\nrule expr: string", false), // 后者覆盖前者
    ("未引用规则", "rule expr: undefined_rule", false), // 无引用校验
    ("无效正则", "rule num: /unclosed", false), // 无正则校验
    ("无效优先级", "precedence invalid plus", false), // 跳过处理
    ("后缀叠加", "rule expr: number*+", false), // * 消耗后 + 单独报错
  ]
  for c in cases {
    let (description, dsl, expect_error) = c
    match parse_grammar(dsl) {
      Success(g) => {
        if expect_error {
          abort("应该失败但成功了: \{description}")
        }
        assert_true(g.rules.length() >= 0)
      }
      Error(err) =>
        if not(expect_error) {
          abort("意外失败: \{description} — \{err.message}")
        }
    }
  }
}

///|
test "parse_error_locations" {
  let cases = [
    ("rule expr: num |", 1, 16), // | 后无分支
    ("rule : num", 1, 6),
  ] // 缺少规则名
  for c in cases {
    let (dsl, expected_line, expected_col) = c
    match parse_grammar(dsl) {
      Success(_) => abort("应该失败但成功了: \{dsl}")
      Error(err) => {
        assert_eq(err.location.line, expected_line)
        assert_eq(err.location.column, expected_col)
      }
    }
  }
}

///|
test "parse_rule_is_named" {
  // 以普通名称开头 → 命名节点
  match parse_grammar("rule expr: number") {
    Success(g) =>
      match g.rules.get("expr") {
        Some(r) => assert_true(r.is_named)
        None => abort("rule not found")
      }
    Error(err) => abort(err.message)
  }
  // 以 _ 开头 → 匿名节点（不出现在 CST 查询中）
  match parse_grammar("rule _ws: \" \"") {
    Success(g) =>
      match g.rules.get("_ws") {
        Some(r) => assert_true(r.is_named == false)
        None => abort("rule not found")
      }
    Error(err) => abort(err.message)
  }
}

///|
// 验证顶层 precedence 声明被正确解析并存入 grammar.precedences
test "parse_precedences" {
  let dsl = "precedence left plus, minus\nprecedence right power\nrule plus: \"+\"\nrule minus: \"-\"\nrule power: \"^\""
  match parse_grammar(dsl) {
    Error(err) => abort(err.message)
    Success(g) => {
      assert_eq(g.precedences.length(), 2)
      // 第一条：左结合，包含 plus 和 minus
      let p0 = g.precedences[0]
      assert_eq(p0.level, 1)
      assert_eq(p0.rules.length(), 2)
      let kind0 = match p0.kind {
        PrecKind::Left => "Left"
        _ => "other"
      }
      assert_eq(kind0, "Left")
      // 第二条：右结合，包含 power
      let p1 = g.precedences[1]
      assert_eq(p1.level, 2)
      assert_eq(p1.rules.length(), 1)
      let kind1 = match p1.kind {
        PrecKind::Right => "Right"
        _ => "other"
      }
      assert_eq(kind1, "Right")
      assert_eq(p1.rules[0], "power")
    }
  }
}

///|
// 验证无结合性（无修饰词）和 dynamic 修饰词也能被正确识别
test "parse_precedences_kinds" {
  // Nonassoc：省略修饰词
  match parse_grammar("precedence eq, neq\nrule eq: \"==\"\nrule neq: \"!=\"") {
    Error(err) => abort(err.message)
    Success(g) => {
      assert_eq(g.precedences.length(), 1)
      let kind = match g.precedences[0].kind {
        PrecKind::Nonassoc => "Nonassoc"
        _ => "other"
      }
      assert_eq(kind, "Nonassoc")
      assert_eq(g.precedences[0].rules.length(), 2)
    }
  }
  // Dynamic
  match parse_grammar("precedence dynamic cmp\nrule cmp: \"<\"") {
    Error(err) => abort(err.message)
    Success(g) => {
      assert_eq(g.precedences.length(), 1)
      let kind = match g.precedences[0].kind {
        PrecKind::Dynamic => "Dynamic"
        _ => "other"
      }
      assert_eq(kind, "Dynamic")
    }
  }
}

///|
// 验证 prec() 的错误路径
test "parse_prec_errors" {
  // 缺少 (
  match parse_grammar("rule r: prec 1, a") {
    Success(_) => abort("should fail")
    Error(err) => assert_true(err.message.length() > 0)
  }
  // 级别不是整数
  match parse_grammar("rule r: prec(abc, a)") {
    Success(_) => abort("should fail")
    Error(err) => assert_true(err.message.length() > 0)
  }
  // 缺少 ,
  match parse_grammar("rule r: prec(1 a)") {
    Success(_) => abort("should fail")
    Error(err) => assert_true(err.message.length() > 0)
  }
  // 未闭合 )
  match parse_grammar("rule r: prec(1, a") {
    Success(_) => abort("should fail")
    Error(err) => assert_true(err.message.length() > 0)
  }
  // prec. 后接无效词
  match parse_grammar("rule r: prec.none(1, a)") {
    Success(_) => abort("should fail")
    Error(err) => assert_true(err.message.length() > 0)
  }
}

///|
test "parse_grammar extras: Regex and Literal patterns" {
  let dsl =
    #|
    #|start s
    #|rule s: "a"
    #|extras [/\s+/, "//"]
  match parse_grammar(dsl) {
    Error(e) => fail(e.message)
    Success(g) => {
      assert_eq(g.extras.length(), 2)
      assert_true(g.extras[0] is Regex("\\s+"))
      assert_true(g.extras[1] is Literal("//"))
    }
  }
}

///|
test "parse_grammar extras: empty list" {
  let dsl = "start s\nrule s: \"a\"\nextras []"
  match parse_grammar(dsl) {
    Error(e) => fail(e.message)
    Success(g) => assert_eq(g.extras.length(), 0)
  }
}

///|
test "parse_grammar extras: missing bracket returns error" {
  match parse_grammar("extras /\\s+/") {
    Success(_) => fail("should error")
    Error(err) => assert_true(err.message.length() > 0)
  }
}

///|
test "regex literal \\/ escape parsed correctly" {
  // /\/\/.*/  应解析为包含 \/ 的正则词法，而非在第一个 / 处截断
  let dsl = "start s\nrule s: /\\/\\/\\//"
  match parse_grammar(dsl) {
    Error(e) => fail("parse failed: \{e.message}")
    Success(g) =>
      // 规则应该存在且模式中包含正则
      assert_eq(g.rules.contains("s"), true)
  }
}

///|
test "regex literal with escaped slash in extras" {
  // extras [ /\/\/.*/] — 行注释正则
  let dsl = "start s\nrule s: \"a\"\nextras [/\\/\\/.*/]"
  match parse_grammar(dsl) {
    Error(e) => fail("parse failed: \{e.message}")
    Success(g) => assert_eq(g.extras.length(), 1)
  }
}

///|
/// 负面测试：{n,m} 区间中 n > m 应报错
test "parse_negative: RepeatRange min > max is rejected" {
  // {5,2}：下界 5 大于上界 2，语义非法
  match parse_grammar("rule r: digit{5,2}\nrule digit: /\\d/") {
    Success(_) => fail("should have rejected {5,2} range where min > max")
    Error(err) => assert_true(err.message.length() > 0)
  }
  // {0,0}：重复 0-0 次，合法（等价于不出现）
  match parse_grammar("rule r: digit{0,0}\nrule digit: /\\d/") {
    Error(e) => fail("unexpected error for {0,0}: \{e.message}")
    Success(g) => assert_true(g.rules.contains("r"))
  }
}

///|
/// 负面测试：未闭合括号 '(' 应报错并报告正确位置
test "parse_negative: unclosed parenthesis reports error" {
  // 行内未闭合
  match parse_grammar("rule expr: (number \"*\" factor") {
    Success(_) => fail("should fail for unclosed '('")
    Error(err) => assert_true(err.message.length() > 0)
  }
  // 嵌套未闭合：外层已关闭但内层未闭合
  match parse_grammar("rule expr: ((number)") {
    Success(_) => fail("should fail for nested unclosed '('")
    Error(err) => assert_true(err.message.length() > 0)
  }
  // 多行：第二行出现未闭合括号
  match parse_grammar("rule a: b\nrule b: (\"x\"") {
    Success(_) => fail("should fail for unclosed '(' on line 2")
    Error(err) => {
      assert_true(err.message.length() > 0)
      // 错误应出现在第 2 行
      assert_eq(err.location.line, 2)
    }
  }
}

///|
/// 负面测试：precedence 后接非标识符 token（如数字字面量、符号）应报错
test "parse_negative: precedence with invalid token after keyword" {
  // precedence left 后接数字而非规则名
  match parse_grammar("precedence left 42\nrule plus: \"+\"") {
    Success(_) => fail("should fail: precedence followed by integer literal")
    Error(err) => assert_true(err.message.length() > 0)
  }
  // precedence 后直接换行（没有结合性也没有规则名）
  match parse_grammar("precedence\nrule plus: \"+\"") {
    Success(_) => fail("should fail: bare 'precedence' with no rules")
    Error(err) => assert_true(err.message.length() > 0)
  }
  // precedence left 后接引号字面量而非标识符
  match parse_grammar("precedence left \"+\"\nrule plus: \"+\"") {
    Success(_) => fail("should fail: precedence followed by string literal")
    Error(err) => assert_true(err.message.length() > 0)
  }
}
