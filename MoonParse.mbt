// Main package file for your library code.
// Put public APIs and shared helpers here.
// Keep blocks small and focused for easy refactors.

// import "grammar" { parse_grammar }
// import "generator" { generate_parser }
// import "runtime" { ParseTree, parse }
// import "wasm" { WasmParser, create_parser, parse_code }

///|
/// 公共解析器类型
// pub type Parser = WasmParser

///|
/// 生成解析器
pub fn generate(grammar : String) -> String {
  // let g = parse_grammar(grammar)
  // let code = generate_parser(g)
  // TODO: 编译生成的代码为 WASM
  // create_parser()
  "TODO: implement parser generation from: " + grammar
}

///|
/// 解析源代码
pub fn parse(parser : String, source : String) -> String {
  // parse_code(parser, source)
  "TODO: implement parsing"
}
