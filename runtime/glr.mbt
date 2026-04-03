///|
// ─── §8 GLR 解析引擎（Phase 2c 存根）──────────────────────────────────────────
//
// GLR（广义 LR）允许在 LALR 冲突点并行维护多个解析路径（version），
// 通过 Graph-Structured Stack（GSS）共享公共前缀。
//
// Phase 2c 实现目标：
//   · GssNode      — GSS 结点，每个结点代表一个 (state, predecessor_list) 对
//   · StackVersion — 解析版本（每条并行路径对应一个 version）
//   · glr_parse    — 替代 parse_linear，支持歧义语法
//
// 当前状态：类型骨架占位，函数体为 TODO。
// 复用 parser.mbt 的 parse_linear 直至 Phase 2c 启动。

///|
/// GSS 结点引用（弱引用，避免循环）
/// Phase 2c 可改为引用计数或 Arena 分配的下标
type GssRef = Int

///|
/// GSS（Graph-Structured Stack）结点
///
/// 多条解析路径共享同一 GssNode 前缀时，可大幅减少重复推导。
///
/// predecessors：前驱结点列表（空 = 初始结点）
struct GssNode {
  state : Int // LR 状态
  node : CstNode? // 该状态对应的 CST 节点（None = 底部哨兵）
  predecessors : Array[GssRef] // 前驱结点引用列表（GSS 边）
} derive(Show)

///|
/// GLR 解析版本（单条解析路径）
///
/// 每个版本拥有：
///   · 当前 GSS 栈顶结点（gss_top）
///   · 错误状态（error_status）
///   · 待归约 / 已移入的前瞻 token
///
/// Phase 2c 前 max_version_count 个版本可并行存在；
/// 超过 max_version_count_overflow 时触发版本裁剪。
struct StackVersion {
  gss_top : GssRef
  error_status : ErrorStatus
} derive(Show)

///|
/// GLR 解析引擎（包含全部 GSS 结点与并行版本）
struct GlrEngine {
  /// GSS 所有结点（以 GssRef = 下标访问）
  gss_nodes : Array[GssNode]
  /// 当前活跃版本列表（最多 max_version_count 条）
  versions : Array[StackVersion]
  /// 词法引擎（context-aware，所有版本共享）
  lexer : LexerEngine
}

///|
fn GlrEngine::new(lexer : LexerEngine) -> GlrEngine {
  // 初始 GSS：单一底部结点（state=1, node=None, predecessors=[]）
  let root_node : GssNode = { state: 1, node: None, predecessors: [] }
  let initial_version : StackVersion = {
    gss_top: 0,
    error_status: {
      cost: 0,
      node_count: 0,
      dynamic_precedence: 0,
      is_in_error: false,
    },
  }
  { gss_nodes: [root_node], versions: [initial_version], lexer }
}

///|
/// GLR 解析入口（Phase 2c — TODO: 未实现，暂时 fallback 至 parse_linear）
///
/// 当解析表不含冲突时，等价于 parse_linear；
/// 含冲突时并行展开所有 Shift / Reduce 路径，最终合并为 CST 森林（AmbiguityNode）。
pub fn glr_parse(
  table : @tablegen.ParseTable,
  input : String,
) -> Result[CstNode, ParseError] {
  // TODO Phase 2c: 实现 GSS 主循环
  // 当前直接调用线性 LR 解析作为兜底
  parse_linear(table, input)
}

///|
/// 向 GSS 添加新结点，返回其 GssRef
fn GlrEngine::add_gss_node(
  self : GlrEngine,
  state : Int,
  node : CstNode?,
  preds : Array[GssRef],
) -> GssRef {
  let ref = self.gss_nodes.length()
  self.gss_nodes.push({ state, node, predecessors: preds })
  ref
}

///|
/// 从 GSS 结点反向收集完整的状态路径（调试 / 错误报告用）
fn GlrEngine::state_path(self : GlrEngine, top : GssRef) -> Array[Int] {
  let path : Array[Int] = []
  let mut cur = top
  while cur >= 0 && cur < self.gss_nodes.length() {
    let n = self.gss_nodes[cur]
    path.push(n.state)
    if n.predecessors.is_empty() {
      break
    }
    cur = n.predecessors[0] // 取第一条前驱路径（歧义时有多条）
  }
  array_rev_inplace(path)
  path
}
