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
/// predecessor    : 前驱结点的 GssRef
/// node           : 跨越该边时产生的 CST 节点
///                    · Shift  边：叶节点（token）
///                    · Reduce 边：内部节点（产生式归约结果）
///                    · 底部哨兵边：None（初始结点无前驱）
/// leading_extras : Shift 前积累的 extras 节点（空白/注释）；Reduce 边为空。
///                  extras 不占 LR body slot，由 enum_paths 将其插入产生式子节点序列。
struct GssLink {
  predecessor : GssRef
  node : CstNode?
  leading_extras : Array[CstNode]
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
  // extras token 在 Shift 前积累，在下一次普通 token Shift 时附加到 GssLink。
  // extras 不改变 LR 状态，故不影响 active_tops，但需出现在最终 CST 中。
  let pending_extras : Array[CstNode] = []
  while true {
    // ── EOF 检查 ──────────────────────────────────────────────────────────────
    if pos >= input.length() {
      self.run_reduce_worklist(table, @tablegen.eoi_id)
      return self.collect_root_glr(table, pos, cur_point)
    }

    // ── 计算所有活跃状态的合法 token 并集 ────────────────────────────────────
    // GLR 中多条路径处于同一位置，词法器需对所有路径的合法符号取并集，
    // 确保任意路径在当前位置认为合法的 token 都能被识别。
    let valid : Set[Int] = Set::new()
    for top_ref in self.active_tops {
      let state = self.gss_nodes[top_ref].state
      match table.lexer_dfa.valid_tokens.get(state) {
        Some(ts) =>
          for t in ts {
            valid.add(t)
          }
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
        return self.collect_root_glr(table, pos, cur_point)
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

        // ── Extras token：创建叶节点，积累到 pending_extras ──────────────────
        // extras 不改变 LR 状态，但需出现在 CST 中。
        // 此处创建叶节点并推入 pending_extras；下次普通 Shift 时通过
        // GssLink.leading_extras 携带，enum_paths 将其插入产生式子节点序列。
        if tok.is_extra {
          let ep = bytes_to_point(
            input,
            tok.start_byte,
            cur_point,
            tok.end_byte,
          )
          let extra_node = CstNode::leaf(
            tok.terminal_id,
            false,
            tok.start_byte,
            tok.end_byte,
            cur_point,
            ep,
            0,
            tok.lookahead_bytes,
            tok.is_keyword,
            true,
          )
          cur_point = ep
          pending_extras.push(extra_node)
          pos = new_pos
          continue
        }

        // ── 普通 token：Reduce 到不动点，再 Shift ────────────────────────────
        self.run_reduce_worklist(table, tok.terminal_id)
        let next_tops = self.run_shift(
          table, tok, cur_point, input, pending_extras,
        )
        // pending_extras 已由 run_shift 复制到每条 GssLink，此处清空
        while not(pending_extras.is_empty()) {
          let _ = pending_extras.pop()
        }
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
          input,
          tok.start_byte,
          cur_point,
          tok.end_byte,
        )
        pos = new_pos
      }
    }
  }
  // 理论上不可达（while true 内所有路径均 return 或 continue）
  Err({ position: 0, point: { row: 0, column: 0 }, message: "unreachable" })
}

///|
/// Accept 时从活跃集中寻找根节点
///
/// 算法：
///   遍历 active_tops，对每个结点检查 action[(state, eoi_id)]：
///     · Shift(s_acc) 且 s_acc 有 Accept（即 $accept → start • $ 状态）
///                            → 根节点在该结点的入边（links）上
///
///   为什么只处理 Shift(s_acc) 而不直接检查 Accept：
///     LALR 增广文法结构为 $accept → start $。run_reduce_worklist(eoi_id)
///     产生 [$accept → start • $] 状态的 active_top，该状态对 eoi 的动作是
///     Shift(s_acc)，只有 s_acc 才有 Accept。当前 active_top 自身永远不持有
///     Accept，Case 1（直接 Accept）是死代码，故已删除。
///
///   多路径（歧义）：Phase 2b 返回第一条；Phase 2c 改为 AmbiguityNode。
fn GlrEngine::collect_root_glr(
  self : GlrEngine,
  table : @tablegen.ParseTable,
  pos : Int,
  cur_pt : Point,
) -> Result[CstNode, ParseError] {
  for top_ref in self.active_tops {
    let state = self.gss_nodes[top_ref].state
    match table.action.get((state, @tablegen.eoi_id)) {
      None => ()
      Some(acts) =>
        for act in acts {
          match act {
            // Shift(s_acc) 且 s_acc 有 Accept：
            //   对应 [$accept → start • $] 状态，入边携带 start 的 CstNode
            Shift(s_acc) =>
              match table.action.get((s_acc, @tablegen.eoi_id)) {
                None => ()
                Some(acc_acts) => {
                  let mut is_accept = false
                  for a2 in acc_acts {
                    match a2 {
                      Accept => {
                        is_accept = true
                        break
                      }
                      _ => ()
                    }
                  }
                  if is_accept {
                    for link in self.gss_nodes[top_ref].links {
                      match link.node {
                        Some(n) => return Ok(n)
                        None => ()
                      }
                    }
                  }
                }
              }
            Accept | Reduce(_) => () // Accept 不在此处触发；Reduce 已由 worklist 处理
          }
        }
    }
  }
  Err({ position: pos, point: cur_pt, message: "accept: no root node" })
}

///|
/// 在 candidate_tops 中查找 state 相同的结点；
/// 找到则尝试追加 new_link（歧义合并），返回 (已有 GssRef, link_added)；
/// 找不到则新建结点，推入 candidate_tops，返回 (新 GssRef, true)。
///
/// link_added：true = 实际发生了新建结点或新增了入边（调用方据此决定是否重入队）
///             false = same predecessor 已存在，跳过（防止无限循环）
///
/// 重复前驱检测：若 candidate_tops 中已有 state 相同的结点，且该结点已有一条
/// predecessor == new_link.predecessor 的入边，则不再追加（Phase 2b 保留首条）。
/// 这防止了同一路径被反复归约、worklist 无限增长的问题。
fn GlrEngine::find_or_merge(
  self : GlrEngine,
  state : Int,
  new_link : GssLink,
  candidate_tops : Array[GssRef],
) -> (GssRef, Bool) {
  // ── 在 candidate_tops 中线性扫描同 state 的结点 ─────────────────────────
  for r in candidate_tops {
    if self.gss_nodes[r].state == state {
      // 检查是否已存在相同前驱（避免重复添加）
      let mut dup = false
      for existing in self.gss_nodes[r].links {
        if existing.predecessor == new_link.predecessor {
          dup = true
          break
        }
      }
      if dup {
        return (r, false) // 重复前驱：不追加，不触发重入队
      }
      // 新前驱：追加入边（局部歧义合并）
      self.gss_nodes[r].links.push(new_link)
      return (r, true)
    }
  }
  // ── 找不到：新建结点，加入 candidate_tops ───────────────────────────────
  let new_ref = self.gss_nodes.length()
  self.gss_nodes.push({ state, links: [new_link] })
  candidate_tops.push(new_ref)
  (new_ref, true)
}

///|
/// 从 from 结点沿入边向前回溯，枚举所有长度恰好为 len 的路径。
///
/// 返回值：每个元素是 (base_ref, path)：
///   · base_ref：沿该路径走完 len 步后所在的 GSS 结点（用于查 goto 表）
///   · path：CstNode? 序列，第 0 项对应最靠近底部的边节点，
///           最后一项对应最靠近 from 的边节点（左→右顺序，与产生式 body 对应）
///
/// · len = 0 → 返回 [(from, [])]（ε 产生式，base 就是 from 自身）
/// · len = k → 对 from 的每条入边 link，递归 enum_paths(link.predecessor, k-1)，
///             将 link.node 追加到每条子路径末尾，base_ref 继承自子路径
///
/// 注意：结果可能为多条（同一结点有多条入边时），这正是 GLR 并行性的体现。
/// 每条路径携带各自的 base_ref，替代原来单独调用的 walk_base。
fn GlrEngine::enum_paths(
  self : GlrEngine,
  from : GssRef,
  len : Int,
) -> Array[(GssRef, Array[CstNode?])] {
  // 基础情形：len = 0，base 就是当前结点 from，路径为空
  if len == 0 {
    return [(from, [])]
  }
  let results : Array[(GssRef, Array[CstNode?])] = []
  let node = self.gss_nodes[from]
  // 沿每条入边递归
  for link in node.links {
    let sub_paths = self.enum_paths(link.predecessor, len - 1)
    for item in sub_paths {
      let (base, path) = item
      // 复制子路径：先追加 leading_extras（shift 前积累的 extras），再追加主节点
      let new_path = path.copy()
      for ex in link.leading_extras {
        new_path.push(Some(ex))
      }
      new_path.push(link.node)
      results.push((base, new_path))
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
///   extras 创建叶节点后存入 pending_extras，随本次 Shift 的 GssLink 一起传入。
///
/// 返回 next_tops：若为空则表示当前 token 无任何 Shift 动作（潜在语法错误）。
fn GlrEngine::run_shift(
  self : GlrEngine,
  table : @tablegen.ParseTable,
  tok : Token,
  cur_point : Point,
  input : String,
  pending_extras : Array[CstNode],
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
    0, // parse_state：GLR 暂置 0（增量复用 Phase 3a 补充）
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
              let link : GssLink = {
                predecessor: top_ref,
                node: Some(leaf),
                // 将 pending_extras 复制到每条 Shift 边；
                // enum_paths 归约时会把它们插入产生式子节点序列
                leading_extras: pending_extras.copy(),
              }
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

  // 初始化：把 worklist 启动前已在 active_tops 里的结点的 Reduce 动作全部入队。
  // 说明：此处只枚举启动时已有的顶点。运行过程中 find_or_merge 新建或扩展的结点
  // 由主循环末尾的 enqueue_reduces(merged_ref) 负责入队，两者协作才覆盖所有路径。
  let mut i = 0
  let initial_tops_len = self.active_tops.length()
  while i < initial_tops_len {
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

    // 枚举所有长度为 body_len 的路径，同时得到每条路径的 base 结点
    // （base = 沿路径走完 body_len 步后所在的 GSS 结点，即 goto 查找的来源）
    let paths = self.enum_paths(top, body_len)
    for path_item in paths {
      let (base_ref, path) = path_item
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
          let new_link : GssLink = {
            predecessor: base_ref,
            node: Some(inner),
            leading_extras: [], // Reduce 边不携带 extras（extras 仅在 Shift 边）
          }
          let (merged_ref, link_added) = self.find_or_merge(
            goto_st,
            new_link,
            self.active_tops,
          )
          // 仅当实际新建结点或新增了入边时，才将该结点的 Reduce 入队
          // find_or_merge 返回 false = 重复前驱（已有相同路径），不触发重入队
          if link_added {
            enqueue_reduces(merged_ref)
          }
        }
      }
    }
  }
}

// walk_base 已由 enum_paths 携带的 base_ref 替代，不再需要。

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
