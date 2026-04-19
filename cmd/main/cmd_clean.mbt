///|
// clean 命令处理器
// 删除构建产物目录：generated/、build/、dist/

///|
/// clean 命令主体。
/// 删除项目中所有标准构建输出目录，确保干净的重构建环境。
/// 返回退出码：0=成功，2=部分删除失败（错误信息已输出到 stderr）。
pub fn cmd_clean(_args : CleanArgs) -> Int {
  let targets = ["generated", "build", "dist"]
  let mut had_error = false
  for dir in targets {
    match remove_dir_all(dir) {
      Ok(_) => print_info("removed: " + dir + "/")
      Err(msg) => {
        // 目录不存在时 rm -rf 也返回 0，此处有错误说明是真实的失败
        print_err("warning: " + msg)
        had_error = true
      }
    }
  }
  if had_error {
    2
  } else {
    0
  }
}
