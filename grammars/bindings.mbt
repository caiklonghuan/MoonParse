///|
// 内置语言绑定查询字符串
//
// 每个常量对应一种内置语法的 scope/definition/reference 查询，
// 可直接传给 @query.compile() 并配合 @query.build_binding_graph() 使用。
//
// 捕获名使用 P2 约定：
//   @scope / @scope.function / @scope.block / @scope.class / @scope.loop
//   @definition.variable / @definition.function / @definition.type / @definition.parameter
//   @reference.variable / @reference.function / @reference.type
//
// 同时兼容旧的 local.* 约定（由 bindings.capture_role 自动映射）。

///|
/// Grammar DSL 绑定查询。
///
/// rule 定义为 definition，rule body 中的 identifier 为 reference。
pub let grammar_dsl_bindings_query : String =
  #|; rule 名 → definition（归入隐式 root Module scope）
  #|(rule_definition name: (identifier) @definition.rule)
  #|
  #|; rule body 中的标识符 → reference
  #|(rule_definition (identifier) @reference.rule)

///|
/// MoonBit 绑定查询。
///
/// 函数体 block 为作用域，let/fn/参数为定义，标识符为引用。

///|
/// Python 绑定查询。
///
/// 函数/类体为作用域，def/class/参数为定义，标识符为引用。

///|
/// C 绑定查询。
///
/// 花括号块和函数定义为作用域，声明和参数为定义，标识符为引用。
pub let c_bindings_query : String =
  #|; 作用域
  #|(compound_statement) @scope.block
  #|(function_definition) @scope.function
  #|
  #|; 定义
  #|(function_definition (declarator (identifier) @definition.function))
  #|(declaration (init_declarator_list (identifier) @definition.variable))
  #|(parameter_declaration (identifier) @definition.parameter)
  #|(struct_specifier (identifier) @definition.type)
  #|(enum_specifier (identifier) @definition.type)
  #|
  #|; 引用
  #|(identifier) @reference.variable

///|
/// 语言 id → binding query 映射，LSP 按 languageId 选择。
pub fn binding_query_for_lang(lang_id : String) -> String? {
  match lang_id {
    "__dsl__" => Some(grammar_dsl_bindings_query)
    "moonbit" => Some(moonbit_bindings_query)
    "python" => Some(python_bindings_query)
    "c" => Some(c_bindings_query)
    _ => None
  }
}

///|
/// MoonBit Pack 中的权威 Binding Query。
pub let moonbit_bindings_query : String = builtin_moonbit_bundle.bindings_source.unwrap()

///|
/// Python Pack 中的权威 Binding Query。
pub let python_bindings_query : String = builtin_python_bundle.bindings_source.unwrap()
