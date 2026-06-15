; 作用域
(block) @scope.block
(function_decl) @scope.function

; 定义
(function_decl (fn_name (identifier) @definition.function))
(let_statement (identifier) @definition.variable)
(parameter (identifier) @definition.parameter)
(struct_decl (identifier) @definition.type)
(enum_decl (identifier) @definition.type)
(type_alias_decl (identifier) @definition.type)
(enum_case (identifier) @definition.variable)

; 引用
(identifier) @reference.variable
