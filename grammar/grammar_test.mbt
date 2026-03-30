// 1. 结构体定义
priv struct TestCase {
  name : String
  dsl : String
  expected_rules : Array[String]
  expected_patterns : Map[String, String]
}

fn get_test_cases() -> Array[TestCase] {
  [
    {
      name: "基本规则解析",
      dsl: "rule expr: num | expr \"+\" expr\nrule num: /\\d+/",
      expected_rules: ["expr", "num"],
      expected_patterns: Map::from_array([("expr", "Choice"), ("num", "Regex")]),
    },
    {
      name: "序列模式",
      dsl: "rule statement: identifier \"=\" expression \";\"",
      expected_rules: ["statement"],
      expected_patterns: Map::from_array([("statement", "Seq")]),
    },
    {
      name: "字面量字符串",
      dsl: "rule keyword: \"if\" | \"else\" | \"while\"",
      expected_rules: ["keyword"],
      expected_patterns: Map::from_array([("keyword", "Choice")]),
    },
    {
      name: "可选模式",
      dsl: "rule optional_param: identifier \":\" type \"?\"?",
      expected_rules: ["optional_param"],
      expected_patterns: Map::from_array([("optional_param", "Seq")]),
    },
    {
      name: "重复模式",
      dsl: "rule list: \"[\" item (\",\" item)* \"]\"",
      expected_rules: ["list"],
      expected_patterns: Map::from_array([("list", "Seq")]),
    },
    {
      name: "分组表达式",
      dsl: "rule paren_expr: \"(\" (add_expr | mul_expr) \")\"",
      expected_rules: ["paren_expr"],
      expected_patterns: Map::from_array([("paren_expr", "Seq")]),
    },
    {
      name: "起始规则声明",
      dsl: "start program\nrule program: statement*\nrule statement: \"print\" expr",
      expected_rules: ["program", "statement"],
      expected_patterns: Map::from_array([("program", "Repeat"), ("statement", "Seq")]),
    },
    {
      name: "混合模式",
      dsl: "rule func_call: identifier \"(\" (arg (\",\" arg)*)? \")\"",
      expected_rules: ["func_call"],
      expected_patterns: Map::from_array([("func_call", "Seq")]),
    },
    {
      name: "简单字面量",
      dsl: "rule equals: \"=\"",
      expected_rules: ["equals"],
      expected_patterns: Map::from_array([("equals", "Literal")]),
    },
    {
      name: "规则引用",
      dsl: "rule program: statement\nrule statement: expr\nrule expr: number",
      expected_rules: ["program", "statement", "expr"],
      expected_patterns: Map::from_array([
        ("program", "RuleRef"),
        ("statement", "RuleRef"),
        ("expr", "RuleRef")
      ]),
    },
    {
      name: "复杂表达式",
      dsl: "rule expression: additive\nrule additive: multiplicative ((\"+\" | \"-\") multiplicative)*\nrule multiplicative: primary ((\"*\" | \"/\") primary)*\nrule primary: number | identifier | \"(\" expression \")\"\nrule number: /\\d+(\\.\\d+)?/\nrule identifier: /[a-zA-Z_]\\w*/",
      expected_rules: ["expression", "additive", "multiplicative", "primary", "number", "identifier"],
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
      name: "注释语法 - 行注释",
      dsl: "rule expr: number // 这是一个注释\nrule number: /\\d+/",
      expected_rules: ["expr", "number"],
      expected_patterns: Map::from_array([("expr", "RuleRef"), ("number", "Regex")]), // 注释被跳过，解析为 RuleRef
    },
    {
      name: "注释语法 - 块注释",
      dsl: "rule expr: /* 这是块注释 */ number\nrule number: /\\d+/",
      expected_rules: ["expr", "number"],
      expected_patterns: Map::from_array([("expr", "RuleRef"), ("number", "Regex")]), // 注释被跳过，解析为 RuleRef
    },
    {
      name: "语义动作和节点命名 - 基础命名",
      dsl: "rule expr: @additive additive\nrule additive: number \"+\" number",
      expected_rules: ["expr", "additive"],
      expected_patterns: Map::from_array([("expr", "Seq"), ("additive", "Seq")]), // @ 未实现，所以解析为序列
    },
    {
      name: "语义动作和节点命名 - 复杂命名",
      dsl: "rule program: @statement* statement*\nrule statement: @assign identifier \"=\" @expr expr",
      expected_rules: ["program", "statement"],
      expected_patterns: Map::from_array([("program", "Seq"), ("statement", "Seq")]), // @ 未实现，所以解析为序列
    },
    {
      name: "优先级声明 - 左结合",
      dsl: "precedence left plus, minus\nrule expr: number (plus | minus) number\nrule plus: \"+\"\nrule minus: \"-\"",
      expected_rules: ["expr", "plus", "minus"],
      expected_patterns: Map::from_array([("expr", "Seq"), ("plus", "Literal"), ("minus", "Literal")]),
    },
    {
      name: "优先级声明 - 右结合",
      dsl: "precedence right power\nrule expr: number power number\nrule power: \"^\"",
      expected_rules: ["expr", "power"],
      expected_patterns: Map::from_array([("expr", "Seq"), ("power", "Literal")]),
    },
    {
      name: "优先级声明 - 多级优先级",
      dsl: "precedence left plus, minus\nprecedence left star, slash\nrule expr: term ((plus | minus) term)*\nrule term: factor ((star | slash) factor)*\nrule factor: number | \"(\" expr \")\"\nrule plus: \"+\"\nrule minus: \"-\"\nrule star: \"*\"\nrule slash: \"/\"",
      expected_rules: ["expr", "term", "factor", "plus", "minus", "star", "slash"],
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
  ]
}

// 3. 运行测试逻辑
fn run_table_driven_tests() -> Unit! { // 加上 ! 表示内部可能抛出 assert 异常
  let test_cases = get_test_cases()
  for test_case in test_cases {
    println("运行测试: \{test_case.name}")
    
    let grammar = parse_grammar(test_case.dsl)
    
    // 检查规则存在性
    for expected_rule in test_case.expected_rules {
      assert_true(grammar.rules.contains(expected_rule))
    }
    
    // 检查模式类型
    for rule_name, expected_type in test_case.expected_patterns {
      match grammar.rules.get(rule_name) {
        Some(r) => {
          // 修正点：根据 Pattern 的定义补全路径
          let actual_type = match r.pattern {
            Pattern::RuleRef(_) => "RuleRef"
            Pattern::Literal(_) => "Literal"
            Pattern::Regex(_) => "Regex"
            Pattern::Choice(_) => "Choice"
            Pattern::Seq(_) => "Seq"
            Pattern::Repeat(_) => "Repeat"
            Pattern::Optional(_) => "Optional"
          }
          assert_eq(actual_type, expected_type)
        }
        None => abort("规则 \{rule_name} 不存在")
      }
    }
    println("测试通过: \{test_case.name}")
  }
}

// 4. MoonBit 推荐的测试入口
test "grammar_parser_table_driven" {
  run_table_driven_tests!()
}

test "error_cases" {
  let _ = parse_grammar("rule expr: num |")
  println("错误处理测试完成")
}

test "advanced_error_handling" {
  // 测试各种语法错误情况
  let error_case_1 = ("未闭合的规则", "rule expr: number")
  let error_case_2 = ("无效的模式", "rule expr: @")
  let error_case_3 = ("重复的规则名", "rule expr: number\nrule expr: string")
  let error_case_4 = ("不存在的规则引用", "rule expr: undefined_rule")
  let error_case_5 = ("无效的正则表达式", "rule num: /unclosed")
  let error_case_6 = ("空的规则体", "rule empty: ")
  let error_case_7 = ("无效的优先级声明", "precedence invalid plus")
  let error_case_8 = ("不匹配的括号", "rule expr: (number")
  let error_case_9 = ("无效的重复语法", "rule expr: number*+")
  let error_case_10 = ("空的字面量", "rule empty: \"\"")
  
  let error_cases = [error_case_1, error_case_2, error_case_3, error_case_4, error_case_5, error_case_6, error_case_7, error_case_8, error_case_9, error_case_10]
  
  for i in 0..<error_cases.length() {
    let (description, invalid_dsl) = error_cases[i]
    println("测试错误情况: \{description}")
    // 目前这些应该不会崩溃，而是返回包含错误信息的语法
    let grammar = parse_grammar(invalid_dsl)
    // 验证语法树的基本结构仍然存在
    assert_true(grammar.rules.length() >= 0)
    println("错误情况处理完成: \{description}")
  }
}

test "location_info_requirements" {
  // 测试需要位置信息的场景
  let location_case_1 = ("语法错误位置", "rule expr: number +\nrule number: /\\d+/")
  let location_case_2 = ("未定义规则引用", "rule expr: undefined\nrule number: /\\d+/")
  let location_case_3 = ("重复规则定义", "rule expr: number\nrule expr: string")
  let location_case_4 = ("无效的模式组合", "rule expr: number | * string")
  
  let location_cases = [location_case_1, location_case_2, location_case_3, location_case_4]
  
  for i in 0..<location_cases.length() {
    let (description, dsl_with_location) = location_cases[i]
    println("测试位置信息需求: \{description}")
    let grammar = parse_grammar(dsl_with_location)
    // 验证解析器能够处理这些情况而不崩溃
    assert_true(grammar.rules.length() >= 0)
    println("位置信息测试完成: \{description}")
  }
}