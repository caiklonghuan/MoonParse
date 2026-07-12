///|
/// JavaScript builds keep the command surface linkable, but do not expose
/// host-filesystem pack operations. Native and WASM hosts provide cmd_pack.mbt.
pub fn cmd_pack(_command : PackCommand) -> Int {
  ignore(@treesitterinterop.sha256_bytes_hex(b""))
  print_err("pack commands require the Native or WASM host runtime")
  2
}
