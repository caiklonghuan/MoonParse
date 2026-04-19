///|
// 用简单的表达式语法验证 infer_grammar 的推导结果

///|
/// 构造一个最小算术表达式语法：
///   start = expr
///   expr  = binary_expr | unary_expr | number
///   binary_expr = field(lhs: expr) op field(rhs: expr)
///   unary_expr  = op field(operand: expr)
///   number = /[0-9]+/
///   op = "+" | "-" | "*" | "/"
fn make_expr_grammar() -> @grammar.Grammar {
  let rules : Map[String, @grammar.Rule] = Map::new()
  // number: token rule
  rules.set("number", {
    name: "number",
    pattern: @grammar.Pattern::Regex("[0-9]+"),
    is_named: true,
    is_token: true,
    params: [],
    attributes: [],
    location: None,
  })
  // op: anonymous token (name starts with _)
  rules.set("_op", {
    name: "_op",
    pattern: @grammar.Pattern::Choice([
      @grammar.Pattern::Literal("+"),
      @grammar.Pattern::Literal("-"),
      @grammar.Pattern::Literal("*"),
      @grammar.Pattern::Literal("/"),
    ]),
    is_named: false,
    is_token: true,
    params: [],
    attributes: [],
    location: None,
  })
  // binary_expr: Seq with named fields
  rules.set("binary_expr", {
    name: "binary_expr",
    pattern: @grammar.Pattern::Seq([
      @grammar.Pattern::Field("lhs", @grammar.Pattern::RuleRef("expr")),
      @grammar.Pattern::RuleRef("_op"),
      @grammar.Pattern::Field("rhs", @grammar.Pattern::RuleRef("expr")),
    ]),
    is_named: true,
    is_token: false,
    params: [],
    attributes: [],
    location: None,
  })
  // unary_expr: Seq with one named field
  rules.set("unary_expr", {
    name: "unary_expr",
    pattern: @grammar.Pattern::Seq([
      @grammar.Pattern::RuleRef("_op"),
      @grammar.Pattern::Field("operand", @grammar.Pattern::RuleRef("expr")),
    ]),
    is_named: true,
    is_token: false,
    params: [],
    attributes: [],
    location: None,
  })
  // expr: Choice of named rules → Enum
  rules.set("expr", {
    name: "expr",
    pattern: @grammar.Pattern::Choice([
      @grammar.Pattern::RuleRef("binary_expr"),
      @grammar.Pattern::RuleRef("unary_expr"),
      @grammar.Pattern::RuleRef("number"),
    ]),
    is_named: true,
    is_token: false,
    params: [],
    attributes: [],
    location: None,
  })
  {
    start: Some("expr"),
    rules,
    precedences: [],
    extras: [],
    externals: [],
    duplicate_rule_names: [],
    word: None,
    conflicts: [],
    supertypes: [],
  }
}

///|
test "infer_grammar / token rule → Token" {
  let g = make_expr_grammar()
  let schema = infer_grammar(g)
  match schema.get("number") {
    Some(NodeShape::Token) => ()
    other => fail("number 应为 Token，得到: \{other}")
  }
}

///|
test "infer_grammar / _op (starts with _) → skipped" {
  let g = make_expr_grammar()
  let schema = infer_grammar(g)
  // 以 _ 开头的规则不应出现在 schema 中
  assert_true(!schema.contains("_op"))
}

///|
test "infer_grammar / binary_expr (Seq with fields) → Struct" {
  let g = make_expr_grammar()
  let schema = infer_grammar(g)
  match schema.get("binary_expr") {
    Some(NodeShape::Struct(fields)) => {
      assert_eq(fields.length(), 2)
      let names = fields.map(fn(f) { f.0 })
      assert_true(names.contains("lhs"))
      assert_true(names.contains("rhs"))
      // lhs 和 rhs 都引用 expr
      for pair in fields {
        match pair.1 {
          FieldShape::One(NodeRef::Named("expr")) => ()
          other =>
            fail(
              "binary_expr 字段应为 One(Named(\"expr\"))，得到: \{other}",
            )
        }
      }
    }
    other => fail("binary_expr 应为 Struct，得到: \{other}")
  }
}

///|
test "infer_grammar / unary_expr (Seq with one field) → Struct" {
  let g = make_expr_grammar()
  let schema = infer_grammar(g)
  match schema.get("unary_expr") {
    Some(NodeShape::Struct(fields)) => {
      assert_eq(fields.length(), 1)
      assert_eq(fields[0].0, "operand")
    }
    other => fail("unary_expr 应为 Struct，得到: \{other}")
  }
}

///|
test "infer_grammar / expr (Choice of named rules) → Enum" {
  let g = make_expr_grammar()
  let schema = infer_grammar(g)
  match schema.get("expr") {
    Some(NodeShape::Enum(variants)) => {
      assert_eq(variants.length(), 3)
      let names = variants.map(fn(v) { v.0 })
      assert_true(names.contains("binary_expr"))
      assert_true(names.contains("unary_expr"))
      assert_true(names.contains("number"))
    }
    other => fail("expr 应为 Enum，得到: \{other}")
  }
}

///|
test "infer_grammar / inline rule → skipped" {
  let rules : Map[String, @grammar.Rule] = Map::new()
  rules.set("ws", {
    name: "ws",
    pattern: @grammar.Pattern::Regex("\\s+"),
    is_named: true,
    is_token: true,
    params: [],
    attributes: [@grammar.RuleAttribute::Inline],
    location: None,
  })
  rules.set("root", {
    name: "root",
    pattern: @grammar.Pattern::RuleRef("ws"),
    is_named: true,
    is_token: false,
    params: [],
    attributes: [],
    location: None,
  })
  let g : @grammar.Grammar = {
    start: Some("root"),
    rules,
    precedences: [],
    extras: [],
    externals: [],
    duplicate_rule_names: [],
    word: None,
    conflicts: [],
    supertypes: [],
  }
  let schema = infer_grammar(g)
  assert_true(!schema.contains("ws"))
}

///|
test "infer_grammar / Optional field → FieldShape::Optional" {
  let rules : Map[String, @grammar.Rule] = Map::new()
  rules.set("body", {
    name: "body",
    pattern: @grammar.Pattern::Regex(".+"),
    is_named: true,
    is_token: true,
    params: [],
    attributes: [],
    location: None,
  })
  rules.set("func_def", {
    name: "func_def",
    pattern: @grammar.Pattern::Seq([
      @grammar.Pattern::Literal("fn"),
      @grammar.Pattern::Field(
        "body",
        @grammar.Pattern::Optional(@grammar.Pattern::RuleRef("body")),
      ),
    ]),
    is_named: true,
    is_token: false,
    params: [],
    attributes: [],
    location: None,
  })
  let g : @grammar.Grammar = {
    start: Some("func_def"),
    rules,
    precedences: [],
    extras: [],
    externals: [],
    duplicate_rule_names: [],
    word: None,
    conflicts: [],
    supertypes: [],
  }
  let schema = infer_grammar(g)
  match schema.get("func_def") {
    Some(NodeShape::Struct(fields)) => {
      assert_eq(fields.length(), 1)
      match fields[0].1 {
        FieldShape::Optional(NodeRef::Named("body")) => ()
        other =>
          fail("body 字段应为 Optional(Named(\"body\"))，得到: \{other}")
      }
    }
    other => fail("func_def 应为 Struct，得到: \{other}")
  }
}

///|
test "infer_grammar / Repeat field → FieldShape::Many" {
  let rules : Map[String, @grammar.Rule] = Map::new()
  rules.set("stmt", {
    name: "stmt",
    pattern: @grammar.Pattern::Regex(".+"),
    is_named: true,
    is_token: true,
    params: [],
    attributes: [],
    location: None,
  })
  rules.set("block", {
    name: "block",
    pattern: @grammar.Pattern::Seq([
      @grammar.Pattern::Literal("{"),
      @grammar.Pattern::Field(
        "stmts",
        @grammar.Pattern::Repeat(@grammar.Pattern::RuleRef("stmt")),
      ),
      @grammar.Pattern::Literal("}"),
    ]),
    is_named: true,
    is_token: false,
    params: [],
    attributes: [],
    location: None,
  })
  let g : @grammar.Grammar = {
    start: Some("block"),
    rules,
    precedences: [],
    extras: [],
    externals: [],
    duplicate_rule_names: [],
    word: None,
    conflicts: [],
    supertypes: [],
  }
  let schema = infer_grammar(g)
  match schema.get("block") {
    Some(NodeShape::Struct(fields)) => {
      assert_eq(fields.length(), 1)
      match fields[0].1 {
        FieldShape::Many(NodeRef::Named("stmt")) => ()
        other =>
          fail("stmts 字段应为 Many(Named(\"stmt\"))，得到: \{other}")
      }
    }
    other => fail("block 应为 Struct，得到: \{other}")
  }
}

///|
test "infer_grammar / supertype → Enum" {
  let rules : Map[String, @grammar.Rule] = Map::new()
  rules.set("int_lit", {
    name: "int_lit",
    pattern: @grammar.Pattern::Regex("[0-9]+"),
    is_named: true,
    is_token: true,
    params: [],
    attributes: [],
    location: None,
  })
  rules.set("str_lit", {
    name: "str_lit",
    pattern: @grammar.Pattern::Regex("\".*\""),
    is_named: true,
    is_token: true,
    params: [],
    attributes: [],
    location: None,
  })
  rules.set("literal", {
    name: "literal",
    pattern: @grammar.Pattern::Choice([
      @grammar.Pattern::RuleRef("int_lit"),
      @grammar.Pattern::RuleRef("str_lit"),
    ]),
    is_named: true,
    is_token: false,
    params: [],
    attributes: [],
    location: None,
  })
  let g : @grammar.Grammar = {
    start: Some("literal"),
    rules,
    precedences: [],
    extras: [],
    externals: [],
    duplicate_rule_names: [],
    word: None,
    conflicts: [],
    supertypes: ["literal"],
  }
  let schema = infer_grammar(g)
  match schema.get("literal") {
    Some(NodeShape::Enum(variants)) => {
      assert_eq(variants.length(), 2)
      let names = variants.map(fn(v) { v.0 })
      assert_true(names.contains("int_lit"))
      assert_true(names.contains("str_lit"))
    }
    other => fail("literal 应为 Enum（supertype），得到: \{other}")
  }
}

///|
test "infer_grammar / RuleRef simple alias → Alias" {
  let rules : Map[String, @grammar.Rule] = Map::new()
  rules.set("ident", {
    name: "ident",
    pattern: @grammar.Pattern::Regex("[a-z]+"),
    is_named: true,
    is_token: true,
    params: [],
    attributes: [],
    location: None,
  })
  rules.set("name", {
    name: "name",
    pattern: @grammar.Pattern::RuleRef("ident"),
    is_named: true,
    is_token: false,
    params: [],
    attributes: [],
    location: None,
  })
  let g : @grammar.Grammar = {
    start: Some("name"),
    rules,
    precedences: [],
    extras: [],
    externals: [],
    duplicate_rule_names: [],
    word: None,
    conflicts: [],
    supertypes: [],
  }
  let schema = infer_grammar(g)
  match schema.get("name") {
    Some(NodeShape::Alias("ident")) => ()
    other => fail("name 应为 Alias(\"ident\")，得到: \{other}")
  }
}

///|
test "infer_grammar / schema size includes only non-skipped rules" {
  let g = make_expr_grammar()
  let schema = infer_grammar(g)
  // _op 被跳过，剩余 4 条：number, binary_expr, unary_expr, expr
  assert_eq(schema.size(), 4)
}
