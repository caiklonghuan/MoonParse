///|
// LALR(1) 解析表构建

///|
/// 向 action 表的 (state, terminal) 格加入动作；已存在相同动作时跳过。
fn add_action(
  action : Map[(StateId, TerminalId), Array[Action]],
  state : StateId,
  terminal : TerminalId,
  act : Action,
) -> Unit {
  let key = (state, terminal)
  match action.get(key) {
    None => action.set(key, [act])
    Some(arr) => {
      let mut found = false
      for a in arr {
        if a == act {
          found = true
          break
        }
      }
      if !found {
        arr.push(act)
      }
    }
  }
}

// 内部：LALR(1) 精确前瞻集合计算

///|
/// 用反向 goto 追踪 + 不动点传播，计算每个规约项目 [A→α•] 在状态 i 的
/// LALR(1) 精确前瞻集合，取代 SLR(1) 中错误使用的全局 FOLLOW(A)。
///
/// 算法梗概（DeRemer & Pennello 风格）：
///   对于 [A→α•] in state i：
///     通过反向 goto 追踪 α，找出所有"出发态" j0（goto*(j0, α) = i）；
///     对每个 j0，扫描其项目集中所有 [C→δ•Aγ]：
///       - FIRST(γ) 自发加入 LA(i, A→α)；
///       - 若 γ 可推导 ε，则建立传播边
///         LA(goto*(goto(j0,A), γ), C→δAγ) → LA(i, A→α)；
///   最后不动点传播直至稳定。
fn compute_lalr_lookaheads(
  grammar : AugmentedGrammar,
  item_sets : Array[Set[LRItem]],
  goto_map : Map[(StateId, Symbol), StateId],
) -> Map[(StateId, ProductionId), Set[TerminalId]] {
  let n = item_sets.length()

  // (1) 构建反向 goto：(target_state, sym) → [src_states]
  let rev_goto : Map[(StateId, Symbol), Array[StateId]] = Map::new()
  for key, tgt in goto_map {
    let (src, sym) = key
    let rk = (tgt, sym)
    match rev_goto.get(rk) {
      None => rev_goto.set(rk, [src])
      Some(arr) => arr.push(src)
    }
  }

  // (2) 初始化所有规约项目的前瞻集合为空
  let la : Map[(StateId, ProductionId), Set[TerminalId]] = Map::new()
  for i in 0..<n {
    for item in item_sets[i] {
      let prod = grammar.productions[item.prod]
      if item.dot == prod.body.length() {
        let key = (i, item.prod)
        if la.get(key) == None {
          la.set(key, Set::new())
        }
      }
    }
  }

  // (3) 传播边：prop[(src_state, src_prod)] = [(dst_state, dst_prod)]
  //     含义：LA(dst) ⊇ LA(src)
  let prop : Map[(StateId, ProductionId), Array[(StateId, ProductionId)]] = Map::new()

  // (4) 对每个规约项目 [A→α•] in state i 建立自发前瞻与传播边
  for i in 0..<n {
    for item in item_sets[i] {
      let prod = grammar.productions[item.prod]
      if item.dot == prod.body.length() {
        // [A → α •]
        let alpha_n = prod.body.length()

        // 反向追踪：从 state i 沿 α 逆向，找出所有"出发态" j0
        let mut cur_states : Array[StateId] = [i]
        let mut step = alpha_n - 1
        while step >= 0 {
          let sym = prod.body[step].symbol
          let prev : Array[StateId] = []
          for cs in cur_states {
            match rev_goto.get((cs, sym)) {
              None => ()
              Some(srcs) =>
                for s in srcs {
                  prev.push(s)
                }
            }
          }
          cur_states = prev
          step = step - 1
        }

        // 对每个出发态 j0，扫描 item_sets[j0] 中 [C→δ•Aγ]（A = prod.head）
        for j0 in cur_states {
          for item2 in item_sets[j0] {
            let prod2 = grammar.productions[item2.prod]
            if item2.dot < prod2.body.length() &&
              prod2.body[item2.dot].symbol == NonTerminal(prod.head) {
              // [C→δ•Aγ]，γ = prod2.body[item2.dot+1 ..]
              let gamma_start = item2.dot + 1
              let gamma_len = prod2.body.length() - gamma_start
              let gamma_syms : Array[Symbol] = []
              for k in 0..<gamma_len {
                gamma_syms.push(prod2.body[gamma_start + k].symbol)
              }

              // FIRST(γ) 自发加入 LA(i, prod.id)
              let fg = first_seq(grammar, gamma_syms)
              let dst_set = match la.get((i, prod.id)) {
                None => {
                  let s : Set[TerminalId] = Set::new()
                  la.set((i, prod.id), s)
                  s
                }
                Some(s) => s
              }
              for t in fg {
                dst_set.add(t)
              }

              // 若 γ 可推导 ε：建立传播边
              //   j2 = goto*(goto(j0, A), γ)
              //   prop[(j2, prod2.id)] → [(i, prod.id)]
              if nullable(grammar, gamma_syms) {
                match goto_map.get((j0, NonTerminal(prod.head))) {
                  None => ()
                  Some(jA) => {
                    let mut state = jA
                    let mut ok = true
                    for gsym in gamma_syms {
                      match goto_map.get((state, gsym)) {
                        None => {
                          ok = false
                          break
                        }
                        Some(ns) => state = ns
                      }
                    }
                    if ok {
                      let src_key = (state, prod2.id)
                      let dst_key = (i, prod.id)
                      match prop.get(src_key) {
                        None => prop.set(src_key, [dst_key])
                        Some(arr) => {
                          let mut found = false
                          for p in arr {
                            if p == dst_key {
                              found = true
                              break
                            }
                          }
                          if !found {
                            arr.push(dst_key)
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // (5) 不动点传播
  let mut changed = true
  while changed {
    changed = false
    for src_key, dsts in prop {
      match la.get(src_key) {
        None => ()
        Some(src_la) =>
          for dst_key in dsts {
            let dst_set = match la.get(dst_key) {
              None => {
                let s : Set[TerminalId] = Set::new()
                la.set(dst_key, s)
                s
              }
              Some(s) => s
            }
            // 用快照避免在同一集合上迭代时修改
            for t in src_la.to_array() {
              if !dst_set.contains(t) {
                dst_set.add(t)
                changed = true
              }
            }
          }
      }
    }
  }

  la
}

// 公开 API

///|
/// 构建 LALR(1) 解析表
pub fn build_lalr_table(
  grammar : AugmentedGrammar,
  item_sets : Array[Set[LRItem]],
  goto_map : Map[(StateId, Symbol), StateId],
) -> ParseTable {
  let action : Map[(StateId, TerminalId), Array[Action]] = Map::new()
  let goto_table : Map[(StateId, NonTerminalId), StateId] = Map::new()

  // Step 1：从 goto_map 填充 Shift 与 goto
  for key, target in goto_map {
    let (state, sym) = key
    match sym {
      Terminal(t) => add_action(action, state, t, Shift(target))
      EndOfInput => add_action(action, state, eoi_id, Shift(target))
      NonTerminal(nt) => goto_table.set((state, nt), target)
    }
  }

  // Step 2：从 reduce 项目填充 Reduce / Accept
  // LALR(1) 精确前瞻集合（取代 SLR(1) 的全局 FOLLOW）
  let lalr_la = compute_lalr_lookaheads(grammar, item_sets, goto_map)
  let n = item_sets.length()
  let mut i = 0
  while i < n {
    let state : StateId = i
    for item in item_sets[i] {
      let prod = grammar.productions[item.prod]
      if item.dot == prod.body.length() {
        // [A → α •]：reduce 项目
        if prod.head == grammar.start {
          // 增广起始产生式 $accept → start $ — Accept
          add_action(action, state, eoi_id, Accept)
        } else {
          // 普通产生式 — LALR(1) 精确前瞻（经前瞻约束过滤）
          let la = match lalr_la.get((state, item.prod)) {
            Some(s) => s
            None => Set::new()
          }
          for t in la {
            let ok = match prod.lookahead {
              None => true
              Some(NotFollowedBy(tids)) => {
                let mut found = false
                for tid in tids {
                  if tid == t {
                    found = true
                    break
                  }
                }
                !found
              }
              Some(FollowedBy(tids)) => {
                let mut found = false
                for tid in tids {
                  if tid == t {
                    found = true
                    break
                  }
                }
                found
              }
            }
            if ok {
              add_action(action, state, t, Reduce(prod.id))
            }
          }
        }
      }
    }
    i = i + 1
  }

  // Step 3：整理 symbol_metadata（下标 = NonTerminalId）
  let mut max_nt = 0
  for _, id in grammar.nonterminals {
    if id > max_nt {
      max_nt = id
    }
  }
  let symbol_metadata : Array[SymbolMeta] = Array::make(max_nt + 1, {
    name: "",
    is_named: false,
    is_synthetic: false,
    field_slots: [],
  })
  for name, id in grammar.nonterminals {
    // grammar.nt_metas 已由 normalize.mbt 按 rule.is_named 准确填充，直接读取
    // （趋吧：$accept 和辅助 NT 名称以 _ 开头，is_named 已称 false）
    let is_named = if id < grammar.nt_metas.length() {
      grammar.nt_metas[id].is_named
    } else {
      false
    }
    let is_synthetic = if id < grammar.nt_metas.length() {
      grammar.nt_metas[id].is_synthetic
    } else {
      false
    }
    let field_slots = if id < grammar.nt_metas.length() {
      grammar.nt_metas[id].field_slots
    } else {
      []
    }
    symbol_metadata[id] = { name, is_named, is_synthetic, field_slots }
  }

  // Step 4：桩 LexerDfa（Phase 1 不生成词法 DFA）
  let stub_dfa : LexerDfa = { states: [], start: 0, valid_tokens: Map::new() }

  {
    states: item_sets.length(),
    action,
    goto_table,
    productions: grammar.productions,
    lexer_dfa: stub_dfa,
    symbol_metadata,
    terminal_patterns: grammar.terminal_patterns,
    terminal_names: Map::new(), // 由 generate_parse_table() 在 augment 后填充
    extras: [], // 由 generate_parse_table() 从 aug.extras 填充
    external_token_ids: [], // 由 generate_parse_table() 从 aug.external_ids 填充
    word_token: None, // 由 generate_parse_table() 从 aug.word_token 填充
    keyword_map: Map::new(), // 由 generate_parse_table() 构建
  }
}
