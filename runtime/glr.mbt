///|
// ─── §8 GLR 解析引擎（Phase 2b）─────────────────────────────────────────────
//
// GLR（广义 LR）允许在 LALR 冲突点并行维护多个解析路径，
// 通过 Graph-Structured Stack（GSS）共享公共前缀，避免指数爆炸。
//
// 核心数据结构设计：
//   · GssLink  — GSS 边，携带跨越该边时产生的 CstNode（而非挂在结点上）
//   · GssNode  — GSS 结点，持有 LR 状态 + 入边列表（links）
//   · GlrEngine — 持有全部 GSS 结点 + 当前活跃栈顶集合（active_tops）
//
// 为什么节点不挂 CstNode，而由边来携带：
//   同一个 LR 状态可以通过不同的前驱（即不同的归约路径）到达，
//   每条路径产生的子树不同。把 CstNode 放在边上，才能正确区分局部歧义。
//
// 实现阶段：
//   Phase 2b（本次）：基础类型重构，为主循环做准备
//   Phase 2c（后续）：glr_parse 主循环、enum_paths、find_or_merge

///|
/// GSS 结点引用（Arena 下标，避免循环引用）
type GssRef = Int

///|
/// GSS 边（Graph-Structured Stack edge）
///
/// predecessor : 前驱结点的 GssRef
/// node        : 跨越该边时产生的 CST 节点
///                 · Shift  边：叶节点（token）
///                 · Reduce 边：内部节点（产生式归约结果）
///                 · 底部哨兵边：None（初始结点无前驱）
struct GssLink {
  predecessor : GssRef
  node : CstNode?
} derive(Show)

///|
/// GSS 结点（Graph-Structured Stack node）
///
/// 一个结点代表 "在某个 LR 状态下，存在至少一条活跃解析路径到达此处"。
/// 同一 state 只保留一个结点（find_or_merge 负责合并），
/// 局部歧义体现为同一结点拥有多条入边（links.length() > 1）。
struct GssNode {
  /// 当前 LR 状态（ParseTable.action 的 key 之一）
  state : Int
  /// 入边列表（空 = 底部哨兵结点，永不弹出）
  links : Array[GssLink]
} derive(Show)

///|
/// GLR 解析引擎
///
/// gss_nodes   : GSS Arena，所有结点按 GssRef（下标）访问
/// active_tops : 本轮 token 位置下的活跃栈顶集合（每个元素是一个 GssRef）
///               每消费一个 token 后，active_tops 被替换为新的 Shift 目标集
/// lexer       : 词法引擎，context-aware，所有路径共享
struct GlrEngine {
  gss_nodes : Array[GssNode]
  active_tops : Array[GssRef]
  lexer : LexerEngine
}

///|
/// 初始化 GLR 引擎
///
/// 创建唯一底部哨兵结点（state=0, links=[]），并将其设为唯一活跃栈顶。
fn GlrEngine::new(lexer : LexerEngine) -> GlrEngine {
  let sentinel : GssNode = { state: 0, links: [] }
  { gss_nodes: [sentinel], active_tops: [0], lexer }
}

///|
/// GLR 解析入口（Phase 2b — TODO: 主循环待实现，暂 fallback 至 parse_linear）
///
/// 当解析表不含冲突时，等价于 parse_linear；
/// 含冲突时并行展开所有 Shift / Reduce 路径。
pub fn glr_parse(
  table : @tablegen.ParseTable,
  input : String,
) -> Result[CstNode, ParseError] {
  // TODO Phase 2c: 实现 GSS 主循环（enum_paths + reduce worklist + shift）
  parse_linear(table, input)
}

///|
/// 在 candidate_tops 中查找 state 相同的结点；
/// 找到则追加 new_link（歧义合并），返回已有 GssRef；
/// 找不到则新建结点，推入 candidate_tops，返回新 GssRef。
///
/// candidate_tops：本轮 Shift/Reduce 正在构造的"下一步活跃集"
///（与 self.active_tops 不同——active_tops 是当前 token 的集合，
///  candidate_tops 是下一 token 的集合，在 shift 阶段逐步填充）
fn GlrEngine::find_or_merge(
  self : GlrEngine,
  state : Int,
  new_link : GssLink,
  candidate_tops : Array[GssRef],
) -> GssRef {
  // ── 在 candidate_tops 中线性扫描同 state 的结点 ─────────────────────────
  for r in candidate_tops {
    if self.gss_nodes[r].state == state {
      // 找到：追加入边（局部歧义合并），不新建结点
      self.gss_nodes[r].links.push(new_link)
      return r
    }
  }
  // ── 找不到：新建结点，加入 candidate_tops ───────────────────────────────
  let ref = self.gss_nodes.length()
  self.gss_nodes.push({ state, links: [new_link] })
  candidate_tops.push(ref)
  ref
}

///|
/// 从 from 结点沿入边向前回溯，枚举所有长度恰好为 len 的 CstNode? 序列。
///
/// 返回值：每个元素是一条完整路径，路径中第 0 项对应最靠近底部的边节点，
///         最后一项对应最靠近 from 的边节点（即左→右顺序，与产生式 body 对应）。
///
/// · len = 0 → 返回 [[]]（ε 产生式，空 body）
/// · len = k → 对 from 的每条入边 link，递归 enum_paths(link.predecessor, k-1)，
///             将 link.node 追加到每条子路径末尾
///
/// 注意：结果可能为多条（同一结点有多条入边时），这正是 GLR 并行性的体现。
fn GlrEngine::enum_paths(
  self : GlrEngine,
  from : GssRef,
  len : Int,
) -> Array[Array[CstNode?]] {
  // 基础情形：len = 0，返回包含一条空路径的列表
  if len == 0 {
    return [[]]
  }
  let results : Array[Array[CstNode?]] = []
  let node = self.gss_nodes[from]
  // 沿每条入边递归
  for link in node.links {
    let sub_paths = self.enum_paths(link.predecessor, len - 1)
    for path in sub_paths {
      // 复制子路径，追加当前边的节点（保持左→右顺序）
      let new_path = path.copy()
      new_path.push(link.node)
      results.push(new_path)
    }
  }
  results
}

///|
/// 从 GSS 结点反向收集状态路径（调试用）
///
/// 沿第一条入边回溯，返回从底部到 top 的状态序列。
fn GlrEngine::state_path(self : GlrEngine, top : GssRef) -> Array[Int] {
  let path : Array[Int] = []
  let mut cur = top
  while cur >= 0 && cur < self.gss_nodes.length() {
    let n = self.gss_nodes[cur]
    path.push(n.state)
    if n.links.is_empty() {
      break
    }
    cur = n.links[0].predecessor // 取第一条入边（歧义时有多条）
  }
  array_rev_inplace(path)
  path
}
