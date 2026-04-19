///|
// emit 阶段测试：验证 type_name 工具函数、类型定义生成、访问器生成、端到端入口

// ─── 工具函数 ────────────────────────────────────────────────────────────────

///|
test "rule_name_to_type_name / basic cases" {
  assert_eq(rule_name_to_type_name("binary_expr"), "BinaryExpr")
  assert_eq(rule_name_to_type_name("number"), "Number")
  assert_eq(rule_name_to_type_name("json_object"), "JsonObject")
  assert_eq(rule_name_to_type_name("a"), "A")
  assert_eq(rule_name_to_type_name("abc_def_ghi"), "AbcDefGhi")
}

///|
test "rule_name_to_type_name / conflict escaping" {
  // True / False / Some / None / Ok / Err 应加 _ 后缀
  assert_eq(rule_name_to_type_name("true"), "True_")
  assert_eq(rule_name_to_type_name("false"), "False_")
  assert_eq(rule_name_to_type_name("some"), "Some_")
  assert_eq(rule_name_to_type_name("none"), "None_")
  assert_eq(rule_name_to_type_name("ok"), "Ok_")
  assert_eq(rule_name_to_type_name("err"), "Err_")
}

///|
test "escape_field_name / keyword escaping" {
  assert_eq(escape_field_name("type"), "type_")
  assert_eq(escape_field_name("fn"), "fn_")
  assert_eq(escape_field_name("match"), "match_")
  assert_eq(escape_field_name("else"), "else_")
  // 非关键字不变
  assert_eq(escape_field_name("condition"), "condition")
  assert_eq(escape_field_name("lhs"), "lhs")
}

// ─── 辅助：构建最小语法 ──────────────────────────────────────────────────────

///|
fn make_mini_grammar() -> @grammar.Grammar {
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
  // binary_expr: Seq with two named fields
  rules.set("binary_expr", {
    name: "binary_expr",
    pattern: @grammar.Pattern::Seq([
      @grammar.Pattern::Field("lhs", @grammar.Pattern::RuleRef("expr")),
      @grammar.Pattern::Literal("+"),
      @grammar.Pattern::Field("rhs", @grammar.Pattern::RuleRef("expr")),
    ]),
    is_named: true,
    is_token: false,
    params: [],
    attributes: [],
    location: None,
  })
  // expr: Choice → Enum
  rules.set("expr", {
    name: "expr",
    pattern: @grammar.Pattern::Choice([
      @grammar.Pattern::RuleRef("binary_expr"),
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

// ─── emit_type_defs ──────────────────────────────────────────────────────────

///|
test "emit_type_defs / struct contains _node field" {
  let schema = infer_grammar(make_mini_grammar())
  let out = emit_type_defs(schema)
  assert_true(out.contains("pub(all) struct BinaryExpr"))
  assert_true(out.contains("_node : @runtime.CstNode"))
}

///|
test "emit_type_defs / token struct emitted" {
  let schema = infer_grammar(make_mini_grammar())
  let out = emit_type_defs(schema)
  assert_true(out.contains("pub(all) struct Number"))
}

///|
test "emit_type_defs / enum emitted with variants" {
  let schema = infer_grammar(make_mini_grammar())
  let out = emit_type_defs(schema)
  assert_true(out.contains("pub(all) enum Expr"))
  assert_true(out.contains("BinaryExpr(@runtime.CstNode)"))
  assert_true(out.contains("Number(@runtime.CstNode)"))
}

///|
test "emit_type_defs / no @inline rule appears" {
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
  let out = emit_type_defs(schema)
  assert_true(!out.contains("struct Ws"))
  assert_true(out.contains("struct Root"))
}

// ─── emit_accessors ──────────────────────────────────────────────────────────

///|
test "emit_accessors / struct has node() and of()" {
  let schema = infer_grammar(make_mini_grammar())
  let out = emit_accessors(schema)
  assert_true(out.contains("BinaryExpr::node(self : BinaryExpr)"))
  assert_true(out.contains("BinaryExpr::of(node : @runtime.CstNode)"))
}

///|
test "emit_accessors / field accessors for lhs and rhs" {
  let schema = infer_grammar(make_mini_grammar())
  let out = emit_accessors(schema)
  assert_true(out.contains("BinaryExpr::lhs(self : BinaryExpr)"))
  assert_true(out.contains("BinaryExpr::rhs(self : BinaryExpr)"))
  // 字段访问器中包含字段名字符串
  assert_true(out.contains("Some(\"lhs\")"))
  assert_true(out.contains("Some(\"rhs\")"))
}

///|
test "emit_accessors / enum has from_node and node()" {
  let schema = infer_grammar(make_mini_grammar())
  let out = emit_accessors(schema)
  assert_true(
    out.contains("Expr::from_node(node : @runtime.CstNode, rule_name : String)"),
  )
  assert_true(out.contains("Expr::node(self : Expr)"))
  // from_node 包含规则名字符串分支
  assert_true(out.contains("\"binary_expr\""))
  assert_true(out.contains("\"number\""))
}

///|
test "emit_accessors / enum node() uses | pattern" {
  let schema = infer_grammar(make_mini_grammar())
  let out = emit_accessors(schema)
  // 多个变体应用 | 合并为单个 match arm
  assert_true(out.contains("BinaryExpr(n)"))
  assert_true(out.contains("Number(n)"))
  assert_true(out.contains("=> n"))
}

///|
test "emit_accessors / Many field returns Array" {
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
  let out = emit_accessors(schema)
  assert_true(out.contains("Array[@runtime.CstNode]"))
  assert_true(out.contains("result.push("))
}

// ─── generate_typed_api ──────────────────────────────────────────────────────

///|
test "generate_typed_api / ok result contains header" {
  match generate_typed_api(make_mini_grammar(), "my_module") {
    Err(e) => fail("expected Ok, got Err: \{e}")
    Ok(src) => {
      assert_true(src.has_prefix("// Auto-generated by MoonParse typegen."))
      assert_true(src.contains("Grammar: my_module"))
    }
  }
}

///|
test "generate_typed_api / ok result contains types and accessors" {
  match generate_typed_api(make_mini_grammar(), "test") {
    Err(e) => fail("expected Ok, got Err: \{e}")
    Ok(src) => {
      // 类型定义
      assert_true(src.contains("pub(all) struct BinaryExpr"))
      assert_true(src.contains("pub(all) enum Expr"))
      // 访问器
      assert_true(src.contains("BinaryExpr::lhs"))
      assert_true(src.contains("Expr::from_node"))
    }
  }
}

///|
test "generate_typed_api / empty grammar returns Err" {
  let empty_g : @grammar.Grammar = {
    start: None,
    rules: Map::new(),
    precedences: [],
    extras: [],
    externals: [],
    duplicate_rule_names: [],
    word: None,
    conflicts: [],
    supertypes: [],
  }
  match generate_typed_api(empty_g, "empty") {
    Ok(_) => fail("expected Err for empty grammar")
    Err(_) => () // expected
  }
}

///|
test "generate_typed_api / keyword field name is escaped in output" {
  let rules : Map[String, @grammar.Rule] = Map::new()
  rules.set("if_expr", {
    name: "if_expr",
    pattern: @grammar.Pattern::Seq([
      @grammar.Pattern::Field("else", @grammar.Pattern::Regex(".+")),
    ]),
    is_named: true,
    is_token: false,
    params: [],
    attributes: [],
    location: None,
  })
  let g : @grammar.Grammar = {
    start: Some("if_expr"),
    rules,
    precedences: [],
    extras: [],
    externals: [],
    duplicate_rule_names: [],
    word: None,
    conflicts: [],
    supertypes: [],
  }
  match generate_typed_api(g, "kw_test") {
    Err(e) => fail("expected Ok, got Err: \{e}")
    Ok(src) => {
      // 字段名 'else' 应被转义为 'else_'
      assert_true(src.contains("::else_"))
      // 查找 else_ 字段访问器，内部字符串仍用原始 "else"
      assert_true(src.contains("Some(\"else\")"))
    }
  }
}
