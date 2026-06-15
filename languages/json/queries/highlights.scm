; 字符串
(jstring) @string

; 数字
(number) @number

; 关键字字面量
"true" @constant.builtin
"false" @constant.builtin
"null" @constant.builtin

; 对象键（pair 的第一个 jstring）
(pair (jstring) @property)

; 括号
"{" @punctuation.bracket
"}" @punctuation.bracket
"[" @punctuation.bracket
"]" @punctuation.bracket

; 分隔符
"," @punctuation.delimiter
":" @punctuation.delimiter
