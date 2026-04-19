///|
// scripts/exit_native.mbt — native/llvm 退出实现

///|
extern "c" fn c_exit(code : Int) -> Unit = "exit"

///|
fn script_exit_impl(code : Int) -> Unit {
  c_exit(code)
}
