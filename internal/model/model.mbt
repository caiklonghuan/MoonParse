///|
/// `.mpack` format identity carried by model and codec code only.
pub(all) struct PackFormatVersion {
  major : Int
  minor : Int
  runtime_abi : Int
}

///|
/// Section kinds reserved by the frozen v1 `.mpack` registry.
pub(all) enum PackSectionKind {
  Manifest
  Strings
  SymbolsFields
  Lexer
  Parser
  Recovery
  QueryIndex
  QueryBytecode
  ScannerBytecode
  DebugMap
}

///|
/// Hard resource ceilings checked before any pack-model allocation.
pub(all) struct PackResourceLimits {
  pack_bytes : Int
  sections : Int
  strings : Int
  symbols : Int
  parser_states : Int
  productions : Int
  query_programs : Int
  query_bytecode_bytes : Int
  scanner_states : Int
}
