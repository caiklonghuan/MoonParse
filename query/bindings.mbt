///|
// Binding 数据模型 — 通用名称绑定（scope / definition / reference / edge / diagnostic / graph）
//
// 这是 CST 之上的语义派生层。与 locals.mbt 的区别：
//   - locals.mbt 处理局部变量（由 locals query 提供 scope/def/ref 捕获）
//   - bindings.mbt 是通用框架：任意语言的 scope rules → 完整的 BindingGraph
//
// TS 侧 lsp/src/binding-types.ts 保留为 JSON wire type（描述序列化后的形状）。

///|
/// 作用域种类
pub(all) enum ScopeKind {
  Module // 文件顶层
  Function // 函数体
  Block // 花括号块 { ... }
  Class // 类体
  Loop // for / while 循环体
  Rule // Grammar DSL rule 体
} derive(Debug, Eq)

///|
/// 一个作用域区域
pub(all) struct BindingScope {
  id : Int
  parent : Int // 父作用域 id，-1 表示根（module）
  start_byte : Int
  end_byte : Int
  kind : ScopeKind
} derive(Debug)

///|
/// 定义/引用的符号种类
pub(all) enum SymbolKind {
  Variable
  Constant
  Function
  Method
  Type
  Struct
  Enum
  Trait
  Field
  EnumMember
  Parameter
  TypeParameter
  Rule // Grammar DSL rule
  Token // Grammar DSL token
} derive(Debug, Eq)

///|
/// 命名空间（同一作用域内不同命名空间允许重名）
pub(all) enum NameSpace {
  Value // 变量 / 函数
  Type // 类型 / 类 / 接口
  Member // member field namespace
  Rule // Grammar DSL rule name
} derive(Debug, Eq)

///|
/// 一个符号定义
pub(all) struct BindingDefinition {
  id : Int
  name : String
  kind : SymbolKind
  ns : NameSpace // 'namespace' 是 MoonBit 保留字，故用 ns
  scope_id : Int // 定义所在的作用域
  start_byte : Int
  end_byte : Int
  declaration_start_byte : Int
  declaration_end_byte : Int
} derive(Debug)

///|
/// 一个符号引用
pub(all) struct BindingReference {
  id : Int
  name : String
  kind : SymbolKind
  ns : NameSpace
  scope_id : Int // 引用所在的作用域
  start_byte : Int
  end_byte : Int
  diagnose_unresolved : Bool
} derive(Debug)

///|
/// 引用 → 定义的绑定边
pub(all) struct BindingEdge {
  reference_id : Int
  definition_id : Int
} derive(Debug)

///|
/// 绑定诊断种类
pub(all) enum BindingDiagKind {
  Unresolved // 引用找不到对应定义
  Duplicate // 同一作用域内重复定义
  Ambiguous // 引用可解析到多个定义
} derive(Debug, Eq)

///|
/// 绑定诊断
pub(all) struct BindingDiagnostic {
  kind : BindingDiagKind
  message : String
  reference_id : Int // -1 表示不关联引用
  definition_id : Int // -1 同理
  start_byte : Int
  end_byte : Int
} derive(Debug)

///|
/// 单文件的完整绑定图
pub(all) struct BindingGraph {
  uri : String
  scopes : Array[BindingScope]
  definitions : Array[BindingDefinition]
  references : Array[BindingReference]
  edges : Array[BindingEdge]
  diagnostics : Array[BindingDiagnostic]
} derive(Debug)

///|
/// 空图
pub fn empty_binding_graph(uri : String) -> BindingGraph {
  {
    uri,
    scopes: [],
    definitions: [],
    references: [],
    edges: [],
    diagnostics: [],
  }
}

// ── P2: capture name 解析 ─────────────────────────────────────────
//
// 新的 capture 约定（推荐）:
//   @scope / @scope.function / @scope.block / @scope.class / @scope.loop
//   @definition.variable / @definition.function / @definition.type / @definition.parameter
//   @reference.variable / @reference.function / @reference.type
//   @reference.soft.variable / @reference.soft.function / @reference.soft.type
//   @symbol.variable / @symbol.function / @symbol.type
//
// 旧的 capture 约定（兼容 locals.mbt）:
//   local.scope              → scope
//   local.definition         → definition.variable
//   local.definition.xxx     → definition.xxx
//   local.reference          → reference.variable

///|
/// 捕获角色的分类结果
pub(all) enum BindingCaptureRole {
  Scope(ScopeKind?) // Scope(Some(kind)) 或 Scope(None) 表示通用 scope
  Definition(SymbolKind?) // Definition(Some(kind)) 或 Definition(None)
  Reference(SymbolKind?, Bool) // 第二项表示未解析时是否生成诊断
  Symbol(SymbolKind?) // 声明完整范围，与同 match_id 的 definition 配对
  Unknown // 不参与绑定的 capture（如 @highlight, @fold 等）
} derive(Debug, Eq)

///|
pub impl Show for BindingCaptureRole with fn output(self, logger) {
  match self {
    Scope(Some(k)) => logger.write_string("Scope(Some(\{k}))")
    Scope(None) => logger.write_string("Scope(None)")
    Definition(Some(k)) => logger.write_string("Definition(Some(\{k}))")
    Definition(None) => logger.write_string("Definition(None)")
    Reference(Some(k), diagnose) =>
      logger.write_string("Reference(Some(\{k}), \{diagnose})")
    Reference(None, diagnose) =>
      logger.write_string("Reference(None, \{diagnose})")
    Symbol(Some(k)) => logger.write_string("Symbol(Some(\{k}))")
    Symbol(None) => logger.write_string("Symbol(None)")
    Unknown => logger.write_string("Unknown")
  }
}

///|
pub impl Show for ScopeKind with fn output(self, logger) {
  match self {
    Module => logger.write_string("Module")
    Function => logger.write_string("Function")
    Block => logger.write_string("Block")
    Class => logger.write_string("Class")
    Loop => logger.write_string("Loop")
    Rule => logger.write_string("Rule")
  }
}

///|
pub impl Show for SymbolKind with fn output(self, logger) {
  match self {
    Variable => logger.write_string("Variable")
    Constant => logger.write_string("Constant")
    Function => logger.write_string("Function")
    Method => logger.write_string("Method")
    Type => logger.write_string("Type")
    Struct => logger.write_string("Struct")
    Enum => logger.write_string("Enum")
    Trait => logger.write_string("Trait")
    Field => logger.write_string("Field")
    EnumMember => logger.write_string("EnumMember")
    Parameter => logger.write_string("Parameter")
    TypeParameter => logger.write_string("TypeParameter")
    Rule => logger.write_string("Rule")
    Token => logger.write_string("Token")
  }
}

///|
pub impl Show for NameSpace with fn output(self, logger) {
  match self {
    Value => logger.write_string("Value")
    Type => logger.write_string("Type")
    Member => logger.write_string("Member")
    Rule => logger.write_string("Rule")
  }
}

///|
/// 解析 capture name 为 BindingCaptureRole。
///
/// 优先级：新约定 > 旧约定 > Unknown
pub fn capture_role(name : String) -> BindingCaptureRole {
  // ── 新约定 @scope / @scope.xxx ──
  if name == "scope" {
    return Scope(None)
  }
  if str_starts_with(name, "scope.") {
    let sub = name[6:].to_owned()
    let k = scope_kind_from_str(sub)
    return Scope(k)
  }

  // ── 新约定 @definition / @definition.xxx ──
  if name == "definition" {
    return Definition(None)
  }
  if str_starts_with(name, "definition.") {
    let sub = name[11:].to_owned()
    let k = symbol_kind_from_str(sub)
    return Definition(k)
  }

  // ── 新约定 @reference / @reference.xxx ──
  if name == "reference" {
    return Reference(None, true)
  }
  if name == "reference.soft" {
    return Reference(None, false)
  }
  if str_starts_with(name, "reference.soft.") {
    let sub = name[15:].to_owned()
    let k = symbol_kind_from_str(sub)
    return Reference(k, false)
  }
  if str_starts_with(name, "reference.") {
    let sub = name[10:].to_owned()
    let k = symbol_kind_from_str(sub)
    return Reference(k, true)
  }

  // ── 声明完整范围 @symbol / @symbol.xxx ──
  if name == "symbol" {
    return Symbol(None)
  }
  if str_starts_with(name, "symbol.") {
    let sub = name[7:].to_owned()
    let k = symbol_kind_from_str(sub)
    return Symbol(k)
  }

  // ── 旧约定兼容 ──
  if name == "local.scope" {
    return Scope(None)
  }
  if name == "local.definition" {
    return Definition(Some(Variable))
  }
  if str_starts_with(name, "local.definition.") {
    let sub = name[17:].to_owned()
    let k = symbol_kind_from_str(sub)
    return Definition(k)
  }
  if name == "local.reference" {
    return Reference(Some(Variable), true)
  }

  Unknown
}

///|
/// 从 capture 后缀字符串解析 SymbolKind
pub fn symbol_kind_from_str(s : String) -> SymbolKind? {
  match s {
    "variable" => Some(Variable)
    "constant" => Some(Constant)
    "function" => Some(Function)
    "method" => Some(Method)
    "type" => Some(Type)
    "struct" => Some(Struct)
    "enum" => Some(Enum)
    "trait" => Some(Trait)
    "field" => Some(Field)
    "enum_member" => Some(EnumMember)
    "parameter" => Some(Parameter)
    "type_parameter" => Some(TypeParameter)
    "rule" => Some(Rule)
    "token" => Some(Token)
    _ => None
  }
}

///|
/// 从 capture 后缀字符串解析 ScopeKind
fn scope_kind_from_str(s : String) -> ScopeKind? {
  match s {
    "module" => Some(Module)
    "function" => Some(Function)
    "block" => Some(Block)
    "class" => Some(Class)
    "loop" => Some(Loop)
    "rule" => Some(Rule)
    _ => None
  }
}

///|
/// SymbolKind → NameSpace
pub fn ns_from_kind(kind : SymbolKind) -> NameSpace {
  match kind {
    Variable | Constant | Function | Method | Parameter | EnumMember => Value
    Type | Struct | Enum | Trait | TypeParameter => Type
    Field => Member
    Rule | Token => Rule
  }
}

///|
/// ScopeKind → NameSpace（用于判断 scope 内默认的 namespace）
pub fn ns_from_scope_kind(kind : ScopeKind) -> NameSpace {
  match kind {
    Module | Function | Block | Loop => Value
    Class => Type
    Rule => Rule
  }
}

// ── P2: 工厂函数 ─────────────────────────────────────────────

///|
fn _make_scope(
  parent : Int,
  start_byte : Int,
  end_byte : Int,
  kind : ScopeKind,
) -> BindingScope {
  { id: -1, parent, start_byte, end_byte, kind }
}

///|
fn _make_definition(
  name : String,
  kind : SymbolKind,
  ns : NameSpace,
  scope_id : Int,
  start_byte : Int,
  end_byte : Int,
) -> BindingDefinition {
  {
    id: -1,
    name,
    kind,
    ns,
    scope_id,
    start_byte,
    end_byte,
    declaration_start_byte: start_byte,
    declaration_end_byte: end_byte,
  }
}

///|
fn _make_reference(
  name : String,
  kind : SymbolKind,
  ns : NameSpace,
  scope_id : Int,
  start_byte : Int,
  end_byte : Int,
) -> BindingReference {
  {
    id: -1,
    name,
    kind,
    ns,
    scope_id,
    start_byte,
    end_byte,
    diagnose_unresolved: true,
  }
}

///|
fn _make_edge(reference_id : Int, definition_id : Int) -> BindingEdge {
  { reference_id, definition_id }
}

///|
fn _make_diagnostic(
  kind : BindingDiagKind,
  message : String,
  start_byte : Int,
  end_byte : Int,
  reference_id : Int,
  definition_id : Int,
) -> BindingDiagnostic {
  { kind, message, reference_id, definition_id, start_byte, end_byte }
}

// ── P3: 单文件 lexical binding 构建 ───────────────────────────────
//
// 算法（复用 locals.mbt 的核心思路，升级为 BindingGraph）:
//   1. exec(binding_query) → CaptureResult[]
//   2. 按 capture_role 分拣到 scopes / definitions / references
//   3. 建 scope parent 链（按区间包含关系）
//   4. definition 归入最内层 scope
//   5. reference 归入最内层 scope
//   6. 从当前 scope 向 parent 查找同名同 namespace 的 definition
//   7. 找到 → 生成 edge；找不到 → 生成 unresolved diagnostic
//   8. 检查同一 scope 内同 namespace 的重复定义

///|
/// 在 CST 上运行 binding_query 并构建完整的 BindingGraph。
pub fn build_binding_graph(
  root : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
  binding_query : CompiledQuery,
) -> BindingGraph {
  let captures = exec(binding_query, root, input, table)

  // ── 步骤 1: 分拣捕获 ───────────────────────────────────────────
  // 未分配 ID 的临时列表
  let scopes_raw : Array[BindingScope] = []
  let defs_raw : Array[BindingDefinition] = []
  let refs_raw : Array[BindingReference] = []

  // @symbol.* 通常是顶层 capture，执行顺序晚于其子 definition capture，
  // 因此先独立收集，再构造 definition。
  let symbol_ranges : Map[Int, (SymbolKind, Int, Int)] = Map([])
  for c in captures {
    match capture_role(c.capture_name) {
      Symbol(kind_opt) => {
        let kind = match kind_opt {
          Some(value) => value
          None => guess_symbol_kind(c.node, table)
        }
        if !symbol_ranges.contains(c.match_id) {
          symbol_ranges[c.match_id] = (kind, c.node.start_byte, c.node.end_byte)
        }
      }
      _ => ()
    }
  }

  for c in captures {
    let role = capture_role(c.capture_name)
    match role {
      Scope(scope_kind_opt) => {
        let kind = match scope_kind_opt {
          Some(k) => k
          None => guess_scope_kind(c.node, table)
        }
        scopes_raw.push({
          id: -1,
          parent: -1,
          start_byte: c.node.start_byte,
          end_byte: c.node.end_byte,
          kind,
        })
      }
      Definition(sym_kind_opt) => {
        let text = node_text(c.node, input)
        if !text.is_empty() {
          let kind = match sym_kind_opt {
            Some(k) => k
            None => guess_symbol_kind(c.node, table)
          }
          let declaration = match symbol_ranges.get(c.match_id) {
            Some((symbol_kind, start_byte, end_byte)) if symbol_kind == kind =>
              (start_byte, end_byte)
            _ => (c.node.start_byte, c.node.end_byte)
          }
          defs_raw.push({
            id: -1,
            name: text,
            kind,
            ns: ns_from_kind(kind),
            scope_id: -1,
            start_byte: c.node.start_byte,
            end_byte: c.node.end_byte,
            declaration_start_byte: declaration.0,
            declaration_end_byte: declaration.1,
          })
        }
      }
      Reference(sym_kind_opt, diagnose_unresolved) => {
        let text = node_text(c.node, input)
        if !text.is_empty() {
          let kind = match sym_kind_opt {
            Some(k) => k
            None => Variable // 引用默认按 variable 处理
          }
          refs_raw.push({
            id: -1,
            name: text,
            kind,
            ns: ns_from_kind(kind),
            scope_id: -1,
            start_byte: c.node.start_byte,
            end_byte: c.node.end_byte,
            diagnose_unresolved,
          })
        }
      }
      Symbol(_) | Unknown => ()
    }
  }

  // ── 步骤 2: 建 scope parent ────────────────────────────────────
  // 自动插入隐式 root Module scope（覆盖整个文件）
  let root_scope : BindingScope = {
    id: 0,
    parent: -1,
    start_byte: root.start_byte,
    end_byte: root.end_byte,
    kind: Module,
  }

  // 按 start_byte 升序排序，用下标作为 ID（id == 数组下标）
  let sorted_scopes = sort_scopes_by_start(scopes_raw)

  // 在每个 scope id 上加 1，给 root scope 让出 id=0
  let scopes_id : Array[BindingScope] = []
  scopes_id.push(root_scope)
  for i in 0..<sorted_scopes.length() {
    let s = sorted_scopes[i]
    scopes_id.push({ ..s, id: i + 1 })
  }

  // 为每个 scope 找 parent（root scope id=0 作为自动 parent）
  let scopes : Array[BindingScope] = []
  scopes.push({ ..root_scope, parent: -1 })
  for i in 1..<scopes_id.length() {
    let s = scopes_id[i]
    let parent = find_parent_scope(scopes_id, s, i)
    let final_parent = if parent < 0 { 0 } else { parent }
    scopes.push({ ..s, parent: final_parent })
  }

  // ── 步骤 3: definition 归入最内层 scope ─────────────────────────
  let scope_defs : Array[Array[Int]] = scopes.map(fn(_) { [] })
  let definitions : Array[BindingDefinition] = []
  for d in defs_raw {
    let containing = find_containing_scope_ids(scopes, d.start_byte, d.end_byte)
    let scope_id = if containing.is_empty() {
      0 // 无 scope → 归入 root
    } else {
      containing[0]
    }
    // Function/Type/Rule 声明名应归入父 scope（非声明自身 scope）
    // 参数/变量保留在当前 scope
    // 使用 scope parent 链而非 containing[N]，避免同 range duplicate scope 干扰
    let final_scope_id = match d.kind {
      Function | Method | Type | Struct | Enum | Trait | Rule => {
        let p = scope_parent_by_id(scopes, scope_id)
        if p >= 0 {
          p
        } else {
          0
        }
      }
      _ => scope_id
    }
    // id = 数组下标（不再重新编号）
    let def_with_scope = {
      ..d,
      scope_id: final_scope_id,
      id: definitions.length(),
    }
    definitions.push(def_with_scope)
    if def_with_scope.scope_id >= 0 {
      let idx = scope_index(scopes, def_with_scope.scope_id)
      if idx >= 0 {
        scope_defs[idx].push(def_with_scope.id)
      }
    }
  }

  // ── 步骤 4: reference 解析 + 生成 edge / diagnostic ────────────
  let references : Array[BindingReference] = []
  let edges : Array[BindingEdge] = []
  let diagnostics : Array[BindingDiagnostic] = []

  let refs_merged = merge_reference_captures(refs_raw)
  for node in refs_merged {
    // 前过滤：definition 节点被 reference query 同时捕获 → 直接跳过
    if is_definition_capture_self_reference(node, definitions) {
      continue
    }

    let containing = find_containing_scope_ids(
      scopes,
      node.start_byte,
      node.end_byte,
    )
    let scope_id = if containing.is_empty() {
      0 // 无 scope → root
    } else {
      containing[0]
    }

    // Resolve against the nearest scope that has matching candidates.
    let scope_chain = if containing.is_empty() { [0] } else { containing }
    let candidates : Array[Int] = []
    for sid in scope_chain {
      let s_idx = scope_index(scopes, sid)
      if s_idx < 0 {
        continue
      }
      for def_idx in scope_defs[s_idx] {
        let d = definitions[def_idx]
        if d.name == node.name && d.ns == node.ns {
          candidates.push(def_idx)
        }
      }
      if !candidates.is_empty() {
        break
      }
    }

    if candidates.length() == 1 {
      // 有关联的可见定义 → push ref + edge
      let ref_with_scope = { ..node, scope_id, id: references.length() }
      references.push(ref_with_scope)
      let ref_idx = ref_with_scope.id
      edges.push({ reference_id: ref_idx, definition_id: candidates[0] })
    } else if candidates.length() > 1 {
      let ref_with_scope = { ..node, scope_id, id: references.length() }
      references.push(ref_with_scope)
      let ref_idx = ref_with_scope.id
      diagnostics.push({
        kind: Ambiguous,
        message: "ambiguous reference '" + node.name + "'",
        reference_id: ref_idx,
        definition_id: -1,
        start_byte: node.start_byte,
        end_byte: node.end_byte,
      })
    } else {
      // 无可见定义 → unresolved
      let ref_with_scope = { ..node, scope_id, id: references.length() }
      references.push(ref_with_scope)
      let ref_idx = ref_with_scope.id
      if node.diagnose_unresolved {
        diagnostics.push({
          kind: Unresolved,
          message: "unresolved reference '" + node.name + "'",
          reference_id: ref_idx,
          definition_id: -1,
          start_byte: node.start_byte,
          end_byte: node.end_byte,
        })
      }
    }
  }

  // ── 步骤 5: duplicate 诊断 ───────────────────────────────────────
  for i in 0..<scopes.length() {
    let def_indices = scope_defs[i]
    let n = def_indices.length()
    let mut j = 0
    while j < n {
      let dj = definitions[def_indices[j]]
      let mut k = j + 1
      while k < n {
        let dk = definitions[def_indices[k]]
        if dj.name == dk.name && dj.ns == dk.ns {
          diagnostics.push({
            kind: Duplicate,
            message: "duplicate definition '" + dk.name + "' in same scope",
            reference_id: -1,
            definition_id: def_indices[k],
            start_byte: dk.start_byte,
            end_byte: dk.end_byte,
          })
        }
        k = k + 1
      }
      j = j + 1
    }
  }

  // ── 步骤 6: 返回（id 即数组下标，edge 直接匹配） ────────────────
  { uri: "", scopes, definitions, references, edges, diagnostics }
}

// ── P3: 内部辅助 ─────────────────────────────────────────────────

///|
/// 按 start_byte 升序排列 scope
fn same_reference_site(a : BindingReference, b : BindingReference) -> Bool {
  a.name == b.name &&
  a.ns == b.ns &&
  a.start_byte == b.start_byte &&
  a.end_byte == b.end_byte
}

///|
fn prefer_reference_kind(old : SymbolKind, fresh : SymbolKind) -> SymbolKind {
  match old {
    Variable =>
      match fresh {
        Variable => old
        _ => fresh
      }
    Type =>
      match fresh {
        Type => old
        _ => fresh
      }
    _ => old
  }
}

///|
fn merge_reference_captures(
  refs : Array[BindingReference],
) -> Array[BindingReference] {
  let merged : Array[BindingReference] = []
  for r in refs {
    let mut found = -1
    for i in 0..<merged.length() {
      if same_reference_site(merged[i], r) {
        found = i
        break
      }
    }
    if found >= 0 {
      let old = merged[found]
      merged[found] = {
        ..old,
        kind: prefer_reference_kind(old.kind, r.kind),
        diagnose_unresolved: old.diagnose_unresolved && r.diagnose_unresolved,
      }
    } else {
      merged.push(r)
    }
  }
  merged
}

///|
fn sort_scopes_by_start(scopes : Array[BindingScope]) -> Array[BindingScope] {
  let result = scopes
  let n = result.length()
  for i in 1..<n {
    let key = result[i]
    let mut j = i - 1
    while j >= 0 && result[j].start_byte > key.start_byte {
      result[j + 1] = result[j]
      j = j - 1
      if j < 0 {
        break
      }
    }
    if j + 1 != i {
      result[j + 1] = key
    }
  }
  result
}

///|
/// 为 scope 找 parent ID：最内层的外围 scope（要求严格外围，排除同 range）
/// 比较规则：(start 更大) 或 (start 相同但 end 更小)
fn find_parent_scope(
  scopes : Array[BindingScope],
  current : BindingScope,
  current_idx : Int,
) -> Int {
  let mut best_parent = -1
  let mut best_start = -1
  let mut best_end = 999999
  for k in 0..<scopes.length() {
    if k == current_idx {
      continue
    }
    let cand = scopes[k]
    // 要求严格外围：不能完全同 range
    if cand.start_byte <= current.start_byte &&
      current.end_byte <= cand.end_byte &&
      (cand.start_byte < current.start_byte || current.end_byte < cand.end_byte) {
      let better = cand.start_byte > best_start ||
        (cand.start_byte == best_start && cand.end_byte < best_end)
      if better {
        best_parent = cand.id
        best_start = cand.start_byte
        best_end = cand.end_byte
      }
    }
  }
  best_parent
}

///|
/// 给定字节区间，找出包含它的所有 scope id，按最内层优先返回
fn find_containing_scope_ids(
  scopes : Array[BindingScope],
  start_byte : Int,
  end_byte : Int,
) -> Array[Int] {
  let result : Array[Int] = []
  for s in scopes {
    if s.start_byte <= start_byte && end_byte <= s.end_byte {
      result.push(s.id)
    }
  }
  // 按最内层优先排序：(start 更大) 或 (start 相同但 end 更小)
  let n = result.length()
  for i in 1..<n {
    let key = result[i]
    let key_start = scope_start_by_id(scopes, key)
    let key_end = scope_end_by_id(scopes, key)
    let mut j = i - 1
    while j >= 0 {
      let r_start = scope_start_by_id(scopes, result[j])
      let r_end = scope_end_by_id(scopes, result[j])
      let r_is_outer = r_start < key_start ||
        (r_start == key_start && r_end > key_end)
      if r_is_outer {
        result[j + 1] = result[j]
        j = j - 1
        if j < 0 {
          break
        }
      } else {
        break
      }
    }
    result[j + 1] = key
  }
  result
}

///|
fn scope_end_by_id(scopes : Array[BindingScope], id : Int) -> Int {
  for s in scopes {
    if s.id == id {
      return s.end_byte
    }
  }
  999999
}

///|
fn scope_start_by_id(scopes : Array[BindingScope], id : Int) -> Int {
  for s in scopes {
    if s.id == id {
      return s.start_byte
    }
  }
  -1
}

///|
fn scope_index(scopes : Array[BindingScope], id : Int) -> Int {
  for i in 0..<scopes.length() {
    if scopes[i].id == id {
      return i
    }
  }
  -1
}

///|
fn scope_parent_by_id(scopes : Array[BindingScope], id : Int) -> Int {
  for s in scopes {
    if s.id == id {
      return s.parent
    }
  }
  -1
}

///|
/// 根据 CST 节点类型猜测 ScopeKind（用于 capture 未指定 @scope.xxx 后缀时）
fn guess_scope_kind(
  _node : @runtime.CstNode,
  _table : @tablegen.ParseTable,
) -> ScopeKind {
  // 从节点类型名称推测：包含 "function" → Function，"class" → Class，"block" → Block
  Module
}

///|
/// 根据 CST 节点类型猜测 SymbolKind（用于 capture 未指定 @definition.xxx 后缀时）
fn guess_symbol_kind(
  _node : @runtime.CstNode,
  _table : @tablegen.ParseTable,
) -> SymbolKind {
  Variable
}

///|
/// 判断一个 reference 节点是否被 definition capture 同时捕获，
/// 且没有其他可绑定的同名定义（纯自引用，可直接跳过）。

///|
/// 判断 reference 是否被 definition capture 同时捕获。
/// 条件：name、ns、start_byte、end_byte 完全相同，
/// 且没有其他可绑定的同名定义（兼容旧 locals 查询重叠语义）。
/// NOTE: review2 要求严格过滤（不考虑 has_other_def），
/// 但这会破坏 `@local.definition + @local.reference` 旧查询。
/// 改严格需先修复 5 个旧 locals 测试，当前暂保持兼容。
fn is_definition_capture_self_reference(
  node : BindingReference,
  definitions : Array[BindingDefinition],
) -> Bool {
  let mut has_overlap = false
  let mut has_other_def = false
  for d in definitions {
    if d.name == node.name && d.ns == node.ns {
      if d.start_byte == node.start_byte && d.end_byte == node.end_byte {
        has_overlap = true
      } else {
        has_other_def = true
      }
    }
  }
  has_overlap && !has_other_def
}
