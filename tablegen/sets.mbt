///|
// ─── 符号属性集合计算 ──────────────────────────────────────────────────────
//
// 实现 design.md 的四个公开函数：
//   nullable(grammar, seq)     -> Bool
//   first_set(grammar, sym)    -> Set[TerminalId]
//   first_seq(grammar, seq)    -> Set[TerminalId]
//   follow_set(grammar, nt)    -> Set[TerminalId]
//
// 约定：EndOfInput 在 Set[TerminalId] 中用哨兵 eoi_id = -1 表示。
// 终结符 ID 由 normalize.mbt 从 0 起分配，-1 不会与任何真实 ID 冲突。

///|
/// EndOfInput（"$"）在 TerminalId 集合中的哨兵值
pub let eoi_id : TerminalId = -1

// ─── 内部：不动点计算 ─────────────────────────────────────────────────────────

///|
/// 判断产生式体在给定 nullable 表下是否可推导 ε。
/// 空体直接返回 true（对应 ε 产生式）。
fn body_is_nullable(
  nm : Map[NonTerminalId, Bool],
  body : Array[BodySymbol],
) -> Bool {
  let mut all = true
  let mut i = 0
  while all && i < body.length() {
    match body[i].symbol {
      Terminal(_) | EndOfInput => all = false
      NonTerminal(nt) =>
        all = match nm.get(nt) {
          Some(b) => b
          None => false
        }
    }
    i = i + 1
  }
  all
}

///|
/// 不动点迭代：计算 AugmentedGrammar 中所有非终结符的 nullable 标志。
fn compute_nullable(grammar : AugmentedGrammar) -> Map[NonTerminalId, Bool] {
  let nm : Map[NonTerminalId, Bool] = Map::new()
  for _, id in grammar.nonterminals {
    nm.set(id, false)
  }
  let mut changed = true
  while changed {
    changed = false
    for prod in grammar.productions {
      let already = match nm.get(prod.head) {
        Some(b) => b
        None => false
      }
      if !already && body_is_nullable(nm, prod.body) {
        nm.set(prod.head, true)
        changed = true
      }
    }
  }
  nm
}

///|
/// 不动点迭代：在已知 nullable 表下计算每个非终结符的 FIRST 集合。
///
/// - Terminal(t) 贡献 {t}；EndOfInput 贡献 {eoi_id}
/// - 若 body[i] 可 nullable，继续向右累积 body[i+1] 的 FIRST
/// - 快照后再合并，避免自环产生式（left-recursive）边读边改同一集合
fn compute_first(
  grammar : AugmentedGrammar,
  nm : Map[NonTerminalId, Bool],
) -> Map[NonTerminalId, Set[TerminalId]] {
  let fm : Map[NonTerminalId, Set[TerminalId]] = Map::new()
  for _, id in grammar.nonterminals {
    fm.set(id, Set::new())
  }
  let mut changed = true
  while changed {
    changed = false
    for prod in grammar.productions {
      let head_set = match fm.get(prod.head) {
        Some(s) => s
        None => {
          let s : Set[TerminalId] = Set::new()
          fm.set(prod.head, s)
          s
        }
      }
      let mut cont = true
      let mut i = 0
      while cont && i < prod.body.length() {
        match prod.body[i].symbol {
          Terminal(t) => {
            if !head_set.contains(t) {
              head_set.add(t)
              changed = true
            }
            cont = false
          }
          EndOfInput => {
            if !head_set.contains(eoi_id) {
              head_set.add(eoi_id)
              changed = true
            }
            cont = false
          }
          NonTerminal(nt) => {
            // 快照后合并，防止 nt == prod.head 时自环边读边写
            let nt_items = match fm.get(nt) {
              Some(s) => s.to_array()
              None => []
            }
            for t in nt_items {
              if !head_set.contains(t) {
                head_set.add(t)
                changed = true
              }
            }
            cont = match nm.get(nt) {
              Some(b) => b
              None => false
            }
          }
        }
        i = i + 1
      }
    }
  }
  fm
}

///|
/// 不动点迭代：在已知 nullable / FIRST 表下计算每个非终结符的 FOLLOW 集合。
///
/// 对每条产生式 A → α B β：
///   1. 将 FIRST(β) 加入 FOLLOW(B)
///   2. 若 β 全部可 nullable（含 β 为空），将 FOLLOW(A) 加入 FOLLOW(B)
fn compute_follow(
  grammar : AugmentedGrammar,
  nm : Map[NonTerminalId, Bool],
  fm : Map[NonTerminalId, Set[TerminalId]],
) -> Map[NonTerminalId, Set[TerminalId]] {
  let fow : Map[NonTerminalId, Set[TerminalId]] = Map::new()
  for _, id in grammar.nonterminals {
    fow.set(id, Set::new())
  }
  let mut changed = true
  while changed {
    changed = false
    for prod in grammar.productions {
      let n = prod.body.length()
      for idx in 0..<n {
        match prod.body[idx].symbol {
          NonTerminal(b_nt) => {
            let b_fow = match fow.get(b_nt) {
              Some(s) => s
              None => {
                let s : Set[TerminalId] = Set::new()
                fow.set(b_nt, s)
                s
              }
            }
            // 步骤 1：扫描 β = body[idx+1..n-1]，将 FIRST(β) 加入 FOLLOW(b_nt)
            let mut cont = true
            let mut j = idx + 1
            while cont && j < n {
              match prod.body[j].symbol {
                Terminal(t) => {
                  if !b_fow.contains(t) {
                    b_fow.add(t)
                    changed = true
                  }
                  cont = false
                }
                EndOfInput => {
                  if !b_fow.contains(eoi_id) {
                    b_fow.add(eoi_id)
                    changed = true
                  }
                  cont = false
                }
                NonTerminal(nt2) => {
                  let nt2_items = match fm.get(nt2) {
                    Some(s) => s.to_array()
                    None => []
                  }
                  for t in nt2_items {
                    if !b_fow.contains(t) {
                      b_fow.add(t)
                      changed = true
                    }
                  }
                  cont = match nm.get(nt2) {
                    Some(b) => b
                    None => false
                  }
                }
              }
              j = j + 1
            }
            // 步骤 2：β 全部可 nullable（cont 为 true）→ 将 FOLLOW(head) 加入 FOLLOW(b_nt)
            if cont {
              // 快照防止 b_nt == prod.head 时自环
              let head_items = match fow.get(prod.head) {
                Some(s) => s.to_array()
                None => []
              }
              for t in head_items {
                if !b_fow.contains(t) {
                  b_fow.add(t)
                  changed = true
                }
              }
            }
          }
          _ => ()
        }
      }
    }
  }
  fow
}

// ─── 公开 API ─────────────────────────────────────────────────────────────────

///|
/// 判断符号序列是否可推导出 ε。
/// - 空序列返回 true（等同于 ε 产生式）
/// - 含任意终结符 / EndOfInput 的序列返回 false
pub fn nullable(grammar : AugmentedGrammar, seq : Array[Symbol]) -> Bool {
  let nm = compute_nullable(grammar)
  let mut all = true
  let mut i = 0
  while all && i < seq.length() {
    match seq[i] {
      Terminal(_) | EndOfInput => all = false
      NonTerminal(nt) =>
        all = match nm.get(nt) {
          Some(b) => b
          None => false
        }
    }
    i = i + 1
  }
  all
}

///|
/// 计算单个符号的 FIRST 集合。
/// - Terminal(t)  → {t}
/// - EndOfInput   → {eoi_id}
/// - NonTerminal  → 不动点迭代结果（所有通过该 NT 可最左推导出的终结符）
pub fn first_set(grammar : AugmentedGrammar, sym : Symbol) -> Set[TerminalId] {
  match sym {
    Terminal(t) => {
      let s : Set[TerminalId] = Set::new()
      s.add(t)
      s
    }
    EndOfInput => {
      let s : Set[TerminalId] = Set::new()
      s.add(eoi_id)
      s
    }
    NonTerminal(nt) => {
      let nm = compute_nullable(grammar)
      let fm = compute_first(grammar, nm)
      match fm.get(nt) {
        Some(s) => s
        None => Set::new()
      }
    }
  }
}

///|
/// 计算符号序列 α 的 FIRST 集合。
/// 不含 ε 标记——可 nullable 性由 nullable() 函数单独查询。
pub fn first_seq(
  grammar : AugmentedGrammar,
  seq : Array[Symbol],
) -> Set[TerminalId] {
  let nm = compute_nullable(grammar)
  let fm = compute_first(grammar, nm)
  let result : Set[TerminalId] = Set::new()
  let mut cont = true
  let mut i = 0
  while cont && i < seq.length() {
    match seq[i] {
      Terminal(t) => {
        result.add(t)
        cont = false
      }
      EndOfInput => {
        result.add(eoi_id)
        cont = false
      }
      NonTerminal(nt) => {
        let nt_items = match fm.get(nt) {
          Some(s) => s.to_array()
          None => []
        }
        for t in nt_items {
          result.add(t)
        }
        cont = match nm.get(nt) {
          Some(b) => b
          None => false
        }
      }
    }
    i = i + 1
  }
  result
}

///|
/// 计算非终结符 nt 的 FOLLOW 集合。
/// EndOfInput 以哨兵 eoi_id = -1 表示（与 normalize.mbt 分配的终结符 ID 不重叠）。
pub fn follow_set(
  grammar : AugmentedGrammar,
  nt : NonTerminalId,
) -> Set[TerminalId] {
  let nm = compute_nullable(grammar)
  let fm = compute_first(grammar, nm)
  let fow = compute_follow(grammar, nm, fm)
  match fow.get(nt) {
    Some(s) => s
    None => Set::new()
  }
}
