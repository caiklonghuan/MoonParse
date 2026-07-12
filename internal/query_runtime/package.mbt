///|
/// Full and incremental Query execution belong here.
pub(all) struct QueryRuntimeModelLink {
  format : @model.PackFormatVersion
  query_ir : @query_ir.QueryIrModelLink
  syntax : @syntax.SyntaxModelLink
}
