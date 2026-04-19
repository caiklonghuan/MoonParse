///|
// 内置语言高亮查询字符串
//
// 每个常量对应一种内置语法的 Tree-Sitter 风格高亮查询，
// 可直接传给 @query.compile() 并配合 apply_highlights() 使用。
//
// 捕获名遵循 highlight_names 中的标准命名约定：
//   @keyword  @string  @number  @comment  @operator
//   @function  @type  @variable  @property  @constant
//   @punctuation.bracket  @punctuation.delimiter

///|
/// JSON 语法高亮查询。
///
/// 对应 grammars/json.mbt 中的 json_grammar 规则集：
///   json / value / object / pairs / pair / array / elements / jstring / number
pub let json_highlight_query : String =
  #|; 字符串
  #|(jstring) @string
  #|
  #|; 数字
  #|(number) @number
  #|
  #|; 关键字字面量
  #|"true" @constant.builtin
  #|"false" @constant.builtin
  #|"null" @constant.builtin
  #|
  #|; 对象键（pair 的第一个 jstring）
  #|(pair (jstring) @property)
  #|
  #|; 括号
  #|"{" @punctuation.bracket
  #|"}" @punctuation.bracket
  #|"[" @punctuation.bracket
  #|"]" @punctuation.bracket
  #|
  #|; 分隔符
  #|"," @punctuation.delimiter
  #|":" @punctuation.delimiter

///|
/// JSON5 语法高亮查询。
///
/// 在 json_highlight_query 基础上增加注释和额外字面量。
/// 对应 grammars/json5.mbt 中的 json5_grammar 规则集。
pub let json5_highlight_query : String =
  #|; 字符串（双引号 / 单引号）
  #|(string) @string
  #|
  #|; 数字（含十六进制、Infinity、NaN）
  #|(number) @number
  #|
  #|; 关键字字面量
  #|"true"     @constant.builtin
  #|"false"    @constant.builtin
  #|"null"     @constant.builtin
  #|"Infinity" @constant.builtin
  #|"NaN"      @constant.builtin
  #|
  #|; 对象键
  #|(member (property_name (string)) @property)
  #|(member (property_name (identifier)) @property)
  #|
  #|; 括号
  #|"{" @punctuation.bracket
  #|"}" @punctuation.bracket
  #|"[" @punctuation.bracket
  #|"]" @punctuation.bracket
  #|
  #|; 分隔符
  #|"," @punctuation.delimiter
  #|":" @punctuation.delimiter

///|
/// MoonBit 语法子集高亮查询。
///
/// 对应 grammars/moonbit.mbt 中的 moonbit_grammar 规则集。
pub let moonbit_highlight_query : String =
  #|; 字符串与字符
  #|(string_literal) @string
  #|(char_literal)   @string.special
  #|
  #|; 数字
  #|(number_literal) @number
  #|
  #|; 布尔常量
  #|"true"  @constant.builtin
  #|"false" @constant.builtin
  #|"()"    @constant.builtin
  #|
  #|; 函数定义名
  #|(function_decl (fn_name (identifier) @function))
  #|
  #|; 结构体 / 枚举 / 类型别名名
  #|(struct_decl (identifier) @type)
  #|(enum_decl   (identifier) @type)
  #|(type_alias_decl (identifier) @type)
  #|
  #|; 枚举成员（构造子）
  #|(enum_case (identifier) @constructor)
  #|
  #|; 声明关键字
  #|"fn"     @keyword.function
  #|"let"    @keyword
  #|"mut"    @keyword
  #|"type"   @keyword
  #|"struct" @keyword
  #|"enum"   @keyword
  #|"test"   @keyword
  #|"pub"    @keyword
  #|"priv"   @keyword
  #|
  #|; 控制流关键字
  #|"if"       @keyword.control
  #|"else"     @keyword.control
  #|"match"    @keyword.control
  #|"for"      @keyword.control
  #|"while"    @keyword.control
  #|"return"   @keyword.return
  #|"break"    @keyword.control
  #|"continue" @keyword.control
  #|"in"       @keyword.control
  #|
  #|; 运算符
  #|"+"  @operator
  #|"-"  @operator
  #|"*"  @operator
  #|"/"  @operator
  #|"%"  @operator
  #|"="  @operator
  #|":=" @operator
  #|"==" @operator
  #|"!=" @operator
  #|"<"  @operator
  #|">"  @operator
  #|"<=" @operator
  #|">=" @operator
  #|"&&" @operator
  #|"||" @operator
  #|"!"  @operator
  #|".." @operator
  #|
  #|; 泛型 / 标注
  #|"derive" @attribute
  #|
  #|; 括号
  #|"(" @punctuation.bracket
  #|")" @punctuation.bracket
  #|"{" @punctuation.bracket
  #|"}" @punctuation.bracket
  #|"[" @punctuation.bracket
  #|"]" @punctuation.bracket
  #|
  #|; 分隔符
  #|"," @punctuation.delimiter
  #|";" @punctuation.delimiter
  #|":" @punctuation.delimiter
  #|"->" @punctuation.delimiter
  #|"." @punctuation.delimiter
  #|
  #|; 标识符（通用变量回退，放在最后优先级最低）
  #|(identifier) @variable

///|
/// C 语法子集高亮查询。
///
/// 对应 grammars/c.mbt 中的 c_grammar 规则集。
pub let c_highlight_query : String =
  #|; 字符串与字符
  #|(string_literal) @string
  #|(char_literal)   @string.special
  #|
  #|; 数字
  #|(number_literal) @number
  #|
  #|; 预处理指令
  #|(preproc_directive) @keyword.directive
  #|
  #|; 函数定义名
  #|(function_definition (declarator (identifier) @function))
  #|
  #|; 类型名
  #|"void"     @type.builtin
  #|"char"     @type.builtin
  #|"short"    @type.builtin
  #|"int"      @type.builtin
  #|"long"     @type.builtin
  #|"float"    @type.builtin
  #|"double"   @type.builtin
  #|"signed"   @type.builtin
  #|"unsigned" @type.builtin
  #|
  #|; 存储类修饰符
  #|"const"  @keyword
  #|"static" @keyword
  #|"extern" @keyword
  #|"struct" @keyword
  #|
  #|; 控制流
  #|"if"       @keyword.control
  #|"else"     @keyword.control
  #|"while"    @keyword.control
  #|"for"      @keyword.control
  #|"return"   @keyword.return
  #|"break"    @keyword.control
  #|"continue" @keyword.control
  #|
  #|; 运算符
  #|"+"  @operator
  #|"-"  @operator
  #|"*"  @operator
  #|"/"  @operator
  #|"%"  @operator
  #|"="  @operator
  #|"+=" @operator
  #|"-=" @operator
  #|"*=" @operator
  #|"/=" @operator
  #|"%=" @operator
  #|"==" @operator
  #|"!=" @operator
  #|"<"  @operator
  #|">"  @operator
  #|"<=" @operator
  #|">=" @operator
  #|"&&" @operator
  #|"||" @operator
  #|"!"  @operator
  #|"~"  @operator
  #|"&"  @operator
  #|"++" @operator
  #|"--" @operator
  #|"->" @operator
  #|
  #|; 括号
  #|"(" @punctuation.bracket
  #|")" @punctuation.bracket
  #|"{" @punctuation.bracket
  #|"}" @punctuation.bracket
  #|"[" @punctuation.bracket
  #|"]" @punctuation.bracket
  #|
  #|; 分隔符
  #|"," @punctuation.delimiter
  #|";" @punctuation.delimiter
  #|"." @punctuation.delimiter
  #|
  #|; 标识符（通用回退）
  #|(identifier) @variable

///|
/// MoonBit locals 查询（配合 moonbit_highlight_query + apply_highlights_with_locals 使用）。
///
/// 将函数体 block 视为作用域边界，let_statement 的第一个标识符为定义，
/// 所有 identifier 为潜在引用。
pub let moonbit_locals_query : String =
  #|; 作用域边界：函数体 block
  #|(block) @local.scope
  #|
  #|; 局部变量定义（let x = ... 中的 x）
  #|(let_statement (identifier) @local.definition)
  #|
  #|; 函数参数定义
  #|(parameter (identifier) @local.definition.parameter)
  #|
  #|; 所有标识符视为潜在引用
  #|(identifier) @local.reference
