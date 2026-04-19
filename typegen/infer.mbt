///|
// Pattern → NodeShape 推导
// 从 Grammar 直接推导，不依赖 normalize/tablegen 中间产物。

///|
/// 检查规则是否应跳过（不生成类型）：
/// - 带 @inline 或 @hide 属性
/// - 名称以 _ 开头（匿名/内部规则）
/// - 模板规则（params 非空）
fn should_skip(rule : @grammar.Rule) -> Bool {
  if rule.name.has_prefix("_") {
    return true
  }
  if rule.params.length() > 0 {
    return true
  }
  for attr in rule.attributes {
    match attr {
      @grammar.RuleAttribute::Inline | @grammar.RuleAttribute::Hide =>
        return true
      _ => ()
    }
  }
  false
}

///|
/// 从 Pattern 提取 NodeRef（单节点引用）
/// 用于 FieldShape::One / Optional / Many 的内层引用
fn node_ref_of(p : @grammar.Pattern) -> NodeRef {
  match p {
    RuleRef(name) => NodeRef::Named(name)
    Literal(_) | Regex(_) | AnyChar => NodeRef::Token
    // 透明包装，继续向内
    Optional(inner) | Repeat(inner) | Plus(inner) => node_ref_of(inner)
    RepeatRange(inner, _, _) => node_ref_of(inner)
    Prec(_, _, inner) | Tagged(_, inner) | Field(_, inner) | Alias(_, inner) =>
      node_ref_of(inner)
    // 复杂嵌套（Seq/Choice）→ 匿名
    _ => NodeRef::Anonymous
  }
}

///|
/// 从 Pattern 推导字段形状（考虑 Optional / Repeat / Plus 的基数）
fn field_shape_of(p : @grammar.Pattern) -> FieldShape {
  match p {
    Optional(inner) => FieldShape::Optional(node_ref_of(inner))
    Repeat(inner) | Plus(inner) => FieldShape::Many(node_ref_of(inner))
    RepeatRange(inner, _, _) => FieldShape::Many(node_ref_of(inner))
    // 透明包装，递归
    Prec(_, _, inner) | Tagged(_, inner) | Field(_, inner) | Alias(_, inner) =>
      field_shape_of(inner)
    // 非重复类型 → One
    _ => FieldShape::One(node_ref_of(p))
  }
}

///|
/// 从 Seq 的子 Pattern 列表中收集命名字段
/// 仅提取顶层 Field / Tagged，跳过无字段子项
fn collect_fields(
  children : Array[@grammar.Pattern],
) -> Array[(String, FieldShape)] {
  let fields : Array[(String, FieldShape)] = []
  for child in children {
    match child {
      Field(name, inner) => fields.push((name, field_shape_of(inner)))
      Tagged(name, inner) => fields.push((name, field_shape_of(inner)))
      // Prec/Alias 包装：剥开后再尝试
      Prec(_, _, Field(name, inner)) =>
        fields.push((name, field_shape_of(inner)))
      Prec(_, _, Tagged(name, inner)) =>
        fields.push((name, field_shape_of(inner)))
      Alias(_, Field(name, inner)) => fields.push((name, field_shape_of(inner)))
      Alias(_, Tagged(name, inner)) =>
        fields.push((name, field_shape_of(inner)))
      _ => ()
    }
  }
  fields
}

///|
/// 为 Choice 的单个分支推导变体名和载荷
/// i 是分支序号（用于匿名分支自动命名）
fn variant_of(i : Int, p : @grammar.Pattern) -> (String, VariantPayload) {
  match p {
    RuleRef(name) => (name, VariantPayload::Node(NodeRef::Named(name)))
    Alias(alias_name, _) =>
      (alias_name, VariantPayload::Node(NodeRef::Named(alias_name)))
    Tagged(name, inner) => (name, VariantPayload::Node(node_ref_of(inner)))
    Field(name, inner) => (name, VariantPayload::Node(node_ref_of(inner)))
    Literal(s) => {
      // 字面量变体：清理非标识符字符，用 lit_ 前缀
      let safe = sanitize_literal(s)
      ("lit_\{safe}", VariantPayload::Unit)
    }
    // Prec 包装，透传
    Prec(_, _, inner) => variant_of(i, inner)
    // 其余复杂 pattern
    _ => ("Variant\{i}", VariantPayload::Node(node_ref_of(p)))
  }
}

///|
/// 将字面量字符串转为合法 MoonBit 标识符片段
fn sanitize_literal(s : String) -> String {
  let buf = StringBuilder::new()
  for ch in s {
    let code = ch.to_int()
    if (code >= 'a'.to_int() && code <= 'z'.to_int()) ||
      (code >= 'A'.to_int() && code <= 'Z'.to_int()) ||
      (code >= '0'.to_int() && code <= '9'.to_int()) ||
      ch == '_' {
      buf.write_char(ch)
    } else {
      buf.write_string("_")
    }
  }
  let result = buf.to_string()
  if result == "" {
    "sym"
  } else {
    result
  }
}

///|
/// 推导任意 Pattern 的 NodeShape（顶层入口）
fn infer_pattern(
  grammar : @grammar.Grammar,
  p : @grammar.Pattern,
  rule_name : String,
  visiting : Array[String],
) -> NodeShape {
  match p {
    // ── 叶节点 ──────────────────────────────────────────────
    Literal(_) | Regex(_) | AnyChar => NodeShape::Token

    // ── 规则引用 ─────────────────────────────────────────────
    RuleRef(ref_name) =>
      match grammar.rules.get(ref_name) {
        None => NodeShape::Token
        Some(ref_rule) =>
          if should_skip(ref_rule) {
            NodeShape::Token // inline/hide/匿名规则透明化
          } else {
            NodeShape::Alias(ref_name)
          }
      }

    // ── Seq ─────────────────────────────────────────────────
    Seq(children) => {
      let fields = collect_fields(children)
      if fields.length() > 0 {
        NodeShape::Struct(fields)
      } else {
        // 没有命名字段：检查是否有单个 RuleRef，则透明 Alias；否则 Token
        let named_refs : Array[String] = []
        for child in children {
          match child {
            RuleRef(n) =>
              match grammar.rules.get(n) {
                Some(r) if !should_skip(r) => named_refs.push(n)
                _ => ()
              }
            _ => ()
          }
        }
        if named_refs.length() == 1 {
          NodeShape::Alias(named_refs[0])
        } else {
          NodeShape::Token
        }
      }
    }

    // ── Choice ───────────────────────────────────────────────
    Choice(alts) => {
      let variants : Array[(String, VariantPayload)] = []
      for i, alt in alts {
        variants.push(variant_of(i, alt))
      }
      NodeShape::Enum(variants)
    }

    // ── 透明包装（Priority / Prec / Alias / Tagged / Field）────
    Prec(_, _, inner) => infer_pattern(grammar, inner, rule_name, visiting)
    Alias(alias_name, _) => NodeShape::Alias(alias_name)
    Tagged(_, inner) | Field(_, inner) =>
      infer_pattern(grammar, inner, rule_name, visiting)

    // ── Optional / Repeat / Plus → 退化为 Token（不作为顶层规则）
    Optional(_) | Repeat(_) | Plus(_) | RepeatRange(_, _, _) => NodeShape::Token

    // ── 其余（Not/And/RuleApp/AnyChar 作为顶层）→ Token ──────
    _ => NodeShape::Token
  }
}

///|
/// 主入口：从 Grammar 推导整个 TypeSchema
///
/// 推导策略：
/// - 跳过 @inline / @hide / 名称以 `_` 开头 / 模板规则
/// - supertypes 中的规则强制生成 Enum（即使其 pattern 不是纯 Choice）
/// - 使用 visiting 列表避免循环递归
pub fn infer_grammar(grammar : @grammar.Grammar) -> TypeSchema {
  let schema = TypeSchema::new(grammar.start.unwrap_or("grammar"))
  let supertype_set : Set[String] = Set::new()
  for s in grammar.supertypes {
    supertype_set.add(s)
  }
  for name, rule in grammar.rules {
    if should_skip(rule) {
      continue
    }
    let visiting : Array[String] = [name]
    let shape = if supertype_set.contains(name) {
      // supertypes 强制展开为 Enum
      infer_as_supertype(grammar, rule, visiting)
    } else {
      infer_pattern(grammar, rule.pattern, name, visiting)
    }
    schema.set(name, shape)
  }
  schema
}

///|
/// 将 supertypes 规则展开为 Enum（即使其 body 不是纯 Choice）
fn infer_as_supertype(
  grammar : @grammar.Grammar,
  rule : @grammar.Rule,
  visiting : Array[String],
) -> NodeShape {
  // 剥去 Prec 等无关包装，找到底层 pattern
  let p = unwrap_prec(rule.pattern)
  match p {
    Choice(alts) => {
      let variants : Array[(String, VariantPayload)] = []
      for i, alt in alts {
        variants.push(variant_of(i, alt))
      }
      NodeShape::Enum(variants)
    }
    RuleRef(ref_name) =>
      // 单一引用的 supertype → 单变体枚举
      NodeShape::Enum([
        (ref_name, VariantPayload::Node(NodeRef::Named(ref_name))),
      ])
    _ =>
      // 其他情况回退到通用推导
      infer_pattern(grammar, rule.pattern, rule.name, visiting)
  }
}

///|
/// 剥去顶层 Prec 包装
fn unwrap_prec(p : @grammar.Pattern) -> @grammar.Pattern {
  match p {
    Prec(_, _, inner) => unwrap_prec(inner)
    _ => p
  }
}
