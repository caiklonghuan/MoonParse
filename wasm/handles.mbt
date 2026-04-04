///|
// 句柄注册表
//
// 职责：在 JS 可操作的整数 ID 与 WASM GC 对象之间建立映射。
// MoonBit GC 对象无法被 JS 直接引用，因此所有跨边界的有状态对象
// 都放入全局注册表，JS 只持有整数句柄（>= 1 有效，-1 表示失败）。
//
// 所有类型均为 priv，仅在 wasm/ 包内使用。

///|
/// 泛型注册表：整数 ID ↔ T 对象
priv struct Registry[T] {
  /// 下一个可用 ID（从 1 开始，0 保留为"无效 ID"）
  mut next_id : Int
  /// ID → 对象 的映射表
  entries : Map[Int, T]
}

///|
fn[T] Registry::new() -> Registry[T] {
  { next_id: 1, entries: Map::new() }
}

///|
/// 注册一个对象，返回分配的整数 ID
fn[T] Registry::register(self : Registry[T], val : T) -> Int {
  let id = self.next_id
  self.next_id = self.next_id + 1
  self.entries[id] = val
  id
}

///|
/// 按 ID 查找对象；未找到返回 None
fn[T] Registry::get(self : Registry[T], id : Int) -> T? {
  self.entries.get(id)
}

///|
/// 按 ID 删除对象；删除成功返回 true，ID 不存在返回 false
fn[T] Registry::remove(self : Registry[T], id : Int) -> Bool {
  match self.entries.get(id) {
    Some(_) => {
      self.entries.remove(id)
      true
    }
    None => false
  }
}

///|
// 条目类型

///|
/// 解析器条目：已编译的解析表 + 原始 DSL（调试用）
priv struct ParserEntry {
  table : @tablegen.ParseTable
  dsl : String
}

///|
/// 语法树条目：CST 根节点 + 对应的原始输入（node_text 查询用）
priv struct TreeEntry {
  root : @runtime.CstNode
  input : String
}

///|
// 全局注册表实例（模块加载时初始化）

///|
let parser_registry : Registry[ParserEntry] = Registry::new()

///|
let tree_registry : Registry[TreeEntry] = Registry::new()
