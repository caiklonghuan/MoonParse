///|
/// Canonical LR(1), witnesses, and safe table compression belong here.
pub(all) struct AutomataModelLink {
  format : @model.PackFormatVersion
  grammar : @grammar.GrammarModelLink
  regex : @regex.RegexModelLink
}
