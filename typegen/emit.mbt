///|
// TypeSchema → MoonBit 类型定义代码生成
//
// 设计原则：
// - 所有命名规则（Struct / Token / Alias）生成带 _node 字段的 struct，统一访问模式
// - Enum 规则生成 MoonBit enum，每个变体携带 @runtime.CstNode（避免嵌套 dispatch 问题）
// - 访问器函数在 emit_accessors.mbt 中生成

///|
/// PascalCase 转换后与 MoonBit 内置构造器冲突的名称（加 _ 后缀）
let moonbit_ctor_conflicts : Array[String] = [
  "True", "False", "Some", "None", "Ok", "Err", "Unit",
]

///|
/// 在 snake_case 字段名中不能直接用作 MoonBit 标识符的关键字
let moonbit_field_keywords : Array[String] = [
  "type", "fn", "let", "mut", "pub", "priv", "struct", "enum", "return", "if", "else",
  "match", "for", "while", "loop", "break", "continue", "true", "false", "as", "in",
  "is", "raise", "try", "catch", "with", "guard", "test", "derive", "and", "or",
  "not", "do", "end", "import", "extern",
]

///|
/// snake_case 规则名 → PascalCase 类型名
/// 例："binary_expr" → "BinaryExpr"、"json_object" → "JsonObject"
pub fn rule_name_to_type_name(name : String) -> String {
  let result = StringBuilder::new()
  let n = name.length()
  let mut seg_start = 0
  let mut i = 0
  while i <= n {
    if i == n || name[i] == '_' {
      if i > seg_start {
        let first_code = name[seg_start].to_int()
        // 小写字母 a-z (97-122) → 大写
        let upper_code = if first_code >= 97 && first_code <= 122 {
          first_code - 32
        } else {
          first_code
        }
        result.write_char(upper_code.to_char().unwrap())
        let mut j = seg_start + 1
        while j < i {
          result.write_char(name[j].to_int().to_char().unwrap())
          j = j + 1
        }
      }
      seg_start = i + 1
    }
    i = i + 1
  }
  let type_name = result.to_string()
  // 避免与内置构造器或 Bool 字面量冲突
  let mut conflict = false
  for kw in moonbit_ctor_conflicts {
    if type_name == kw {
      conflict = true
      break
    }
  }
  if conflict {
    type_name + "_"
  } else {
    type_name
  }
}

///|
/// 字段名安全化：与 MoonBit 关键字冲突时加 _ 后缀
pub fn escape_field_name(name : String) -> String {
  let mut is_kw = false
  for kw in moonbit_field_keywords {
    if name == kw {
      is_kw = true
      break
    }
  }
  if is_kw {
    name + "_"
  } else {
    name
  }
}

///|
/// 生成 Struct / Token / Alias 规则的类型定义
/// 统一使用含 _node 字段的 struct 包装 @runtime.CstNode
fn emit_node_struct(
  buf : StringBuilder,
  type_name : String,
  doc : String?,
) -> Unit {
  buf.write_string("///|\n")
  match doc {
    Some(d) => {
      buf.write_string("/// ")
      buf.write_string(d)
      buf.write_string("\n")
    }
    None => ()
  }
  buf.write_string("pub(all) struct ")
  buf.write_string(type_name)
  buf.write_string(" {\n  _node : @runtime.CstNode\n}\n")
}

///|
/// 生成 Enum 规则的类型定义
/// 每个变体统一携带 @runtime.CstNode，避免嵌套 dispatch 问题
fn emit_enum_type(
  buf : StringBuilder,
  type_name : String,
  variants : Array[(String, VariantPayload)],
) -> Unit {
  buf.write_string("///|\n")
  buf.write_string("pub(all) enum ")
  buf.write_string(type_name)
  buf.write_string(" {\n")
  for i in 0..<variants.length() {
    let (vname, _payload) = variants[i]
    buf.write_string("  ")
    buf.write_string(rule_name_to_type_name(vname))
    // 所有变体统一携带 @runtime.CstNode（lazy：需要具体类型时再用对应 from_node 包装）
    buf.write_string("(@runtime.CstNode)\n")
  }
  buf.write_string("}\n")
}

///|
/// 将 TypeSchema 的全部规则生成 MoonBit 类型定义字符串（不含访问器）
pub fn emit_type_defs(schema : TypeSchema) -> String {
  let buf = StringBuilder::new()
  for name, shape in schema.shapes {
    let type_name = rule_name_to_type_name(name)
    buf.write_string("\n")
    match shape {
      NodeShape::Struct(_) => emit_node_struct(buf, type_name, None)
      NodeShape::Token => emit_node_struct(buf, type_name, Some("Token rule."))
      NodeShape::Alias(target) =>
        emit_node_struct(
          buf,
          type_name,
          Some("Alias of " + rule_name_to_type_name(target) + "."),
        )
      NodeShape::Enum(variants) => emit_enum_type(buf, type_name, variants)
    }
  }
  buf.to_string()
}
