; Scopes
(function_decl) @scope.function
(impl_method_decl) @scope.function
(trait_method_decl) @scope.function
(fn_expression) @scope.function
(block) @scope.block
(struct_decl) @scope.class
(enum_decl) @scope.class
(trait_decl) @scope.class
(impl_decl) @scope.class
(while_statement) @scope.loop
(loop_statement) @scope.loop
(for_in_statement) @scope.loop
(for_c_statement) @scope.loop
(match_case) @scope.block
(catch_clause) @scope.block

; Top-level and type declarations
(function_decl
  (fn_name (identifier) @definition.function)) @symbol.function

(impl_method_decl
  (identifier) @definition.method) @symbol.method

(trait_method_decl
  (identifier) @definition.method) @symbol.method

(const_decl
  (identifier) @definition.constant) @symbol.constant

(type_alias_decl
  (identifier) @definition.type) @symbol.type

(struct_decl
  (identifier) @definition.struct) @symbol.struct

(enum_decl
  (identifier) @definition.enum) @symbol.enum

(trait_decl
  (identifier) @definition.trait) @symbol.trait

(suberror_decl
  (identifier) @definition.enum) @symbol.enum

; Type parameters
(constrained_param
  (identifier) @definition.type_parameter) @symbol.type_parameter

(type_params
  (identifier) @definition.type_parameter) @symbol.type_parameter

; Members
(field_decl
  (identifier) @definition.field) @symbol.field

(enum_payload_item
  (identifier) @definition.field) @symbol.field

(enum_case
  (identifier) @definition.enum_member) @symbol.enum_member

; Parameters and local binders
(parameter
  (identifier) @definition.parameter) @symbol.parameter

(arrow_expression
  (identifier) @definition.parameter) @symbol.parameter

(for_init_item
  (identifier) @definition.variable) @symbol.variable

(let_decl
  (pattern
    (or_pattern
      (as_pattern
        (single_pattern
          (qualified_identifier
            (identifier) @definition.variable)))))) @symbol.variable

(let_statement
  (pattern
    (or_pattern
      (as_pattern
        (single_pattern
          (qualified_identifier
            (identifier) @definition.variable)))))) @symbol.variable

(for_in_statement
  (pattern
    (or_pattern
      (as_pattern
        (single_pattern
          (qualified_identifier
            (identifier) @definition.variable)))))) @symbol.variable

(match_case
  (pattern
    (or_pattern
      (as_pattern
        (single_pattern
          (qualified_identifier
            (identifier) @definition.variable)))))) @symbol.variable

(catch_binding
  (pattern
    (or_pattern
      (as_pattern
        (single_pattern
          (qualified_identifier
            (identifier) @definition.variable)))))) @symbol.variable

(as_pattern
  (identifier) @definition.variable) @symbol.variable

(pattern_item
  (identifier) @definition.variable
  "~") @symbol.variable

(pattern_item
  ".."
  (identifier) @definition.variable) @symbol.variable

; Soft references for calls, qualified names, members, and type contexts.
(postfix_expression
  (primary_expression
    (qualified_identifier
      (identifier) @reference.soft.variable))
  (postfix_suffix))

(qualified_identifier
  (identifier) @reference.soft.variable
  (identifier) @reference.soft.variable)

(simple_type
  (qualified_identifier
    (identifier) @reference.soft.type))

(trait_bound_list
  (qualified_identifier
    (identifier) @reference.soft.trait))

(derive_clause
  (qualified_identifier
    (identifier) @reference.soft.type))

(impl_decl
  (qualified_identifier
    (identifier) @reference.soft.type))

(record_field
  (identifier) @reference.soft.field)

(argument
  (identifier) @reference.soft.field)

(postfix_suffix
  "."
  (identifier) @reference.soft.field)

(single_pattern
  (qualified_identifier
    (identifier) @reference.soft.enum_member)
  (pattern_suffix))

(primary_expression
  (qualified_identifier
    (identifier) @reference.soft.enum_member))
#match? @reference.soft.enum_member "^[A-Z]"

; Strict local variable reads. Soft captures above can merge with this capture
; and suppress unresolved diagnostics for calls, constructors, and external names.
(primary_expression
  (qualified_identifier
    (identifier) @reference.variable))
