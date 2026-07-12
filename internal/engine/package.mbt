///|
/// Lexer, scanner VM, LR/GLR parsing, recovery, and reuse belong here.
pub(all) struct EngineModelLink {
  format : @model.PackFormatVersion
  syntax : @syntax.SyntaxModelLink
}
