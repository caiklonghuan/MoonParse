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
}

///|
/// 单条校验错误
pub(all) struct ValidationError {
  /// 涉及的规则名（便于定位）
  rule : String
  /// 错误类别及附带信息
  kind : ValidationErrorKind
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
  }
}

// ─── 公开入口 ─────────────────────────────────────────────────────────────────

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

  // 1. start 规则存在性
  match grammar.start {
    Some(start_name) =>
      if not(grammar.rules.contains(start_name)) {
        errors.push({
          rule: start_name,
          kind: ValidationErrorKind::UndefinedStartRule(start_name),
        })
      }
    None => ()
  }

  // 2. 规则引用完整性
  for name, rule in grammar.rules {
    for ref_name in collect_rule_refs(rule.pattern) {
      if not(grammar.rules.contains(ref_name)) {
        errors.push({
          rule: name,
          kind: ValidationErrorKind::UndefinedRule(ref_name),
        })
      }
    }
  }

  // 3 & 4. 左递归检测（直接 + 间接）
  detect_left_recursion(grammar, errors)

  // 5. 可达性分析（仅当声明了 start）
  match grammar.start {
    Some(start_name) =>
      if grammar.rules.contains(start_name) {
        let reachable = reachable_from(grammar, start_name)
        for name, _ in grammar.rules {
          if not(reachable.contains(name)) {
            errors.push({
              rule: name,
              kind: ValidationErrorKind::UnreachableRule(name),
            })
          }
        }
      }
    None => ()
  }

  errors
}

// ─── 辅助：收集 Pattern 中直接引用的规则名 ────────────────────────────────────

///|
/// 递归收集 Pattern 中所有 RuleRef 名称（去重）
fn collect_rule_refs(pattern : Pattern) -> Array[String] {
  let result : Array[String] = []
  collect_rule_refs_into(pattern, result)
  result
}

///|
fn collect_rule_refs_into(pattern : Pattern, out : Array[String]) -> Unit {
  match pattern {
    RuleRef(name) => {
      // 去重
      let mut found = false
      for n in out {
        if n == name {
          found = true
          break
        }
      }
      if not(found) {
        out.push(name)
      }
    }
    Choice(ps) | Seq(ps) =>
      for p in ps {
        collect_rule_refs_into(p, out)
      }
    Repeat(p) | Plus(p) | Optional(p) | Not(p) | And(p) =>
      collect_rule_refs_into(p, out)
    Tagged(_, p) | Field(_, p) | RepeatRange(p, _, _) | Prec(_, _, p) =>
      collect_rule_refs_into(p, out)
    Literal(_) | Regex(_) | AnyChar => ()
  }
}

// ─── 辅助：收集一个 Pattern「序列首位」能直接展开到的规则名 ────────────────────
// 用于左递归检测：只关心「在消耗任何 token 之前就必须先展开的规则」

///|
/// 返回 pattern 在「不消耗任何 token」的前提下，可能首先展开到的规则名集合
/// Optional / Repeat / Not / And 因为可以空匹配，需要继续往后看，
/// 但对左递归检测来说只需要知道「第一步是否能直接跳到 RuleRef」
fn first_rule_refs(pattern : Pattern) -> Array[String] {
  let out : Array[String] = []
  first_rule_refs_into(pattern, out)
  out
}

///|
fn first_rule_refs_into(pattern : Pattern, out : Array[String]) -> Unit {
  match pattern {
    RuleRef(name) => push_unique(out, name)
    // 选择：每个分支都是候选首位
    Choice(ps) =>
      for p in ps {
        first_rule_refs_into(p, out)
      }
    // 序列：首位由第一个元素决定（若第一个可为空，继续看下一个——简化：只看第一个）
    Seq(ps) => if ps.length() > 0 { first_rule_refs_into(ps[0], out) }
    // 以下包装层透传
    Repeat(p) | Plus(p) | Optional(p) => first_rule_refs_into(p, out)
    Tagged(_, p) | Field(_, p) | RepeatRange(p, _, _) | Prec(_, _, p) =>
      first_rule_refs_into(p, out)
    // 非前缀操作符：前瞻不消耗 token，但展开后才是真正的首位
    Not(p) | And(p) => first_rule_refs_into(p, out)
    Literal(_) | Regex(_) | AnyChar => ()
  }
}

///|
fn push_unique(arr : Array[String], s : String) -> Unit {
  for item in arr {
    if item == s {
      return
    }
  }
  arr.push(s)
}

// ─── 辅助：左递归检测（DFS 环检测）─────────────────────────────────────────────

///|
fn detect_left_recursion(
  grammar : Grammar,
  errors : Array[ValidationError],
) -> Unit {
  // 对每条规则做 DFS，维护当前路径以记录间接环
  // visited: 全局已完成检测（避免重复探索）
  // on_path: 当前 DFS 路径上的节点（用于环检测）
  let visited : Array[String] = []
  let on_path : Array[String] = []
  let path_list : Array[String] = [] // 与 on_path 对应的有序列表，用于报错时还原环

  for rule_name, _ in grammar.rules {
    if not(arr_contains(visited, rule_name)) {
      dfs_left(grammar, rule_name, visited, on_path, path_list, errors)
    }
  }
}

///|
fn dfs_left(
  grammar : Grammar,
  name : String,
  visited : Array[String],
  on_path : Array[String],
  path_list : Array[String],
  errors : Array[ValidationError],
) -> Unit {
  // 发现环
  if arr_contains(on_path, name) {
    let cycle_start = arr_index(path_list, name)
    if cycle_start >= 0 {
      let cycle = path_list[cycle_start:].iter().collect()
      cycle.push(name) // 闭合环显示
      if cycle.length() == 2 {
        // 直接左递归（只有 [A, A]）
        errors.push({
          rule: name,
          kind: ValidationErrorKind::DirectLeftRecursion(name),
        })
      } else {
        // 已经在 errors 里找一遍，避免同一个环重复报告
        let already = ref_already_reported(errors, cycle)
        if not(already) {
          errors.push({
            rule: name,
            kind: ValidationErrorKind::IndirectLeftRecursion(cycle),
          })
        }
      }
    }
    return
  }
  if arr_contains(visited, name) {
    return
  }
  match grammar.rules.get(name) {
    None => return // 未定义规则已在引用校验阶段报告
    Some(rule) => {
      on_path.push(name)
      path_list.push(name)
      for ref_name in first_rule_refs(rule.pattern) {
        if ref_name == name {
          // 直接左递归
          let already = errors_has_direct(errors, name)
          if not(already) {
            errors.push({
              rule: name,
              kind: ValidationErrorKind::DirectLeftRecursion(name),
            })
          }
        } else {
          dfs_left(grammar, ref_name, visited, on_path, path_list, errors)
        }
      }
      // 退栈
      let idx = on_path.length() - 1
      if idx >= 0 {
        ignore(on_path.remove(idx))
      }
      let idx2 = path_list.length() - 1
      if idx2 >= 0 {
        ignore(path_list.remove(idx2))
      }
      visited.push(name)
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

// ─── 辅助：可达性分析 ─────────────────────────────────────────────────────────

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
