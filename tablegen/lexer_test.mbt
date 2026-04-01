// lexer_test.mbt — build_lexer_dfa() 黑盒测试
//
// 辅助函数 term_id / build_ag 复用自 sets_test.mbt；
// build_resolved 复用自 conflicts_test.mbt。
//
// 覆盖以下代码路径（lexer.mbt 763 行）：
//   nfa_from_literal       — 字面量链式跳转
//   nfa_from_any           — AnyChar 单步跳转
//   nfa_from_regex         — 完整正则解析器
//     parse_alt            — 交替 a|b
//     parse_concat         — 隐式连接
//     parse_quant          — 量词 *, +, ?
//     parse_atom           — 原子 char / [class] / . / \escape / (group)
//     parse_char_class_trans — 字符类区间展开 [a-z] [0-9]
//     parse_escape_trans   — 转义 \d
//   eps_closure            — ε-闭包（BFS）
//   subset_construct       — 子集构造 NFA→DFA
//   terminal_priority      — 接受优先级（Literal < Regex < AnyChar 数值）
//   build_valid_tokens     — 解析状态 → 合法 token 集合
//   build_lexer_dfa        — 端到端集成

// ─── 辅助函数 ─────────────────────────────────────────────────────────────────

///|
/// 完整流水线 + build_lexer_dfa，直接从 DSL 返回 LexerDfa
fn lexer_for(dsl : String) -> LexerDfa {
  let (aug, table, _) = build_resolved(dsl)
  build_lexer_dfa(aug, table)
}

///|
/// 模拟 DFA 逐字符转移；返回消耗全部输入后所在状态的接受 TerminalId，
/// 任何字符无对应 transition 则立即返回 None。
fn dfa_run(dfa : LexerDfa, input : String) -> TerminalId? {
  let mut state = dfa.start
  for ch in input {
    match dfa.states[state].transitions.get(ch) {
      Some(next) => state = next
      None => return None
    }
  }
  dfa.states[state].accept
}

// ─── 基本属性 ─────────────────────────────────────────────────────────────────

///|
test "DFA 基本属性：states 非空，start = 0" {
  let dfa = lexer_for("start s\nrule s: \"hello\"")
  assert_true(dfa.states.length() > 0)
  assert_eq(dfa.start, 0)
}

///|
test "Literal DFA 状态数 ≥ len+1" {
  // "hello"（5 字符）至少有 6 个 DFA 状态：start + 每字符一跳
  let dfa = lexer_for("start s\nrule s: \"hello\"")
  assert_true(dfa.states.length() >= 6)
}

// ─── nfa_from_literal ────────────────────────────────────────────────────────

///|
test "Literal 精确接受且拒绝前缀/超长/无关词" {
  let (aug, table, _) = build_resolved("start s\nrule s: \"if\"")
  let dfa = build_lexer_dfa(aug, table)
  let tid = term_id(aug, "lit:if")
  assert_eq(dfa_run(dfa, "if"), Some(tid))
  assert_eq(dfa_run(dfa, ""), None) // 空串：start 状态不接受
  assert_eq(dfa_run(dfa, "i"), None) // 前缀：接受状态在第 2 跳后
  assert_eq(dfa_run(dfa, "iff"), None) // 超长：接受后无 transition
  assert_eq(dfa_run(dfa, "hello"), None) // 无关词
}

///|
test "多 Literal 终结符各自独立接受" {
  let (aug, table, _) = build_resolved("start s\nrule s: \"if\" | \"else\"")
  let dfa = build_lexer_dfa(aug, table)
  let id_if = term_id(aug, "lit:if")
  let id_else = term_id(aug, "lit:else")
  assert_true(id_if != id_else)
  assert_eq(dfa_run(dfa, "if"), Some(id_if))
  assert_eq(dfa_run(dfa, "else"), Some(id_else))
  assert_eq(dfa_run(dfa, "elsif"), None)
  assert_eq(dfa_run(dfa, ""), None)
}

// ─── nfa_from_any ─────────────────────────────────────────────────────────────

///|
test "AnyChar 接受任意单字符，拒绝空串和多字符" {
  // '·' (U+00B7) 是 AnyChar 的 terminal key
  let (aug, table, _) = build_resolved("start s\nrule s: .")
  let dfa = build_lexer_dfa(aug, table)
  let tid = term_id(aug, "\u00b7")
  assert_eq(dfa_run(dfa, "a"), Some(tid))
  assert_eq(dfa_run(dfa, "Z"), Some(tid))
  assert_eq(dfa_run(dfa, "0"), Some(tid))
  assert_eq(dfa_run(dfa, ""), None) // 空串不接受
  assert_eq(dfa_run(dfa, "ab"), None) // 接受一字符后无 transition
}

// ─── parse_char_class_trans ──────────────────────────────────────────────────

///|
test "Regex 字符类 [0-9]+ 接受数字序列" {
  let (aug, table, _) = build_resolved("start s\nrule s: /[0-9]+/")
  let dfa = build_lexer_dfa(aug, table)
  let tid = term_id(aug, "re:[0-9]+")
  assert_eq(dfa_run(dfa, "0"), Some(tid))
  assert_eq(dfa_run(dfa, "42"), Some(tid))
  assert_eq(dfa_run(dfa, "999"), Some(tid))
  assert_eq(dfa_run(dfa, ""), None)
  assert_eq(dfa_run(dfa, "abc"), None)
  assert_eq(dfa_run(dfa, "1a"), None) // 数字后跟非数字，DFA 无 transition
}

///|
test "Regex 字符类 [a-z]+ 接受小写字母序列" {
  let dfa = lexer_for("start s\nrule s: /[a-z]+/")
  assert_true(dfa_run(dfa, "hello") is Some(_))
  assert_true(dfa_run(dfa, "x") is Some(_))
  assert_eq(dfa_run(dfa, ""), None)
  assert_eq(dfa_run(dfa, "Hello"), None) // 'H' 不在字母表中
  assert_eq(dfa_run(dfa, "0"), None)
}

// ─── parse_escape_trans ───────────────────────────────────────────────────────

///|
test "Regex 转义 \\d+ 等同 [0-9]+" {
  // DSL 中 /\d+/ 对应 MoonBit 源码字符串 "/\\d+/"
  let (aug, table, _) = build_resolved("start s\nrule s: /\\d+/")
  let dfa = build_lexer_dfa(aug, table)
  let tid = term_id(aug, "re:\\d+")
  assert_eq(dfa_run(dfa, "0"), Some(tid))
  assert_eq(dfa_run(dfa, "99"), Some(tid))
  assert_eq(dfa_run(dfa, "abc"), None)
  assert_eq(dfa_run(dfa, ""), None)
}

// ─── 量词 * + ? ───────────────────────────────────────────────────────────────

///|
test "Regex 量词 * — 起始态即接受，接受零或多个" {
  let dfa = lexer_for("start s\nrule s: /a*/")
  // a* 起始 DFA 状态本身就是接受态（含 ε-path 到 na_out）
  assert_true(dfa_run(dfa, "") is Some(_))
  assert_true(dfa_run(dfa, "a") is Some(_))
  assert_true(dfa_run(dfa, "aaaa") is Some(_))
  // 'b' 不在字母表，DFA 无 transition
  assert_eq(dfa_run(dfa, "b"), None)
  assert_eq(dfa_run(dfa, "ab"), None)
}

///|
test "Regex 量词 + — 起始态不接受，需至少一个字符" {
  let dfa = lexer_for("start s\nrule s: /a+/")
  assert_eq(dfa_run(dfa, ""), None) // 空串：start 状态不接受
  assert_true(dfa_run(dfa, "a") is Some(_))
  assert_true(dfa_run(dfa, "aaa") is Some(_))
}

///|
test "Regex 量词 ? — 接受零或恰好一个字符" {
  let dfa = lexer_for("start s\nrule s: /a?/")
  assert_true(dfa_run(dfa, "") is Some(_)) // 空串接受（start 可选）
  assert_true(dfa_run(dfa, "a") is Some(_)) // 单字符接受
  assert_eq(dfa_run(dfa, "aa"), None) // 接受一个 'a' 后无 transition
}

// ─── 交替 ─────────────────────────────────────────────────────────────────────

///|
test "Regex 交替 a|b — 接受各分支，拒绝拼接和其他字符" {
  let dfa = lexer_for("start s\nrule s: /a|b/")
  assert_true(dfa_run(dfa, "a") is Some(_))
  assert_true(dfa_run(dfa, "b") is Some(_))
  assert_eq(dfa_run(dfa, "c"), None) // 'c' 不在字母表
  assert_eq(dfa_run(dfa, "ab"), None) // 接受后无 transition
  assert_eq(dfa_run(dfa, ""), None) // 空串不接受
}

// ─── terminal_priority ───────────────────────────────────────────────────────

///|
test "接受优先级 Literal(tid) < Regex(10000+tid)，Literal 胜出" {
  let (aug, table, _) = build_resolved("start s\nrule s: \"if\" | /[a-z]+/")
  let dfa = build_lexer_dfa(aug, table)
  let lit_id = term_id(aug, "lit:if")
  let re_id = term_id(aug, "re:[a-z]+")
  // "if" 同时被 Literal 和 Regex 接受，Literal priority = tid < 10000+tid
  assert_eq(dfa_run(dfa, "if"), Some(lit_id))
  // "hello" / "from" 仅 Regex 接受
  assert_eq(dfa_run(dfa, "hello"), Some(re_id))
  assert_eq(dfa_run(dfa, "from"), Some(re_id))
}

///|
test "接受优先级 AnyChar(20000+tid) < Literal(tid)，Literal 胜出" {
  let (aug, table, _) = build_resolved("start s\nrule s: \"x\" | .")
  let dfa = build_lexer_dfa(aug, table)
  let lit_id = term_id(aug, "lit:x")
  let any_id = term_id(aug, "\u00b7")
  // "x" 两路都能接受，Literal priority 更低，胜出
  assert_eq(dfa_run(dfa, "x"), Some(lit_id))
  // 其他单字符仅 AnyChar 接受
  assert_eq(dfa_run(dfa, "a"), Some(any_id))
  assert_eq(dfa_run(dfa, "0"), Some(any_id))
}

// ─── Unicode charset range ───────────────────────────────────────────────────

///|
test "Regex Unicode range [α-ω] accepts Greek letters" {
  let dfa = lexer_for("start s\nrule s: /[α-ω]+/")
  assert_true(dfa_run(dfa, "α") is Some(_))
  assert_true(dfa_run(dfa, "ω") is Some(_))
  assert_true(dfa_run(dfa, "λ") is Some(_))
  assert_eq(dfa_run(dfa, "a"), None) // ASCII letter outside range
  assert_eq(dfa_run(dfa, ""), None)
}

///|
test "Regex Unicode range [中-龥] accepts CJK characters" {
  let dfa = lexer_for("start s\nrule s: /[中-龥]+/")
  assert_true(dfa_run(dfa, "中") is Some(_))
  assert_true(dfa_run(dfa, "文") is Some(_))
  assert_eq(dfa_run(dfa, "a"), None)
  assert_eq(dfa_run(dfa, "α"), None)
}

// ─── build_valid_tokens ───────────────────────────────────────────────────────

///|
test "valid_tokens 至少一个解析状态含非空 token 列表" {
  let dfa = lexer_for("start s\nrule s: \"a\" \"b\"")
  let mut any_nonempty = false
  for _, tokens in dfa.valid_tokens {
    if tokens.length() > 0 {
      any_nonempty = true
    }
  }
  assert_true(any_nonempty)
}

///|
test "valid_tokens 条目数等于 ParseTable.states 数" {
  let (aug, table, _) = build_resolved("start s\nrule s: \"a\" \"b\"")
  let dfa = build_lexer_dfa(aug, table)
  assert_eq(dfa.valid_tokens.length(), table.states)
}
