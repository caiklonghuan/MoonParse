; Comments
(comment) @fold.comment
#match? @fold.comment "^/\\*"

; Declarations
(function_decl) @fold.region
(impl_method_decl) @fold.region
(struct_decl) @fold.region
(enum_decl) @fold.region
(trait_decl) @fold.region
(impl_decl) @fold.region
(suberror_decl) @fold.region

; Control-flow and expression regions
(if_statement) @fold.region
(while_statement) @fold.region
(loop_statement) @fold.region
(for_in_statement) @fold.region
(for_c_statement) @fold.region
(match_expression) @fold.region
(match_case) @fold.region
(try_expression) @fold.region
(catch_clause) @fold.region

; Generic nested blocks, including function bodies and match case bodies
(block) @fold.region
