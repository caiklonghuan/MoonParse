///|
// GLR 解析引擎

///|
/// 计算跳过一个 CstNode 的错误代价
fn error_cost_for_skipped_node(node : CstNode, config : ParseConfig) -> Int {
  let char_cost = (node.end_byte - node.start_byte) *
    config.error_cost_per_skipped_char
  let line_cost = (node.end_point.row - node.start_point.row) *
    config.error_cost_per_skipped_line
  let tree_cost = config.error_cost_per_skipped_tree
  let body_cost = if char_cost > line_cost { char_cost } else { line_cost }
  tree_cost + body_cost
}

///|
/// GSS 结点引用（Arena 下标，避免循环引用）
type GssRef = Int

///|
/// GSS 边
struct GssLink {
  predecessor : GssRef
  node : CstNode?
  leading_extras : Array[CstNode]
} derive(Debug)

///|
/// GSS 结点
struct GssNode {
  /// 当前 LR 状态（ParseTable.action 的 key 之一）
  state : Int
  /// 入边列表（空 = 底部哨兵结点，永不弹出）
  links : Array[GssLink]
} derive(Debug)

///|
/// GLR 解析引擎
priv struct GlrEngine {
  gss_nodes : Array[GssNode]
  active_tops : Array[GssRef]
  lexer : LexerEngine
  /// 各活跃版本的代价记录（GssRef → ErrorStatus）
  /// skip_token / insert_missing 等恢复策略在此累积代价；
  /// condense_stack 据此剪枝超限版本。
  error_status : Map[GssRef, ErrorStatus]
  /// 错误恢复与 GLR 版本数可配置参数
  config : ParseConfig
  /// 有状态词法器的 per-path 状态（GssRef → &StatefulScanner）
  /// GLR 分支时 clone，compact 时 remap，condense_stack 时清理。
  /// 无状态模式下该 map 始终为空。
  scanner_states : Map[GssRef, &StatefulScanner]
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
fn GlrEngine::new(lexer : LexerEngine, config : ParseConfig) -> GlrEngine {
  let sentinel : GssNode = { state: 0, links: [] }
  {
    gss_nodes: [sentinel],
    active_tops: [0],
    lexer,
    error_status: Map::new(),
    config,
    scanner_states: Map::new(),
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
pub fn glr_parse(
  table : @tablegen.ParseTable,
  input : String,
) -> Result[CstNode, ParseError] {
  let lexer = LexerEngine::new(table.lexer_dfa)
  let engine = GlrEngine::new(lexer, ParseConfig::default())
  engine.run(table, input)
}

///|
/// 带自定义错误恢复配置的 GLR 解析入口
///
/// 与 `glr_parse` 相同，但使用调用方传入的 `config` 替代默认配置。
pub fn glr_parse_with_config(
  table : @tablegen.ParseTable,
  input : String,
  config : ParseConfig,
) -> Result[CstNode, ParseError] {
  let lexer = LexerEngine::new(table.lexer_dfa)
  let engine = GlrEngine::new(lexer, config)
  engine.run(table, input)
}

///|
/// 带外部词法器回调的 GLR 解析入口
pub fn glr_parse_with_external_scanner(
  table : @tablegen.ParseTable,
  input : String,
  scanner : ExternalScanner,
) -> Result[CstNode, ParseError] {
  let lexer = LexerEngine::new_with_external(table.lexer_dfa, scanner)
  let engine = GlrEngine::new(lexer, ParseConfig::default())
  engine.run(table, input)
}

///|
/// 带有状态词法器的 GLR 解析入口
///
/// 与无状态 external_scanner 不同，有状态词法器在 GLR 分支时会对
/// scanner 状态进行 clone，确保每条解析路径持有独立的词法器状态。
pub fn glr_parse_with_stateful_scanner(
  table : @tablegen.ParseTable,
  input : String,
  scanner : &StatefulScanner,
) -> Result[CstNode, ParseError] {
  glr_parse_with_stateful_scanner_and_config(
    table,
    input,
    scanner,
    ParseConfig::default(),
  )
}

///|
/// 带有状态词法器 + 自定义错误恢复配置的 GLR 解析入口。
pub fn glr_parse_with_stateful_scanner_and_config(
  table : @tablegen.ParseTable,
  input : String,
  scanner : &StatefulScanner,
  config : ParseConfig,
) -> Result[CstNode, ParseError] {
  let lexer = LexerEngine::new_with_stateful(table.lexer_dfa, scanner)
  let engine = GlrEngine::new(lexer, config)
  // 为初始栈顶（哨兵节点 0）设置初始 scanner 状态
  engine.scanner_states[0] = scanner
  engine.run(table, input)
}

///|
/// GLR 主循环
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
    // 增量子树复用：在词法前尝试直接复用旧树中的 inner 节点。
    // 若成功，将 active_tops 更新为 goto 后的新顶集，pos 跳过子树覆盖的 token 序列。
    // 不同路径对相同 inner 节点的起点和终点必须完全一致才触发（保守策略）。
    let (reused, reuse_pos, reuse_point) = self.try_reuse_subtrees(
      table, input, pos, cur_point, pending_extras,
    )
    if reused {
      // active_tops 已由 try_reuse_subtrees 内部替换为 goto 后的新顶集，无需再次清空
      self.compact(self.active_tops)
      self.condense_stack()
      // 清空 pending_extras（已携带进 goto 边的 leading_extras）
      while !pending_extras.is_empty() {
        let _ = pending_extras.pop()
      }
      cur_point = reuse_point
      pos = reuse_pos
      continue
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

    // 词法（使用并集 valid 集合；支持 external scanner 与 EOF 零宽 token）
    let (maybe_tok, new_pos) = self.lexer.scan_with_valid(
      input, pos, valid, table,
    )
    match maybe_tok {
      None => {
        // EOF：执行最终归约，再把 trailing pending_extras 追加到根节点 children 末尾。
        // 文件尾部的空白/注释已积累在 pending_extras，没有后续 Shift 机会把它们
        // 携带进 GssLink.leading_extras，故在此处直接拼入根节点。
        self.run_reduce_worklist(table, @tablegen.eoi_id)
        match self.collect_root_glr(table, pos, cur_point) {
          Err(e) => return Err(e)
          Ok(root) => {
            if pending_extras.is_empty() {
              return Ok(root)
            }
            // 若 pending_extras 中含有来自 skip_token 的错误节点（is_error=true），
            // 说明解析结束后仍有无法归入语法的错误 token（如多余尾部字符），视为失败。
            // 正常 extra（注释、空白等，is_error=false）直接追加到根节点 children 末尾。
            for ex in pending_extras {
              if ex.is_error {
                return Err({
                  position: ex.start_byte,
                  point: ex.start_point,
                  message: "unexpected token",
                })
              }
            }
            let new_ch = root.children.copy()
            let new_fn = root.field_names.copy()
            for ex in pending_extras {
              new_ch.push(ex)
              new_fn.push(None)
            }
            let last_ex = new_ch[new_ch.length() - 1]
            return Ok({
              ..root,
              children: new_ch,
              field_names: new_fn,
              end_byte: last_ex.end_byte,
              end_point: last_ex.end_point,
            })
          }
        }
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
          self.skip_token(tok, cur_point, input, pending_extras)
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
          // 降级：skip 当前 token，error_node 标为 extra 追加到 pending_extras，
          // active_tops 不变（避免自环 GssNode 污染产生式体）
          self.skip_token(tok, cur_point, input, pending_extras)
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
        while !self.active_tops.is_empty() {
          let _ = self.active_tops.pop()
        }
        for r in next_tops {
          self.active_tops.push(r)
        }
        // pending_extras 已由 run_shift 复制到每条 GssLink，仅在 Shift 成功时才清空
        while !pending_extras.is_empty() {
          let _ = pending_extras.pop()
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
/// 当多条路径均可 Accept 时（Dynamic prec 歧义），优先选取 dynamic_precedence 最高的根节点。
fn GlrEngine::collect_root_glr(
  self : GlrEngine,
  table : @tablegen.ParseTable,
  pos : Int,
  cur_pt : Point,
) -> Result[CstNode, ParseError] {
  let mut best : CstNode? = None
  let mut best_dp : Int = -1
  for top_ref in self.active_tops {
    let state = self.gss_nodes[top_ref].state
    match table.action.get((state, @tablegen.eoi_id)) {
      None => ()
      Some(acts) =>
        for act in acts {
          match act {
            // 直接 Accept 动作（标准 LALR 模式）：当前栈顶即为接受状态
            Accept =>
              for link in self.gss_nodes[top_ref].links {
                match link.node {
                  Some(n) =>
                    match best {
                      None => {
                        best = Some(n)
                        best_dp = n.dynamic_precedence
                      }
                      Some(_) =>
                        if n.dynamic_precedence > best_dp {
                          best = Some(n)
                          best_dp = n.dynamic_precedence
                        }
                    }
                  None => ()
                }
              }
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
                        Some(n) =>
                          match best {
                            None => {
                              best = Some(n)
                              best_dp = n.dynamic_precedence
                            }
                            Some(_) =>
                              if n.dynamic_precedence > best_dp {
                                best = Some(n)
                                best_dp = n.dynamic_precedence
                              }
                          }
                        None => ()
                      }
                    }
                  }
                }
              }
            Reduce(_) => () // Reduce 已由 worklist 处理
          }
        }
    }
  }
  match best {
    Some(n) => Ok(n)
    None =>
      Err({ position: pos, point: cur_pt, message: "accept: no root node" })
  }
}

///|
fn GlrEngine::find_or_merge(
  self : GlrEngine,
  state : Int,
  new_link : GssLink,
  candidate_tops : Array[GssRef],
) -> (GssRef, Bool) {
  // 在 candidate_tops 中线性扫描同 state 的结点
  for r in candidate_tops {
    if self.gss_nodes[r].state == state {
      // 检查是否已存在完全相同的链接（相同前驱 + 相同节点）
      // 仅 predecessor 相同但产生式不同（局部歧义）时，应追加入边而非丢弃。
      let mut dup = false
      for existing in self.gss_nodes[r].links {
        if existing.predecessor == new_link.predecessor {
          let same_node = match (existing.node, new_link.node) {
            (Some(a), Some(b)) =>
              a.symbol == b.symbol && a.production_id == b.production_id
            (None, None) => true
            _ => false
          }
          if same_node {
            dup = true
            break
          }
        }
      }
      if !dup {
        // 新链接（新前驱，或相同前驱但不同产生式/节点）：追加入边（局部歧义合并）
        self.gss_nodes[r].links.push(new_link)
      }
      return (r, !dup)
    }
  }
  // 找不到：新建结点，加入 candidate_tops
  let new_ref = self.gss_nodes.length()
  self.gss_nodes.push({ state, links: [new_link] })
  candidate_tops.push(new_ref)
  (new_ref, true)
}

///|
/// 从 from 结点沿入边向前回溯，枚举所有长度恰好为 len 的路径
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
/// Reduce 到不动点后，对当前活跃栈顶执行所有 Shift 动作
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
                  // 将 tok 的起始字节映射为旧输入坐标
                  // pre-edit（< edit_start）：坐标不变；post-edit（>= new_end_byte）：减去 byte_delta；
                  // inside-edit（edit_start .. new_end_byte）：直接用 tok.start_byte，
                  //   旧树中对应区间节点均有 has_changes=true，is_reusable 会拒绝。
                  let search_pos = if tok.start_byte < self.edit_start {
                    tok.start_byte
                  } else {
                    tok.start_byte - self.byte_delta
                  }
                  let old_end_b = self.new_end_byte - self.byte_delta
                  match
                    find_reusable_node(
                      ot,
                      search_pos,
                      state,
                      self.edit_start,
                      old_end_b,
                    ) {
                    Some(old_node) => {
                      let can_reuse_leaf = old_node.children.is_empty() &&
                        old_node.symbol == tok.terminal_id
                      // pre-edit 节点坐标不需偏移；post-edit 节点需加上 byte_delta
                      let expected_new_end = if search_pos < self.edit_start {
                        old_node.end_byte
                      } else {
                        old_node.end_byte + self.byte_delta
                      }
                      if can_reuse_leaf && expected_new_end == tok.end_byte {
                        // 同跨度复用：仅 post-edit 节点需要字节和行列坐标校正
                        if search_pos < self.edit_start {
                          old_node
                        } else {
                          shift_node(
                            old_node,
                            self.byte_delta,
                            self.old_end_point,
                            self.row_delta,
                            self.col_delta,
                          )
                        }
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
                    state, // parse_state：Shift 前栈顶 LR 状态（增量复用匹配用）
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
              let (new_ref, is_new) = self.find_or_merge(
                next_state, link, next_tops,
              )
              // 有状态词法器：为新建的 GSS 结点克隆 scanner 状态
              if is_new {
                match self.scanner_states.get(top_ref) {
                  Some(ss) => self.scanner_states[new_ref] = ss.clone_scanner()
                  None => ()
                }
              }
            }
            _ => ()
          }
        }
    }
  }
  next_tops
}

///|
fn GlrEngine::skip_token(
  self : GlrEngine,
  tok : Token,
  cur_point : Point,
  input : String,
  pending_extras : Array[CstNode],
) -> Unit {
  // 构造被跳过 token 的叶节点，包进单子 ERROR 节点，标记为 extra，
  // 不创建新的 GssNode（避免自环），仅将 error_node 追加到 pending_extras。
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
  let error_node = {
    ..CstNode::error_node(
      [raw_leaf],
      tok.start_byte,
      tok.end_byte,
      cur_point,
      ep,
    ),
    extra: true,
  } // extra=true: 跳过的 token 是 extra 节点，不应出现在归约产生式 body 中
  // 不修改 active_tops；仅在各 top_ref 上累加错误代价，并把 error_node 推入 pending_extras。
  for top_ref in self.active_tops {
    // 以 top_ref 的 ErrorStatus 为基础，累加本次跳过的代价
    let old_status = self.error_status.get(top_ref)
    let base_cost = match old_status {
      Some(s) => s.cost
      None => 0
    }
    let is_first_error = match old_status {
      Some(s) => !s.is_in_error
      None => true
    }
    let skip_cost = error_cost_for_skipped_node(error_node, self.config)
    let recovery_penalty = if is_first_error {
      self.config.error_cost_per_recovery
    } else {
      0
    }
    let new_cost = base_cost + recovery_penalty + skip_cost
    let existing_cost = match self.error_status.get(top_ref) {
      Some(s) => s.cost
      None => 1_000_000
    }
    if new_cost < existing_cost {
      self.error_status[top_ref] = {
        cost: new_cost,
        dynamic_precedence: 0,
        is_in_error: true,
      }
    }
  }
  pending_extras.push(error_node)
}

///|
/// 增量子树复用：尝试对所有活跃栈顶在当前位置找到可复用的 inner 节点，
/// 并一次性把这些节点（inner nodes，children 非空）跳过它们覆盖的 token 序列。
fn GlrEngine::try_reuse_subtrees(
  self : GlrEngine,
  table : @tablegen.ParseTable,
  _input : String,
  pos : Int,
  cur_point : Point,
  pending_extras : Array[CstNode],
) -> (Bool, Int, Point) {
  if self.byte_delta != 0 {
    return (false, pos, cur_point)
  }
  let ot = match self.old_tree {
    None => return (false, pos, cur_point)
    Some(o) => o
  }
  let old_end_b = self.new_end_byte - self.byte_delta
  // 候选列表：每个活跃栈顶对应一条 (top_ref, old_node, goto_state, expected_new_end, search_pos)
  let candidates : Array[(GssRef, CstNode, Int, Int, Int)] = []
  for top_ref in self.active_tops {
    let state = self.gss_nodes[top_ref].state
    // 将 pos 转为旧输入坐标
    let search_pos = if pos < self.edit_start {
      pos
    } else {
      pos - self.byte_delta
    }
    match
      find_reusable_node(ot, search_pos, state, self.edit_start, old_end_b) {
      Some(n) => {
        // 仅复用 inner 节点（children 非空）；leaf 节点交由 run_shift 处理
        if n.children.is_empty() {
          return (false, pos, cur_point)
        }
        // 长度变化的编辑会改变边界两侧的归约形状。
        // 对恰好从旧编辑边界开始的 inner 节点，保守地放弃复用，
        // 避免把左结合/列表子树当作稳定 suffix 接回去。
        if self.byte_delta != 0 && search_pos == old_end_b {
          return (false, pos, cur_point)
        }
        let nt = n.symbol
        // 检查当前 LR 状态在 nt 上是否有 goto 跳转
        match table.goto_table.get((state, nt)) {
          Some(goto_st) => {
            let expected_new_end = if search_pos < self.edit_start {
              n.end_byte // pre-edit：坐标不变
            } else {
              n.end_byte + self.byte_delta // post-edit：坐标偏移
            }
            candidates.push((top_ref, n, goto_st, expected_new_end, search_pos))
          }
          None => return (false, pos, cur_point) // 路径无法 goto → 放弃
        }
      }
      None => return (false, pos, cur_point) // 任意路径找不到可复用节点 → 放弃
    }
  }
  if candidates.is_empty() {
    return (false, pos, cur_point)
  }
  // 所有路径必须算出相同的 new_end_byte（保守：防止歧义路径导致坐标不一致）
  let target_new_end = candidates[0].3
  for c in candidates {
    if c.3 != target_new_end {
      return (false, pos, cur_point)
    }
  }
  // 应用复用：为 goto 后的新栈顶插入 GssLink
  let new_tops : Array[GssRef] = []
  let mut new_cur_point = cur_point
  for item in candidates {
    let (top_ref, n, goto_st, _, search_pos) = item
    // post-edit 节点需要坐标校正
    let shifted = if search_pos < self.edit_start {
      n
    } else {
      shift_node(
        n,
        self.byte_delta,
        self.old_end_point,
        self.row_delta,
        self.col_delta,
      )
    }
    new_cur_point = shifted.end_point
    let link : GssLink = {
      predecessor: top_ref,
      node: Some(shifted),
      leading_extras: pending_extras.copy(),
    }
    let (new_ref, is_new) = self.find_or_merge(goto_st, link, new_tops)
    // 有状态词法器：为新建的 GSS 结点克隆 scanner 状态
    if is_new {
      match self.scanner_states.get(top_ref) {
        Some(ss) => self.scanner_states[new_ref] = ss.clone_scanner()
        None => ()
      }
    }
  }
  // 用新栈顶替换 active_tops
  while !self.active_tops.is_empty() {
    let _ = self.active_tops.pop()
  }
  for r in new_tops {
    self.active_tops.push(r)
  }
  (true, target_new_end, new_cur_point)
}

///|
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
          Some(s) => (s.cost, !s.is_in_error)
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
                    // 有状态词法器：继承前驱的 scanner 状态
                    match self.scanner_states.get(top_ref) {
                      Some(ss) =>
                        self.scanner_states[new_ref] = ss.clone_scanner()
                      None => ()
                    }
                    while !self.active_tops.is_empty() {
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
                    if !shifted.is_empty() {
                      let new_cost = base_cost +
                        (if is_first_error {
                          self.config.error_cost_per_recovery
                        } else {
                          0
                        }) +
                        self.config.error_cost_per_missing_tree
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
  while !self.active_tops.is_empty() {
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
    if !dup {
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
        dynamic_precedence: 0,
        is_in_error: false, // 成功插入并推进，退出错误模式
      }
    }
  }
  true
}

///|
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
          Some(s) => (s.cost, !s.is_in_error)
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
                    // 有状态词法器：继承前驱的 scanner 状态
                    match self.scanner_states.get(top_ref) {
                      Some(ss) =>
                        self.scanner_states[new_ref] = ss.clone_scanner()
                      None => ()
                    }
                    while !self.active_tops.is_empty() {
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
                    let (maybe_retok, new_pos2) = self.lexer.scan_with_valid(
                      input, pos, new_valid, table,
                    )
                    match maybe_retok {
                      None => ()
                      Some(retok) =>
                        if retok.terminal_id != sym_error && !retok.is_extra {
                          self.run_reduce_worklist(table, retok.terminal_id)
                          let shifted = self.run_shift(
                            table,
                            retok,
                            cur_point,
                            input,
                            [],
                          )
                          if !shifted.is_empty() {
                            let new_cost = base_cost +
                              (if is_first_error {
                                self.config.error_cost_per_recovery
                              } else {
                                0
                              }) +
                              self.config.error_cost_per_missing_tree
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
  while !self.active_tops.is_empty() {
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
    if !dup {
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
        dynamic_precedence: 0,
        is_in_error: false,
      }
    }
  }
  // 位置一致性断言：成功恢复后新位置不得后退（防止解析死循环）
  if result_new_pos < pos {
    abort("insert_missing_and_relex: pos regressed \{result_new_pos} < \{pos}")
  }
  (true, result_new_pos, result_new_point)
}

///|
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
      Some(s) => (s.cost, !s.is_in_error)
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
        Some(n) => error_cost_for_skipped_node(n, self.config)
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
            Some(n) => error_cost_for_skipped_node(n, self.config)
            None => 0
          }
          frontier.push(
            (link.predecessor, new_collected, path_cost + extra_cost),
          )
        }
      }
      // 若路径上有内容，尝试从 anc_ref 处恢复
      if !collected.is_empty() {
        // 将收集到的节点反转为左→右解析顺序，包进 ERROR 节点
        let children : Array[CstNode] = collected.copy()
        array_rev_inplace(children)
        let first = children[0]
        let last = children[children.length() - 1]
        let error_node = {
          ..CstNode::error_node(
            children,
            first.start_byte,
            last.end_byte,
            first.start_point,
            last.end_point,
          ),
          extra: true,
        }
        while !self.active_tops.is_empty() {
          let _ = self.active_tops.pop()
        }
        self.active_tops.push(anc_ref)
        self.run_reduce_worklist(table, tok.terminal_id)
        let shifted = self.run_shift(table, tok, cur_point, input, [error_node])
        if !shifted.is_empty() {
          let recovery_penalty = if is_first_error {
            self.config.error_cost_per_recovery
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
  while !self.active_tops.is_empty() {
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
    if !dup {
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
        dynamic_precedence: 0,
        is_in_error: false,
      }
    }
  }
  true
}

///|
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

    // 检查前瞻约束（由 Not/And 断言生成）：约束不满足则跳过本次归约
    match prod.lookahead {
      Some(NotFollowedBy(tids)) => {
        let mut blocked = false
        for t in tids {
          if t == tok_id {
            blocked = true
            break
          }
        }
        if blocked {
          continue
        }
      }
      Some(FollowedBy(tids)) => {
        let mut allowed = false
        for t in tids {
          if t == tok_id {
            allowed = true
            break
          }
        }
        if !allowed {
          continue
        }
      }
      None => ()
    }

    let body_len = prod.body.length()

    // 枚举所有长度为 body_len 的路径，同时得到每条路径的 base 结点
    // （base = 沿路径走完 body_len 步后所在的 GSS 结点，即 goto 查找的来源）
    let paths = self.enum_paths(top, body_len)

    // fragile 判据（仅当真正存在并行路径时才标 true）：
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
          // children 和 fnames 同步构造：来自 leading_extras 的 extra 节点对应 None 字段名
          let children : Array[CstNode] = []
          let fnames : Array[String?] = []
          let mut body_idx = 0
          for maybe_node in path {
            match maybe_node {
              Some(n) => {
                children.push(n)
                if n.extra {
                  fnames.push(None)
                } else {
                  let fname = if body_idx < prod.body.length() {
                    prod.body[body_idx].field_name
                  } else {
                    None
                  }
                  fnames.push(fname)
                  body_idx = body_idx + 1
                }
              }
              None => () // 底部哨兵边，不产生子节点
            }
          }
          let meta : @tablegen.SymbolMeta = if nt <
            table.symbol_metadata.length() {
            table.symbol_metadata[nt]
          } else {
            { name: "?", is_named: false, is_synthetic: false, field_slots: [] }
          }
          let fragile_right = if children.is_empty() {
            false
          } else {
            children[children.length() - 1].fragile_right
          }
          // 计算 dynamic_precedence：从子节点累积 + 生产式自身动态优先级
          let child_dp = children.fold(init=0, fn(acc, c) {
            acc + c.dynamic_precedence
          })
          let prod_dp = match prod.assoc {
            Some(@grammar.PrecKind::Dynamic) =>
              match prod.prec {
                Some(p) => p
                None => 0
              }
            _ => 0
          }
          let inner_dp = child_dp + prod_dp
          let inner = CstNode::inner(
            nt,
            meta.is_named,
            children,
            fnames,
            prod.id,
            inner_dp,
            fragile_left,
            fragile_right,
            base_state, // parse_state = goto 查表前的栈顶状态（增量复用匹配用）
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
          // 有状态词法器：reduce-goto 后新结点继承 base_ref 的 scanner 状态
          if link_added {
            match self.scanner_states.get(base_ref) {
              Some(ss) =>
                if self.scanner_states.get(merged_ref) is None {
                  self.scanner_states[merged_ref] = ss.clone_scanner()
                }
              None => ()
            }
          }
          // 传播 dynamic_precedence 到 error_status（用于 condense_stack 排序）
          if inner_dp != 0 {
            let existing_dp = match self.error_status.get(merged_ref) {
              Some(s) => s.dynamic_precedence
              None => 0
            }
            if inner_dp > existing_dp {
              let base = match self.error_status.get(merged_ref) {
                Some(s) => s
                None => { cost: 0, dynamic_precedence: 0, is_in_error: false }
              }
              self.error_status[merged_ref] = {
                cost: base.cost,
                dynamic_precedence: inner_dp,
                is_in_error: base.is_in_error,
              }
            }
          }
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
fn GlrEngine::compact(self : GlrEngine, roots : Array[GssRef]) -> Unit {
  let n = self.gss_nodes.length()

  // 标记可达结点（DFS）
  let live : Array[Bool] = Array::make(n, false)
  let stack : Array[GssRef] = roots.copy()
  while !stack.is_empty() {
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

  // 原地替换 Arena
  self.gss_nodes.clear()
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

  // 重映射 scanner_states（GssRef 键随压缩而变化）
  let remapped_ss : Array[(GssRef, &StatefulScanner)] = []
  self.scanner_states.each(fn(old_ref, ss) {
    if old_ref >= 0 && old_ref < n && live[old_ref] {
      remapped_ss.push((remap[old_ref], ss))
    }
  })
  self.scanner_states.clear()
  for item in remapped_ss {
    let (new_ref, ss) = item
    self.scanner_states[new_ref] = ss
  }
}

///|
/// Condense Stack
fn GlrEngine::condense_stack(self : GlrEngine) -> Unit {
  let n = self.active_tops.length()
  // 仅当超过 max_version_count + max_version_count_overflow 时才触发，
  // 避免在短暂并行爆发窗口内过早丢弃仍有希望的路径。
  if n <= self.config.max_version_count + self.config.max_version_count_overflow {
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
  while self.active_tops.length() > self.config.max_version_count {
    let _ = self.active_tops.pop()
  }
  // compact 回收被丢弃路径的 GssNode
  self.compact(self.active_tops)
}

///|
/// 从 GSS 结点反向收集状态路径
///
/// 沿第一条入边回溯，返回从底部到 top 的状态序列。
fn GlrEngine::_state_path(self : GlrEngine, top : GssRef) -> Array[Int] {
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
