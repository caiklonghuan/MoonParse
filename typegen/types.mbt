///|
// 类型形状中间表示（Type Shape IR）
// 由 infer.mbt 从 Grammar 推导而来，供 emit.mbt 生成 MoonBit 类型代码使用。

///|
/// 字段/引用指向的节点种类
pub(all) enum NodeRef {
  /// 引用另一条命名规则（对应 Pattern::RuleRef(name)）
  Named(String)
  /// 匿名/标点节点，不对应具体命名规则
  Anonymous
  /// 纯叶节点（token 规则、Literal、Regex）
  Token
} derive(Debug, Eq)

///|
pub impl Show for NodeRef with output(self, logger) {
  match self {
    Named(name) => logger.write_string("Named(\{name})")
    Anonymous => logger.write_string("Anonymous")
    Token => logger.write_string("Token")
  }
}

///|
/// 字段的基数描述
pub(all) enum FieldShape {
  /// 恰好一个子节点（Pattern::Field / Pattern::Tagged 直接引用）
  One(NodeRef)
  /// 零或一个子节点（来自 Pattern::Optional）
  Optional(NodeRef)
  /// 零或多个子节点（来自 Pattern::Repeat / Pattern::Plus / Pattern::RepeatRange）
  Many(NodeRef)
} derive(Debug)

///|
pub impl Show for FieldShape with output(self, logger) {
  match self {
    One(node_ref) => logger.write_string("One(\{node_ref})")
    Optional(node_ref) => logger.write_string("Optional(\{node_ref})")
    Many(node_ref) => logger.write_string("Many(\{node_ref})")
  }
}

///|
/// 枚举变体的载荷类型
pub(all) enum VariantPayload {
  /// 无载荷变体（对应 Literal、匿名 pattern 等）
  Unit
  /// 携带单个节点引用
  Node(NodeRef)
} derive(Debug)

///|
pub impl Show for VariantPayload with output(self, logger) {
  match self {
    Unit => logger.write_string("Unit")
    Node(node_ref) => logger.write_string("Node(\{node_ref})")
  }
}

///|
/// 语法规则推导出的类型形状
pub(all) enum NodeShape {
  /// 对应 Seq 中含有命名 Field / Tagged 子项的规则
  /// 字段列表：(字段名, 字段形状)
  Struct(Array[(String, FieldShape)])
  /// 对应顶层 Choice，或 supertypes 声明的抽象类型
  /// 变体列表：(变体名, 变体载荷)
  Enum(Array[(String, VariantPayload)])
  /// 纯叶节点（token 规则或字面量规则）
  Token
  /// 内联展开或透明别名，直接引用另一规则
  Alias(String)
} derive(Debug)

///|
pub impl Show for NodeShape with output(self, logger) {
  match self {
    Struct(fields) => logger.write_string("Struct(\{fields})")
    Enum(variants) => logger.write_string("Enum(\{variants})")
    Token => logger.write_string("Token")
    Alias(name) => logger.write_string("Alias(\{name})")
  }
}

///|
/// 整个语法的类型映射：规则名 → NodeShape
/// 只包含需要生成代码的用户命名规则（已过滤 @inline/@hide/匿名规则）
pub(all) struct TypeSchema {
  /// 规则名 → 节点形状
  shapes : Map[String, NodeShape]
  /// 产生此 schema 的语法名（用于生成模块注释）
  grammar_name : String
} derive(Debug)

///|
pub fn TypeSchema::new(grammar_name : String) -> TypeSchema {
  { shapes: Map::new(), grammar_name }
}

///|
pub fn TypeSchema::set(
  self : TypeSchema,
  name : String,
  shape : NodeShape,
) -> Unit {
  self.shapes.set(name, shape)
}

///|
pub fn TypeSchema::get(self : TypeSchema, name : String) -> NodeShape? {
  self.shapes.get(name)
}

///|
pub fn TypeSchema::contains(self : TypeSchema, name : String) -> Bool {
  self.shapes.contains(name)
}

///|
pub fn TypeSchema::size(self : TypeSchema) -> Int {
  self.shapes.length()
}

///|
pub fn TypeSchema::iter(self : TypeSchema) -> Iter[(String, NodeShape)] {
  self.shapes.iter()
}
