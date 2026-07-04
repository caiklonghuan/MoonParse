; Export candidates are normalized by MoonLanguage.modules(), which checks the
; declaration prefix for MoonBit's pub/pub(...) visibility. This workaround is
; needed because recovered visibility tokens are not exposed as named CST
; children by the current grammar runtime.
(function_decl
  (fn_name (identifier) @module.export.candidate))

(const_decl
  (identifier) @module.export.candidate)

(type_alias_decl
  (identifier) @module.export.candidate)

(struct_decl
  (identifier) @module.export.candidate)

(enum_decl
  (identifier) @module.export.candidate)

(trait_decl
  (identifier) @module.export.candidate)

(suberror_decl
  (identifier) @module.export.candidate)

; The JS API splits these internal whole-expression captures into the public
; module.reference and module.member.* captures with one shared match_id.
(postfix_expression) @module.qualified.value

(simple_type) @module.qualified.type
