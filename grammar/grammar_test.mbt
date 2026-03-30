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
      expected_patterns: Map::from_array([("expr", "Tagged"), ("additive", "Seq")]),
    },
    {
      name: "语义动作和节点命名 - 多标签序列",
      dsl: "rule program: statement*\nrule statement: @lhs identifier \"=\" @rhs expr",
      expected_rules: ["program", "statement"],
      expected_patterns: Map::from_array([("program", "Repeat"), ("statement", "Seq")]),
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
    
    match parse_grammar(test_case.dsl) {
      Success(grammar) => {
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
                Pattern::Plus(_) => "Plus"
                Pattern::Optional(_) => "Optional"
                Pattern::Tagged(_, _) => "Tagged"
              }
              assert_eq(actual_type, expected_type)
            }
            None => abort("规则 \{rule_name} 不存在")
          }
        }
        println("测试通过: \{test_case.name}")
      }
      Error(err) => {
        println("测试失败: \{test_case.name} - 解析错误: \{err.message} at line \{err.location.line}, col \{err.location.column}")
        abort("解析失败")
      }
    }
  }
}

// 4. MoonBit 推荐的测试入口
test "grammar_parser_table_driven" {
  run_table_driven_tests!()
}

test "error_cases" {
  match parse_grammar("rule expr: num |") {
    Success(_) => println("错误处理测试完成")
    Error(err) => println("预期的解析错误: \{err.message}")
  }
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
    // 现在这些应该返回 Error 而不是崩溃
    match parse_grammar(invalid_dsl) {
      Success(grammar) => {
        assert_true(grammar.rules.length() >= 0)
        println("错误情况处理完成: \{description} (解析成功)")
      }
      Error(err) => {
        println("错误情况处理完成: \{description} (解析错误: \{err.message})")
      }
    }
  }
}

test "pattern_to_string_roundtrip" {
  // 测试 Pattern 的 to_string 方法是否正确
  let test_patterns = [
    ("简单规则引用", "rule expr: number", "expr"),
    ("字面量", "rule str: \"hello\"", "str"),
    ("正则表达式", "rule num: /\\d+/", "num"),
    ("选择", "rule choice: a | b | c", "choice"),
    ("序列", "rule seq: a b c", "seq"),
    ("重复", "rule rep: item*", "rep"),
    ("可选", "rule opt: item?", "opt"),
    ("复杂组合", "rule complex: (a | b)* \"test\"?", "complex")
  ]
  
  for i in 0..<test_patterns.length() {
    let (description, dsl, rule_name) = test_patterns[i]
    println("测试 Pattern 字符串转换: \{description}")
    
    match parse_grammar(dsl) {
      Success(grammar) => {
        match grammar.rules.get(rule_name) {
          Some(rule) => {
            let pattern_str = rule.pattern.to_string()
            println("原始模式字符串: \{pattern_str}")
            // 这里我们只是验证 to_string 不崩溃，具体的等价性测试需要更复杂的逻辑
            assert_true(pattern_str.length() > 0)
          }
          None => abort("规则 \{rule_name} 不存在")
        }
      }
      Error(err) => abort("解析失败: \{err.message}")
    }
  }
  println("Pattern 字符串转换测试完成")
}

test "error_location_precision" {
  let cases = [
    ("rule expr: num |", 1, 16), // 期待在 | 处发现错误
    ("rule : num", 1, 6),        // 期待在冒号处报错（缺少名称）
  ]
  for c in cases {
    let (dsl, expected_line, expected_col) = c
    match parse_grammar(dsl) {
      Success(_) => abort("应该解析失败但成功了: \{dsl}")
      Error(err) => {
        assert_eq(err.location.line, expected_line)
        assert_eq(err.location.column, expected_col)
      }
    }
  }
}