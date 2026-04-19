///|
// 访问器函数代码生成
//
// 生成规则：
// - 每种类型生成 node(self) -> @runtime.CstNode 和 of(node) -> TypeName
// - Struct 规则额外生成各字段的具名访问器（One/Optional → CstNode?, Many → Array[CstNode]）
// - Enum 规则生成 from_node(node, rule_name) -> TypeName? 和合并的 node(self) getter

///|
/// 生成 struct 类型的 `node()` 获取器和 `of()` 构造器
fn emit_struct_base_accessors(buf : StringBuilder, type_name : String) -> Unit {
  // node()
  buf.write_string("\n///|\npub fn ")
  buf.write_string(type_name)
  buf.write_string("::node(self : ")
  buf.write_string(type_name)
  buf.write_string(") -> @runtime.CstNode {\n  self._node\n}\n")
  // of()
  buf.write_string("\n///|\npub fn ")
  buf.write_string(type_name)
  buf.write_string("::of(node : @runtime.CstNode) -> ")
  buf.write_string(type_name)
  buf.write_string(" {\n  { _node: node }\n}\n")
}

///|
/// 生成 Struct 规则每个字段的访问器
/// - One / Optional → `FieldName(self) -> @runtime.CstNode?`（均返回 Optional，应对错误恢复）
/// - Many           → `FieldName(self) -> Array[@runtime.CstNode]`
fn emit_field_accessors(
  buf : StringBuilder,
  type_name : String,
  fields : Array[(String, FieldShape)],
) -> Unit {
  for i in 0..<fields.length() {
    let (fname, shape) = fields[i]
    let safe_fname = escape_field_name(fname)
    buf.write_string("\n///|\n")
    buf.write_string("pub fn ")
    buf.write_string(type_name)
    buf.write_string("::")
    buf.write_string(safe_fname)
    buf.write_string("(self : ")
    buf.write_string(type_name)
    match shape {
      FieldShape::Many(_) => {
        buf.write_string(") -> Array[@runtime.CstNode] {\n")
        buf.write_string("  let result : Array[@runtime.CstNode] = []\n")
        buf.write_string("  for idx in 0..<self._node.field_names.length() {\n")
        buf.write_string("    if self._node.field_names[idx] == Some(\"")
        buf.write_string(fname)
        buf.write_string("\") {\n")
        buf.write_string("      result.push(self._node.children[idx])\n")
        buf.write_string("    }\n  }\n  result\n}\n")
      }
      _ => {
        buf.write_string(") -> @runtime.CstNode? {\n")
        buf.write_string("  for idx in 0..<self._node.field_names.length() {\n")
        buf.write_string("    if self._node.field_names[idx] == Some(\"")
        buf.write_string(fname)
        buf.write_string("\") {\n")
        buf.write_string("      return Some(self._node.children[idx])\n")
        buf.write_string("    }\n  }\n  None\n}\n")
      }
    }
  }
}

///|
/// 生成 Enum 的 `from_node` 和 `node` 访问器
///
/// `from_node(node, rule_name)` 按规则名（字符串）分派到对应变体；
/// rule_name 可由 `table.symbol_metadata[node.symbol].name` 获取。
fn emit_enum_accessors(
  buf : StringBuilder,
  type_name : String,
  variants : Array[(String, VariantPayload)],
) -> Unit {
  // from_node
  buf.write_string("\n///|\n")
  buf.write_string("/// 将 CstNode 按规则名转换为 ")
  buf.write_string(type_name)
  buf.write_string("。\n")
  buf.write_string(
    "/// rule_name 可由 `table.symbol_metadata[node.symbol].name` 获取。\n",
  )
  buf.write_string("pub fn ")
  buf.write_string(type_name)
  buf.write_string(
    "::from_node(node : @runtime.CstNode, rule_name : String) -> ",
  )
  buf.write_string(type_name)
  buf.write_string("? {\n  match rule_name {\n")
  for i in 0..<variants.length() {
    let (vname, _) = variants[i]
    buf.write_string("    \"")
    buf.write_string(vname)
    buf.write_string("\" => Some(")
    buf.write_string(type_name)
    buf.write_string("::")
    buf.write_string(rule_name_to_type_name(vname))
    buf.write_string("(node))\n")
  }
  buf.write_string("    _ => None\n  }\n}\n")
  // node() — 利用 | 模式合并所有变体
  buf.write_string("\n///|\npub fn ")
  buf.write_string(type_name)
  buf.write_string("::node(self : ")
  buf.write_string(type_name)
  buf.write_string(") -> @runtime.CstNode {\n  match self {\n")
  // 若只有一个变体，直接生成单行匹配；多个变体用 | 连接
  if variants.length() == 0 {
    buf.write_string("  }\n}\n")
    return
  }
  // 先拼出所有 CtorName(n) 用 | 连接，最后写 => n
  let mut first = true
  for i in 0..<variants.length() {
    let (vname, _) = variants[i]
    let ctor = rule_name_to_type_name(vname)
    if first {
      buf.write_string("    ")
      first = false
    } else {
      buf.write_string(" | ")
    }
    buf.write_string(ctor)
    buf.write_string("(n)")
  }
  buf.write_string(" => n\n  }\n}\n")
}

///|
/// 从 TypeSchema 生成全部访问器函数，返回完整 MoonBit 源码片段
pub fn emit_accessors(schema : TypeSchema) -> String {
  let buf = StringBuilder::new()
  for name, shape in schema.shapes {
    let type_name = rule_name_to_type_name(name)
    match shape {
      NodeShape::Struct(fields) => {
        emit_struct_base_accessors(buf, type_name)
        emit_field_accessors(buf, type_name, fields)
      }
      NodeShape::Token | NodeShape::Alias(_) =>
        emit_struct_base_accessors(buf, type_name)
      NodeShape::Enum(variants) => emit_enum_accessors(buf, type_name, variants)
    }
  }
  buf.to_string()
}
