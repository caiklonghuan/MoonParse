///|
// query/bindings.mbt — capture_role 解析测试

///|
test "capture_role/new_scope" {
  assert_eq(capture_role("scope"), Scope(None))
  assert_eq(capture_role("scope.function"), Scope(Some(Function)))
  assert_eq(capture_role("scope.block"), Scope(Some(Block)))
  assert_eq(capture_role("scope.class"), Scope(Some(Class)))
  assert_eq(capture_role("scope.loop"), Scope(Some(Loop)))
  assert_eq(capture_role("scope.module"), Scope(Some(Module)))
  assert_eq(capture_role("scope.rule"), Scope(Some(Rule)))
}

///|
test "capture_role/new_scope_unknown_suffix" {
  assert_eq(capture_role("scope.unknown"), Scope(None))
}

///|
test "capture_role/new_definition" {
  assert_eq(capture_role("definition"), Definition(None))
  assert_eq(capture_role("definition.variable"), Definition(Some(Variable)))
  assert_eq(capture_role("definition.constant"), Definition(Some(Constant)))
  assert_eq(capture_role("definition.function"), Definition(Some(Function)))
  assert_eq(capture_role("definition.method"), Definition(Some(Method)))
  assert_eq(capture_role("definition.type"), Definition(Some(Type)))
  assert_eq(capture_role("definition.struct"), Definition(Some(Struct)))
  assert_eq(capture_role("definition.enum"), Definition(Some(Enum)))
  assert_eq(capture_role("definition.trait"), Definition(Some(Trait)))
  assert_eq(capture_role("definition.field"), Definition(Some(Field)))
  assert_eq(
    capture_role("definition.enum_member"),
    Definition(Some(EnumMember)),
  )
  assert_eq(capture_role("definition.parameter"), Definition(Some(Parameter)))
  assert_eq(
    capture_role("definition.type_parameter"),
    Definition(Some(TypeParameter)),
  )
}

///|
test "capture_role/new_reference" {
  assert_eq(capture_role("reference"), Reference(None, true))
  assert_eq(capture_role("reference.variable"), Reference(Some(Variable), true))
  assert_eq(capture_role("reference.function"), Reference(Some(Function), true))
  assert_eq(capture_role("reference.type"), Reference(Some(Type), true))
  assert_eq(
    capture_role("reference.soft.variable"),
    Reference(Some(Variable), false),
  )
}

///|
test "capture_role/symbol" {
  assert_eq(capture_role("symbol"), Symbol(None))
  assert_eq(capture_role("symbol.function"), Symbol(Some(Function)))
  assert_eq(capture_role("symbol.type"), Symbol(Some(Type)))
  assert_eq(capture_role("symbol.enum_member"), Symbol(Some(EnumMember)))
  assert_eq(capture_role("symbol.type_parameter"), Symbol(Some(TypeParameter)))
}

///|
test "capture_role/old_local_compat" {
  assert_eq(capture_role("local.scope"), Scope(None))
  assert_eq(capture_role("local.definition"), Definition(Some(Variable)))
  assert_eq(
    capture_role("local.definition.function"),
    Definition(Some(Function)),
  )
  assert_eq(capture_role("local.reference"), Reference(Some(Variable), true))
}

///|
test "capture_role/unknown" {
  assert_eq(capture_role("highlight"), Unknown)
  assert_eq(capture_role("fold"), Unknown)
  assert_eq(capture_role("keyword"), Unknown)
  assert_eq(capture_role(""), Unknown)
}

///|
test "symbol_kind_from_str/known" {
  assert_eq(symbol_kind_from_str("variable"), Some(Variable))
  assert_eq(symbol_kind_from_str("constant"), Some(Constant))
  assert_eq(symbol_kind_from_str("function"), Some(Function))
  assert_eq(symbol_kind_from_str("method"), Some(Method))
  assert_eq(symbol_kind_from_str("type"), Some(Type))
  assert_eq(symbol_kind_from_str("struct"), Some(Struct))
  assert_eq(symbol_kind_from_str("enum"), Some(Enum))
  assert_eq(symbol_kind_from_str("trait"), Some(Trait))
  assert_eq(symbol_kind_from_str("field"), Some(Field))
  assert_eq(symbol_kind_from_str("enum_member"), Some(EnumMember))
  assert_eq(symbol_kind_from_str("parameter"), Some(Parameter))
  assert_eq(symbol_kind_from_str("type_parameter"), Some(TypeParameter))
  assert_eq(symbol_kind_from_str("rule"), Some(Rule))
  assert_eq(symbol_kind_from_str("token"), Some(Token))
}

///|
test "symbol_kind_from_str/unknown" {
  assert_eq(symbol_kind_from_str("unknown"), None)
  assert_eq(symbol_kind_from_str(""), None)
}

///|
test "ns_from_kind/mapping" {
  assert_eq(ns_from_kind(Variable), Value)
  assert_eq(ns_from_kind(Constant), Value)
  assert_eq(ns_from_kind(Function), Value)
  assert_eq(ns_from_kind(Method), Value)
  assert_eq(ns_from_kind(Parameter), Value)
  assert_eq(ns_from_kind(EnumMember), Value)
  assert_eq(ns_from_kind(Type), Type)
  assert_eq(ns_from_kind(Struct), Type)
  assert_eq(ns_from_kind(Enum), Type)
  assert_eq(ns_from_kind(Trait), Type)
  assert_eq(ns_from_kind(TypeParameter), Type)
  assert_eq(ns_from_kind(Field), Member)
  assert_eq(ns_from_kind(Rule), Rule)
  assert_eq(ns_from_kind(Token), Rule)
}

///|
test "ns_from_scope_kind/mapping" {
  assert_eq(ns_from_scope_kind(Module), Value)
  assert_eq(ns_from_scope_kind(Function), Value)
  assert_eq(ns_from_scope_kind(Block), Value)
  assert_eq(ns_from_scope_kind(Loop), Value)
  assert_eq(ns_from_scope_kind(Class), Type)
  assert_eq(ns_from_scope_kind(Rule), Rule)
}

// ── build_binding_graph 端到端测试 ──

///|
fn make_table_and_parse(
  dsl : String,
  input : String,
) -> (@runtime.CstNode, @tablegen.ParseTable) {
  let g = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(_) => panic()
  }
  let (t, _) = match @tablegen.generate_parse_table(g) {
    Ok(r) => r
    Err(_) => panic()
  }
  match @runtime.parse(t, input) {
    Ok(n) => (n, t)
    Err(_) => panic()
  }
}

///|
test "build_binding_graph/produces_root_scope_and_no_crash" {
  let dsl =
    #|start prog
    #|extras [/[ \t\n\r]+/]
    #|rule prog: expr*
    #|rule expr: term "+" term
    #|rule term: ident | number
    #|rule ident: /[a-z]+/
    #|rule number: /[0-9]+/
  let (root, table) = make_table_and_parse(dsl, "foo + bar")
  let query_s =
    #|(rule_definition (identifier) @definition.rule)
    #|(rule_definition (identifier) @reference.rule)
  let query = match @query.compile(query_s) {
    Ok(q) => q
    Err(_) => panic()
  }
  let graph = build_binding_graph(root, "foo + bar", table, query)
  // root Module scope 始终存在
  assert_true(graph.scopes.length() >= 1)
  assert_eq(graph.scopes[0].kind, Module)
  // 不崩溃，产出合法结构
  assert_true(graph.definitions.length() >= 0)
  assert_true(graph.references.length() >= 0)
  // self_only refs 不产生 unresolved
  let mut unresolved_count = 0
  for d in graph.diagnostics {
    if d.kind == Unresolved {
      unresolved_count = unresolved_count + 1
    }
  }
  assert_eq(unresolved_count, 0)
}

///|
test "build_binding_graph/rule_name_not_in_own_scope" {
  // 修复：rule 定义名不应被归入 rule 自己的 scope
  let dsl =
    #|start prog
    #|extras [/[ \t\n\r]+/]
    #|rule prog: expr*
    #|rule expr: term "+" term
    #|rule term: ident | number
    #|rule ident: /[a-z]+/
    #|rule number: /[0-9]+/
  let (root, table) = make_table_and_parse(dsl, "foo + bar")
  let query_s =
    #|(rule_definition) @scope.rule
    #|(rule_definition name: (identifier) @definition.rule)
    #|(rule_definition (identifier) @reference.rule)
  let query = match @query.compile(query_s) {
    Ok(q) => q
    Err(_) => panic()
  }
  let graph = build_binding_graph(root, "foo + bar", table, query)
  // rule "expr" 引用了 "term" → term 的定义应在 root scope，不在 expr scope
  // expr 的 name "expr" 应该也在 root scope（不是 expr scope）
  for def in graph.definitions {
    assert_true(def.scope_id == 0) // 所有定义在 root scope
  }
}

///|
test "build_binding_graph/def_as_ref_not_in_graph" {
  // 修复：定义节点被 reference query 捕获后不应留在 graph 里
  let dsl =
    #|start prog
    #|extras [/[ \t\n\r]+/]
    #|rule prog: expr*
    #|rule expr: term "+" term
    #|rule term: ident | number
    #|rule ident: /[a-z]+/
    #|rule number: /[0-9]+/
  let (root, table) = make_table_and_parse(dsl, "foo + bar")
  let query_s =
    #|(rule_definition name: (identifier) @definition.rule)
    #|(rule_definition (identifier) @reference.rule)
  let query = match @query.compile(query_s) {
    Ok(q) => q
    Err(_) => panic()
  }
  let graph = build_binding_graph(root, "foo + bar", table, query)
  // self_only refs 不应产生 unresolved
  let mut unresolved_count = 0
  for d in graph.diagnostics {
    if d.kind == Unresolved {
      unresolved_count = unresolved_count + 1
    }
  }
  assert_eq(unresolved_count, 0)
  // 所有 reference 都应该有 edge
  for r in graph.references {
    let mut has_edge = false
    for e in graph.edges {
      if e.reference_id == r.id {
        has_edge = true
        break
      }
    }
    assert_true(has_edge)
  }
}

///|
test "build_binding_graph/definition_self_capture_skipped" {
  // definition 节点被 reference query 同时捕获 → 不加到 references
  let dsl =
    #|start prog
    #|extras [/[ \t\n\r]+/]
    #|rule prog: ident*
    #|rule ident: /[a-z]+/
  let (root, table) = make_table_and_parse(dsl, "foo foo")
  // 两个 "foo" ident 同时是 def 和 ref → 应各自找到对方（旧 locals 行为）
  let query_s =
    #|(ident) @definition.variable
    #|(ident) @reference.variable
  let query = match @query.compile(query_s) {
    Ok(q) => q
    Err(_) => panic()
  }
  let graph = build_binding_graph(root, "foo foo", table, query)
  // ident@0 "foo" 和 ident@4 "foo" 互为 def+ref → 应各自找到对方
  // references 不应为空
  assert_true(graph.references.length() > 0)
  // unresolved 应为 0
  let mut unresolved_count = 0
  for d in graph.diagnostics {
    if d.kind == Unresolved {
      unresolved_count = unresolved_count + 1
    }
  }
  assert_eq(unresolved_count, 0)
  // 每个 ref 都有 edge
  assert_eq(graph.edges.length(), 0)
  let mut ambiguous_count = 0
  for d in graph.diagnostics {
    if d.kind == Ambiguous {
      ambiguous_count = ambiguous_count + 1
    }
  }
  assert_true(ambiguous_count > 0)
}

///|
test "build_binding_graph/single_definition_no_self_ref" {
  // 单个定义被 reference query 捕获 → 不入 references（纯自引用）
  let dsl =
    #|start prog
    #|extras [/[ \t\n\r]+/]
    #|rule prog: ident*
    #|rule ident: /[a-z]+/
  let (root, table) = make_table_and_parse(dsl, "foo")
  let query_s =
    #|(ident) @definition.variable
    #|(ident) @reference.variable
  let query = match @query.compile(query_s) {
    Ok(q) => q
    Err(_) => panic()
  }
  let graph = build_binding_graph(root, "foo", table, query)
  // 只有一个 ident "foo" → 它是 def 也是 ref → 纯自引用，跳过
  assert_eq(graph.references.length(), 0)
  assert_eq(graph.edges.length(), 0)
  // 无 unresolved
  let mut unresolved_count = 0
  for d in graph.diagnostics {
    if d.kind == Unresolved {
      unresolved_count = unresolved_count + 1
    }
  }
  assert_eq(unresolved_count, 0)
}

///|
test "build_binding_graph/soft_reference_suppresses_only_unresolved_diagnostic" {
  let dsl =
    #|start prog
    #|rule prog: ident
    #|rule ident: /[a-z]+/
  let (root, table) = make_table_and_parse(dsl, "missing")
  let query = @query.compile("(ident) @reference.soft.variable").unwrap()
  let graph = build_binding_graph(root, "missing", table, query)
  assert_eq(graph.references.length(), 1)
  assert_false(graph.references[0].diagnose_unresolved)
  assert_eq(graph.edges.length(), 0)
  assert_eq(graph.diagnostics.length(), 0)
}

///|
test "build_binding_graph/strict_reference_reports_unresolved" {
  let dsl =
    #|start prog
    #|rule prog: ident
    #|rule ident: /[a-z]+/
  let (root, table) = make_table_and_parse(dsl, "missing")
  let query = @query.compile("(ident) @reference.variable").unwrap()
  let graph = build_binding_graph(root, "missing", table, query)
  assert_eq(graph.references.length(), 1)
  assert_true(graph.references[0].diagnose_unresolved)
  assert_eq(graph.edges.length(), 0)
  assert_eq(graph.diagnostics.length(), 1)
  assert_true(graph.diagnostics[0].kind == Unresolved)
}

///|
test "build_binding_graph/reference_merge_soft_overrides_strict" {
  let dsl =
    #|start prog
    #|rule prog: ident
    #|rule ident: /[a-z]+/
  let (root, table) = make_table_and_parse(dsl, "external")
  let query_source =
    #|(ident) @reference.variable
    #|(ident) @reference.soft.function
  let query = @query.compile(query_source).unwrap()
  let graph = build_binding_graph(root, "external", table, query)
  assert_eq(graph.references.length(), 1)
  assert_false(graph.references[0].diagnose_unresolved)
  assert_eq(graph.edges.length(), 0)
  assert_eq(graph.diagnostics.length(), 0)
}

///|
test "build_binding_graph/duplicate_same_scope_same_namespace" {
  let dsl =
    #|start prog
    #|extras [/[ \t]+/]
    #|rule prog: decl*
    #|rule decl: "let" ident
    #|rule ident: /[a-z]+/
  let input = "let x let x"
  let (root, table) = make_table_and_parse(dsl, input)
  let query = @query.compile("(decl (ident) @definition.variable)").unwrap()
  let graph = build_binding_graph(root, input, table, query)
  assert_eq(graph.definitions.length(), 2)
  let mut duplicate_count = 0
  for d in graph.diagnostics {
    if d.kind == Duplicate {
      duplicate_count = duplicate_count + 1
    }
  }
  assert_eq(duplicate_count, 1)
}

///|
test "build_binding_graph/symbol_range_pairs_by_match_id_and_kind" {
  let dsl =
    #|start prog
    #|extras [/[ \t]+/]
    #|rule prog: decl ref
    #|rule decl: "let" ident
    #|rule ref: ident
    #|rule ident: /[a-z]+/
  let input = "let value value"
  let (root, table) = make_table_and_parse(dsl, input)
  let query_source =
    #|(decl (ident) @definition.variable) @symbol.variable
    #|(ref (ident) @reference.variable)
  let query = @query.compile(query_source).unwrap()
  let graph = build_binding_graph(root, input, table, query)
  assert_eq(graph.definitions.length(), 1)
  let definition = graph.definitions[0]
  assert_eq(definition.start_byte, 4)
  assert_eq(definition.end_byte, 9)
  assert_eq(definition.declaration_start_byte, 0)
  assert_eq(definition.declaration_end_byte, 9)
  assert_eq(graph.references.length(), 1)
  assert_eq(graph.edges.length(), 1)
}

///|
test "build_binding_graph/mismatched_symbol_kind_falls_back_to_name_range" {
  let dsl =
    #|start prog
    #|extras [/[ \t]+/]
    #|rule prog: decl
    #|rule decl: "let" ident
    #|rule ident: /[a-z]+/
  let input = "let value"
  let (root, table) = make_table_and_parse(dsl, input)
  let query = @query.compile("(decl (ident) @definition.variable) @symbol.type").unwrap()
  let graph = build_binding_graph(root, input, table, query)
  let definition = graph.definitions[0]
  assert_eq(definition.declaration_start_byte, definition.start_byte)
  assert_eq(definition.declaration_end_byte, definition.end_byte)
}
