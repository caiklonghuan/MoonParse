///|
// 线性 LR 解析器
//
// 实现最基础的单栈确定性 LR 解析循环：
//   · 初始状态 1（state 0 保留为 ERROR 哨兵，遵照 tree-sitter 惯例）
//   · extras token：推入 node_stack，不推 state_stack（LR 状态不变）
//   · trailing extras：reduce 时分离，推回到新内部节点之后
//   · 限制：GLR 冲突取第一个动作；语法错误直接返回 Err
//
// 注：state_stack[0] = 1（初始状态，永不弹出）

///|
/// 线性 LR 解析器（单栈）
///
/// state_stack：仅含非 extras 的 LR 状态，最底一项永远是初始状态 1。
/// node_stack ：含 extras 和非 extras 的全部 CstNode，按推入顺序排列。
/// 仅用于全量解析和测试基准；增量解析由 GlrEngine 负责。
struct LrParser {
  state_stack : Array[Int]
  node_stack : Array[CstNode]
  lexer : LexerEngine
}

///|
fn LrParser::new(lexer : LexerEngine) -> LrParser {
  { state_stack: [0], node_stack: [], lexer }
}

///|
fn LrParser::top_state(self : LrParser) -> Int {
  self.state_stack[self.state_stack.length() - 1]
}

///|
/// 从 input 解析完整 CST。
/// 语法错误时返回 Err；GLR 冲突取第一个动作（非歧义文法专用）。
pub fn parse_linear(
  table : @tablegen.ParseTable,
  input : String,
) -> Result[CstNode, ParseError] {
  let lexer = LexerEngine::new(table.lexer_dfa)
  let parser = LrParser::new(lexer)
  parser.run(table, input)
}

///|
/// LR 主循环
fn LrParser::run(
  self : LrParser,
  table : @tablegen.ParseTable,
  input : String,
) -> Result[CstNode, ParseError] {
  let mut pos : Int = 0
  let mut cur_point : Point = { row: 0, column: 0 }
  while true {
    let state = self.top_state()

    // 词法：每轮用当前 LR 状态扫描（context-aware）
    let (maybe_tok, after_tok_pos) = self.lexer.next_token(
      input, pos, table, state,
    )

    match maybe_tok {
      // EOF
      None =>
        // 用 eoi_id（= -1）查 action 表
        match table.action.get((state, @tablegen.eoi_id)) {
          None =>
            return Err({
              position: pos,
              point: cur_point,
              message: "unexpected EOF at state \{state}",
            })
          Some(acts) => {
            if acts.is_empty() {
              return Err({
                position: pos,
                point: cur_point,
                message: "no action on EOF",
              })
            }
            match acts[0] {
              Accept => return self.collect_root(pos, cur_point)
              Reduce(prod_id) =>
                match self.do_reduce(table, prod_id, pos, cur_point) {
                  Err(e) => return Err(e)
                  Ok(_) => ()
                }
              // Shift on EOF：增广文法 $accept → start • $ 过渡到 accept 状态
              // 不消耗输入，不推 CST 节点，只推 state
              Shift(next_state) => self.state_stack.push(next_state)
            }
          }
        }
      // 非 EOF token
      Some(tok) => {
        // 词法错误：terminal_id == sym_error（= -1 = eoi_id 数值上相同）
        // 必须在 action 表查询前识别，否则会把词法错误当 EOF 处理
        if tok.terminal_id == sym_error {
          return Err({
            position: tok.start_byte,
            point: cur_point,
            message: "lexer error: unrecognized character at byte \{tok.start_byte}",
          })
        }

        // extras token：推入 node_stack，不改变 LR 状态
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
            state,
            tok.lookahead_bytes,
            tok.is_keyword,
            true,
          )
          cur_point = ep
          self.node_stack.push(extra_node)
          pos = after_tok_pos
        } else {
          // 普通 token：查 action 表
          match table.action.get((state, tok.terminal_id)) {
            None =>
              return Err({
                position: tok.start_byte,
                point: cur_point,
                message: "syntax error: unexpected token (id=\{tok.terminal_id}) at byte \{tok.start_byte}",
              })
            Some(acts) => {
              if acts.is_empty() {
                return Err({
                  position: tok.start_byte,
                  point: cur_point,
                  message: "empty action list in table",
                })
              }
              // 多动作时取第一个（GLR 冲突在 glr_parse 中并行处理）
              match acts[0] {
                Shift(next_state) => {
                  let ep = bytes_to_point(
                    input,
                    tok.start_byte,
                    cur_point,
                    tok.end_byte,
                  )
                  let node = CstNode::leaf(
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
                  cur_point = ep
                  pos = after_tok_pos
                  self.state_stack.push(next_state)
                  self.node_stack.push(node)
                }
                Reduce(prod_id) =>
                  // 不消耗 token（pos / cur_point 保持不变）
                  match self.do_reduce(table, prod_id, pos, cur_point) {
                    Err(e) => return Err(e)
                    Ok(_) => ()
                  }
                Accept => return self.collect_root(pos, cur_point)
              }
            }
          }
        }
      }
    }
  }
  // 理论上不可达（while true 内所有路径均 return 或继续下一轮）
  Err({ position: 0, point: { row: 0, column: 0 }, message: "unreachable" })
}

///|
/// 执行一次 Reduce 动作
fn LrParser::do_reduce(
  self : LrParser,
  table : @tablegen.ParseTable,
  prod_id : @tablegen.ProductionId,
  pos : Int,
  cur_pt : Point,
) -> Result[Unit, ParseError] {
  let prod = table.productions[prod_id]
  let body_len = prod.body.length()

  // 从 state_stack 弹出 body_len 个状态（保留底部哨兵）
  let max_pop = self.state_stack.length() - 1
  let real_pops = if body_len < max_pop { body_len } else { max_pop }
  let mut i = 0
  while i < real_pops {
    let _ = self.state_stack.pop()
    i = i + 1
  }

  // 从 node_stack 收集对应子节点（含 extras）
  // 依次从栈顶弹出，直到累计 real_pops 个非 extras 节点
  let raw : Array[CstNode] = []
  let mut real_count = 0
  while real_count < real_pops && not(self.node_stack.is_empty()) {
    match self.node_stack.pop() {
      None => break
      Some(n) => {
        raw.push(n)
        if not(n.extra) {
          real_count = real_count + 1
        }
      }
    }
  }
  // raw 目前是倒序（最后推入的在 raw[0]）→ 反转得到左→右顺序
  array_rev_inplace(raw)

  // 分离 trailing extras
  // 产生式体末端之后的 extras 在 reduce 后需成为新内部节点的后续兄弟节点
  let trailing : Array[CstNode] = []
  while not(raw.is_empty()) {
    let last = raw[raw.length() - 1]
    if last.extra {
      let _ = raw.pop()
      trailing.push(last)
    } else {
      break
    }
  }
  // trailing 同样需要反转（使其恢复原顺序：最早的 extra 在前）
  array_rev_inplace(trailing)

  // 弹出后的栈顶状态
  let base_state = self.state_stack[self.state_stack.length() - 1]

  // 查 goto 表
  let nt = prod.head
  match table.goto_table.get((base_state, nt)) {
    None =>
      Err({
        position: pos,
        point: cur_pt,
        message: "goto missing: nt=\{nt} from state=\{base_state}",
      })
    Some(goto_st) => {
      // 构造内部节点
      let meta : @tablegen.SymbolMeta = if nt < table.symbol_metadata.length() {
        table.symbol_metadata[nt]
      } else {
        { name: "?", is_named: false }
      }
      let fnames : Array[String?] = prod.body.map(fn(bs) { bs.field_name })
      let inner = CstNode::inner(
        nt,
        meta.is_named,
        raw,
        fnames,
        prod.id,
        0,
        false,
        false,
      )

      // 推入新状态与内部节点
      self.state_stack.push(goto_st)
      self.node_stack.push(inner)

      // 重新推入 trailing extras（不影响 state_stack）
      for ex in trailing {
        self.node_stack.push(ex)
      }
      Ok(())
    }
  }
}

///|
/// Accept 时从 node_stack 中找到最后一个非 extras 节点作为根
fn LrParser::collect_root(
  self : LrParser,
  pos : Int,
  cur_pt : Point,
) -> Result[CstNode, ParseError] {
  let mut j = self.node_stack.length() - 1
  while j >= 0 {
    let n = self.node_stack[j]
    if not(n.extra) {
      return Ok(n)
    }
    j = j - 1
  }
  Err({ position: pos, point: cur_pt, message: "accept: no root node on stack" })
}

///|
/// 原地反转数组（辅助函数）
fn[T] array_rev_inplace(arr : Array[T]) -> Unit {
  let n = arr.length()
  let mut lo = 0
  let mut hi = n - 1
  while lo < hi {
    let tmp = arr[lo]
    arr[lo] = arr[hi]
    arr[hi] = tmp
    lo = lo + 1
    hi = hi - 1
  }
}
