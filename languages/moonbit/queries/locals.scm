; 作用域边界：函数体 block
(block) @local.scope

; 局部变量定义（let x = ... 中的 x）
(let_statement (identifier) @local.definition)

; 函数参数定义
(parameter (identifier) @local.definition.parameter)

; 所有标识符视为潜在引用
(identifier) @local.reference
