///|
// 词法引擎（LexerEngine）
//
// 职责：
//   · 从 input[pos..] 用 DFA 最长匹配扫描下一个 token
//   · context-aware：只匹配 valid_tokens[lr_state] ∪ extras 中的 terminal
//   · extras 识别后标记 is_extra=true（parser 决定如何处理）
//   · 单槽 token 缓存，GLR 多版本同位置复用
//
// 暂不实现：
//   · 两阶段 keyword 检查
//   · 外部词法器（external scanner，不做）

///|
/// 词法引擎
pub struct LexerEngine {
  dfa : @tablegen.LexerDfa
  /// 单槽 DFA 结果缓存：GLR 多版本同位置时避免重复扫描
  mut cached_pos : Int
  mut cached_valid_hash : Int
  mut cached_result : (Token?, Int)
}

///|
pub fn LexerEngine::new(dfa : @tablegen.LexerDfa) -> LexerEngine {
  { dfa, cached_pos: -1, cached_valid_hash: 0, cached_result: (None, 0) }
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
  // EOF
  if pos >= input.length() {
    return (None, pos)
  }

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

  // DFA 最长匹配
  // 在 valid 集合内尝试匹配，取最长匹配的候选
  let (tok, new_pos) = self.run_dfa(input, pos, valid, table)
  (tok, new_pos)
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
  let mut valid_hash = 0
  for t in valid {
    valid_hash = valid_hash ^ t
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

  let tok : Token = {
    terminal_id: best_tid,
    start_byte: pos,
    end_byte: best_pos,
    lookahead_bytes: best_pos, // TODO: 应为 DFA 实际读到的最远位置
    is_keyword: false, // TODO: 两阶段 keyword 检查
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
