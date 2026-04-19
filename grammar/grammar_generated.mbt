///|
pub let moonbit_grammar : String =
  #|start structure
  #|
  #|extras [/\s/]
  #|externals [_scanner_reset, _automatic_semicolon, ";", "#|", "$|", _double_literal, "for", error_sentinel]
  #|word lowercase_identifier
  #|supertypes [_expression, _statement_expression, _structure_item, _type, _pattern]
  #|conflicts [[optional_label, qualified_identifier], [positional_parameter, qualified_identifier], [unit_expression, parameters], [qualified_identifier, arrow_function_expression], [positional_parameter, identifier], [optional_label, identifier], [_simple_expression, positional_parameter], [_simple_type, positional_parameter], [_simple_expression, arrow_function_expression], [_simple_pattern, lexmatch_simple_pattern]]
  #|
  #|rule structure: ((_structure_item | package_statement) (_semicolon (_structure_item | package_statement))* _semicolon?)?
  #|rule _structure_item: package_declaration | import_declaration | using_declaration | type_definition | error_type_definition | struct_definition | tuple_struct_definition | enum_definition | value_definition | const_definition | function_definition | test_definition | trait_definition | impl_definition | impl_declaration | type_alias_definition | trait_alias_definition | function_alias_definition
  #|rule package_statement: package_assignment_statement | package_apply_statement
  #|rule package_declaration: prec(1, "package") string_literal
  #|rule import_declaration: prec(1, "import") ("{" (import_item ("," import_item)* ","?)? "}" package_import_for_clause? | "(" import_item* ")" | package_import_kind "{" (import_item ("," import_item)* ","?)? "}")
  #|rule import_item: path: string_literal (alias: package_identifier | "as" alias: package_identifier)?
  #|rule package_import_for_clause: "for" kind: package_import_kind
  #|rule package_import_kind: string_literal
  #|rule package_assignment_statement: name: package_statement_identifier "=" value: package_expression
  #|rule package_apply_statement: name: package_statement_identifier "(" (package_argument ("," package_argument)* ","?)? ")"
  #|rule package_argument: label: (package_statement_identifier | string_literal) ":" value: package_expression
  #|rule package_expression: boolean_literal | integer_literal | string_literal | package_array_expression | package_map_expression
  #|rule package_array_expression: "[" (package_expression ("," package_expression)* ","?)? "]"
  #|rule package_map_expression: "{" (package_map_entry ("," package_map_entry)* ","?)? "}"
  #|rule package_map_entry: key: string_literal ":" value: package_expression
  #|rule visibility: "priv" | "pub" pub_attribute?
  #|token rule pub_attribute: "(" ("readonly" | "all" | "open") ")"
  #|rule derive_item: type_name arguments?
  #|rule derive_directive: "derive" "(" (derive_item ("," derive_item)* ","?)? ")"
  #|rule type_definition: attributes? visibility? "extern"? "type" identifier type_parameters? ("=" _type)? derive_directive?
  #|rule error_type_definition: attributes? visibility? "extern"? ("type" "!" | "suberror") identifier (_type | "{" (enum_constructor (_semicolon enum_constructor)* _semicolon?)? "}")? derive_directive?
  #|rule type_alias_target: identifier | identifier "as" identifier
  #|rule type_alias_targets: _type "as" identifier type_parameters? | _type "=" _type | package_identifier dot_identifier | dot_identifier | package_identifier ".(" (type_alias_target ("," type_alias_target)* ","?)? ")"
  #|rule type_alias_definition: attributes? visibility? "typealias" type_alias_targets
  #|rule struct_definition: attributes? visibility? "struct" identifier type_parameters? "{" (_struct_body_item (_semicolon _struct_body_item)* _semicolon?)? "}" derive_directive?
  #|rule _struct_body_item: prec(1, struct_constructor_declaration) | struct_field_declaration
  #|rule tuple_struct_definition: attributes? visibility? "struct" identifier type_parameters? "(" (_type ("," _type)* ","?)? ")" derive_directive?
  #|rule struct_field_declaration: visibility? mutability? _lowercase_identifier ":" _type
  #|rule struct_constructor_declaration: attributes? "async"? "fn" type_parameters? _lowercase_identifier alias("parameters", _signature_parameters) ("->" return_type | error_annotation)?
  #|rule enum_definition: attributes? visibility? "enum" identifier type_parameters? "{" (enum_constructor (_semicolon enum_constructor)* _semicolon?)? "}" derive_directive?
  #|rule enum_constructor_payload: "(" constructor_parameter ("," constructor_parameter)* ","? ")" | "=" integer_literal
  #|rule enum_constructor: _uppercase_identifier enum_constructor_payload?
  #|rule constructor_parameter: "mut"? _type | "mut"? label ":" _type
  #|rule value_definition: attributes? visibility? "let" _lowercase_identifier (type_annotation? "=" _expression | type_annotation)
  #|rule const_definition: attributes? pub? "const" _uppercase_identifier type_annotation? "=" _expression
  #|rule external_linkage: "extern" string_literal
  #|rule external_source: string_literal | string_literal string_literal | multiline_string_literal
  #|rule function_definition: attributes? visibility? external_linkage? "async"? "fn" type_parameters? function_identifier "!"? alias("parameters", _signature_parameters)? ("->" return_type | error_annotation)? (block_expression | "=" external_source) | attributes? visibility? external_linkage? "async"? "fn" type_parameters? function_identifier "!"? alias("parameters", _signature_parameters)? ("->" return_type | error_annotation)
  #|rule _signature_parameters: "(" (_signature_parameter ("," _signature_parameter)* ","?)? ")"
  #|rule _signature_parameter: parameter | alias("parameter", _signature_type_only_parameter)
  #|rule _signature_type_only_parameter: _type
  #|rule test_definition: attributes? "async"? "test" string_literal? parameters? block_expression
  #|rule trait_definition: attributes? visibility? "trait" identifier super_trait_declaration? ("{" (trait_method_declaration (_semicolon trait_method_declaration)* _semicolon?)? "}")?
  #|rule super_trait_declaration: ":" (qualified_type_identifier ("+" qualified_type_identifier)*)?
  #|rule trait_method_parameter: _type | parameter
  #|rule trait_method_declaration: attributes? "async"? function_identifier "!"? type_parameters? "(" (trait_method_parameter ("," trait_method_parameter)* ","?)? ")" ("->" return_type)? trait_method_default_annotation?
  #|token rule trait_method_default_annotation: "=" "_"
  #|rule trait_alias_target: identifier | identifier "as" identifier
  #|rule trait_alias_targets: _type "as" identifier type_parameters? | _type "=" _type | package_identifier dot_identifier | dot_identifier | package_identifier ".(" (trait_alias_target ("," trait_alias_target)* ","?)? ")"
  #|rule trait_alias_definition: attributes? visibility? "traitalias" trait_alias_targets
  #|rule function_alias_target: _lowercase_identifier | _lowercase_identifier "as" _lowercase_identifier
  #|rule function_alias_targets: _lowercase_identifier "=" qualified_identifier | function_alias_target | package_identifier dot_lowercase_identifier | package_identifier dot_lowercase_identifier "as" _lowercase_identifier | type_name "::" _lowercase_identifier | type_name "::" _lowercase_identifier "as" _lowercase_identifier | "(" function_alias_target ("," function_alias_target)* ","? ")" | package_identifier ".(" (function_alias_target ("," function_alias_target)* ","?)? ")" | type_name "::" "(" (function_alias_target ("," function_alias_target)* ","?)? ")"
  #|rule function_alias_definition: attributes? visibility? "fnalias" function_alias_targets
  #|rule using_target: "type" _type ("as" identifier)? | "trait" qualified_type_identifier ("as" identifier)? | _lowercase_identifier
  #|rule using_targets: package_identifier "{" (using_target ("," using_target)* ","?)? "}" | type_name "::" "{" (using_target ("," using_target)* ","?)? "}"
  #|rule using_declaration: attributes? visibility? "using" using_targets
  #|rule impl_definition: attributes? visibility? "impl" type_parameters? type_name ("for" _type)? "with" function_identifier "!"? parameters ("->" return_type)? (block_expression | "=" external_source)
  #|rule impl_declaration: attributes? visibility? "impl" type_parameters? type_name "for" _type
  #|rule _complex_expression: if_expression | while_expression | loop_expression | match_expression | lexmatch_expression | for_expression | for_in_expression | try_catch_expression | try_expression | arrow_function_expression
  #|rule _arrow_function_body: _expression | raise_expression | assign_expression | unfinished
  #|rule arrow_function_expression: parameters "=>" _arrow_function_body | _lowercase_identifier "=>" _arrow_function_body | "_" "=>" _arrow_function_body
  #|rule pipe_arrow_function_expression: prec(1, (parameters "=>" block_expression | _lowercase_identifier "=>" block_expression | "_" "=>" block_expression))
  #|rule _expression: _complex_expression | _simple_expression
  #|rule _simple_expression: atomic_expression | qualified_identifier | unary_expression | struct_expression | alias("block_expression", nonempty_block_expression) | anonymous_lambda_expression | anonymous_matrix_lambda_expression | constructor_expression | apply_expression | array_access_expression | dot_apply_expression | dot_dot_apply_expression | access_expression | method_expression | unit_expression | tuple_expression | parenthesized_expression | constraint_expression | array_expression | map_expression | as_expression | is_expression | range_expression | binary_expression | lexmatch_test_expression | "_"
  #|rule atomic_expression: string_interpolation | literal
  #|rule string_interpolation: "\"" string_fragment* interpolator (string_fragment | interpolator)* "\""
  #|rule interpolator: "\\{" _expression "}"
  #|rule literal: boolean_literal | double_literal | float_literal | integer_literal | byte_literal | byte_escape_literal | char_literal | string_literal | bytes_literal | regex_literal | multiline_string_literal
  #|token rule boolean_literal: "true" | "false"
  #|token rule integer_literal: /[0-9][0-9_]*(UL|U|L|N)?/ | /0[xX][0-9a-fA-F_]+(UL|U|L|N)?/ | /0[oO][0-7_]+(UL|U|L|N)?/ | /0[bB][01_]+(UL|U|L|N)?/
  #|rule float_literal: _double_literal "F"
  #|rule double_literal: _double_literal
  #|rule byte_literal: "b'" (escape_sequence | /[^']/) "'"
  #|token rule byte_escape_literal: /\\x[0-9a-fA-F]{1,2}/ | /\\o[0-7]{1,3}/
  #|rule char_literal: "'" (escape_sequence | /[^']/) "'"
  #|rule string_literal: "\"" string_fragment* "\""
  #|rule bytes_literal: "b\"" string_fragment* "\""
  #|rule regex_literal: "re\"" string_fragment* "\""
  #|rule string_fragment: unescaped_string_fragment | escape_sequence
  #|token rule unescaped_string_fragment: prec(1, /\\[^ntbrf'"\\{]/) | prec(1, /[^"\\]+/)
  #|token rule escape_sequence: /\\[ntbrf'"\\]/ | /\\o[0-7]{1,3}/ | /\\x[0-9a-fA-F]{1,2}/ | /\\x\{[0-9a-fA-F]+\}/ | /\\u[0-9a-fA-F]{4}/ | /\\u\{[0-9a-fA-F]+\}/
  #|token rule multiline_string_content: /[^\n]*/
  #|rule multiline_string_fragment: "#|" multiline_string_content
  #|rule multiline_interpolation_content: prec(1, /\\[^{]/) | prec(1, /[^\n\\]+/) | interpolator
  #|rule multiline_interpolation_fragment: "$|" multiline_interpolation_content*
  #|rule multiline_string_literal: prec.left(0, (multiline_string_fragment | multiline_interpolation_fragment)+)
  #|rule unary_expression: ("-" | "+" | "!" | "not") _simple_expression
  #|rule binary_expression: prec.left(4, (_simple_expression ("*" | "/" | "%") _simple_expression)) | prec.left(5, (_simple_expression ("+" | "-") _simple_expression)) | prec.left(6, (_simple_expression ("<<" | ">>") _simple_expression)) | prec.left(7, (_simple_expression (">" | ">=" | "<=" | "<" | "==" | "!=") _simple_expression)) | prec.left(8, (_simple_expression "&" _simple_expression)) | prec.left(9, (_simple_expression "^" _simple_expression)) | prec.left(10, (_simple_expression "|" _simple_expression)) | prec.left(12, (_simple_expression "&&" _simple_expression)) | prec.left(13, (_simple_expression "||" _simple_expression)) | prec.left(14, (_simple_expression "|>" (_simple_expression | pipe_arrow_function_expression)))
  #|rule struct_expression: "{" (labeled_expression_pun "," (struct_field_expression ("," struct_field_expression)* ","?)? | labeled_expression ","? | labeled_expression "," struct_field_expression ("," struct_field_expression)* ","?) "}" | type_name "::" "{" (struct_field_expression ("," struct_field_expression)* ","?)? "}" | (type_name "::")? "{" ".." _expression "}" | (type_name "::")? "{" ".." _expression "," (struct_field_expression ("," struct_field_expression)* ","?)? "}"
  #|rule struct_field_expression: labeled_expression | labeled_expression_pun
  #|rule labeled_expression: _lowercase_identifier ":" _expression
  #|rule labeled_expression_pun: _lowercase_identifier
  #|rule block_expression: "{" (_statement_expression (_semicolon _statement_expression)* _semicolon?)? "}"
  #|rule nonempty_block_expression: "{" _statement_expression (_semicolon _statement_expression)* _semicolon? "}"
  #|rule anonymous_lambda_expression: "async"? "fn" "!"? parameters ("->" return_type)? block_expression
  #|rule anonymous_matrix_lambda_expression: "async"? "fn" "!"? "{" (matrix_case_clause (_semicolon matrix_case_clause)* _semicolon?)? "}"
  #|rule pattern_guard: "if" _expression
  #|rule matrix_case_clause: _pattern ("," _pattern)* ","? pattern_guard? "=>" _statement_expression
  #|rule constructor_expression: _uppercase_identifier | package_identifier dot_uppercase_identifier | type_name "::" _uppercase_identifier
  #|rule labelled_argument: _lowercase_identifier "=" _expression
  #|rule forwarded_labelled_argument: label
  #|rule optional_argument: optional_label "=" _expression
  #|rule forwarded_optional_argument: optional_label
  #|rule argument: _expression | labelled_argument | forwarded_labelled_argument | optional_argument | forwarded_optional_argument
  #|token rule apply_operator: "!" | "!!" | "?"
  #|rule arguments: "(" (argument ("," argument)* ","?)? ")"
  #|rule apply_expression: prec.right(0, (_simple_expression apply_operator? arguments))
  #|rule array_access_expression: _simple_expression "[" (_expression | _expression? ":" _expression?) "]"
  #|rule dot_apply_expression: _simple_expression dot_identifier "(" (argument ("," argument)* ","?)? ")"
  #|rule dot_dot_apply_expression: _simple_expression dot_dot_identifier "(" (argument ("," argument)* ","?)? ")"
  #|rule access_expression: _simple_expression accessor
  #|rule accessor: dot_identifier | "." /[0-9]+/
  #|rule method_expression: type_name "::" _lowercase_identifier
  #|token rule unit_expression: "(" ")"
  #|rule tuple_expression: "(" _expression ("," _expression)+ ","? ")" | "(" _expression "," ")"
  #|rule parenthesized_expression: "(" _expression ")"
  #|rule constraint_expression: "(" _expression ":" _type ")"
  #|rule array_expression: "[" (".."? _expression ("," ".."? _expression)* ","?)? "]"
  #|rule map_expression: "{" (map_element_expression ("," map_element_expression)* ","?)? "}"
  #|rule map_element_key: literal | "-" (integer_literal | double_literal | float_literal)
  #|rule map_element_expression: map_element_key ":" _expression
  #|rule as_expression: _simple_expression "as" type_name
  #|rule is_expression: _simple_expression "is" (range_pattern | _simple_pattern)
  #|rule match_expression: "match" _simple_expression "{" (case_clause (_semicolon case_clause)* _semicolon?)? "}"
  #|rule lexmatch_expression: "lexmatch" _simple_expression (("using" | "with") "longest")? "{" (lexmatch_case_clause (_semicolon lexmatch_case_clause)* _semicolon?)? "}"
  #|rule lexmatch_test_expression: prec.right(-1, (_simple_expression "lexmatch?" lexmatch_pattern))
  #|rule case_clause: _pattern pattern_guard? "=>" _statement_expression
  #|rule lexmatch_case_clause: lexmatch_pattern pattern_guard? "=>" _statement_expression
  #|rule break_expression: "break" label? (_expression ("," (_expression | "$..."))*)?
  #|rule continue_expression: "continue" label? (_expression ("," (_expression | "$..."))*)?
  #|rule try_catch_expression: "try"? _simple_expression try_catch_clause try_else_clause?
  #|rule try_expression: "try" ("!" | "?") _simple_expression
  #|rule try_catch_clause: "catch" "!"? "{" (case_clause (_semicolon case_clause)* _semicolon?)? "}" noraise_clause?
  #|rule noraise_clause: "noraise" "{" (case_clause (_semicolon case_clause)* _semicolon?)? "}"
  #|rule try_else_clause: "else" "{" (case_clause (_semicolon case_clause)* _semicolon?)? "}"
  #|rule if_expression: "if" _simple_expression block_expression else_clause?
  #|rule else_clause: "else" (block_expression | if_expression)
  #|rule nobreak_clause: "nobreak" block_expression
  #|rule _statement_expression: struct_definition | enum_definition | type_definition | let_expression | letrec_expression | and_expression | let_mut_expression | guard_expression | guard_let_expression | assign_expression | named_lambda_expression | named_matrix_expression | break_expression | continue_expression | return_expression | raise_expression | defer_expression | _expression | unfinished
  #|rule defer_expression: "defer" _expression
  #|token rule unfinished: "..."
  #|rule let_expression: "let" _pattern type_annotation? "=" _expression
  #|rule letrec_expression: "letrec" _pattern type_annotation? "=" _expression
  #|rule and_expression: "and" _pattern type_annotation? "=" _expression
  #|rule let_mut_expression: "let" "mut" _lowercase_identifier type_annotation? "=" _expression
  #|rule guard_expression: "guard" _simple_expression guard_else_expression?
  #|rule guard_else_expression: "else" block_expression
  #|rule guard_let_expression: "guard" "let" _pattern "=" _simple_expression guard_let_else_expression?
  #|rule guard_let_else_expression: "else" "{" (case_clause (_semicolon case_clause)* _semicolon?)? "}"
  #|token rule assign_operator: "=" | "+=" | "-=" | "*=" | "/=" | "%="
  #|rule assign_expression: left_value assign_operator _expression
  #|rule left_value: qualified_identifier | access_expression | array_access_expression
  #|rule named_lambda_expression: "async"? "fn" _lowercase_identifier "!"? parameters ("->" return_type | error_annotation)? block_expression
  #|rule named_matrix_expression: "async"? "fn" _lowercase_identifier "!"? "{" (matrix_case_clause (_semicolon matrix_case_clause)* _semicolon?)? "}"
  #|rule loop_label: label ":"
  #|rule while_expression: loop_label? "while" _simple_expression block_expression (else_clause | nobreak_clause)?
  #|rule loop_expression: loop_label? "loop" _expression ("," (_expression | "$..."))* "{" (matrix_case_clause (_semicolon matrix_case_clause)* _semicolon?)? "}"
  #|rule for_binder: _lowercase_identifier "=" _expression
  #|rule for_expression: loop_label? "for" (for_binder ("," (for_binder | "$..."))*)? _semicolon _expression? _semicolon (for_binder ("," (for_binder | "$..."))*)? block_expression (else_clause | nobreak_clause)? | loop_label? "for" (for_binder ("," (for_binder | "$..."))*)? block_expression (else_clause | nobreak_clause)?
  #|rule for_in_expression: loop_label? "for" (_lowercase_identifier ("," (_lowercase_identifier | "$..."))*)? "in" _expression (_semicolon (for_binder ("," (for_binder | "$..."))*)?)? block_expression (else_clause | nobreak_clause)?
  #|rule range_expression: prec.left(0, (_simple_expression ("..<" | "..=" | "..<=" | "..>" | "..>=" | ">..") _simple_expression))
  #|rule return_expression: "return" _expression?
  #|rule raise_expression: "raise" _expression
  #|rule _pattern: _simple_pattern | range_pattern | as_pattern | or_pattern
  #|rule as_pattern: _pattern "as" _lowercase_identifier
  #|rule or_pattern: prec.right(0, (_pattern "|" _pattern))
  #|rule _simple_pattern: ".." | parenthesized_pattern | atomic_pattern | _lowercase_identifier | constructor_pattern | tuple_pattern | constraint_pattern | array_pattern | struct_pattern | map_pattern | empty_struct_or_map_pattern | any_pattern
  #|rule parenthesized_pattern: "(" _pattern ")"
  #|rule atomic_pattern: literal | "-" integer_literal | "-" double_literal | "-" float_literal
  #|token rule any_pattern: "_"
  #|rule constructor_pattern_argument: _lowercase_identifier "=" _pattern | label | _pattern
  #|rule constructor_pattern: prec.right(0, (constructor_expression ("(" (constructor_pattern_argument ("," constructor_pattern_argument)* ","?)? ")")?))
  #|rule tuple_pattern: "(" _pattern "," _pattern ("," _pattern)* ","? ")"
  #|rule constraint_pattern: "(" _pattern ":" _type ")"
  #|rule array_pattern: "[" (array_sub_pattern ("," array_sub_pattern)* ","?)? "]"
  #|rule bitstring_pattern: /[ui]\d+(le|be)?/ "(" _pattern ")"
  #|rule lexmatch_pattern: lexmatch_or_pattern | lexmatch_as_pattern | lexmatch_range_pattern | lexmatch_sequence_pattern | lexmatch_simple_pattern
  #|rule lexmatch_sequence_pattern: prec.right(1, (lexmatch_simple_pattern lexmatch_simple_pattern+))
  #|rule lexmatch_or_pattern: prec.right(0, (lexmatch_pattern "|" lexmatch_pattern))
  #|rule lexmatch_as_pattern: prec.right(0, (lexmatch_pattern "as" _lowercase_identifier))
  #|rule lexmatch_range_pattern: prec.left(2, (lexmatch_simple_pattern ("..<" | "..=") lexmatch_simple_pattern))
  #|rule lexmatch_simple_pattern: lexmatch_parenthesized_pattern | atomic_pattern | _lowercase_identifier | constructor_pattern | lexmatch_tuple_pattern | constraint_pattern | array_pattern | any_pattern
  #|rule lexmatch_tuple_pattern: "(" lexmatch_pattern "," lexmatch_pattern ("," lexmatch_pattern)* ","? ")"
  #|rule lexmatch_parenthesized_pattern: "(" lexmatch_pattern ")"
  #|rule array_sub_pattern: ".." qualified_identifier | ".." constructor_expression | ".." string_literal | ".." bytes_literal | bitstring_pattern | _pattern
  #|rule struct_pattern: "{" struct_field_pattern ("," struct_field_pattern)* ","? ".."? "}"
  #|rule struct_field_pattern: labeled_pattern | labeled_pattern_pun
  #|rule labeled_pattern: _lowercase_identifier ":" _pattern
  #|rule labeled_pattern_pun: _lowercase_identifier
  #|rule map_pattern: "{" map_element_pattern ("," map_element_pattern)* ","? ".."? "}"
  #|rule map_element_pattern: map_element_key "?"? ":" _pattern
  #|token rule empty_struct_or_map_pattern: "{" "}"
  #|rule range_pattern: _simple_pattern ("..<" | "..=") _simple_pattern
  #|rule _type: _simple_type | function_type
  #|rule tuple_type: "(" _type ("," _type)+ ","? ")"
  #|rule function_type: "async"? "(" (_type ("," _type)* ","?)? ")" "->" return_type
  #|rule _simple_type: qualified_type_identifier | apply_type | tuple_type | trait_object_type | parenthesized_type | option_type | "_"
  #|rule parenthesized_type: "(" _type ")"
  #|rule apply_type: qualified_type_identifier type_arguments
  #|rule option_type: prec.left(1, (_simple_type "?"))
  #|rule trait_object_type: "&" qualified_type_identifier
  #|rule type_arguments: "[" _type ("," _type)* ","? "]"
  #|rule type_parameters: "[" type_identifier ("," type_identifier)* ","? "]"
  #|rule type_annotation: ":" _type
  #|rule error_annotation: "raise" | "noraise" | "raise" _type | "raise" "?"
  #|rule return_type: _type | _simple_type "!" | _simple_type "!" _type | _simple_type "?" _type | _simple_type error_annotation
  #|rule label: _lowercase_identifier "~"
  #|rule optional_label: _lowercase_identifier "?"
  #|rule positional_parameter: (_lowercase_identifier | "_") type_annotation?
  #|rule labelled_parameter: label type_annotation?
  #|rule optional_parameter: optional_label type_annotation?
  #|rule optional_parameter_with_default: (label | optional_label) type_annotation? "=" _expression
  #|rule parameter: positional_parameter | labelled_parameter | optional_parameter | optional_parameter_with_default
  #|rule parameters: "(" (parameter ("," parameter)* ","?)? ")"
  #|token rule any: "_"
  #|token rule mutability: "mut"
  #|token rule pub: "pub"
  #|token rule uppercase_identifier: /[\p{Uppercase_Letter}][_\p{XID_Continue}]*/
  #|rule _uppercase_identifier: uppercase_identifier
  #|token rule lowercase_identifier: /[_[\p{XID_Start}--\p{Uppercase_Letter}]][_\p{XID_Continue}]*/
  #|rule _lowercase_identifier: lowercase_identifier
  #|rule identifier: _uppercase_identifier | _lowercase_identifier
  #|token rule package_statement_identifier: /[_a-z][_a-zA-Z0-9-]*/
  #|rule _semicolon: _automatic_semicolon | ";"
  #|rule dot_identifier: dot_lowercase_identifier | dot_uppercase_identifier
  #|token rule dot_lowercase_identifier: /\.[_[\p{XID_Start}--\p{Uppercase_Letter}]][_\p{XID_Continue}]*/
  #|token rule dot_uppercase_identifier: /\.[\p{Uppercase_Letter}][_\p{XID_Continue}]*/
  #|token rule dot_dot_identifier: ".." /[_\p{XID_Start}][_\p{XID_Continue}]*/
  #|token rule package_identifier: /@[_\p{XID_Start}\/][_\p{XID_Continue}\/]*/
  #|rule qualified_identifier: _lowercase_identifier | package_identifier dot_lowercase_identifier
  #|rule qualified_type_identifier: identifier | package_identifier dot_identifier
  #|rule type_name: qualified_type_identifier | "&" qualified_type_identifier
  #|rule function_identifier: _lowercase_identifier | type_name "::" _lowercase_identifier
  #|rule type_identifier: identifier | identifier ":" constraints
  #|rule constraints: constraint ("+" constraint)* "+"?
  #|rule constraint: qualified_type_identifier
  #|token rule comment: /\/\/.*/
  #|token rule block_comment: "/*" /[^*]*\*+([^/*][^*]*\*+)*/ "/"
  #|rule attribute_properties: "(" (attribute_property ("," attribute_property)* ","?)? ")"
  #|rule attribute_property: _lowercase_identifier "=" attribute_expression | attribute_expression
  #|rule attribute_expression: _lowercase_identifier | _uppercase_identifier | _lowercase_identifier dot_lowercase_identifier | _lowercase_identifier attribute_properties | _lowercase_identifier dot_lowercase_identifier attribute_properties | _uppercase_identifier attribute_properties | string_literal
  #|rule attribute: "#" attribute_expression
  #|rule attributes: attribute+
