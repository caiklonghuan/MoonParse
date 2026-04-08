// Grammar 校验层
// 对已解析的 Grammar 做语义检查，收集全部错误而不提前中止

///|
/// 校验错误类别
pub(all) enum ValidationErrorKind {
  /// 引用了不存在的规则
  UndefinedRule(String)
  /// start 声明指向的规则不存在
  UndefinedStartRule(String)
  /// 规则存在直接左递归（A -> A …）
  DirectLeftRecursion(String)
  /// 规则存在间接左递归（A -> B -> … -> A）
  IndirectLeftRecursion(Array[String])
  /// 规则不可从 start 到达（仅在声明了 start 时报告）
  UnreachableRule(String)
  /// 规则体中的正则表达式语法非法（regex, error_message）
  InvalidRegex(String, String)
}

///|
/// 单条校验错误
pub(all) struct ValidationError {
  /// 涉及的规则名（便于定位）
  rule : String
  /// 错误类别及附带信息
  kind : ValidationErrorKind
  /// 规则名在源码中的位置（行列）
  location : SourceLocation?
}

///|
/// 将校验错误转换为可读字符串
pub fn ValidationError::to_string(self : ValidationError) -> String {
  match self.kind {
    UndefinedRule(ref_name) =>
      "rule '\{self.rule}': references undefined rule '\{ref_name}'"
    UndefinedStartRule(name) =>
      "start rule '\{name}' is not defined in the grammar"
    DirectLeftRecursion(name) =>
      "rule '\{name}': direct left recursion detected"
    IndirectLeftRecursion(cycle) =>
      "indirect left recursion cycle: " + cycle.join(" -> ")
    UnreachableRule(name) => "rule '\{name}' is unreachable from start"
    InvalidRegex(re, msg) =>
      "rule '\{self.rule}': invalid regex '/" + re + "/': " + msg
  }
}

// 公开入口

///|
/// 对已解析的 Grammar 进行语义校验，返回所有错误（不提前中止）
///
/// 检查项：
/// 1. start 规则是否存在
/// 2. 规则体内的 RuleRef 是否都有对应定义
/// 3. 直接左递归（A 的第一个可能 token 是 A 本身）
/// 4. 间接左递归（通过 DFS 环检测）
/// 5. 从 start 出发的可达性（仅在声明了 start 时执行）
pub fn validate_grammar(grammar : Grammar) -> Array[ValidationError] {
  let errors : Array[ValidationError] = []

  // start 规则存在性
  match grammar.start {
    Some(start_name) =>
      if not(grammar.rules.contains(start_name)) {
        errors.push({
          rule: start_name,
          kind: ValidationErrorKind::UndefinedStartRule(start_name),
          location: None,
        })
      }
    None => ()
  }

  // 规则引用完整性
  for name, rule in grammar.rules {
    for ref_name in collect_rule_refs(rule.pattern) {
      if not(grammar.rules.contains(ref_name)) {
        errors.push({
          rule: name,
          kind: ValidationErrorKind::UndefinedRule(ref_name),
          location: match grammar.rules.get(name) {
            Some(r) => r.location
            None => None
          },
        })
      }
    }
  }

  // 3 & 4. 左递归检测（直接 + 间接）
  detect_left_recursion(grammar, errors)

  // 5. 正则表达式语法校验
  for name, rule in grammar.rules {
    let regexes : Array[String] = []
    collect_regex_patterns(rule.pattern, regexes)
    for re in regexes {
      match validate_regex_syntax(re) {
        Some(msg) =>
          errors.push({
            rule: name,
            kind: ValidationErrorKind::InvalidRegex(re, msg),
            location: match grammar.rules.get(name) {
              Some(r) => r.location
              None => None
            },
          })
        None => ()
      }
    }
  }

  // 可达性分析（仅当声明了 start）
  match grammar.start {
    Some(start_name) =>
      if grammar.rules.contains(start_name) {
        let reachable = reachable_from(grammar, start_name)
        for name, _ in grammar.rules {
          if not(reachable.contains(name)) {
            errors.push({
              rule: name,
              kind: ValidationErrorKind::UnreachableRule(name),
              location: match grammar.rules.get(name) {
                Some(r) => r.location
                None => None
              },
            })
          }
        }
      }
    None => ()
  }

  errors
}

// 辅助：收集 Pattern 中直接引用的规则名

///|
/// 递归收集 Pattern 中所有 RuleRef 名称（去重）
fn collect_rule_refs(pattern : Pattern) -> Array[String] {
  let seen : Set[String] = Set::new()
  collect_rule_refs_into(pattern, seen)
  seen.to_array()
}

///|
fn collect_rule_refs_into(pattern : Pattern, out : Set[String]) -> Unit {
  match pattern {
    RuleRef(name) => out.add(name)
    Choice(ps) | Seq(ps) =>
      for p in ps {
        collect_rule_refs_into(p, out)
      }
    Repeat(p) | Plus(p) | Optional(p) | Not(p) | And(p) =>
      collect_rule_refs_into(p, out)
    Tagged(_, p)
    | Field(_, p)
    | RepeatRange(p, _, _)
    | Prec(_, _, p)
    | Alias(_, p) => collect_rule_refs_into(p, out)
    Literal(_) | Regex(_) | AnyChar => ()
  }
}

// 辅助：判断 Pattern 是否可以不消耗 token 就匹配成功（可空性检测，浅层）

///|
/// 浅层可空性判断：若 Pattern 本身可以零宽匹配则返回 true。
/// 此处只关心结构层可空性（Repeat/Optional/Not/And），不递归追踪 RuleRef。
fn is_trivially_nullable(pattern : Pattern) -> Bool {
  match pattern {
    Repeat(_) | Optional(_) | Not(_) | And(_) => true
    _ => false
  }
}

// 辅助：收集一个 Pattern「序列首位」能直接展开到的规则名
// 用于左递归检测：只关心「在消耗任何 token 之前就必须先展开的规则」

///|
/// 返回 pattern 在「不消耗任何 token」的前提下，可能首先展开到的规则名集合
/// Optional / Repeat / Not / And 因为可以空匹配，需要继续往后看，
/// 但对左递归检测来说只需要知道「第一步是否能直接跳到 RuleRef」
fn first_rule_refs(pattern : Pattern) -> Array[String] {
  let out : Set[String] = Set::new()
  first_rule_refs_into(pattern, out)
  out.to_array()
}

///|
fn first_rule_refs_into(pattern : Pattern, out : Set[String]) -> Unit {
  match pattern {
    RuleRef(name) => out.add(name)
    // 选择：每个分支都是候选首位
    Choice(ps) =>
      for p in ps {
        first_rule_refs_into(p, out)
      }
    // 序列：首位由第一个元素决定；若前缀元素可为空，继续向后传播
    Seq(ps) =>
      for p in ps {
        first_rule_refs_into(p, out)
        if not(is_trivially_nullable(p)) {
          break
        }
      }
    // 以下包装层透传
    Repeat(p) | Plus(p) | Optional(p) => first_rule_refs_into(p, out)
    Tagged(_, p)
    | Field(_, p)
    | RepeatRange(p, _, _)
    | Prec(_, _, p)
    | Alias(_, p) => first_rule_refs_into(p, out)
    // 非前缀操作符：前瞻不消耗 token，但展开后才是真正的首位
    Not(p) | And(p) => first_rule_refs_into(p, out)
    Literal(_) | Regex(_) | AnyChar => ()
  }
}

// 辅助：左递归检测（DFS 环检测）

///|
fn detect_left_recursion(
  grammar : Grammar,
  errors : Array[ValidationError],
) -> Unit {
  // visited: Set — 全局已完成检测（O(1) 查找）
  // on_path_set: Set — 当前 DFS 路径上的节点（O(1) 环检测）
  // path_list: Array — 当前路径有序列表，用于报错时还原环
  let visited : Set[String] = Set::new()
  let on_path_set : Set[String] = Set::new()
  let path_list : Array[String] = []

  for rule_name, _ in grammar.rules {
    if not(visited.contains(rule_name)) {
      dfs_left(grammar, rule_name, visited, on_path_set, path_list, errors)
    }
  }
}

///|
fn dfs_left(
  grammar : Grammar,
  name : String,
  visited : Set[String],
  on_path : Set[String],
  path_list : Array[String],
  errors : Array[ValidationError],
) -> Unit {
  // 发现环
  if on_path.contains(name) {
    let cycle_start = arr_index(path_list, name)
    if cycle_start >= 0 {
      let cycle = path_list[cycle_start:].iter().collect()
      cycle.push(name) // 闭合环显示
      if cycle.length() == 2 {
        // 直接左递归（只有 [A, A]）
        errors.push({
          rule: name,
          kind: ValidationErrorKind::DirectLeftRecursion(name),
          location: match grammar.rules.get(name) {
            Some(r) => r.location
            None => None
          },
        })
      } else {
        // 已经在 errors 里找一遗，避免同一个环重复报告
        let already = ref_already_reported(errors, cycle)
        if not(already) {
          errors.push({
            rule: name,
            kind: ValidationErrorKind::IndirectLeftRecursion(cycle),
            location: match grammar.rules.get(name) {
              Some(r) => r.location
              None => None
            },
          })
        }
      }
    }
    return
  }
  if visited.contains(name) {
    return
  }
  match grammar.rules.get(name) {
    None => return // 未定义规则已在引用校验阶段报告
    Some(rule) => {
      on_path.add(name)
      path_list.push(name)
      for ref_name in first_rule_refs(rule.pattern) {
        if ref_name == name {
          // 直接左递归
          let already = errors_has_direct(errors, name)
          if not(already) {
            errors.push({
              rule: name,
              kind: ValidationErrorKind::DirectLeftRecursion(name),
              location: match grammar.rules.get(name) {
                Some(r) => r.location
                None => None
              },
            })
          }
        } else {
          dfs_left(grammar, ref_name, visited, on_path, path_list, errors)
        }
      }
      // 退栈
      on_path.remove(name)
      let idx2 = path_list.length() - 1
      if idx2 >= 0 {
        ignore(path_list.remove(idx2))
      }
      visited.add(name)
    }
  }
}

///|
fn arr_contains(arr : Array[String], s : String) -> Bool {
  for item in arr {
    if item == s {
      return true
    }
  }
  false
}

///|
fn arr_index(arr : Array[String], s : String) -> Int {
  for i in 0..<arr.length() {
    if arr[i] == s {
      return i
    }
  }
  -1
}

///|
fn errors_has_direct(errors : Array[ValidationError], name : String) -> Bool {
  for e in errors {
    match e.kind {
      ValidationErrorKind::DirectLeftRecursion(n) =>
        if n == name {
          return true
        }
      _ => ()
    }
  }
  false
}

///|
fn ref_already_reported(
  errors : Array[ValidationError],
  cycle : Array[String],
) -> Bool {
  // 简单判断：cycle 中的第一个节点已经在某个 IndirectLeftRecursion 里
  if cycle.length() == 0 {
    return false
  }
  let head = cycle[0]
  for e in errors {
    match e.kind {
      ValidationErrorKind::IndirectLeftRecursion(c) =>
        if arr_contains(c, head) {
          return true
        }
      _ => ()
    }
  }
  false
}

// 辅助：可达性分析

///|
/// 从 start_name 出发，BFS/DFS 收集所有可达规则名
fn reachable_from(grammar : Grammar, start_name : String) -> Array[String] {
  let visited : Array[String] = []
  let queue : Array[String] = [start_name]
  while queue.length() > 0 {
    let current = queue.remove(0)
    if arr_contains(visited, current) {
      continue
    }
    visited.push(current)
    match grammar.rules.get(current) {
      None => ()
      Some(rule) =>
        for ref_name in collect_rule_refs(rule.pattern) {
          if not(arr_contains(visited, ref_name)) {
            queue.push(ref_name)
          }
        }
    }
  }
  visited
}

// 辅助：正则表达式语法校验

///|
/// 递归收集 Pattern 中所有 Regex 原始字符串（含嵌套）
fn collect_regex_patterns(pattern : Pattern, out : Array[String]) -> Unit {
  match pattern {
    Regex(re) => out.push(re)
    Choice(ps) | Seq(ps) =>
      for p in ps {
        collect_regex_patterns(p, out)
      }
    Repeat(p) | Plus(p) | Optional(p) | Not(p) | And(p) =>
      collect_regex_patterns(p, out)
    Tagged(_, p)
    | Field(_, p)
    | RepeatRange(p, _, _)
    | Prec(_, _, p)
    | Alias(_, p) => collect_regex_patterns(p, out)
    RuleRef(_) | Literal(_) | AnyChar => ()
  }
}

///|
/// 对正则表达式字符串做浅层语法校验（括号/括弧平衡、尾部反斜杠检测）。
/// 返回 None 表示合法，Some(error_msg) 表示发现问题。
fn validate_regex_syntax(re : String) -> String? {
  let chars : Array[Char] = []
  for c in re {
    chars.push(c)
  }
  let mut paren_depth = 0
  let mut i = 0
  while i < chars.length() {
    match chars[i] {
      '\\' => {
        // 跳过转义字符；末尾孤立的 \ 为非法
        if i + 1 >= chars.length() {
          return Some("trailing backslash")
        }
        i = i + 2
      }
      '(' => {
        paren_depth = paren_depth + 1
        i = i + 1
      }
      ')' => {
        paren_depth = paren_depth - 1
        if paren_depth < 0 {
          return Some("unmatched ')'")
        }
        i = i + 1
      }
      '[' => {
        i = i + 1
        // 跳过可选的 '^'
        if i < chars.length() && chars[i] == '^' {
          i = i + 1
        }
        // 扫描至 ']'
        let mut found_close = false
        while i < chars.length() {
          if chars[i] == ']' {
            found_close = true
            i = i + 1
            break
          } else if chars[i] == '\\' {
            i = i + 2 // 跳过转义
          } else {
            i = i + 1
          }
        }
        if not(found_close) {
          return Some("unclosed '['")
        }
      }
      _ => i = i + 1
    }
  }
  if paren_depth != 0 {
    return Some("unclosed '('")
  }
  None
}
