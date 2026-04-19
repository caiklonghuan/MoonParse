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
  /// 规则被重复定义（同名规则出现多次）
  DuplicateRule(String)
  /// 同时使用了顶层 precedence 声明和内联 prec(n,p) 两套优先级机制
  MixedPrecSystems
  /// extras 列表中出现了非终结符模式（extras 只允许 Literal / Regex / AnyChar）
  ExtrasNonTerminal(String)
  /// 模板规则实例化中引用了未定义的或非模板规则（rule_name）
  UndefinedTemplateRule(String)
  /// 模板实例化参数数量与模板声明不一致（rule_name, expected, got）
  RuleAppArityMismatch(String, Int, Int)
  /// 普通 RuleRef 引用了参数化模板规则（需用 name[...] 实例化）
  TemplateRuleUsedAsRef(String)
  /// word 声明指向的规则不存在
  UndefinedWordRule(String)
  /// token rule 的 pattern 中引用了非 token 的语法规则（rule_name）
  TokenRuleContainsRef(String)
  /// conflicts 声明中出现了未定义的规则名（rule_name）
  ConflictUndeclaredRule(String)
  /// supertypes 声明中出现了未定义的规则名
  SupertypeUndeclaredRule(String)
  /// 非已废弃规则引用了 @deprecated 标记的规则（警告）
  DeprecatedRuleUsed(String)
  /// Not / And 断言出现在 Seq 非末尾位置（运行时无法作用于 reduce 点，会被静默丢弃）
  LookaheadNonTailAssertion
  /// Seq 尾部同时含有 &p（FollowedBy）和 !p（NotFollowedBy）两类断言
  /// （normalize 阶段只保留 FollowedBy；NotFollowedBy 被静默丢弃）
  LookaheadMixedAssertions
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
  /// 可选的修复提示（hint），为用户提供具体建议
  hint : String?
}

///|
/// 将校验错误转换为可读字符串
pub fn ValidationError::to_string(self : ValidationError) -> String {
  let base = match self.kind {
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
    DuplicateRule(name) => "rule '\{name}' is defined more than once"
    MixedPrecSystems =>
      "grammar uses both top-level 'precedence' declarations and inline 'prec(n,p)' annotations; pick one system to avoid ambiguity"
    ExtrasNonTerminal(desc) =>
      "extras pattern '\{desc}' is not a terminal; extras only allow Literal, Regex, or AnyChar"
    UndefinedTemplateRule(rule_name) =>
      "rule '\{self.rule}': '\{rule_name}[...]' instantiates an undefined or non-template rule"
    RuleAppArityMismatch(rule_name, expected, got) =>
      "rule '\{self.rule}': template '\{rule_name}' expects \{expected} argument(s) but got \{got}"
    TemplateRuleUsedAsRef(tmpl_name) =>
      "rule '\{self.rule}': references template rule '\{tmpl_name}' without instantiation; use '\{tmpl_name}[...]'"
    UndefinedWordRule(name) =>
      "word rule '\{name}' is not defined in the grammar"
    TokenRuleContainsRef(ref_name) =>
      "token rule '\{self.rule}': references non-token rule '\{ref_name}'; token rules may only contain terminal patterns"
    ConflictUndeclaredRule(ref_name) =>
      "conflicts: rule '\{ref_name}' is not defined in the grammar"
    SupertypeUndeclaredRule(ref_name) =>
      "supertypes: rule '\{ref_name}' is not defined in the grammar"
    DeprecatedRuleUsed(ref_name) =>
      "rule '\{self.rule}': references deprecated rule '\{ref_name}'; consider replacing with a non-deprecated alternative"
    LookaheadNonTailAssertion =>
      "rule '\{self.rule}': '!' or '&' assertion is not in tail position; it will be silently ignored at parse time"
    LookaheadMixedAssertions =>
      "rule '\{self.rule}': both '&' (positive) and '!' (negative) lookahead assertions appear at the sequence tail; only the '&' constraint takes effect"
  }
  match self.hint {
    None => base
    Some(h) => base + "\n  hint: " + h
  }
}

// 公开入口

///|
/// 对已解析的 Grammar 进行语义校验，返回所有错误
pub fn validate_grammar(grammar : Grammar) -> Array[ValidationError] {
  let errors : Array[ValidationError] = []

  // 重复定义规则检查
  for name in grammar.duplicate_rule_names {
    errors.push({
      rule: name,
      kind: ValidationErrorKind::DuplicateRule(name),
      location: match grammar.rules.get(name) {
        Some(r) => r.location
        None => None
      },
      hint: None,
    })
  }

  // start 规则存在性
  match grammar.start {
    Some(start_name) =>
      if !grammar.rules.contains(start_name) {
        errors.push({
          rule: start_name,
          kind: ValidationErrorKind::UndefinedStartRule(start_name),
          location: None,
          hint: Some(
            "declare '" +
            start_name +
            "' with 'rule " +
            start_name +
            ": ...' or change the 'start' declaration to an existing rule",
          ),
        })
      }
    None => ()
  }

  // 规则引用完整性（externals 声明的名称不作为未定义规则报告）
  for name, rule in grammar.rules {
    for ref_name in collect_rule_refs(rule.pattern) {
      if !grammar.rules.contains(ref_name) &&
        !grammar.externals.contains(ref_name) {
        errors.push({
          rule: name,
          kind: ValidationErrorKind::UndefinedRule(ref_name),
          location: match grammar.rules.get(name) {
            Some(r) => r.location
            None => None
          },
          hint: Some(
            "declare '" +
            ref_name +
            "' with 'rule " +
            ref_name +
            ": ...' or replace the reference with an existing rule",
          ),
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
            hint: None,
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
          if !reachable.contains(name) {
            errors.push({
              rule: name,
              kind: ValidationErrorKind::UnreachableRule(name),
              location: match grammar.rules.get(name) {
                Some(r) => r.location
                None => None
              },
              hint: None,
            })
          }
        }
      }
    None => ()
  }

  // 6. 统一优先级机制：顶层 precedence 与内联 prec() 不可混用
  let has_toplevel_prec = !grammar.precedences.is_empty()
  let has_inline_prec = grammar.rules
    .values()
    .any(fn(r) { contains_prec_pattern(r.pattern) })
  if has_toplevel_prec && has_inline_prec {
    errors.push({
      rule: "<grammar>",
      kind: ValidationErrorKind::MixedPrecSystems,
      location: None,
      hint: Some(
        "either keep top-level 'precedence' declarations and remove inline 'prec(...)', or remove the top-level declarations and keep inline precedence annotations",
      ),
    })
  }

  // 7. extras 只允许终结符模式
  for ep in grammar.extras {
    match ep {
      Literal(_) | Regex(_) | AnyChar => ()
      _ => {
        let desc = pattern_to_string(ep)
        errors.push({
          rule: "<extras>",
          kind: ValidationErrorKind::ExtrasNonTerminal(desc),
          location: None,
          hint: None,
        })
      }
    }
  }

  // 8. 模板规则实例化校验 & 普通引用不能引用模板规则
  // 同时校验 word 声明
  let template_rules : Set[String] = Set::new()
  for name, rule in grammar.rules {
    if !rule.params.is_empty() {
      template_rules.add(name)
    }
  }

  for rule_name, rule in grammar.rules {
    let loc = rule.location
    check_ruleapp_refs(
      rule_name,
      rule.pattern,
      grammar,
      template_rules,
      errors,
      loc,
    )
  }

  // 9. word 规则校验
  match grammar.word {
    Some(word_name) =>
      match grammar.rules.get(word_name) {
        None =>
          errors.push({
            rule: word_name,
            kind: ValidationErrorKind::UndefinedWordRule(word_name),
            location: None,
            hint: None,
          })
        Some(wr) =>
          if !wr.is_token {
            errors.push({
              rule: word_name,
              kind: ValidationErrorKind::UndefinedWordRule(word_name),
              location: wr.location,
              hint: Some("declare the rule with 'token rule'"),
            })
          }
      }
    None => ()
  }

  // 10. token rule 纯净性：token rule 不得引用非 token 语法规则
  for rule_name, rule in grammar.rules {
    if rule.is_token {
      check_token_rule_purity(
        rule_name,
        rule.pattern,
        grammar,
        errors,
        rule.location,
      )
    }
  }

  // 11. conflicts 声明中的规则名必须存在
  for group in grammar.conflicts {
    for ref_name in group {
      if !grammar.rules.contains(ref_name) {
        errors.push({
          rule: "<conflicts>",
          kind: ValidationErrorKind::ConflictUndeclaredRule(ref_name),
          location: None,
          hint: Some(
            "declare '" +
            ref_name +
            "' before listing it in 'conflicts', or remove it from the conflict group",
          ),
        })
      }
    }
  }

  // 12. supertypes 声明中的规则名必须存在
  for name in grammar.supertypes {
    if !grammar.rules.contains(name) {
      errors.push({
        rule: "<supertypes>",
        kind: ValidationErrorKind::SupertypeUndeclaredRule(name),
        location: None,
        hint: Some(
          "declare '" +
          name +
          "' before listing it in 'supertypes', or remove it from the supertype list",
        ),
      })
    }
  }

  // 13. 非已废弃规则引用了 @deprecated 规则（警告）
  let deprecated_names : Set[String] = Set::new()
  for _, rule in grammar.rules {
    if rule.attributes.contains(RuleAttribute::Deprecated) {
      deprecated_names.add(rule.name)
    }
  }
  for rule_name, rule in grammar.rules {
    if !rule.attributes.contains(RuleAttribute::Deprecated) {
      check_deprecated_refs(
        rule_name,
        rule.pattern,
        deprecated_names,
        errors,
        rule.location,
      )
    }
  }

  // 14. 前瞻断言位置与混用检查
  for rule_name, rule in grammar.rules {
    check_lookahead_assertions(rule_name, rule.pattern, errors, rule.location)
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
    RuleApp(name, args) => {
      out.add(name)
      for a in args {
        collect_rule_refs_into(a, out)
      }
    }
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

///|
fn first_rule_refs(pattern : Pattern) -> Array[String] {
  let out : Set[String] = Set::new()
  first_rule_refs_into(pattern, out)
  out.to_array()
}

///|
fn first_rule_refs_into(pattern : Pattern, out : Set[String]) -> Unit {
  match pattern {
    RuleRef(name) => out.add(name)
    RuleApp(name, _) => out.add(name)
    // 选择：每个分支都是候选首位
    Choice(ps) =>
      for p in ps {
        first_rule_refs_into(p, out)
      }
    // 序列：首位由第一个元素决定；若前缀元素可为空，继续向后传播
    Seq(ps) =>
      for p in ps {
        first_rule_refs_into(p, out)
        if !is_trivially_nullable(p) {
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
  let visited : Set[String] = Set::new()
  let on_path_set : Set[String] = Set::new()
  let path_list : Array[String] = []

  for rule_name, _ in grammar.rules {
    if !visited.contains(rule_name) {
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
          hint: None,
        })
      } else {
        // 已经在 errors 里找一遗，避免同一个环重复报告
        let already = ref_already_reported(errors, cycle)
        if !already {
          errors.push({
            rule: name,
            kind: ValidationErrorKind::IndirectLeftRecursion(cycle),
            location: match grammar.rules.get(name) {
              Some(r) => r.location
              None => None
            },
            hint: None,
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
          if !already {
            errors.push({
              rule: name,
              kind: ValidationErrorKind::DirectLeftRecursion(name),
              location: match grammar.rules.get(name) {
                Some(r) => r.location
                None => None
              },
              hint: None,
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

// 辅助：新检查项

///|
/// 检查 Pattern 中是否含有内联 Prec(...) 节点
fn contains_prec_pattern(p : Pattern) -> Bool {
  match p {
    Prec(_, _, _) => true
    Choice(ps) | Seq(ps) => ps.any(fn(q) { contains_prec_pattern(q) })
    Repeat(q) | Plus(q) | Optional(q) | Not(q) | And(q) =>
      contains_prec_pattern(q)
    Tagged(_, q) | Field(_, q) | RepeatRange(q, _, _) | Alias(_, q) =>
      contains_prec_pattern(q)
    RuleApp(_, args) => args.any(fn(q) { contains_prec_pattern(q) })
    RuleRef(_) | Literal(_) | Regex(_) | AnyChar => false
  }
}

///|
/// 递归检查 Pattern 中的 RuleApp 与 RuleRef，收集模板相关错误
fn check_ruleapp_refs(
  rule_name : String,
  p : Pattern,
  grammar : Grammar,
  template_rules : Set[String],
  errors : Array[ValidationError],
  loc : SourceLocation?,
) -> Unit {
  match p {
    RuleRef(ref_name) =>
      if template_rules.contains(ref_name) {
        errors.push({
          rule: rule_name,
          kind: ValidationErrorKind::TemplateRuleUsedAsRef(ref_name),
          location: loc,
          hint: Some("use '" + ref_name + "[...]' to instantiate the template"),
        })
      }
    RuleApp(tmpl_name, args) => {
      match grammar.rules.get(tmpl_name) {
        None =>
          // 只有当不在 externals 里才报告（外部符号不是模板）
          if !grammar.externals.contains(tmpl_name) {
            errors.push({
              rule: rule_name,
              kind: ValidationErrorKind::UndefinedTemplateRule(tmpl_name),
              location: loc,
              hint: None,
            })
          }
        Some(tmpl_rule) =>
          if tmpl_rule.params.is_empty() {
            errors.push({
              rule: rule_name,
              kind: ValidationErrorKind::UndefinedTemplateRule(tmpl_name),
              location: loc,
              hint: None,
            })
          } else if tmpl_rule.params.length() != args.length() {
            errors.push({
              rule: rule_name,
              kind: ValidationErrorKind::RuleAppArityMismatch(
                tmpl_name,
                tmpl_rule.params.length(),
                args.length(),
              ),
              location: loc,
              hint: Some(
                "supply " +
                tmpl_rule.params.length().to_string() +
                " argument(s) to '" +
                tmpl_name +
                "[...]' or update the template parameter list",
              ),
            })
          }
      }
      // 递归检查参数 Pattern
      for a in args {
        check_ruleapp_refs(rule_name, a, grammar, template_rules, errors, loc)
      }
    }
    Choice(ps) | Seq(ps) =>
      for q in ps {
        check_ruleapp_refs(rule_name, q, grammar, template_rules, errors, loc)
      }
    Repeat(q) | Plus(q) | Optional(q) | Not(q) | And(q) =>
      check_ruleapp_refs(rule_name, q, grammar, template_rules, errors, loc)
    Tagged(_, q)
    | Field(_, q)
    | RepeatRange(q, _, _)
    | Prec(_, _, q)
    | Alias(_, q) =>
      check_ruleapp_refs(rule_name, q, grammar, template_rules, errors, loc)
    Literal(_) | Regex(_) | AnyChar => ()
  }
}

///|
/// 递归检查 token rule 的 pattern，发现非 token 规则引用则报错
fn check_token_rule_purity(
  rule_name : String,
  p : Pattern,
  grammar : Grammar,
  errors : Array[ValidationError],
  loc : SourceLocation?,
) -> Unit {
  match p {
    RuleRef(ref_name) =>
      // 若被引用的规则存在但不是 token rule 且不在 externals 中 → 违规
      if !grammar.externals.contains(ref_name) {
        match grammar.rules.get(ref_name) {
          Some(r) =>
            if !r.is_token {
              errors.push({
                rule: rule_name,
                kind: ValidationErrorKind::TokenRuleContainsRef(ref_name),
                location: loc,
                hint: Some(
                  "declare '\{ref_name}' as 'token rule' or inline its pattern",
                ),
              })
            }
          None => () // 未定义引用已由其他检查报告
        }
      }
    RuleApp(tmpl_name, args) => {
      // RuleApp 到非 token 模板也违规
      if !grammar.externals.contains(tmpl_name) {
        match grammar.rules.get(tmpl_name) {
          Some(r) =>
            if !r.is_token {
              errors.push({
                rule: rule_name,
                kind: ValidationErrorKind::TokenRuleContainsRef(tmpl_name),
                location: loc,
                hint: Some(
                  "declare '\{tmpl_name}' as 'token rule' or inline its pattern",
                ),
              })
            }
          None => ()
        }
      }
      for a in args {
        check_token_rule_purity(rule_name, a, grammar, errors, loc)
      }
    }
    Choice(ps) | Seq(ps) =>
      for q in ps {
        check_token_rule_purity(rule_name, q, grammar, errors, loc)
      }
    Repeat(q) | Plus(q) | Optional(q) | Not(q) | And(q) =>
      check_token_rule_purity(rule_name, q, grammar, errors, loc)
    Tagged(_, q)
    | Field(_, q)
    | RepeatRange(q, _, _)
    | Prec(_, _, q)
    | Alias(_, q) => check_token_rule_purity(rule_name, q, grammar, errors, loc)
    Literal(_) | Regex(_) | AnyChar => ()
  }
}

///|
/// 检查规则 pattern 中是否引用了已 @deprecated 的规则
fn check_deprecated_refs(
  rule_name : String,
  p : Pattern,
  deprecated_names : Set[String],
  errors : Array[ValidationError],
  loc : SourceLocation?,
) -> Unit {
  match p {
    RuleRef(ref_name) =>
      if deprecated_names.contains(ref_name) {
        errors.push({
          rule: rule_name,
          kind: ValidationErrorKind::DeprecatedRuleUsed(ref_name),
          location: loc,
          hint: None,
        })
      }
    RuleApp(ref_name, args) => {
      if deprecated_names.contains(ref_name) {
        errors.push({
          rule: rule_name,
          kind: ValidationErrorKind::DeprecatedRuleUsed(ref_name),
          location: loc,
          hint: None,
        })
      }
      for a in args {
        check_deprecated_refs(rule_name, a, deprecated_names, errors, loc)
      }
    }
    Choice(ps) | Seq(ps) =>
      for q in ps {
        check_deprecated_refs(rule_name, q, deprecated_names, errors, loc)
      }
    Repeat(q) | Plus(q) | Optional(q) | Not(q) | And(q) =>
      check_deprecated_refs(rule_name, q, deprecated_names, errors, loc)
    Tagged(_, q)
    | Field(_, q)
    | RepeatRange(q, _, _)
    | Prec(_, _, q)
    | Alias(_, q) =>
      check_deprecated_refs(rule_name, q, deprecated_names, errors, loc)
    Literal(_) | Regex(_) | AnyChar => ()
  }
}

///|
/// 检查 Seq 中 Not/And 断言的使用是否合法：
/// - 不允许在非末尾位置使用断言（LALR 只在 reduce 点消费前瞻）
/// - 不允许在同一 Seq 尾部混用 & 与 ! 两种断言（只有 & 会生效）
fn check_lookahead_assertions(
  rule_name : String,
  p : Pattern,
  errors : Array[ValidationError],
  loc : SourceLocation?,
) -> Unit {
  match p {
    Seq(elems) => {
      let n = elems.length()
      // 从末尾确定"尾部断言段"的起点（连续 Not/And 的起始下标）
      let mut tail_start = n
      while tail_start > 0 {
        match elems[tail_start - 1] {
          Not(_) | And(_) => tail_start = tail_start - 1
          _ => break
        }
      }
      // 检查：尾部之前是否含有断言（非末尾断言，每个 Seq 只报告一次）
      let mut reported_non_tail = false
      for i in 0..<tail_start {
        if !reported_non_tail {
          match elems[i] {
            Not(_) | And(_) => {
              reported_non_tail = true
              errors.push({
                rule: rule_name,
                kind: ValidationErrorKind::LookaheadNonTailAssertion,
                location: loc,
                hint: Some(
                  "move '!' or '&' assertions to the end of the sequence; LALR lookahead constraints only take effect at the reduce point",
                ),
              })
            }
            _ => ()
          }
        }
      }
      // 检查：尾部段是否同时含 & 和 !
      let mut has_not = false
      let mut has_and = false
      for i in tail_start..<n {
        match elems[i] {
          Not(_) => has_not = true
          And(_) => has_and = true
          _ => ()
        }
      }
      if has_not && has_and {
        errors.push({
          rule: rule_name,
          kind: ValidationErrorKind::LookaheadMixedAssertions,
          location: loc,
          hint: Some(
            "use either '&' (positive lookahead) or '!' (negative lookahead), not both; when mixed, only the '&' constraint takes effect",
          ),
        })
      }
      // 递归检查所有子 Pattern
      for elem in elems {
        check_lookahead_assertions(rule_name, elem, errors, loc)
      }
    }
    Choice(ps) =>
      for q in ps {
        check_lookahead_assertions(rule_name, q, errors, loc)
      }
    Repeat(q) | Plus(q) | Optional(q) | Not(q) | And(q) =>
      check_lookahead_assertions(rule_name, q, errors, loc)
    Tagged(_, q)
    | Field(_, q)
    | RepeatRange(q, _, _)
    | Prec(_, _, q)
    | Alias(_, q) => check_lookahead_assertions(rule_name, q, errors, loc)
    RuleApp(_, args) =>
      for a in args {
        check_lookahead_assertions(rule_name, a, errors, loc)
      }
    RuleRef(_) | Literal(_) | Regex(_) | AnyChar => ()
  }
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
          if !arr_contains(visited, ref_name) {
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
    RuleApp(_, args) =>
      for a in args {
        collect_regex_patterns(a, out)
      }
    RuleRef(_) | Literal(_) | AnyChar => ()
  }
}

///|
/// 对正则表达式字符串做浅层语法校验（括号/括弧平衡、尾部反斜杠、量词符槀查）。
/// 返回 None 表示合法，Some(error_msg) 表示发现问题。
fn validate_regex_syntax(re : String) -> String? {
  let chars : Array[Char] = []
  for c in re {
    chars.push(c)
  }
  let n = chars.length()
  let mut paren_depth = 0
  let mut i = 0
  // 记录当前位置前一个有效原子是否存在（用于量词符整凁性检查）
  // state: 0 = 起始/当前无前置原子, 1 = 已有原子, 2 = 量词符后正嬰量词符
  let mut atom_state = 0 // 0=no_atom, 1=has_atom, 2=after_quantifier
  while i < n {
    match chars[i] {
      '\\' => {
        // 跳过转义字符；末尾孤立的 \ 为非法
        if i + 1 >= n {
          return Some("trailing backslash")
        }
        i = i + 2
        atom_state = 1
      }
      '(' => {
        paren_depth = paren_depth + 1
        i = i + 1
        // Handle special group prefixes: (?!...) (?=...) (?:...) (?<...)
        // These start with '?' and should not be treated as a quantifier.
        if i < n && chars[i] == '?' {
          i = i + 1 // consume '?'
          if i < n {
            match chars[i] {
              '!' | '=' | ':' | '<' => i = i + 1
              _ => ()
            }
          }
        }
        atom_state = 0 // reset: after '(' no atom yet in this group
      }
      ')' => {
        paren_depth = paren_depth - 1
        if paren_depth < 0 {
          return Some("unmatched ')'")
        }
        i = i + 1
        atom_state = 1 // group itself is an atom
      }
      '[' => {
        i = i + 1
        // 跳过可选的 '^'
        if i < n && chars[i] == '^' {
          i = i + 1
        }
        // 扫描至 ']'
        let mut found_close = false
        while i < n {
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
        if !found_close {
          return Some("unclosed '['")
        }
        atom_state = 1 // char class is an atom
      }
      '|' => {
        // 空分支：| 在起始位置或紧跟另一个 |
        // 我们不检查空分支（有些工具允许），仅重置 atom_state
        i = i + 1
        atom_state = 0
      }
      '*' | '+' | '?' => {
        // 量词符必须有前置原子
        if atom_state == 0 {
          return Some(
            "quantifier '\{chars[i]}' requires a preceding element (nothing to repeat)",
          )
        }
        // 连续量词符（如 ** 、+? 等）——允许 *? / +? / ?? （懒惰量词符）但不允许 ** / ++ / *+ / +*
        if atom_state == 2 {
          let q = chars[i]
          // 允许第二个量词符为 '?' （懒惰模式）
          if q != '?' {
            return Some(
              "nested quantifier '\{chars[i]}' after another quantifier is not allowed",
            )
          }
        }
        i = i + 1
        atom_state = 2
      }
      '{' => {
        // 量词符 {n} / {n,} / {n,m}
        if atom_state == 0 {
          return Some(
            "quantifier '{...}' requires a preceding element (nothing to repeat)",
          )
        }
        i = i + 1
        // 读取 n
        let mut num1 = -1
        let mut has_num1 = false
        while i < n && chars[i] >= '0' && chars[i] <= '9' {
          let d = chars[i].to_int() - '0'.to_int()
          num1 = if num1 < 0 { d } else { num1 * 10 + d }
          has_num1 = true
          i = i + 1
        }
        if !has_num1 {
          // 不是数字开头，当作普通字符
          atom_state = 1
          continue
        }
        if i >= n {
          return Some("unclosed '{' in quantifier")
        }
        if chars[i] == '}' {
          // {n}
          i = i + 1
          atom_state = 2
          continue
        }
        if chars[i] != ',' {
          // 非 '{n}' 也非 '{n,'，当作普通字符
          atom_state = 1
          continue
        }
        i = i + 1 // 跳过 ','
        if i < n && chars[i] == '}' {
          // {n,}
          i = i + 1
          atom_state = 2
          continue
        }
        // 读取 m
        let mut num2 = -1
        let mut has_num2 = false
        while i < n && chars[i] >= '0' && chars[i] <= '9' {
          let d = chars[i].to_int() - '0'.to_int()
          num2 = if num2 < 0 { d } else { num2 * 10 + d }
          has_num2 = true
          i = i + 1
        }
        if !has_num2 || i >= n || chars[i] != '}' {
          return Some("unclosed '{' in quantifier")
        }
        if num1 > num2 {
          return Some(
            "invalid repetition range {\{num1},\{num2}}: minimum exceeds maximum",
          )
        }
        i = i + 1 // 跳过 '}'
        atom_state = 2
      }
      _ => {
        i = i + 1
        atom_state = 1
      }
    }
  }
  if paren_depth != 0 {
    return Some("unclosed '('")
  }
  None
}
