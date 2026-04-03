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
/// GLR 解析入口
///
/// 构造 GlrEngine，调用主循环 run，返回解析结果。
/// 当解析表不含冲突时，等价于 parse_linear；
/// 含冲突时并行展开所有 Shift / Reduce 路径。
pub fn glr_parse(
  table : @tablegen.ParseTable,
  input : String,
) -> Result[CstNode, ParseError] {
  let lexer = LexerEngine::new(table.lexer_dfa)
  let engine = GlrEngine::new(lexer)
  engine.run(table, input)
}

///|
/// GLR 主循环
///
/// 每轮：
///   1. EOF → run_reduce(eoi_id) → collect_root_glr
///   2. 合并所有活跃栈顶的 valid_tokens，调用 DFA 词法
///   3. extras token → 前进 pos，active_tops 不变（Phase 2b: 暂不追踪入 GSS）
///   4. 普通 token → run_reduce_worklist → run_shift → 替换 active_tops
fn GlrEngine::run(
  self : GlrEngine,
  table : @tablegen.ParseTable,
  input : String,
) -> Result[CstNode, ParseError] {
  let mut pos : Int = 0
  let mut cur_point : Point = { row: 0, column: 0 }
  while true {
    // ── EOF 检查 ──────────────────────────────────────────────────────────────
    if pos >= input.length() {
      self.run_reduce_worklist(table, @tablegen.eoi_id)
      return self.collect_root_glr(pos, cur_point)
    }

    // ── 计算所有活跃状态的合法 token 并集 ────────────────────────────────────
    // GLR 中多条路径处于同一位置，词法器需对所有路径的合法符号取并集，
    // 确保任意路径在当前位置认为合法的 token 都能被识别。
    let valid : Set[Int] = Set::new()
    for top_ref in self.active_tops {
      let state = self.gss_nodes[top_ref].state
      match table.lexer_dfa.valid_tokens.get(state) {
        Some(ts) => for t in ts { valid.add(t) }
        None => ()
      }
    }
    for t in table.extras {
      valid.add(t)
    }

    // ── 词法（直接调用 run_dfa，使用并集 valid 集合）─────────────────────────
    let (maybe_tok, new_pos) = self.lexer.run_dfa(input, pos, valid, table)
    match maybe_tok {
      None => {
        // pos < input.length() 但 DFA 无匹配：当做 EOF 处理
        self.run_reduce_worklist(table, @tablegen.eoi_id)
        return self.collect_root_glr(pos, cur_point)
      }
      Some(tok) => {
        // ── 词法错误 ──────────────────────────────────────────────────────────
        if tok.terminal_id == sym_error {
          return Err({
            position: tok.start_byte,
            point: cur_point,
            message: "lexer error: unrecognized character at byte \{tok.start_byte}",
          })
        }

        // ── Extras token：前进 pos，active_tops 不变 ─────────────────────────
        // Phase 2b 限制：extras 节点暂不追踪进 GSS，不出现在 GLR 路径中。
        // GLR CST 中 extras 的完整支持留待 Phase 3 补充。
        if tok.is_extra {
          cur_point = bytes_to_point(
            input, tok.start_byte, cur_point, tok.end_byte,
          )
          pos = new_pos
          continue
        }

        // ── 普通 token：Reduce 到不动点，再 Shift ────────────────────────────
        self.run_reduce_worklist(table, tok.terminal_id)
        let next_tops = self.run_shift(table, tok, cur_point, input)
        if next_tops.is_empty() {
          return Err({
            position: tok.start_byte,
            point: cur_point,
            message: "syntax error: unexpected token (id=\{tok.terminal_id}) at byte \{tok.start_byte}",
          })
        }

        // ── 替换 active_tops（原地清空 + 填入 next_tops）────────────────────
        while not(self.active_tops.is_empty()) {
          let _ = self.active_tops.pop()
        }
        for r in next_tops {
          self.active_tops.push(r)
        }
        cur_point = bytes_to_point(
          input, tok.start_byte, cur_point, tok.end_byte,
        )
        pos = new_pos
      }
    }
  }
  // 理论上不可达（while true 内所有路径均 return 或 continue）
  Err({ position: 0, point: { row: 0, column: 0 }, message: "unreachable" })
}

///|
/// Accept 时从活跃集中寻找根节点（Phase 2b 存根，Step 7 实现）
fn GlrEngine::collect_root_glr(
  self : GlrEngine,
  pos : Int,
  cur_pt : Point,
) -> Result[CstNode, ParseError] {
  // TODO Step 7: 找 action[(s, eoi)] = Accept 的活跃栈顶，沿路径取根 CstNode
  ignore(self)
  Err({ position: pos, point: cur_pt, message: "collect_root_glr: not yet implemented" })
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
/// Shift 阶段：Reduce 到不动点后，对当前活跃栈顶执行所有 Shift 动作。
///
/// 算法：
///   1. 对 active_tops 中每个结点，查 action[(state, tok.terminal_id)] 中的 Shift(s)
///   2. 用同一个叶节点 leaf（所有路径共享同一 token，不必复制）
///   3. find_or_merge(s, {predecessor: top, node: leaf}) 写入 next_tops
///   4. 返回 next_tops（主循环替换 active_tops）和新的 pos / cur_point
///
/// extras token 不走本函数，由主循环在 Shift 前单独处理：
///   extras 直接追加叶节点到 pending_extras 中，active_tops 不变。
///
/// 返回 next_tops：若为空则表示当前 token 无任何 Shift 动作（潜在语法错误）。
fn GlrEngine::run_shift(
  self : GlrEngine,
  table : @tablegen.ParseTable,
  tok : Token,
  cur_point : Point,
  input : String,
) -> Array[GssRef] {
  let next_tops : Array[GssRef] = []

  // 构造叶节点（所有 Shift 路径共享同一 token，CstNode 不可变可安全共享）
  let ep = bytes_to_point(input, tok.start_byte, cur_point, tok.end_byte)
  let leaf = CstNode::leaf(
    tok.terminal_id,
    false,
    tok.start_byte,
    tok.end_byte,
    cur_point,
    ep,
    0,              // parse_state：GLR 暂置 0（增量复用 Phase 3a 补充）
    tok.lookahead_bytes,
    tok.is_keyword,
    false,
  )

  // 对每个活跃栈顶，收集所有 Shift 动作
  for top_ref in self.active_tops {
    let state = self.gss_nodes[top_ref].state
    match table.action.get((state, tok.terminal_id)) {
      None => ()
      Some(acts) =>
        for act in acts {
          match act {
            Shift(next_state) => {
              let link : GssLink = { predecessor: top_ref, node: Some(leaf) }
              let _ = self.find_or_merge(next_state, link, next_tops)
            }
            _ => ()
          }
        }
    }
  }
  next_tops
}

///|
/// Reduce worklist 阶段：对活跃栈顶集合执行所有可能的 Reduce 动作至不动点。
///
/// 算法（Tomita 风格 worklist）：
///   1. 将 active_tops 中每个结点对 (top, prod_id) 放入 worklist
///   2. 每次取出一个 (top, prod_id)：
///      a. enum_paths(top, |body|) 得到所有子节点列表
///      b. 对每条路径，取路径起点（base）的前驱结点作为 base_state 来源
///      c. 查 goto[base_state, head] 得目标状态
///      d. 构造 CstNode::inner，find_or_merge 合入 active_tops
///      e. 若是新结点或新加了边 → 该新 top 的 Reduce 也须入队
///   3. worklist 空 → Reduce 到不动点
///
/// tok_id  : 当前前瞻 token 的 TerminalId（用于查 action 表，EOF 传 eoi_id）
/// active_tops 原地扩展（新 Reduce 结果追加到同一集合中）
fn GlrEngine::run_reduce_worklist(
  self : GlrEngine,
  table : @tablegen.ParseTable,
  tok_id : Int,
) -> Unit {
  // worklist 中每项 = (栈顶 GssRef, 产生式 ProductionId)
  let worklist : Array[(GssRef, Int)] = []

  // ── 初始化：把 active_tops 上所有 Reduce 动作入队 ─────────────────────────
  fn enqueue_reduces(top : GssRef) -> Unit {
    let state = self.gss_nodes[top].state
    match table.action.get((state, tok_id)) {
      None => ()
      Some(acts) =>
        for act in acts {
          match act {
            Reduce(pid) => worklist.push((top, pid))
            _ => ()
          }
        }
    }
  }

  // 注意：active_tops 在处理过程中可能扩展，用下标遍历以涵盖新加入的顶点
  let mut i = 0
  while i < self.active_tops.length() {
    enqueue_reduces(self.active_tops[i])
    i = i + 1
  }

  // ── 主循环：处理 worklist 直到空 ─────────────────────────────────────────
  let mut wi = 0
  while wi < worklist.length() {
    let (top, prod_id) = worklist[wi]
    wi = wi + 1

    let prod = table.productions[prod_id]
    let body_len = prod.body.length()

    // 枚举所有长度为 body_len 的路径
    let paths = self.enum_paths(top, body_len)
    for path in paths {
      // path[0..body_len-1] 是子节点列表（CstNode?）
      // path 起点之前的那个结点是"归约之后的栈顶"候选的前驱
      // 找到路径起点的前驱：沿 links 走 body_len 步到达的那个结点
      // enum_paths 返回路径末端是 top，头部是 body_len 步之前的边，
      // 头部结点的 predecessor 就是 base（归约后 goto 的来源）。
      //
      // 更直接做法：沿 top 的 links 深度优先走 body_len 步取到 base_ref
      // enum_paths 中 len=0 时对应 base，base_ref = 走完所有边后剩余结点。
      // 我们单独再走一次链来取 base_ref。
      let base_ref = self.walk_base(top, body_len)
      let base_state = self.gss_nodes[base_ref].state

      // 查 goto 表
      let nt = prod.head
      match table.goto_table.get((base_state, nt)) {
        None => () // goto 缺失 → 跳过（不应发生于合法语法）
        Some(goto_st) => {
          // 构造内部节点
          let children : Array[CstNode] = []
          for maybe_node in path {
            match maybe_node {
              Some(n) => children.push(n)
              None => () // 底部哨兵边，不产生子节点
            }
          }
          let meta : @tablegen.SymbolMeta = if nt <
            table.symbol_metadata.length() {
            table.symbol_metadata[nt]
          } else {
            { name: "?", is_named: false }
          }
          let fnames : Array[String?] = prod.body.map(fn(bs) { bs.field_name })
          let inner = CstNode::inner(
            nt,
            meta.is_named,
            children,
            fnames,
            prod.id,
            0,
            true, // fragile = true（GLR 合并结果，不可增量复用）
          )
          let new_link : GssLink = { predecessor: base_ref, node: Some(inner) }
          let prev_len = self.active_tops.length()
          let merged_ref = self.find_or_merge(
            goto_st,
            new_link,
            self.active_tops,
          )
          // 若是新结点（active_tops 扩展了）或新加了边
          // → 该结点上的 Reduce 也需入队（不动点条件）
          let is_new_node = self.active_tops.length() > prev_len
          let is_new_link = not(is_new_node) &&
            self.gss_nodes[merged_ref].links.length() > 1
          if is_new_node || is_new_link {
            enqueue_reduces(merged_ref)
          }
        }
      }
    }
  }
}

///|
/// 从 top 沿第一条入边向前走 steps 步，返回到达的 GssRef（base 结点）。
///
/// 注意：GLR 中同一结点可能有多条入边，此函数只沿第一条边走（用于非歧义路径）。
/// 歧义情形由 enum_paths 全量枚举，walk_base 仅用于单路径情形。
fn GlrEngine::walk_base(self : GlrEngine, from : GssRef, steps : Int) -> GssRef {
  let mut cur = from
  let mut s = steps
  while s > 0 {
    let node = self.gss_nodes[cur]
    if node.links.is_empty() {
      break
    }
    cur = node.links[0].predecessor
    s = s - 1
  }
  cur
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
