///|
// ─── §6 词法器编译器 ─────────────────────────────────────────────────────────
//
// Literal / Regex / AnyChar  →  Thompson NFA  →  DFA（子集构造）
// → LexerDfa + valid_tokens 映射。
//
// 字母表策略：从 terminal_patterns 中扫描，显式字符与区间均展开为个体字符。
// AnyChar / `.` 展开为 range_chars（覆盖 ASCII 可打印字符 + 常用控制字符）。
//
// 优先级规则（值越小越优先）：
//   Literal(tid) → tid          (0…9999)
//   Regex(tid)   → 10000 + tid
//   AnyChar(tid) → 20000 + tid
//
// Phase 3 TODO：Hopcroft DFA 最小化。

// ─── 字符常量 ─────────────────────────────────────────────────────────────────

///|
/// 用于 AnyChar / `.` 展开及字符区间展开的基准字符集
/// （覆盖 ASCII 控制字符子集 + 全部可打印 ASCII，共 ~100 个字符）
let range_chars : String = "\t\n\r !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"

// ─── NFA 内部类型 ─────────────────────────────────────────────────────────────

///|
/// NFA 边标签
priv enum NfaTrans {
  Eps               // ε-跳转（内部用）
  Ch(Char)          // 精确字符匹配
  Range(Char, Char) // 字符区间 [lo, hi]（闭区间）
  Any               // 匹配任意字符（`.` 或 AnyChar）
}

///|
/// NFA 构造上下文（可变）
priv struct NfaCtx {
  mut nxt : Int
  /// edges[state] = [(label, target_state)]
  edges : Array[Array[(NfaTrans, Int)]]
  /// acc[state]: -1 = 非接受; ≥0 = 接受优先级（越小越优先）
  acc : Array[Int]
}

///|
fn NfaCtx::new() -> NfaCtx {
  { nxt: 0, edges: [], acc: [] }
}

///|
fn NfaCtx::mk(ctx : NfaCtx) -> Int {
  let id = ctx.nxt
  ctx.nxt = ctx.nxt + 1
  ctx.edges.push([])
  ctx.acc.push(-1)
  id
}

///|
fn NfaCtx::edge(ctx : NfaCtx, from : Int, lbl : NfaTrans, to : Int) -> Unit {
  ctx.edges[from].push((lbl, to))
}

// ─── Thompson 片段构造辅助 ───────────────────────────────────────────────────

///|
/// Kleene star(*)
fn nfa_star(ctx : NfaCtx, s : Int, a : Int) -> (Int, Int) {
  let ns = NfaCtx::mk(ctx)
  let na = NfaCtx::mk(ctx)
  NfaCtx::edge(ctx, ns, Eps, s)
  NfaCtx::edge(ctx, ns, Eps, na)
  NfaCtx::edge(ctx, a, Eps, s)
  NfaCtx::edge(ctx, a, Eps, na)
  (ns, na)
}

///|
/// Plus(+)：a -ε-> s（循环），a -ε-> na（出口）
fn nfa_plus(ctx : NfaCtx, s : Int, a : Int) -> (Int, Int) {
  let na = NfaCtx::mk(ctx)
  NfaCtx::edge(ctx, a, Eps, s)
  NfaCtx::edge(ctx, a, Eps, na)
  (s, na)
}

///|
/// Optional(?)
fn nfa_opt(ctx : NfaCtx, s : Int, a : Int) -> (Int, Int) {
  let ns = NfaCtx::mk(ctx)
  let na = NfaCtx::mk(ctx)
  NfaCtx::edge(ctx, ns, Eps, s)
  NfaCtx::edge(ctx, ns, Eps, na)
  NfaCtx::edge(ctx, a, Eps, na)
  (ns, na)
}

///|
/// 连接两片段：a1 -ε-> s2
fn nfa_concat(ctx : NfaCtx, a1 : Int, s2 : Int) -> Unit {
  NfaCtx::edge(ctx, a1, Eps, s2)
}

///|
/// 交替：ns -ε-> s1/s2，a1/a2 -ε-> na
fn nfa_alt_frag(
  ctx : NfaCtx,
  s1 : Int,
  a1 : Int,
  s2 : Int,
  a2 : Int,
) -> (Int, Int) {
  let ns = NfaCtx::mk(ctx)
  let na = NfaCtx::mk(ctx)
  NfaCtx::edge(ctx, ns, Eps, s1)
  NfaCtx::edge(ctx, ns, Eps, s2)
  NfaCtx::edge(ctx, a1, Eps, na)
  NfaCtx::edge(ctx, a2, Eps, na)
  (ns, na)
}

// ─── 字面量 / AnyChar → NFA ──────────────────────────────────────────────────

///|
/// 字符串字面量：链式字符跳转片段
fn nfa_from_literal(ctx : NfaCtx, s : String) -> (Int, Int) {
  let start = NfaCtx::mk(ctx)
  let mut prev = start
  for ch in s {
    let next = NfaCtx::mk(ctx)
    NfaCtx::edge(ctx, prev, Ch(ch), next)
    prev = next
  }
  (start, prev)
}

///|
/// AnyChar：单个 Any 边
fn nfa_from_any(ctx : NfaCtx) -> (Int, Int) {
  let s = NfaCtx::mk(ctx)
  let a = NfaCtx::mk(ctx)
  NfaCtx::edge(ctx, s, Any, a)
  (s, a)
}

// ─── 正则字符串递归下降解析器 ────────────────────────────────────────────────

///|
priv struct RexParse {
  src : Array[Char]
  mut pos : Int
}

///|
fn RexParse::new(s : String) -> RexParse {
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  { src: chars, pos: 0 }
}

///|
fn RexParse::peek(p : RexParse) -> Char? {
  if p.pos < p.src.length() {
    Some(p.src[p.pos])
  } else {
    None
  }
}

///|
fn RexParse::peek2(p : RexParse) -> Char? {
  if p.pos + 1 < p.src.length() {
    Some(p.src[p.pos + 1])
  } else {
    None
  }
}

///|
fn RexParse::next(p : RexParse) -> Char {
  let c = p.src[p.pos]
  p.pos = p.pos + 1
  c
}

///|
/// 解析 `\x` 转义，返回 NfaTrans 列表
fn parse_escape_trans(p : RexParse) -> Array[NfaTrans] {
  let c = RexParse::next(p)
  match c {
    'd' => [Range('0', '9')]
    'w' => [Range('a', 'z'), Range('A', 'Z'), Range('0', '9'), Ch('_')]
    's' => [Ch(' '), Ch('\t'), Ch('\n'), Ch('\r')]
    'n' => [Ch('\n')]
    't' => [Ch('\t')]
    'r' => [Ch('\r')]
    _ => [Ch(c)]
  }
}

///|
/// 解析 `[...]` 字符类，返回 NfaTrans 列表
/// 调用时 pos 指向 `[` 之后的第一个字符
fn parse_char_class_trans(p : RexParse) -> Array[NfaTrans] {
  let negated = match RexParse::peek(p) {
    Some('^') => {
      let _ = RexParse::next(p)
      true
    }
    _ => false
  }
  let result : Array[NfaTrans] = []
  let mut go = true
  while go {
    match RexParse::peek(p) {
      None | Some(']') => go = false
      Some('\\') => {
        let _ = RexParse::next(p)
        for t in parse_escape_trans(p) {
          result.push(t)
        }
      }
      Some(c) => {
        let _ = RexParse::next(p)
        // 检查是否为区间：c '-' hi（其中 hi ≠ ']'）
        match RexParse::peek(p) {
          Some('-') =>
            match RexParse::peek2(p) {
              Some(']') | None => result.push(Ch(c))
              Some(_) => {
                let _ = RexParse::next(p) // consume '-'
                let hi = RexParse::next(p)
                result.push(Range(c, hi))
              }
            }
          _ => result.push(Ch(c))
        }
      }
    }
  }
  // consume ']'
  match RexParse::peek(p) {
    Some(']') => {
      let _ = RexParse::next(p)
      ()
    }
    _ => ()
  }
  // 否定类：Phase 2 近似为 Any
  if negated {
    [Any]
  } else {
    result
  }
}

///|
/// 解析原子（atom）；与 parse_alt 互递归
fn parse_atom(ctx : NfaCtx, p : RexParse) -> (Int, Int) {
  match RexParse::peek(p) {
    Some('(') => {
      let _ = RexParse::next(p)
      let (s, a) = parse_alt(ctx, p)
      match RexParse::peek(p) {
        Some(')') => {
          let _ = RexParse::next(p)
          ()
        }
        _ => ()
      }
      (s, a)
    }
    Some('[') => {
      let _ = RexParse::next(p)
      let ts = parse_char_class_trans(p)
      let s = NfaCtx::mk(ctx)
      let a = NfaCtx::mk(ctx)
      for t in ts {
        NfaCtx::edge(ctx, s, t, a)
      }
      (s, a)
    }
    Some('.') => {
      let _ = RexParse::next(p)
      nfa_from_any(ctx)
    }
    Some('\\') => {
      let _ = RexParse::next(p)
      let ts = parse_escape_trans(p)
      let s = NfaCtx::mk(ctx)
      let a = NfaCtx::mk(ctx)
      for t in ts {
        NfaCtx::edge(ctx, s, t, a)
      }
      (s, a)
    }
    Some('|') | Some(')') | Some('*') | Some('+') | Some('?') | None => {
      // 元字符 / EOF → ε 片段
      let s = NfaCtx::mk(ctx)
      (s, s)
    }
    Some(c) => {
      let _ = RexParse::next(p)
      let s = NfaCtx::mk(ctx)
      let a = NfaCtx::mk(ctx)
      NfaCtx::edge(ctx, s, Ch(c), a)
      (s, a)
    }
  }
}

///|
/// 解析带量词的 atom
fn parse_quant(ctx : NfaCtx, p : RexParse) -> (Int, Int) {
  let (s, a) = parse_atom(ctx, p)
  match RexParse::peek(p) {
    Some('*') => {
      let _ = RexParse::next(p)
      nfa_star(ctx, s, a)
    }
    Some('+') => {
      let _ = RexParse::next(p)
      nfa_plus(ctx, s, a)
    }
    Some('?') => {
      let _ = RexParse::next(p)
      nfa_opt(ctx, s, a)
    }
    _ => (s, a)
  }
}

///|
/// 解析连接串（隐式连接，直到 `|` `)` EOF 停止）
fn parse_concat(ctx : NfaCtx, p : RexParse) -> (Int, Int) {
  let stop = match RexParse::peek(p) {
    None | Some('|') | Some(')') => true
    _ => false
  }
  if stop {
    let s = NfaCtx::mk(ctx)
    return (s, s)
  }
  let (cs0, ca0) = parse_quant(ctx, p)
  let cs = cs0
  let mut ca = ca0
  let mut cont = true
  while cont {
    let should_stop = match RexParse::peek(p) {
      None | Some('|') | Some(')') => true
      _ => false
    }
    if should_stop {
      cont = false
    } else {
      let (ns, na) = parse_quant(ctx, p)
      nfa_concat(ctx, ca, ns)
      ca = na
    }
  }
  (cs, ca)
}

///|
/// 解析交替（`|`）
fn parse_alt(ctx : NfaCtx, p : RexParse) -> (Int, Int) {
  let (s0, a0) = parse_concat(ctx, p)
  let mut s = s0
  let mut a = a0
  let mut cont = true
  while cont {
    match RexParse::peek(p) {
      Some('|') => {
        let _ = RexParse::next(p)
        let (s2, a2) = parse_concat(ctx, p)
        let (ns, na) = nfa_alt_frag(ctx, s, a, s2, a2)
        s = ns
        a = na
      }
      _ => cont = false
    }
  }
  (s, a)
}

///|
/// 正则字符串 → NFA 片段
fn nfa_from_regex(ctx : NfaCtx, re : String) -> (Int, Int) {
  let p = RexParse::new(re)
  parse_alt(ctx, p)
}

// ─── 字母表收集 ──────────────────────────────────────────────────────────────

///|
/// 将字符区间 [lo, hi] 中的字符加入集合（在 range_chars 范围内展开）
fn add_range_chars(set : Set[Char], lo : Char, hi : Char) -> Unit {
  for c in range_chars {
    if lo <= c && c <= hi {
      set.add(c)
    }
  }
}

///|
/// 扫描正则字符串，将涉及的字符加入字母表（粗扫，不完整解析）
fn collect_regex_alphabet(re : String, set : Set[Char]) -> Unit {
  let p = RexParse::new(re)
  while p.pos < p.src.length() {
    match p.src[p.pos] {
      '\\' => {
        p.pos = p.pos + 1
        if p.pos < p.src.length() {
          match p.src[p.pos] {
            'd' => add_range_chars(set, '0', '9')
            'w' => {
              add_range_chars(set, 'a', 'z')
              add_range_chars(set, 'A', 'Z')
              add_range_chars(set, '0', '9')
              set.add('_')
            }
            's' => {
              set.add(' ')
              set.add('\t')
              set.add('\n')
              set.add('\r')
            }
            'n' => set.add('\n')
            't' => set.add('\t')
            'r' => set.add('\r')
            x => set.add(x)
          }
          p.pos = p.pos + 1
        }
      }
      '[' => {
        p.pos = p.pos + 1
        // skip optional '^'
        if p.pos < p.src.length() && p.src[p.pos] == '^' {
          p.pos = p.pos + 1
        }
        let mut in_cls = true
        while in_cls && p.pos < p.src.length() {
          match p.src[p.pos] {
            ']' => in_cls = false
            '\\' => {
              p.pos = p.pos + 1
              if p.pos < p.src.length() {
                match p.src[p.pos] {
                  'd' => add_range_chars(set, '0', '9')
                  'w' => {
                    add_range_chars(set, 'a', 'z')
                    add_range_chars(set, 'A', 'Z')
                    add_range_chars(set, '0', '9')
                    set.add('_')
                  }
                  's' => {
                    set.add(' ')
                    set.add('\t')
                    set.add('\n')
                    set.add('\r')
                  }
                  x => set.add(x)
                }
                p.pos = p.pos + 1
              }
            }
            lo => {
              p.pos = p.pos + 1
              // range: lo '-' hi (hi ≠ ']')
              if p.pos + 1 < p.src.length() &&
                p.src[p.pos] == '-' &&
                p.src[p.pos + 1] != ']' {
                p.pos = p.pos + 1
                let hi = p.src[p.pos]
                p.pos = p.pos + 1
                add_range_chars(set, lo, hi)
              } else {
                set.add(lo)
              }
            }
          }
        }
        if p.pos < p.src.length() && p.src[p.pos] == ']' {
          p.pos = p.pos + 1
        }
      }
      '.' => {
        for c in range_chars {
          set.add(c)
        }
        p.pos = p.pos + 1
      }
      '|' | '*' | '+' | '?' | '(' | ')' => p.pos = p.pos + 1
      c => {
        set.add(c)
        p.pos = p.pos + 1
      }
    }
  }
}

///|
/// 从 terminal_patterns 收集词法器字母表
fn collect_alphabet(grammar : AugmentedGrammar) -> Array[Char] {
  let set : Set[Char] = Set::new()
  for _, def in grammar.terminal_patterns {
    match def {
      Literal(s) => for c in s { set.add(c) }
      Regex(re) => collect_regex_alphabet(re, set)
      AnyChar => for c in range_chars { set.add(c) }
    }
  }
  set.to_array()
}

// ─── ε-closure ───────────────────────────────────────────────────────────────

///|
/// NFA 状态集合的 ε-closure（BFS）；返回已排序的去重状态数组
fn eps_closure(ctx : NfaCtx, init : Array[Int]) -> Array[Int] {
  let visited : Set[Int] = Set::new()
  let worklist : Array[Int] = []
  for s in init {
    if visited.add_and_check(s) {
      worklist.push(s)
    }
  }
  let mut i = 0
  while i < worklist.length() {
    let s = worklist[i]
    i = i + 1
    for edge in ctx.edges[s] {
      let (lbl, t) = edge
      match lbl {
        Eps => if visited.add_and_check(t) { worklist.push(t) }
        _ => ()
      }
    }
  }
  worklist
}

// ─── 子集构造辅助 ─────────────────────────────────────────────────────────────

///|
/// NFA 状态集合 → 字符串 key（用于 Map 去重）
fn nfa_set_key(states : Array[Int]) -> String {
  let arr : Array[Int] = []
  for s in states {
    arr.push(s)
  }
  arr.sort_by(fn(a, b) { a.compare(b) })
  // 去重
  let dedup : Array[Int] = []
  for s in arr {
    if dedup.length() == 0 || dedup[dedup.length() - 1] != s {
      dedup.push(s)
    }
  }
  let mut key = ""
  let mut first = true
  for s in dedup {
    if first {
      first = false
    } else {
      key = key + ","
    }
    key = key + "\{s}"
  }
  key
}

///|
/// NFA 状态集合 × 字符 → 可达 NFA 状态集合（不含 ε）
fn nfa_move(ctx : NfaCtx, states : Array[Int], ch : Char) -> Array[Int] {
  let result : Array[Int] = []
  for s in states {
    for edge in ctx.edges[s] {
      let (lbl, t) = edge
      let matches = match lbl {
        Eps => false
        Ch(c) => c == ch
        Range(lo, hi) => lo <= ch && ch <= hi
        Any => true
      }
      if matches {
        result.push(t)
      }
    }
  }
  result
}

// ─── 子集构造：NFA → DFA ─────────────────────────────────────────────────────

///|
/// 子集构造，返回 DFA 状态数组（下标即 DfaStateId）和起始状态 0。
///
/// `accept_info` : NFA 接受状态 → (TerminalId, priority)
/// `alphabet`    : 枚举的字符集
fn subset_construct(
  ctx : NfaCtx,
  super_start : Int,
  accept_info : Map[Int, (TerminalId, Int)],
  alphabet : Array[Char],
) -> Array[DfaState] {
  // DFA state = (sorted, deduped) NFA state array, keyed by string
  let dfa_nfa_sets : Array[Array[Int]] = []
  let key_to_dfa : Map[String, DfaStateId] = Map::new()
  // trans[dfa_id] = [(char, target_dfa)]
  let dfa_trans : Array[Array[(Char, DfaStateId)]] = []

  let init_set = eps_closure(ctx, [super_start])
  let init_key = nfa_set_key(init_set)
  dfa_nfa_sets.push(init_set)
  key_to_dfa.set(init_key, 0)
  dfa_trans.push([])

  let mut qi = 0
  while qi < dfa_nfa_sets.length() {
    let nfa_set = dfa_nfa_sets[qi]
    let this_trans = dfa_trans[qi]
    for ch in alphabet {
      let moved = nfa_move(ctx, nfa_set, ch)
      if moved.length() > 0 {
        let next_set = eps_closure(ctx, moved)
        if next_set.length() > 0 {
          let next_key = nfa_set_key(next_set)
          let target_id = match key_to_dfa.get(next_key) {
            Some(id) => id
            None => {
              let new_id = dfa_nfa_sets.length()
              dfa_nfa_sets.push(next_set)
              key_to_dfa.set(next_key, new_id)
              dfa_trans.push([])
              new_id
            }
          }
          this_trans.push((ch, target_id))
        }
      }
    }
    qi = qi + 1
  }

  // 组装 DfaState 数组
  let result : Array[DfaState] = []
  let mut did = 0
  while did < dfa_nfa_sets.length() {
    let nfa_set = dfa_nfa_sets[did]
    // 寻找优先级最小的接受 NFA 状态
    let mut best_pri = -1
    let mut best_tid : TerminalId = -1
    for nfa_s in nfa_set {
      match accept_info.get(nfa_s) {
        Some(pair) => {
          let (tid, pri) = pair
          if best_pri < 0 || pri < best_pri {
            best_pri = pri
            best_tid = tid
          }
        }
        None => ()
      }
    }
    let accept : TerminalId? = if best_tid >= 0 { Some(best_tid) } else { None }
    let transitions : Map[Char, DfaStateId] = Map::new()
    for tp in dfa_trans[did] {
      let (ch, tid2) = tp
      transitions.set(ch, tid2)
    }
    result.push({ id: did, transitions, accept })
    did = did + 1
  }
  result
}

// ─── valid_tokens 计算 ───────────────────────────────────────────────────────

///|
/// valid_tokens[s] = { t | action[(s,t)] ≠ ∅ } ∪ extras_set
fn build_valid_tokens(
  grammar : AugmentedGrammar,
  table : ParseTable,
) -> Map[StateId, Array[TerminalId]] {
  let extras_set : Set[TerminalId] = Set::new()
  for t in grammar.extras {
    extras_set.add(t)
  }
  let result : Map[StateId, Array[TerminalId]] = Map::new()
  let mut s = 0
  while s < table.states {
    let tids : Set[TerminalId] = Set::new()
    for _, t in grammar.terminals {
      match table.action.get((s, t)) {
        Some(acts) => if acts.length() > 0 { tids.add(t) }
        None => ()
      }
    }
    for t in grammar.extras {
      tids.add(t)
    }
    result.set(s, tids.to_array())
    s = s + 1
  }
  result
}

// ─── 优先级 ──────────────────────────────────────────────────────────────────

///|
/// 接受优先级（越小越优先）：Literal > Regex > AnyChar；同类内以 TerminalId 为次序
fn terminal_priority(tid : TerminalId, def : TerminalDef) -> Int {
  match def {
    Literal(_) => tid
    Regex(_) => 10000 + tid
    AnyChar => 20000 + tid
  }
}

// ─── 公开 API ────────────────────────────────────────────────────────────────

///|
/// 将 AugmentedGrammar 的全部终结符 Pattern 编译为上下文敏感词法器 DFA。
///
/// 算法：
///   1. 为每个终结符建立 Thompson NFA
///   2. 引入超级起始态 super_start，以 ε 连接各 NFA 入口
///   3. 子集构造（NFA → DFA），字母表从 terminal_patterns 中收集
///   4. 计算 valid_tokens：每个解析状态可合法扫描的终结符列表
///
/// Phase 3 TODO：Hopcroft DFA 最小化（当前直接使用子集构造输出）
pub fn build_lexer_dfa(
  grammar : AugmentedGrammar,
  table : ParseTable,
) -> LexerDfa {
  let ctx = NfaCtx::new()
  let super_start = NfaCtx::mk(ctx)

  // accept_info: NFA 接受态 → (TerminalId, priority)
  let accept_info : Map[Int, (TerminalId, Int)] = Map::new()

  for tid, def in grammar.terminal_patterns {
    let (ns, na) = match def {
      Literal(s) => nfa_from_literal(ctx, s)
      Regex(re) => nfa_from_regex(ctx, re)
      AnyChar => nfa_from_any(ctx)
    }
    NfaCtx::edge(ctx, super_start, Eps, ns)
    let pri = terminal_priority(tid, def)
    ctx.acc[na] = pri
    accept_info.set(na, (tid, pri))
  }

  let alphabet = collect_alphabet(grammar)
  let dfa_states = subset_construct(ctx, super_start, accept_info, alphabet)
  let valid_tokens = build_valid_tokens(grammar, table)

  { states: dfa_states, start: 0, valid_tokens }
}
