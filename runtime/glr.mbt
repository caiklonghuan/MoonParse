///|
// GLR 解析引擎
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
  /// 各活跃版本的代价记录（GssRef → ErrorStatus）
  /// skip_token / insert_missing 等恢复策略在此累积代价；
  /// condense_stack 据此剪枝超限版本。
  error_status : Map[GssRef, ErrorStatus]
  // 增量复用上下文（None = 非增量全量解析）
  old_tree : OldTree?
  byte_delta : Int // new_end_byte - old_end_byte（常数，整个 parse 期间不变）
  edit_start : Int // 编辑起始字节（旧输入坐标，is_reusable 的边界检查）
  new_end_byte : Int // 编辑结束字节（新输入坐标，坐标换算的分界线）
  old_end_point : Point // 编辑末点（旧坐标，Point 偏移的行列分界线）
  row_delta : Int // new_end_point.row    - old_end_point.row
  col_delta : Int // new_end_point.column - old_end_point.column
}

///|
/// 初始化 GLR 引擎
///
/// 创建唯一底部哨兵结点（state=0, links=[]），并将其设为唯一活跃栈顶。
fn GlrEngine::new(lexer : LexerEngine) -> GlrEngine {
  let sentinel : GssNode = { state: 0, links: [] }
  {
    gss_nodes: [sentinel],
    active_tops: [0],
    lexer,
    error_status: Map::new(),
    old_tree: None,
    byte_delta: 0,
    edit_start: 0,
    new_end_byte: 0,
    old_end_point: { row: 0, column: 0 },
    row_delta: 0,
    col_delta: 0,
  }
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
/// EOF → run_reduce(eoi_id) → collect_root_glr
/// 合并所有活跃栈顶的 valid_tokens，调用 DFA 词法
/// extras token → 创建叶节点累积到 pending_extras，active_tops 不变
/// 普通 token → run_reduce_worklist → run_shift → 替换 active_tops → compact Arena
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
    // EOF 检查
    if pos >= input.length() {
      self.run_reduce_worklist(table, @tablegen.eoi_id)
      return self.collect_root_glr(table, pos, cur_point)
    }

    // 计算所有活跃状态的合法 token 并集
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

    // 词法（直接调用 run_dfa，使用并集 valid 集合）
    let (maybe_tok, new_pos) = self.lexer.run_dfa(input, pos, valid, table)
    match maybe_tok {
      None => {
        // pos < input.length() 但 DFA 无匹配：当做 EOF 处理
        self.run_reduce_worklist(table, @tablegen.eoi_id)
        return self.collect_root_glr(table, pos, cur_point)
      }
      Some(tok) => {
        // 词法错误：先尝试 insert_missing_and_relex（插入缺失 token 后重词法）；
        // 失败再降级到 skip
        if tok.terminal_id == sym_error {
          let (ok, new_pos2, new_point2) = self.insert_missing_and_relex(
            table, pos, cur_point, input,
          )
          if ok {
            self.compact(self.active_tops)
            self.condense_stack()
            cur_point = new_point2
            pos = new_pos2
            continue
          }
          self.skip_token(tok, cur_point, input)
          cur_point = bytes_to_point(
            input,
            tok.start_byte,
            cur_point,
            tok.end_byte,
          )
          pos = new_pos
          continue
        }

        // Extras token：创建叶节点，积累到 pending_extras
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

        // 普通 token：Reduce 到不动点，再 Shift
        self.run_reduce_worklist(table, tok.terminal_id)
        let next_tops = self.run_shift(
          table, tok, cur_point, input, pending_extras,
        )
        // pending_extras 已由 run_shift 复制到每条 GssLink，此处清空
        while not(pending_extras.is_empty()) {
          let _ = pending_extras.pop()
        }
        if next_tops.is_empty() {
          // 先尝试 insert_missing（插入虚拟 token，代价 610）；
          // 再尝试 recover_to_state（回退到可接受当前 token 的祖先状态）；
          // 最后降级到 skip_token（跳过当前 token，代价 601+）
          if self.insert_missing(table, tok, cur_point, input) {
            self.compact(self.active_tops)
            self.condense_stack()
            cur_point = bytes_to_point(
              input,
              tok.start_byte,
              cur_point,
              tok.end_byte,
            )
            pos = new_pos
            continue
          }
          if self.recover_to_state(table, tok, cur_point, input) {
            self.compact(self.active_tops)
            self.condense_stack()
            cur_point = bytes_to_point(
              input,
              tok.start_byte,
              cur_point,
              tok.end_byte,
            )
            pos = new_pos
            continue
          }
          // 降级：skip 当前 token，为所有活跃路径创建 ERROR 停留路径
          self.skip_token(tok, cur_point, input)
          cur_point = bytes_to_point(
            input,
            tok.start_byte,
            cur_point,
            tok.end_byte,
          )
          pos = new_pos
          continue
        }

        // 替换 active_tops（原地清空 + 填入 next_tops）
        while not(self.active_tops.is_empty()) {
          let _ = self.active_tops.pop()
        }
        for r in next_tops {
          self.active_tops.push(r)
        }
        // compact：回收当前 active_tops 不可达的旧 GssNode，防止 Arena 线性增长。
        // 必须在 active_tops 已切换为 next_tops 之后调用，确保旧前缀结点都已成为垃圾。
        self.compact(self.active_tops)
        // condense：GLR 并行路径过多时按代价截尾，防止版本数无限增长。
        self.condense_stack()
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
///   多路径（歧义）：当前返回第一条可接受路径。
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
/// predecessor == new_link.predecessor 的入边，则不再追加（保留首条）。
/// 这防止了同一路径被反复归约、worklist 无限增长的问题。
fn GlrEngine::find_or_merge(
  self : GlrEngine,
  state : Int,
  new_link : GssLink,
  candidate_tops : Array[GssRef],
) -> (GssRef, Bool) {
  // 在 candidate_tops 中线性扫描同 state 的结点
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
  // 找不到：新建结点，加入 candidate_tops
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
/// 对 active_tops 中每个结点，查 action[(state, tok.terminal_id)] 中的 Shift(s)
/// 用同一个叶节点 leaf（所有路径共享同一 token，不必复制）
/// find_or_merge(s, {predecessor: top, node: leaf}) 写入 next_tops
/// 返回 next_tops（主循环替换 active_tops）和新的 pos / cur_point
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

  // ep 从 tok 和 cur_point 计算，各路径相同；leaf 在循环内按栈顶 state 分别构造，
  // 保证 parse_state 正确（单路径无歧义时内部节点非 fragile，leaf 可增量复用）。
  let ep = bytes_to_point(input, tok.start_byte, cur_point, tok.end_byte)

  // 对每个活跃栈顶，收集所有 Shift 动作
  for top_ref in self.active_tops {
    let state = self.gss_nodes[top_ref].state
    match table.action.get((state, tok.terminal_id)) {
      None => ()
      Some(acts) =>
        for act in acts {
          match act {
            Shift(next_state) => {
              // 增量复用：各路径独立查找旧树中的可复用节点。
              // 将新坐标转换为旧树坐标，调用 find_reusable_node 。
              // 仅当旧节点字节偏移后与 tok 跨度一致时才复用（保证 symbol/span 对齐）。
              let leaf = match self.old_tree {
                Some(ot) => {
                  let search_pos = if tok.start_byte < self.new_end_byte {
                    tok.start_byte
                  } else {
                    tok.start_byte - self.byte_delta
                  }
                  match
                    find_reusable_node(ot, search_pos, state, self.edit_start) {
                    Some(old_node) =>
                      if old_node.end_byte + self.byte_delta == tok.end_byte {
                        // 同跨度复用：字节和行列坐标同时校正
                        shift_node(
                          old_node,
                          self.byte_delta,
                          self.old_end_point,
                          self.row_delta,
                          self.col_delta,
                        )
                      } else {
                        CstNode::leaf(
                          tok.terminal_id,
                          false,
                          tok.start_byte,
                          tok.end_byte,
                          cur_point,
                          ep,
                          state,
                          tok.lookahead_bytes,
                          tok.is_keyword,
                          false,
                        )
                      }
                    None =>
                      CstNode::leaf(
                        tok.terminal_id,
                        false,
                        tok.start_byte,
                        tok.end_byte,
                        cur_point,
                        ep,
                        state,
                        tok.lookahead_bytes,
                        tok.is_keyword,
                        false,
                      )
                  }
                }
                None =>
                  CstNode::leaf(
                    tok.terminal_id,
                    false,
                    tok.start_byte,
                    tok.end_byte,
                    cur_point,
                    ep,
                    state, // parse_state：当前栈顶 LR 状态
                    tok.lookahead_bytes,
                    tok.is_keyword,
                    false,
                  )
              }
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
/// Skip 恢复策略：把无法 Shift 的当前 token 包进 ERROR 节点，
/// 为每个活跃栈顶创建「停留路径」（目标 state = 来源 state），令解析继续推进。
///
/// · 首次进入恢复时追加固定惩罚 error_cost_per_recovery（防频繁触发恢复）
/// · 本次跳过的 token 代价由 error_cost_for_skipped_node 计算
/// · 多条路径合并到同一 GssRef 时，保留代价更低的 ErrorStatus
fn GlrEngine::skip_token(
  self : GlrEngine,
  tok : Token,
  cur_point : Point,
  input : String,
) -> Unit {
  // 构造被跳过 token 的叶节点，包进单子 ERROR 节点
  let ep = bytes_to_point(input, tok.start_byte, cur_point, tok.end_byte)
  let raw_leaf = CstNode::leaf(
    tok.terminal_id,
    false,
    tok.start_byte,
    tok.end_byte,
    cur_point,
    ep,
    0,
    tok.lookahead_bytes,
    tok.is_keyword,
    false,
  )
  let error_node = CstNode::error_node(
    [raw_leaf],
    tok.start_byte,
    tok.end_byte,
    cur_point,
    ep,
  )
  let new_tops : Array[GssRef] = []
  for top_ref in self.active_tops {
    let state = self.gss_nodes[top_ref].state
    let link : GssLink = {
      predecessor: top_ref,
      node: Some(error_node),
      leading_extras: [],
    }
    let (merged_ref, _) = self.find_or_merge(state, link, new_tops)
    // 以 top_ref 的 ErrorStatus 为基础，累加本次跳过的代价
    let old_status = self.error_status.get(top_ref)
    let base_cost = match old_status {
      Some(s) => s.cost
      None => 0
    }
    let is_first_error = match old_status {
      Some(s) => not(s.is_in_error)
      None => true
    }
    let skip_cost = error_cost_for_skipped_node(error_node)
    let recovery_penalty = if is_first_error {
      error_cost_per_recovery
    } else {
      0
    }
    let new_cost = base_cost + recovery_penalty + skip_cost
    // 多路径合并：保留代价更低的 ErrorStatus
    let existing_cost = match self.error_status.get(merged_ref) {
      Some(s) => s.cost
      None => 1_000_000
    }
    if new_cost < existing_cost {
      self.error_status[merged_ref] = {
        cost: new_cost,
        node_count: 0,
        dynamic_precedence: 0,
        is_in_error: true,
      }
    }
  }
  // 以停留路径替换 active_tops
  while not(self.active_tops.is_empty()) {
    let _ = self.active_tops.pop()
  }
  for r in new_tops {
    self.active_tops.push(r)
  }
}

///|
/// Insert-Missing 恢复策略：为无法 Shift 的当前 token，
/// 在各活跃路径的合法 terminal 位置插入虚拟 MISSING 节点，
/// 使解析能够继续推进并消费当前 token。
///
/// 算法：
///   对 active_tops 中每个 top_ref：
///     · 枚举 valid_tokens[state] 中所有可 Shift 的 terminal tid（跳过 extras/eoi/error）
///     · 对每个 Shift(next_state) 动作：
///         1. 构造 missing_leaf(tid, byte_pos, cur_point)（零宽，is_missing=true）
///         2. 以 missing_leaf 为边节点新建 GssNode(next_state)
///         3. 以该节点为临时 active_top，对 actual_tok 做 Reduce→Shift 模拟
///         4. 若 Shift 成功 → 收集 result_tops，记录代价
///   result_tops 非空 → 更新 active_tops → 返回 true
///   全部失败   → 还原 active_tops → 返回 false
///
/// 代价 = base_cost
///        + error_cost_per_recovery(500)（首次进入恢复）
///        + error_cost_per_missing_tree(110)
fn GlrEngine::insert_missing(
  self : GlrEngine,
  table : @tablegen.ParseTable,
  actual_tok : Token,
  cur_point : Point,
  input : String,
) -> Bool {
  let byte_pos = actual_tok.start_byte
  let saved_tops = self.active_tops.copy()
  let result_tops : Array[GssRef] = []
  let result_costs : Array[(GssRef, Int)] = []
  for top_ref in saved_tops {
    let state = self.gss_nodes[top_ref].state
    match table.lexer_dfa.valid_tokens.get(state) {
      None => ()
      Some(valid_tids) => {
        let (base_cost, is_first_error) = match self.error_status.get(top_ref) {
          Some(s) => (s.cost, not(s.is_in_error))
          None => (0, true)
        }
        for tid in valid_tids {
          // 跳过 eoi、词法 error 符号、extras（这些不能作为 missing 插入）
          if tid == @tablegen.eoi_id || tid == sym_error {
            continue
          }
          let mut is_extra = false
          for et in table.extras {
            if et == tid {
              is_extra = true
              break
            }
          }
          if is_extra {
            continue
          }
          // 枚举该 terminal 的所有 Shift 动作
          match table.action.get((state, tid)) {
            None => ()
            Some(acts) =>
              for act in acts {
                match act {
                  Shift(next_state) => {
                    // 构造零宽 MISSING 叶节点
                    let is_named = if tid < table.symbol_metadata.length() {
                      table.symbol_metadata[tid].is_named
                    } else {
                      false
                    }
                    let missing = CstNode::missing_leaf(
                      tid, is_named, byte_pos, cur_point,
                    )
                    let link : GssLink = {
                      predecessor: top_ref,
                      node: Some(missing),
                      leading_extras: [],
                    }
                    // 新建「missing 后」状态的 GssNode，临时压入 active_tops
                    let new_ref = self.gss_nodes.length()
                    self.gss_nodes.push({ state: next_state, links: [link] })
                    while not(self.active_tops.is_empty()) {
                      let _ = self.active_tops.pop()
                    }
                    self.active_tops.push(new_ref)
                    // 模拟：以真实 token 为前瞻做 Reduce 到不动点，再尝试 Shift
                    self.run_reduce_worklist(table, actual_tok.terminal_id)
                    let shifted = self.run_shift(
                      table,
                      actual_tok,
                      cur_point,
                      input,
                      [],
                    )
                    if not(shifted.is_empty()) {
                      let new_cost = base_cost +
                        (if is_first_error {
                          error_cost_per_recovery
                        } else {
                          0
                        }) +
                        error_cost_per_missing_tree
                      for r in shifted {
                        result_tops.push(r)
                        result_costs.push((r, new_cost))
                      }
                    }
                  }
                  _ => ()
                }
              }
          }
        }
      }
    }
  }
  // 无论成败都先清空 active_tops，再按结果填入
  while not(self.active_tops.is_empty()) {
    let _ = self.active_tops.pop()
  }
  if result_tops.is_empty() {
    // 全部失败：还原
    for r in saved_tops {
      self.active_tops.push(r)
    }
    return false
  }
  // 成功：对 result_tops 按 GssRef 去重后填入 active_tops
  let seen : Array[GssRef] = []
  for r in result_tops {
    let mut dup = false
    for s in seen {
      if s == r {
        dup = true
        break
      }
    }
    if not(dup) {
      seen.push(r)
      self.active_tops.push(r)
    }
  }
  // 写入 error_status（多路径合并时取代价更低者）
  for item in result_costs {
    let (r, new_cost) = item
    let existing = match self.error_status.get(r) {
      Some(s) => s.cost
      None => 1_000_000
    }
    if new_cost < existing {
      self.error_status[r] = {
        cost: new_cost,
        node_count: 0,
        dynamic_precedence: 0,
        is_in_error: false, // 成功插入并推进，退出错误模式
      }
    }
  }
  true
}

///|
/// Insert-Missing + 重词法策略：用于 sym_error 情形（词法层失败）。
///
/// 与 insert_missing 的区别：
///   insert_missing 使用**已知 actual_tok** 做内部 Reduce→Shift 模拟；
///   本函数在插入 MISSING 后重新计算 valid 集合并重新 lex，
///   用于当前字符无法匹配当前 valid set（但可能匹配 missing_after 状态的 valid set）。
///
/// 返回 (succeeded, new_pos, new_cur_point)。
/// succeeded=true 时 active_tops 已更新为 post-shift 状态。
fn GlrEngine::insert_missing_and_relex(
  self : GlrEngine,
  table : @tablegen.ParseTable,
  pos : Int,
  cur_point : Point,
  input : String,
) -> (Bool, Int, Point) {
  let saved_tops = self.active_tops.copy()
  let result_tops : Array[GssRef] = []
  let result_costs : Array[(GssRef, Int)] = []
  let mut result_new_pos = pos
  let mut result_new_point = cur_point
  for top_ref in saved_tops {
    let state = self.gss_nodes[top_ref].state
    match table.lexer_dfa.valid_tokens.get(state) {
      None => ()
      Some(valid_tids) => {
        let (base_cost, is_first_error) = match self.error_status.get(top_ref) {
          Some(s) => (s.cost, not(s.is_in_error))
          None => (0, true)
        }
        for tid in valid_tids {
          if tid == @tablegen.eoi_id || tid == sym_error {
            continue
          }
          let mut is_extra = false
          for et in table.extras {
            if et == tid {
              is_extra = true
              break
            }
          }
          if is_extra {
            continue
          }
          match table.action.get((state, tid)) {
            None => ()
            Some(acts) =>
              for act in acts {
                match act {
                  Shift(next_state) => {
                    let is_named = if tid < table.symbol_metadata.length() {
                      table.symbol_metadata[tid].is_named
                    } else {
                      false
                    }
                    let missing = CstNode::missing_leaf(
                      tid, is_named, pos, cur_point,
                    )
                    let link : GssLink = {
                      predecessor: top_ref,
                      node: Some(missing),
                      leading_extras: [],
                    }
                    let new_ref = self.gss_nodes.length()
                    self.gss_nodes.push({ state: next_state, links: [link] })
                    while not(self.active_tops.is_empty()) {
                      let _ = self.active_tops.pop()
                    }
                    self.active_tops.push(new_ref)
                    // 重新计算 valid 集合（missing 后的状态）并重新词法
                    let new_valid : Set[Int] = Set::new()
                    for t2 in self.active_tops {
                      let st2 = self.gss_nodes[t2].state
                      match table.lexer_dfa.valid_tokens.get(st2) {
                        Some(ts) =>
                          for t in ts {
                            new_valid.add(t)
                          }
                        None => ()
                      }
                    }
                    for t in table.extras {
                      new_valid.add(t)
                    }
                    let (maybe_retok, new_pos2) = self.lexer.run_dfa(
                      input, pos, new_valid, table,
                    )
                    match maybe_retok {
                      None => ()
                      Some(retok) =>
                        if retok.terminal_id != sym_error && not(retok.is_extra) {
                          self.run_reduce_worklist(table, retok.terminal_id)
                          let shifted = self.run_shift(
                            table,
                            retok,
                            cur_point,
                            input,
                            [],
                          )
                          if not(shifted.is_empty()) {
                            let new_cost = base_cost +
                              (if is_first_error {
                                error_cost_per_recovery
                              } else {
                                0
                              }) +
                              error_cost_per_missing_tree
                            for r in shifted {
                              result_tops.push(r)
                              result_costs.push((r, new_cost))
                            }
                            result_new_pos = new_pos2
                            result_new_point = bytes_to_point(
                              input,
                              retok.start_byte,
                              cur_point,
                              retok.end_byte,
                            )
                          }
                        }
                    }
                  }
                  _ => ()
                }
              }
          }
        }
      }
    }
  }
  // 无论成败先清空 active_tops
  while not(self.active_tops.is_empty()) {
    let _ = self.active_tops.pop()
  }
  if result_tops.is_empty() {
    for r in saved_tops {
      self.active_tops.push(r)
    }
    return (false, pos, cur_point)
  }
  // 去重填入 active_tops
  let seen : Array[GssRef] = []
  for r in result_tops {
    let mut dup = false
    for s in seen {
      if s == r {
        dup = true
        break
      }
    }
    if not(dup) {
      seen.push(r)
      self.active_tops.push(r)
    }
  }
  // 写入 error_status
  for item in result_costs {
    let (r, new_cost) = item
    let existing = match self.error_status.get(r) {
      Some(s) => s.cost
      None => 1_000_000
    }
    if new_cost < existing {
      self.error_status[r] = {
        cost: new_cost,
        node_count: 0,
        dynamic_precedence: 0,
        is_in_error: false,
      }
    }
  }
  (true, result_new_pos, result_new_point)
}

///|
/// Recover-to-State 恢复策略：沿 GSS 入边回溯，找到可以接受当前 token 的祖先状态，
/// 将路径上收集到的内容包进 ERROR 节点后从祖先状态继续解析。
///
/// 三种恢复策略中第三级：当 insert_missing 无法推进时（没有单个缺失 token 能让当前
/// 实际 token 通过），退回到更早的解析状态，把错误区间全部丢进 ERROR 节点重新开始。
///
/// 算法（对每个 active top 做深度优先 BFS，上限 20 层）：
///   1. 从 top_ref 的直接前驱开始，沿 GSS 入边向下遍历
///   2. 先扩展 BFS 前沿（读原始入边），再对当前层执行试验，避免 trial 修改 gss_nodes
///      后污染前沿枚举
///   3. 每一层（anc_ref, collected, path_cost）：
///      a. 将 collected（GSS 遍历顺序 = 逆解析序）反转为左→右顺序，包成 ERROR 节点
///      b. 创建新 GssNode at anc_state 持有 error_node 作为入边
///      c. 设 active_tops = [new_node]，跑 run_reduce_worklist + run_shift(tok)
///      d. Shift 成功 → 记录结果 & 代价；失败 → 该层跳过
///   4. 全部 BFS 结束 → 去重结果填入 active_tops，更新 error_status
///   若无任何祖先可恢复 → 还原 active_tops → 返回 false
///
/// 代价模型：base_cost + error_cost_per_recovery（首次入错误模式）+ path_cost
fn GlrEngine::recover_to_state(
  self : GlrEngine,
  table : @tablegen.ParseTable,
  tok : Token,
  cur_point : Point,
  input : String,
) -> Bool {
  let max_depth = 20
  let saved_tops = self.active_tops.copy()
  let result_tops : Array[GssRef] = []
  let result_costs : Array[(GssRef, Int)] = []
  for top_ref in saved_tops {
    let (base_cost, is_first_error) = match self.error_status.get(top_ref) {
      Some(s) => (s.cost, not(s.is_in_error))
      None => (0, true)
    }
    // BFS 前沿：(祖先节点引用, 沿路收集的 CstNode（GSS 遍历顺序＝逆解析序）, 路径代价)
    let frontier : Array[(GssRef, Array[CstNode], Int)] = []
    // 从 top_ref 的直接前驱开始（至少需收集 1 个节点才有意义）
    let top_node = self.gss_nodes[top_ref]
    for link in top_node.links {
      let collected : Array[CstNode] = []
      match link.node {
        Some(n) => collected.push(n)
        None => () // 哨兵边（底部），无节点
      }
      let lc = match link.node {
        Some(n) => error_cost_for_skipped_node(n)
        None => 0
      }
      frontier.push((link.predecessor, collected, lc))
    }
    let mut fi = 0
    while fi < frontier.length() {
      let (anc_ref, collected, path_cost) = frontier[fi]
      fi = fi + 1
      // 先扩展 BFS（读原始入边，在 trial 修改 gss_nodes 之前）
      if collected.length() < max_depth {
        let anc_node = self.gss_nodes[anc_ref]
        for link in anc_node.links {
          let new_collected = collected.copy()
          match link.node {
            Some(n) => new_collected.push(n)
            None => ()
          }
          let extra_cost = match link.node {
            Some(n) => error_cost_for_skipped_node(n)
            None => 0
          }
          frontier.push(
            (link.predecessor, new_collected, path_cost + extra_cost),
          )
        }
      }
      // 若路径上有内容，尝试从 anc_ref 处恢复
      if not(collected.is_empty()) {
        // 将收集到的节点反转为左→右解析顺序，包进 ERROR 节点
        let children : Array[CstNode] = collected.copy()
        array_rev_inplace(children)
        let first = children[0]
        let last = children[children.length() - 1]
        let error_node = CstNode::error_node(
          children,
          first.start_byte,
          last.end_byte,
          first.start_point,
          last.end_point,
        )
        // 在 anc_ref.state 创建新 GssNode，持有 error_node 作为入边
        let anc_state = self.gss_nodes[anc_ref].state
        let err_link : GssLink = {
          predecessor: anc_ref,
          node: Some(error_node),
          leading_extras: [],
        }
        let new_ref = self.gss_nodes.length()
        self.gss_nodes.push({ state: anc_state, links: [err_link] })
        // 试验：把 active_tops 设为 [new_ref]，跑 Reduce + Shift
        while not(self.active_tops.is_empty()) {
          let _ = self.active_tops.pop()
        }
        self.active_tops.push(new_ref)
        self.run_reduce_worklist(table, tok.terminal_id)
        let shifted = self.run_shift(table, tok, cur_point, input, [])
        if not(shifted.is_empty()) {
          let recovery_penalty = if is_first_error {
            error_cost_per_recovery
          } else {
            0
          }
          let new_cost = base_cost + recovery_penalty + path_cost
          for r in shifted {
            result_tops.push(r)
            result_costs.push((r, new_cost))
          }
        }
      }
    }
  }
  // 清空 active_tops，准备填入最终结果
  while not(self.active_tops.is_empty()) {
    let _ = self.active_tops.pop()
  }
  if result_tops.is_empty() {
    for r in saved_tops {
      self.active_tops.push(r)
    }
    return false
  }
  // 去重填入 active_tops
  let seen : Array[GssRef] = []
  for r in result_tops {
    let mut dup = false
    for s in seen {
      if s == r {
        dup = true
        break
      }
    }
    if not(dup) {
      seen.push(r)
      self.active_tops.push(r)
    }
  }
  // 写入 error_status（多路径合并时取代价更低者）
  for item in result_costs {
    let (r, new_cost) = item
    let existing = match self.error_status.get(r) {
      Some(s) => s.cost
      None => 1_000_000
    }
    if new_cost < existing {
      self.error_status[r] = {
        cost: new_cost,
        node_count: 0,
        dynamic_precedence: 0,
        is_in_error: false,
      }
    }
  }
  true
}

///|
/// Reduce worklist 阶段：对活跃栈顶集合执行所有可能的 Reduce 动作至不动点。
///
/// 算法（Tomita 风格 worklist）：
/// 将 active_tops 中每个结点对 (top, prod_id) 放入 worklist
/// 每次取出一个 (top, prod_id)：
///      a. enum_paths(top, |body|) 得到所有子节点列表
///      b. 对每条路径，取路径起点（base）的前驱结点作为 base_state 来源
///      c. 查 goto[base_state, head] 得目标状态
///      d. 构造 CstNode::inner，find_or_merge 合入 active_tops
///      e. 若是新结点或新加了边 → 该新 top 的 Reduce 也须入队
/// worklist 空 → Reduce 到不动点
///
/// tok_id  : 当前前瞻 token 的 TerminalId（用于查 action 表，EOF 传 eoi_id）
/// active_tops 原地扩展（新 Reduce 结果追加到同一集合中）
///
/// fragile 标记策略：
///   · 仅当存在真正的并行路径时才标 fragile，避免过度标记阻塞增量复用
///   · 判据（任意一条为 true → fragile = true）：
/// active_tops.length() > 1：本轮存在多个并行活跃前缀（S/R 或 R/R 冲突）
/// enum_paths 返回 > 1 条路径：同一 top 通过多条 GSS 前缀归约（局部歧义）
///   · 两者均为 false 时（单路径无歧义），inner 节点标 fragile=false，可增量复用
fn GlrEngine::run_reduce_worklist(
  self : GlrEngine,
  table : @tablegen.ParseTable,
  tok_id : Int,
) -> Unit {
  // worklist 中每项 = (栈顶 GssRef, 产生式 ProductionId)
  let worklist : Array[(GssRef, Int)] = []

  // 初始化：把 active_tops 上所有 Reduce 动作入队
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

  // 主循环：处理 worklist 直到空
  let mut wi = 0
  while wi < worklist.length() {
    let (top, prod_id) = worklist[wi]
    wi = wi + 1

    let prod = table.productions[prod_id]
    let body_len = prod.body.length()

    // 枚举所有长度为 body_len 的路径，同时得到每条路径的 base 结点
    // （base = 沿路径走完 body_len 步后所在的 GSS 结点，即 goto 查找的来源）
    let paths = self.enum_paths(top, body_len)

    // fragile 判据（仅当真正存在并行路径时才标 true）：
    //   · active_tops.length() > 1 — 本轮有多个活跃并行前缀（S/R 或 R/R 冲突）
    //   · paths.length() > 1       — 此产生式经由多条 GSS 路径归约（局部歧义）
    // 两者均影响左边界（产生式起始位置因路径不同而异），右边界始终同步于当前词法单元位置。
    // fragile_left: 有并行路径时为 true；fragile_right: 从最后一个子节点传播。
    let fragile_left = self.active_tops.length() > 1 || paths.length() > 1
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
          let fragile_right = if children.is_empty() {
            false
          } else {
            children[children.length() - 1].fragile_right
          }
          let inner = CstNode::inner(
            nt,
            meta.is_named,
            children,
            fnames,
            prod.id,
            0,
            fragile_left,
            fragile_right,
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
/// 压缩 GSS 结点 Arena，回收从 roots 不可达的结点。
///
/// 每次 run_shift 之后，旧 active_tops 被替换为 next_tops，旧的前缀结点（可能有
/// 数十个）不再被任何活跃栈顶引用，但仍留在 gss_nodes 数组中。对长输入文件，
/// 这会导致 Arena 线性增长（每 token 增加 O(states) 个死亡结点）。
///
/// 算法：
/// 从 roots 出发 DFS，标记所有可达的 GssRef（包括哨兵结点 0）
/// 建立 old_ref → new_compact_ref 的重映射表
/// 用新索引重建 gss_nodes（所有 GssLink.predecessor 用新索引）
/// 原地更新 roots 数组为新索引
///
/// 调用时机：每次 run_shift 完成、active_tops 切换为下一轮栈顶之后。
fn GlrEngine::compact(self : GlrEngine, roots : Array[GssRef]) -> Unit {
  let n = self.gss_nodes.length()

  // 标记可达结点（DFS）
  let live : Array[Bool] = Array::make(n, false)
  let stack : Array[GssRef] = roots.copy()
  while not(stack.is_empty()) {
    match stack.pop() {
      None => break
      Some(r) => {
        if r < 0 || r >= n || live[r] {
          continue
        }
        live[r] = true
        for link in self.gss_nodes[r].links {
          stack.push(link.predecessor)
        }
      }
    }
  }

  // 建立重映射表（旧索引 → 新紧凑索引）
  let remap : Array[Int] = Array::make(n, -1)
  let mut new_idx = 0
  let mut old_i = 0
  while old_i < n {
    if live[old_i] {
      remap[old_i] = new_idx
      new_idx = new_idx + 1
    }
    old_i = old_i + 1
  }

  // 无死亡结点 → 不需要重建
  if new_idx == n {
    return
  }

  // 重建 gss_nodes（仅保留可达结点，predecessor refs 用新索引）
  let new_nodes : Array[GssNode] = []
  let mut oi = 0
  while oi < n {
    if live[oi] {
      let old_node = self.gss_nodes[oi]
      let new_links : Array[GssLink] = []
      for lnk in old_node.links {
        new_links.push({
          predecessor: remap[lnk.predecessor],
          node: lnk.node,
          leading_extras: lnk.leading_extras,
        })
      }
      new_nodes.push({ state: old_node.state, links: new_links })
    }
    oi = oi + 1
  }

  // 原地替换 Arena ─────────────────────────────────────────────────────────────
  while not(self.gss_nodes.is_empty()) {
    let _ = self.gss_nodes.pop()
  }
  for nd in new_nodes {
    self.gss_nodes.push(nd)
  }

  // 更新 roots 的索引为新紧凑索引
  let mut ri = 0
  while ri < roots.length() {
    roots[ri] = remap[roots[ri]]
    ri = ri + 1
  }

  // 重映射 error_status（GssRef 键随压缩而变化）
  let remapped_es : Array[(GssRef, ErrorStatus)] = []
  self.error_status.each(fn(old_ref, status) {
    if old_ref >= 0 && old_ref < n && live[old_ref] {
      remapped_es.push((remap[old_ref], status))
    }
  })
  self.error_status.clear()
  for item in remapped_es {
    let (new_ref, status) = item
    self.error_status[new_ref] = status
  }
}

///|
/// Condense Stack：当 active_tops 超过 max_version_count 时，
/// 按 ErrorStatus 代价排序并截尾，只保留最优的 max_version_count 条路径。
///
/// 排序键（升序优先）：
///   主键：cost（越小越优先）
///   次键：dynamic_precedence（越大越优先，即次键降序）
/// 没有 ErrorStatus 记录的路径视为 cost=0（无错误路径，最优），
/// 排在所有有代价路径之前。
///
/// 截尾后调用 compact 回收已剪掉的路径占用的 GssNode。
/// 必须在 compact 之后调用（此时 GssRef 已经是紧凑索引）。
///
/// 超出阈值时截至 max_version_count（硬上限）；
/// 仅当超过 max_version_count + max_version_count_overflow 时才触发，
/// 避免在短暂并行爆发窗口内过早丢弃仍有希望的路径。
fn GlrEngine::condense_stack(self : GlrEngine) -> Unit {
  let n = self.active_tops.length()
  if n <= max_version_count {
    return
  }
  // 对 active_tops 按 (cost ASC, dynamic_precedence DESC) 排序
  // 使用插入排序（active_tops 通常很小，≤ max_version_count_overflow + max_version_count）
  let tops = self.active_tops
  let mut i = 1
  while i < tops.length() {
    let ref_i = tops[i]
    let (ci, dpi) = match self.error_status.get(ref_i) {
      Some(s) => (s.cost, s.dynamic_precedence)
      None => (0, 0)
    }
    let mut j = i - 1
    while j >= 0 {
      let ref_j = tops[j]
      let (cj, dpj) = match self.error_status.get(ref_j) {
        Some(s) => (s.cost, s.dynamic_precedence)
        None => (0, 0)
      }
      // ref_i 比 ref_j 更优 ⟺ ci < cj 或 (ci == cj 且 dpi > dpj)
      let i_better = ci < cj || (ci == cj && dpi > dpj)
      if i_better {
        tops[j + 1] = tops[j]
        j = j - 1
      } else {
        break
      }
    }
    tops[j + 1] = ref_i
    i = i + 1
  }
  // 截尾：只保留前 max_version_count 条
  while self.active_tops.length() > max_version_count {
    let _ = self.active_tops.pop()
  }
  // compact 回收被丢弃路径的 GssNode
  self.compact(self.active_tops)
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
