///|
// 词法引擎（LexerEngine）
//
// 职责：
//   · 从 input[pos..] 用 DFA 最长匹配扫描下一个 token
//   · context-aware：只匹配 valid_tokens[lr_state] ∪ extras 中的 terminal
//   · extras 识别后标记 is_extra=true（parser 决定如何处理）
//   · 单槽 token 缓存，GLR 多版本同位置复用
//   · 两阶段 keyword 检查：Regex/AnyChar 匹配后，在 valid 集合中查是否有同内容的 Literal，
//     若有则升级 terminal_id 并标记 is_keyword=true
//   · 外部词法器（external scanner）：若有回调，则在 DFA 之后对 ext_valid 中的
//     外部 token 尝试匹配；取 DFA 与外部结果中的较长者（外部优先等长时）

///|
/// 外部词法器回调类型
/// fn(input, pos, valid_external_tids) -> (matched_tid, end_pos)?
/// - 返回 None 表示未匹配；返回 Some((tid, end)) 表示从 pos 到 end 匹配了 tid
pub type ExternalScanner = (String, Int, Array[Int]) -> (Int, Int)?

///|
/// 词法引擎
pub struct LexerEngine {
  dfa : @tablegen.LexerDfa
  /// 单槽 DFA 结果缓存：GLR 多版本同位置时避免重复扫描
  mut cached_pos : Int
  mut cached_valid_hash : Int
  mut cached_result : (Token?, Int)
  /// 外部词法器回调（可选）
  external_scanner : ExternalScanner?
}

///|
pub fn LexerEngine::new(dfa : @tablegen.LexerDfa) -> LexerEngine {
  {
    dfa,
    cached_pos: -1,
    cached_valid_hash: 0,
    cached_result: (None, 0),
    external_scanner: None,
  }
}

///|
/// 创建携带外部词法器回调的 LexerEngine
pub fn LexerEngine::new_with_external(
  dfa : @tablegen.LexerDfa,
  scanner : ExternalScanner,
) -> LexerEngine {
  {
    dfa,
    cached_pos: -1,
    cached_valid_hash: 0,
    cached_result: (None, 0),
    external_scanner: Some(scanner),
  }
}

///|
/// 从 input[pos..] 扫描下一个 token。
/// 返回 (token?, new_pos)：
///   · token = None  → EOF（pos >= input.length()）
///   · token.terminal_id = sym_error(−1) → 词法错误（无法识别任何合法字符）
///   · 否则为正常 token，is_extra 标记是否属于 extras
///
/// state：当前 LR 状态（用于查 valid_tokens）
pub fn LexerEngine::next_token(
  self : LexerEngine,
  input : String,
  pos : Int,
  table : @tablegen.ParseTable,
  state : Int,
) -> (Token?, Int) {
  // 计算本状态下合法的终结符集合
  // valid_tokens[state] + extras
  let valid : Set[Int] = Set::new()
  match table.lexer_dfa.valid_tokens.get(state) {
    Some(ts) =>
      for t in ts {
        valid.add(t)
      }
    None => ()
  }
  for t in table.extras {
    valid.add(t)
  }

  self.scan_with_valid(input, pos, valid, table)
}

///|
/// 以调用方提供的 valid 集合作为上下文，执行 DFA + 外部词法器联合扫描。
///
/// 该入口用于：
/// - 线性 LR 路径（单状态 valid 集合）
/// - GLR 路径（多状态 valid 集合并集）
/// - EOF 位置的零宽 external token（如布局 dedent）
fn LexerEngine::scan_with_valid(
  self : LexerEngine,
  input : String,
  pos : Int,
  valid : Set[Int],
  table : @tablegen.ParseTable,
) -> (Token?, Int) {
  // 分离 DFA valid 和外部 token valid
  let ext_tids : Array[Int] = []
  for tid in table.external_token_ids {
    if valid.contains(tid) {
      ext_tids.push(tid)
    }
  }

  // EOF 时允许 external scanner 产生零宽 token；只有在非 EOF 时才运行 DFA。
  let (dfa_tok, dfa_pos) = if pos >= input.length() {
    (None, pos)
  } else {
    self.run_dfa(input, pos, valid, table)
  }

  // 外部词法器尝试（仅当有回调且有合法的外部 token）
  match self.external_scanner {
    None => (dfa_tok, dfa_pos)
    Some(scanner) =>
      if ext_tids.is_empty() {
        (dfa_tok, dfa_pos)
      } else {
        match scanner(input, pos, ext_tids) {
          None => (dfa_tok, dfa_pos) // 外部未匹配，使用 DFA 结果
          Some((ext_tid, ext_end)) => {
            if ext_end < pos {
              return (dfa_tok, dfa_pos)
            }
            // 外部匹配成功：与 DFA 结果比较，取较长者（等长时外部优先）
            let dfa_len = dfa_pos - pos
            let ext_len = ext_end - pos
            let prefer_external = ext_len == 0 || ext_len >= dfa_len
            if prefer_external {
              let mut is_extra = false
              for t in table.extras {
                if t == ext_tid {
                  is_extra = true
                  break
                }
              }
              let ext_tok : Token = {
                terminal_id: ext_tid,
                start_byte: pos,
                end_byte: ext_end,
                lookahead_bytes: ext_end,
                is_keyword: false,
                is_extra,
              }
              (Some(ext_tok), ext_end)
            } else {
              (dfa_tok, dfa_pos)
            }
          }
        }
      }
  }
}

///|
/// DFA 最长匹配核心
/// 返回 (token?, new_pos)
fn LexerEngine::run_dfa(
  self : LexerEngine,
  input : String,
  pos : Int,
  valid : Set[Int],
  table : @tablegen.ParseTable,
) -> (Token?, Int) {
  // 单槽缓存：同一起始位置且 valid 集相同时直接复用（GLR 多版本并行加速）
  // 多项式滚动哈希：h = h * 31 + t，避免 XOR 对不同集合碰撞的问题
  // （XOR 缺陷示例：{1,2} 与 {3} 均得到 3）
  let mut valid_hash = 17
  for t in valid {
    valid_hash = valid_hash * 31 + t
  }
  if pos == self.cached_pos && valid_hash == self.cached_valid_hash {
    return self.cached_result
  }
  let dfa = self.dfa
  let n = input.length()

  // 记录最后一次命中接受态时的 (terminal_id, pos)
  let mut best_tid : Int = -1
  let mut best_pos : Int = pos

  let mut cur_state : Int = dfa.start
  let mut cur_pos : Int = pos

  // 检查起始状态是否已是接受态（零宽 token，如 ε）
  match dfa.states[cur_state].accept {
    Some(tid) =>
      if valid.contains(tid) {
        best_tid = tid
        best_pos = cur_pos
      }
    None => ()
  }

  while cur_pos < n {
    let ch = input[cur_pos].to_int().to_char().unwrap()
    match dfa.states[cur_state].transitions.get(ch) {
      None => break // 无转移，停止
      Some(next) => {
        cur_state = next
        cur_pos = cur_pos + 1
        // 检查新状态是否是接受态
        match dfa.states[cur_state].accept {
          Some(tid) =>
            if valid.contains(tid) {
              best_tid = tid
              best_pos = cur_pos
            }
          None => ()
        }
      }
    }
  }

  // 没有任何合法匹配
  if best_tid == -1 {
    // 词法错误：跳过一字节，返回 error token
    let err_tok : Token = {
      terminal_id: sym_error,
      start_byte: pos,
      end_byte: pos + 1,
      lookahead_bytes: pos + 1,
      is_keyword: false,
      is_extra: false,
    }
    self.cached_pos = pos
    self.cached_valid_hash = valid_hash
    self.cached_result = (Some(err_tok), pos + 1)
    return self.cached_result
  }

  // 判断是否是 extras token
  let mut is_extra = false
  for t in table.extras {
    if t == best_tid {
      is_extra = true
      break
    }
  }

  // 两阶段 keyword 检查：若最佳 terminal 对应 Regex/AnyChar 模式，
  // 检查匹配文本是否等于某个合法 Literal terminal，若是则提升为该 keyword terminal。
  let matched_text = input[pos:best_pos].to_string()
  let mut final_tid = best_tid
  let mut is_keyword = false
  match table.terminal_patterns.get(best_tid) {
    Some(@tablegen.TerminalDef::Literal(_)) => () // 已经是 Literal，无需检查
    _ =>
      for t in valid {
        match table.terminal_patterns.get(t) {
          Some(@tablegen.TerminalDef::Literal(lit)) =>
            if lit == matched_text {
              final_tid = t
              is_keyword = true
              break
            }
          _ => ()
        }
      }
  }

  let tok : Token = {
    terminal_id: final_tid,
    start_byte: pos,
    end_byte: best_pos,
    lookahead_bytes: cur_pos, // DFA 实际停止位置（>= end_byte，增量边界检查用）
    is_keyword,
    is_extra,
  }
  self.cached_pos = pos
  self.cached_valid_hash = valid_hash
  self.cached_result = (Some(tok), best_pos)
  self.cached_result
}

///|
/// 将 input[start..end_byte) 的字节位置转换为 Point（行列坐标）
/// start_point：start_byte 对应的已知 Point（避免从头扫描）
pub fn bytes_to_point(
  input : String,
  start_byte : Int,
  start_point : Point,
  end_byte : Int,
) -> Point {
  let mut row = start_point.row
  let mut col = start_point.column
  let mut i = start_byte
  while i < end_byte {
    if input[i].to_int().to_char().unwrap() == '\n' {
      row = row + 1
      col = 0
    } else {
      col = col + 1
    }
    i = i + 1
  }
  { row, column: col }
}
