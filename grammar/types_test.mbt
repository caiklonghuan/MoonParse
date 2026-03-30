// 测试 types.mbt 中 Pattern 的 pattern_to_string / Pattern::to_string 输出

///|
// 验证每种 Pattern 变体的 to_string 输出符合 DSL 语法
test "pattern_to_string" {
  // (描述, DSL, 规则名, 期望的 to_string 输出)
  let cases = [
    ("规则引用", "rule expr: number", "expr", "number"),
    ("字面量", "rule s: \"hello\"", "s", "\"hello\""),
    ("正则表达式", "rule n: /\\d+/", "n", "/\\d+/"),
    ("选择", "rule c: a | b | c", "c", "a | b | c"),
    ("序列", "rule s: a b c", "s", "a b c"),
    ("零或多次", "rule r: item*", "r", "item*"),
    ("一或多次", "rule r: item+", "r", "item+"),
    ("可选", "rule o: item?", "o", "item?"),
    ("负向前瞻", "rule w: !digit", "w", "!digit"),
    ("正向前瞻", "rule i: &digit", "i", "&digit"),
    ("任意字符", "rule a: .", "a", "."),
    ("命名字段", "rule f: lhs: a", "f", "lhs: a"),
    ("重复精确", "rule s: item{3}", "s", "item{3}"),
    ("重复区间", "rule r: item{2,4}", "r", "item{2,4}"),
    // 括号优先级：序列中嵌套 Choice 需要括号
    ("序列含选择", "rule r: (a | b)*", "r", "(a | b)*"),
    ("复杂组合", "rule c: (a | b)* \"x\"?", "c", "(a | b)* \"x\"?"),
  ]
  for c in cases {
    let (description, dsl, rule_name, expected) = c
    match parse_grammar(dsl) {
      Success(grammar) =>
        match grammar.rules.get(rule_name) {
          Some(rule) => {
            let actual = rule.pattern.to_string()
            assert_eq(actual, expected)
          }
          None => abort("规则 \{rule_name} 不存在 [\{description}]")
        }
      Error(err) => abort("解析失败 [\{description}]: \{err.message}")
    }
  }
}
