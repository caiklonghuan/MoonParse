///|
// ─── §4 LALR(1) 解析表构建 ───────────────────────────────────────────────────
//
// 实现 design.md §4 的公开函数：
//   build_lalr_table(grammar, item_sets, goto_map) -> ParseTable
//
// 算法概览：
//   Step 1  遍历 goto_map →
//             Terminal(t)     : action[(state, t)]  += Shift(target)
//             EndOfInput      : action[(state, -1)] += Shift(target)  (-1 = eoi_id)
//             NonTerminal(nt) : goto_table[(state, nt)] = target
//   Step 2  遍历每个状态的 reduce 项 [A → α •] →
//             若 A == grammar.start ($accept) : action[(state, eoi_id)] += Accept
//             否则 : 对 FOLLOW(A) 中每个 t    : action[(state, t)]     += Reduce(id)
//   Step 3  整理 symbol_metadata（下标 = NonTerminalId）
//   Step 4  组装 ParseTable (词法 DFA 在 Phase 1 置为桩实现)

// ─── 辅助：向 action 表插入去重动作 ─────────────────────────────────────────

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

// ─── 公开 API ─────────────────────────────────────────────────────────────────

///|
/// 构建 LALR(1) 解析表。
///
/// - `item_sets`：所有 LR(0) 项目集，下标即 StateId（由 build_item_sets 生成）
/// - `goto_map`  ：(state, symbol) → target state（由 build_goto_map 生成）
///
/// 返回的 ParseTable.lexer_dfa 为桩实现（Phase 1 不生成词法 DFA）。
pub fn build_lalr_table(
  grammar : AugmentedGrammar,
  item_sets : Array[Set[LRItem]],
  goto_map : Map[(StateId, Symbol), StateId],
) -> ParseTable {
  let action : Map[(StateId, TerminalId), Array[Action]] = Map::new()
  let goto_table : Map[(StateId, NonTerminalId), StateId] = Map::new()

  // ── Step 1：从 goto_map 填充 Shift 与 goto ─────────────────────────────────
  for key, target in goto_map {
    let (state, sym) = key
    match sym {
      Terminal(t) => add_action(action, state, t, Shift(target))
      EndOfInput => add_action(action, state, eoi_id, Shift(target))
      NonTerminal(nt) => goto_table.set((state, nt), target)
    }
  }

  // ── Step 2：从 reduce 项目填充 Reduce / Accept ──────────────────────────────
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
          // 普通产生式 — LALR lookahead = FOLLOW(head)
          let lookahead = follow_set(grammar, prod.head)
          for t in lookahead {
            add_action(action, state, t, Reduce(prod.id))
          }
        }
      }
    }
    i = i + 1
  }

  // ── Step 3：整理 symbol_metadata（下标 = NonTerminalId）───────────────────
  let mut max_nt = 0
  for _, id in grammar.nonterminals {
    if id > max_nt {
      max_nt = id
    }
  }
  let symbol_metadata : Array[SymbolMeta] = Array::make(max_nt + 1, {
    name: "",
    is_named: false,
  })
  for name, id in grammar.nonterminals {
    // $accept 及内部辅助规则保持 is_named: false；其余规则标记为 true
    let is_named = name != "$accept" && not(name.has_prefix("_"))
    symbol_metadata[id] = { name, is_named }
  }

  // ── Step 4：桩 LexerDfa（Phase 1 不生成词法 DFA）──────────────────────────
  let stub_dfa : LexerDfa = { states: [], start: 0, valid_tokens: Map::new() }

  {
    states: item_sets.length(),
    action,
    goto_table,
    productions: grammar.productions,
    lexer_dfa: stub_dfa,
    symbol_metadata,
    terminal_patterns: grammar.terminal_patterns,
  }
}
