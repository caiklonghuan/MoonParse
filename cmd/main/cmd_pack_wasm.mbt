///|
pub fn cmd_pack(command : PackCommand) -> Int {
  let format = match command {
    Init(args) => args.format
    Check(args) => args.format
    Test(args) => args.format
    Build(args) => args.format
    ExportTreeSitter(args) => {
      let _ : @treesitterinterop.TreeSitterExportOptions = {
        grammar_name: None,
      }
      args.format
    }
    ImportTreeSitter(args) => {
      let _ : @treesitterinterop.TreeSitterImportOptions = {
        output_id: None,
        output_name: None,
        package_version: None,
        extensions: [],
        allow_tags_bindings_candidate: false,
      }
      args.format
    }
  }
  match format {
    Human =>
      print_err(
        "error[CLI208]: Pack CLI filesystem commands are unavailable on WASM",
      )
    Json =>
      println(
        "{\"command\":\"pack\",\"status\":\"error\",\"diagnostics\":[{\"code\":\"CLI208\",\"severity\":\"error\",\"message\":\"Pack CLI filesystem commands are unavailable on WASM\",\"path\":\"\",\"line\":0,\"column\":0,\"hint\":null}],\"summary\":{},\"artifacts\":[]}",
      )
  }
  2
}
