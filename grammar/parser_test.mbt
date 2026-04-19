// parser_test.mbt
// 将 Grammar DSL 解析测试收拢为单文件、按功能模块组织的表驱动套件。

///|
priv struct TestCase {
  name : String
  dsl : String
  expected_rules : Array[String]
  expected_patterns : Map[String, String]
}

///|
priv struct RuleMetaCase {
  name : String
  dsl : String
  rule_name : String
  expected_is_named : Bool
  expected_is_token : Bool
  expected_params : Array[String]
}

///|
priv struct StartCase {
  name : String
  dsl : String
  expected_start : String?
}

///|
priv struct WordCase {
  name : String
  dsl : String
  expected_word : String?
}

///|
priv struct ExtrasCase {
  name : String
  dsl : String
  expected_variants : Array[String]
}

///|
priv struct PrecExpectation {
  level : Int
  kind : PrecKind
  rules : Array[String]
}

///|
priv struct PrecDeclCase {
  name : String
  dsl : String
  expected_precedences : Array[PrecExpectation]
}

///|
priv struct AttrCase {
  name : String
  dsl : String
  rule_name : String
  expected_attrs : Array[RuleAttribute]
  expected_is_token : Bool
}

///|
priv struct ErrorCase {
  name : String
  dsl : String
  expected_line : Int?
  expected_column : Int?
}

///|
priv struct LenientCase {
  name : String
  dsl : String
  expected_error_count : Int
  expected_rules : Array[String]
  expected_duplicate_rules : Array[String]
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
    Pattern::RuleApp(_, _) => "RuleApp"
  }
}

///|
fn assert_parse_ok(name : String, dsl : String) -> Grammar raise {
  match parse_grammar(dsl) {
    Success(grammar) => grammar
    Error(err) =>
      fail(
        "解析失败 [\{name}]: \{err.message} at \{err.location.line}:\{err.location.column}",
      )
  }
}

///|
fn assert_parse_error(name : String, dsl : String) -> ParseError raise {
  match parse_grammar(dsl) {
    Success(_) => fail("应该失败但成功了 [\{name}]")
    Error(err) => err
  }
}

///|
fn assert_rule(
  grammar : Grammar,
  rule_name : String,
  case_name : String,
) -> Rule raise {
  match grammar.rules.get(rule_name) {
    Some(rule) => rule
    None => fail("规则 \{rule_name} 不存在 [\{case_name}]")
  }
}

///|
fn assert_rule_pattern(
  grammar : Grammar,
  rule_name : String,
  expected_variant : String,
  case_name : String,
) -> Unit raise {
  let rule = assert_rule(grammar, rule_name, case_name)
  let actual_variant = pattern_variant(rule.pattern)
  if actual_variant != expected_variant {
    fail(
      "模式断言失败 [\{case_name}] rule=\{rule_name}: expected \{expected_variant}, got \{actual_variant}",
    )
  }
}

///|
fn assert_has_attr(
  grammar : Grammar,
  rule_name : String,
  expected_attr : RuleAttribute,
  case_name : String,
) -> Unit raise {
  let rule = assert_rule(grammar, rule_name, case_name)
  let mut found = false
  for attr in rule.attributes {
    if attr == expected_attr {
      found = true
    }
  }
  assert_true(found)
}

///|
fn run_pattern_cases(cases : Array[TestCase]) -> Unit raise {
  for tc in cases {
    let grammar = assert_parse_ok(tc.name, tc.dsl)
    for rule_name in tc.expected_rules {
      assert_true(grammar.rules.contains(rule_name))
    }
    for rule_name, expected_variant in tc.expected_patterns {
      assert_rule_pattern(grammar, rule_name, expected_variant, tc.name)
    }
  }
}

///|
fn run_rule_meta_cases(cases : Array[RuleMetaCase]) -> Unit raise {
  for tc in cases {
    let grammar = assert_parse_ok(tc.name, tc.dsl)
    let rule = assert_rule(grammar, tc.rule_name, tc.name)
    assert_eq(rule.is_named, tc.expected_is_named)
    assert_eq(rule.is_token, tc.expected_is_token)
    assert_eq(rule.params, tc.expected_params)
  }
}

///|
fn run_start_cases(cases : Array[StartCase]) -> Unit raise {
  for tc in cases {
    let grammar = assert_parse_ok(tc.name, tc.dsl)
    assert_eq(grammar.start, tc.expected_start)
  }
}

///|
fn run_word_cases(cases : Array[WordCase]) -> Unit raise {
  for tc in cases {
    let grammar = assert_parse_ok(tc.name, tc.dsl)
    assert_eq(grammar.word, tc.expected_word)
  }
}

///|
fn run_extras_cases(cases : Array[ExtrasCase]) -> Unit raise {
  for tc in cases {
    let grammar = assert_parse_ok(tc.name, tc.dsl)
    assert_eq(grammar.extras.length(), tc.expected_variants.length())
    for i in 0..<tc.expected_variants.length() {
      assert_eq(pattern_variant(grammar.extras[i]), tc.expected_variants[i])
    }
  }
}

///|
fn run_precedence_cases(cases : Array[PrecDeclCase]) -> Unit raise {
  for tc in cases {
    let grammar = assert_parse_ok(tc.name, tc.dsl)
    assert_eq(grammar.precedences.length(), tc.expected_precedences.length())
    for i in 0..<tc.expected_precedences.length() {
      let actual = grammar.precedences[i]
      let expected = tc.expected_precedences[i]
      assert_eq(actual.level, expected.level)
      assert_eq(actual.kind, expected.kind)
      assert_eq(actual.rules, expected.rules)
    }
  }
}

///|
fn run_attr_cases(cases : Array[AttrCase]) -> Unit raise {
  for tc in cases {
    let grammar = assert_parse_ok(tc.name, tc.dsl)
    let rule = assert_rule(grammar, tc.rule_name, tc.name)
    assert_eq(rule.is_token, tc.expected_is_token)
    assert_eq(rule.attributes.length(), tc.expected_attrs.length())
    for attr in tc.expected_attrs {
      assert_has_attr(grammar, tc.rule_name, attr, tc.name)
    }
  }
}

///|
fn run_error_cases(cases : Array[ErrorCase]) -> Unit raise {
  for tc in cases {
    let err = assert_parse_error(tc.name, tc.dsl)
    match tc.expected_line {
      Some(line) => assert_eq(err.location.line, line)
      None => ()
    }
    match tc.expected_column {
      Some(column) => assert_eq(err.location.column, column)
      None => ()
    }
  }
}

///|
fn run_lenient_cases(cases : Array[LenientCase]) -> Unit raise {
  for tc in cases {
    let _ = tc.name
    let (grammar, errors) = parse_grammar_lenient(tc.dsl)
    assert_eq(errors.length(), tc.expected_error_count)
    for rule_name in tc.expected_rules {
      assert_true(grammar.rules.contains(rule_name))
    }
    assert_eq(grammar.duplicate_rule_names, tc.expected_duplicate_rules)
  }
}

///|
fn get_parser_basic_test_cases() -> Array[TestCase] {
  [
    {
      name: "基础规则 - 选择",
      dsl: "rule expr: num | expr \"+\" expr\nrule num: /\\d+/",
      expected_rules: ["expr", "num"],
      expected_patterns: Map::from_array([("expr", "Choice"), ("num", "Regex")]),
    },
    {
      name: "基础规则 - 序列",
      dsl: "rule statement: identifier \"=\" expression \";\"",
      expected_rules: ["statement"],
      expected_patterns: Map::from_array([("statement", "Seq")]),
    },
    {
      name: "基础规则 - 字面量选择",
      dsl: "rule keyword: \"if\" | \"else\" | \"while\"",
      expected_rules: ["keyword"],
      expected_patterns: Map::from_array([("keyword", "Choice")]),
    },
    {
      name: "基础规则 - 单字面量",
      dsl: "rule equals: \"=\"",
      expected_rules: ["equals"],
      expected_patterns: Map::from_array([("equals", "Literal")]),
    },
    {
      name: "基础规则 - 空字面量",
      dsl: "rule empty: \"\"",
      expected_rules: ["empty"],
      expected_patterns: Map::from_array([("empty", "Literal")]),
    },
    {
      name: "基础规则 - 规则引用链",
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
      name: "token 规则",
      dsl: "token rule num: /\\d+/",
      expected_rules: ["num"],
      expected_patterns: Map::from_array([("num", "Regex")]),
    },
    {
      name: "正则中的转义斜杠",
      dsl: "start s\nrule s: /\\/\\/\\//",
      expected_rules: ["s"],
      expected_patterns: Map::from_array([("s", "Regex")]),
    },
    {
      name: "word 仍可作规则名",
      dsl: "rule word: /[a-z]+/",
      expected_rules: ["word"],
      expected_patterns: Map::from_array([("word", "Regex")]),
    },
    {
      name: "token 仍可作规则名",
      dsl: "rule token: /[a-z]+/",
      expected_rules: ["token"],
      expected_patterns: Map::from_array([("token", "Regex")]),
    },
    {
      name: "未定义引用仅做语法解析",
      dsl: "rule expr: undefined_rule",
      expected_rules: ["expr"],
      expected_patterns: Map::from_array([("expr", "RuleRef")]),
    },
    {
      name: "未闭合正则被宽松解析为正则（产生部分内容的 RegexLiteral）",
      dsl: "rule num: /unclosed",
      expected_rules: ["num"],
      expected_patterns: Map::from_array([("num", "Regex")]),
    },
  ]
}

///|
fn get_parser_basic_rule_meta_cases() -> Array[RuleMetaCase] {
  [
    {
      name: "普通规则默认是命名节点",
      dsl: "rule expr: number",
      rule_name: "expr",
      expected_is_named: true,
      expected_is_token: false,
      expected_params: [],
    },
    {
      name: "下划线规则是匿名节点",
      dsl: "rule _ws: \" \"",
      rule_name: "_ws",
      expected_is_named: false,
      expected_is_token: false,
      expected_params: [],
    },
    {
      name: "token rule 标记为词法规则",
      dsl: "token rule num: /\\d+/",
      rule_name: "num",
      expected_is_named: true,
      expected_is_token: true,
      expected_params: [],
    },
    {
      name: "普通 rule 的 is_token 默认为 false",
      dsl: "rule expr: /\\d+/",
      rule_name: "expr",
      expected_is_named: true,
      expected_is_token: false,
      expected_params: [],
    },
  ]
}

///|
fn get_parser_basic_start_cases() -> Array[StartCase] {
  [
    {
      name: "start 顶层声明写入 grammar.start",
      dsl: "start program\nrule program: statement*\nrule statement: \"print\" expr",
      expected_start: Some("program"),
    },
    {
      name: "未声明 start 时保持 None",
      dsl: "rule expr: number",
      expected_start: None,
    },
  ]
}

///|
fn get_parser_basic_word_cases() -> Array[WordCase] {
  [
    {
      name: "word 顶层声明写入 grammar.word",
      dsl: "word identifier\nrule identifier: /[a-z]+/",
      expected_word: Some("identifier"),
    },
    {
      name: "未声明 word 时保持 None",
      dsl: "rule expr: /\\d+/",
      expected_word: None,
    },
  ]
}

///|
fn get_parser_basic_extras_cases() -> Array[ExtrasCase] {
  [
    {
      name: "extras 支持 Regex 和 Literal",
      dsl: "start s\nrule s: \"a\"\nextras [/\\s+/, \"//\"]",
      expected_variants: ["Regex", "Literal"],
    },
    {
      name: "extras 支持空列表",
      dsl: "start s\nrule s: \"a\"\nextras []",
      expected_variants: [],
    },
    {
      name: "extras 中的转义斜杠正则可正确解析",
      dsl: "start s\nrule s: \"a\"\nextras [/\\/\\/.*/]",
      expected_variants: ["Regex"],
    },
  ]
}

///|
fn get_parser_complex_test_cases() -> Array[TestCase] {
  [
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
      name: "内联优先级 - 右结合",
      dsl: "rule expr: prec.right(3, number)\nrule number: /\\d+/",
      expected_rules: ["expr", "number"],
      expected_patterns: Map::from_array([("expr", "Prec"), ("number", "Regex")]),
    },
    {
      name: "alias 模式",
      dsl: "rule expr: alias(\"num\", number)\nrule number: /\\d+/",
      expected_rules: ["expr", "number"],
      expected_patterns: Map::from_array([
        ("expr", "Alias"),
        ("number", "Regex"),
      ]),
    },
    {
      name: "参数化模板与规则应用",
      dsl: "rule list[T]: T (\",\" T)*\nrule items: list[expr]\nrule expr: /\\d+/",
      expected_rules: ["list", "items", "expr"],
      expected_patterns: Map::from_array([
        ("list", "Seq"),
        ("items", "RuleApp"),
        ("expr", "Regex"),
      ]),
    },
  ]
}

///|
fn get_parser_complex_rule_meta_cases() -> Array[RuleMetaCase] {
  [
    {
      name: "模板规则参数列表 - 单参数",
      dsl: "rule list[T]: T (\",\" T)*",
      rule_name: "list",
      expected_is_named: true,
      expected_is_token: false,
      expected_params: ["T"],
    },
    {
      name: "模板规则参数列表 - 双参数",
      dsl: "rule pair[A, B]: A B",
      rule_name: "pair",
      expected_is_named: true,
      expected_is_token: false,
      expected_params: ["A", "B"],
    },
  ]
}

///|
fn get_parser_complex_precedence_cases() -> Array[PrecDeclCase] {
  [
    {
      name: "precedence 混合 left/right 按顺序入表",
      dsl: "precedence left plus, minus\nprecedence right power\nrule plus: \"+\"\nrule minus: \"-\"\nrule power: \"^\"",
      expected_precedences: [
        { level: 1, kind: PrecKind::Left, rules: ["plus", "minus"] },
        { level: 2, kind: PrecKind::Right, rules: ["power"] },
      ],
    },
    {
      name: "precedence 无修饰词解析为 Nonassoc",
      dsl: "precedence eq, neq\nrule eq: \"==\"\nrule neq: \"!=\"",
      expected_precedences: [
        { level: 1, kind: PrecKind::Nonassoc, rules: ["eq", "neq"] },
      ],
    },
    {
      name: "precedence dynamic 解析为 Dynamic",
      dsl: "precedence dynamic cmp\nrule cmp: \"<\"",
      expected_precedences: [
        { level: 1, kind: PrecKind::Dynamic, rules: ["cmp"] },
      ],
    },
    {
      name: "多级 precedence 按声明顺序分层",
      dsl: "precedence left plus, minus\nprecedence left star, slash\nrule plus: \"+\"\nrule minus: \"-\"\nrule star: \"*\"\nrule slash: \"/\"",
      expected_precedences: [
        { level: 1, kind: PrecKind::Left, rules: ["plus", "minus"] },
        { level: 2, kind: PrecKind::Left, rules: ["star", "slash"] },
      ],
    },
  ]
}

///|
fn get_parser_attr_cases() -> Array[AttrCase] {
  [
    {
      name: "@inline 规则属性",
      dsl: "@inline rule sep: \",\"",
      rule_name: "sep",
      expected_attrs: [RuleAttribute::Inline],
      expected_is_token: false,
    },
    {
      name: "@hide 规则属性",
      dsl: "@hide rule ws: /\\s+/",
      rule_name: "ws",
      expected_attrs: [RuleAttribute::Hide],
      expected_is_token: false,
    },
    {
      name: "@deprecated 规则属性",
      dsl: "@deprecated rule legacy: \"x\"",
      rule_name: "legacy",
      expected_attrs: [RuleAttribute::Deprecated],
      expected_is_token: false,
    },
    {
      name: "多属性 + token rule",
      dsl: "@inline @hide token rule trivia: /\\s+/",
      rule_name: "trivia",
      expected_attrs: [RuleAttribute::Inline, RuleAttribute::Hide],
      expected_is_token: true,
    },
  ]
}

///|
fn get_parser_error_cases() -> Array[ErrorCase] {
  [
    {
      name: "缺少选择分支",
      dsl: "rule expr: num |",
      expected_line: Some(1),
      expected_column: Some(16),
    },
    {
      name: "空规则体",
      dsl: "rule empty: ",
      expected_line: None,
      expected_column: None,
    },
    {
      name: "无效标签 @",
      dsl: "rule expr: @",
      expected_line: None,
      expected_column: None,
    },
    {
      name: "缺少规则名",
      dsl: "rule : num",
      expected_line: Some(1),
      expected_column: Some(6),
    },
    {
      name: "未闭合括号",
      dsl: "rule expr: (number",
      expected_line: None,
      expected_column: None,
    },
    {
      name: "多行未闭合括号定位到第二行",
      dsl: "rule a: b\nrule b: (\"x\"",
      expected_line: Some(2),
      expected_column: None,
    },
    {
      name: "extras 缺少方括号",
      dsl: "extras /\\s+/",
      expected_line: None,
      expected_column: None,
    },
    {
      name: "RepeatRange 下界大于上界",
      dsl: "rule r: digit{5,2}\nrule digit: /\\d/",
      expected_line: None,
      expected_column: None,
    },
    {
      name: "prec 缺少左括号",
      dsl: "rule r: prec 1, a",
      expected_line: None,
      expected_column: None,
    },
    {
      name: "prec 级别不是整数",
      dsl: "rule r: prec(abc, a)",
      expected_line: None,
      expected_column: None,
    },
    {
      name: "prec 缺少逗号",
      dsl: "rule r: prec(1 a)",
      expected_line: None,
      expected_column: None,
    },
    {
      name: "prec 缺少右括号",
      dsl: "rule r: prec(1, a",
      expected_line: None,
      expected_column: None,
    },
    {
      name: "prec 使用无效修饰词",
      dsl: "rule r: prec.none(1, a)",
      expected_line: None,
      expected_column: None,
    },
    {
      name: "precedence 后跟数字",
      dsl: "precedence left 42\nrule plus: \"+\"",
      expected_line: None,
      expected_column: None,
    },
    {
      name: "precedence 缺少规则名",
      dsl: "precedence\nrule plus: \"+\"",
      expected_line: None,
      expected_column: None,
    },
    {
      name: "precedence 后跟字面量",
      dsl: "precedence left \"+\"\nrule plus: \"+\"",
      expected_line: None,
      expected_column: None,
    },
  ]
}

///|
fn get_parser_lenient_cases() -> Array[LenientCase] {
  [
    {
      name: "lenient 模式收集多条错误并保留合法规则",
      dsl: "rule a: |\nrule b: |\nrule c: /\\d+/",
      expected_error_count: 2,
      expected_rules: ["c"],
      expected_duplicate_rules: [],
    },
    {
      name: "合法 DSL 在 lenient 模式下无错误",
      dsl: "start expr\nrule expr: /\\d+/",
      expected_error_count: 0,
      expected_rules: ["expr"],
      expected_duplicate_rules: [],
    },
    {
      name: "重复规则名记录在 duplicate_rule_names",
      dsl: "rule expr: /\\d+/\nrule expr: /[a-z]/",
      expected_error_count: 0,
      expected_rules: ["expr"],
      expected_duplicate_rules: ["expr"],
    },
  ]
}

///|
fn parser_basic_test() -> Unit raise {
  run_pattern_cases(get_parser_basic_test_cases())
  run_rule_meta_cases(get_parser_basic_rule_meta_cases())
  run_start_cases(get_parser_basic_start_cases())
  run_word_cases(get_parser_basic_word_cases())
  run_extras_cases(get_parser_basic_extras_cases())
}

///|
fn parser_complex_test() -> Unit raise {
  run_pattern_cases(get_parser_complex_test_cases())
  run_rule_meta_cases(get_parser_complex_rule_meta_cases())
  run_precedence_cases(get_parser_complex_precedence_cases())
}

///|
fn parser_attr_test() -> Unit raise {
  run_attr_cases(get_parser_attr_cases())
}

///|
fn parser_error_test() -> Unit raise {
  run_error_cases(get_parser_error_cases())
  run_lenient_cases(get_parser_lenient_cases())
}

///|
test "grammar_parsing_suite" {
  parser_basic_test()
  parser_complex_test()
  parser_attr_test()
  parser_error_test()
}
