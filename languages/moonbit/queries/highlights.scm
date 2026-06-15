; 字符串与字符
(string_literal) @string
(char_literal)   @string.special

; 数字
(number_literal) @number

; 布尔常量
"true"  @constant.builtin
"false" @constant.builtin
"()"    @constant.builtin

; 函数定义名
(function_decl (fn_name (identifier) @function))

; 结构体 / 枚举 / 类型别名名
(struct_decl (identifier) @type)
(enum_decl   (identifier) @type)
(type_alias_decl (identifier) @type)

; 枚举成员（构造子）
(enum_case (identifier) @constructor)

; 声明关键字
"fn"     @keyword.function
"let"    @keyword
"mut"    @keyword
"type"   @keyword
"struct" @keyword
"enum"   @keyword
"test"   @keyword
"pub"    @keyword
"priv"   @keyword

; 控制流关键字
"if"       @keyword.control
"else"     @keyword.control
"match"    @keyword.control
"for"      @keyword.control
"while"    @keyword.control
"return"   @keyword.return
"break"    @keyword.control
"continue" @keyword.control
"in"       @keyword.control

; 运算符
"+"  @operator
"-"  @operator
"*"  @operator
"/"  @operator
"%"  @operator
"="  @operator
":=" @operator
"==" @operator
"!=" @operator
"<"  @operator
">"  @operator
"<=" @operator
">=" @operator
"&&" @operator
"||" @operator
"!"  @operator
".." @operator

; 泛型 / 标注
"derive" @attribute

; 括号
"(" @punctuation.bracket
")" @punctuation.bracket
"{" @punctuation.bracket
"}" @punctuation.bracket
"[" @punctuation.bracket
"]" @punctuation.bracket

; 分隔符
"," @punctuation.delimiter
";" @punctuation.delimiter
":" @punctuation.delimiter
"->" @punctuation.delimiter
"." @punctuation.delimiter

; 标识符（通用变量回退，放在最后优先级最低）
(identifier) @variable
