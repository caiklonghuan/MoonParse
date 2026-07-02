///|
fn lint_valid_range(node : @runtime.CstNode, source : String) -> Bool {
  node.start_byte >= 0 &&
  node.start_byte <= node.end_byte &&
  node.end_byte <= source.length()
}

///|
fn lint_capture_groups(
  captures : Array[@query.CaptureResult],
) -> (Array[Int], Map[Int, Array[@query.CaptureResult]]) {
  let match_ids : Array[Int] = []
  let groups : Map[Int, Array[@query.CaptureResult]] = {}
  for capture in captures {
    match groups.get(capture.match_id) {
      Some(group) => group.push(capture)
      None => {
        match_ids.push(capture.match_id)
        groups[capture.match_id] = [capture]
      }
    }
  }
  (match_ids, groups)
}

///|
fn lint_captures_by_name(
  captures : Array[@query.CaptureResult],
) -> Map[String, Array[@query.CaptureResult]] {
  let by_name : Map[String, Array[@query.CaptureResult]] = {}
  for capture in captures {
    match by_name.get(capture.capture_name) {
      Some(items) => items.push(capture)
      None => by_name[capture.capture_name] = [capture]
    }
  }
  by_name
}

///|
fn lint_unique_capture(
  captures : Map[String, Array[@query.CaptureResult]],
  name : String,
  source : String,
) -> @query.CaptureResult? {
  match captures.get(name) {
    Some([capture]) if lint_valid_range(capture.node, source) => Some(capture)
    _ => None
  }
}

///|
fn lint_expand_template(
  template : String,
  captures : Map[String, Array[@query.CaptureResult]],
  source : String,
) -> String? {
  let output = StringBuilder::new()
  let mut index = 0
  let mut literal_start = 0
  while index < template.length() {
    if template[index] != '$' {
      index = index + 1
      continue
    }
    output.write_string(template[literal_start:index].to_string())
    if index + 1 >= template.length() {
      return None
    }
    if template[index + 1] == '$' {
      output.write_string("$")
      index = index + 2
      literal_start = index
      continue
    }
    if template[index + 1] != '{' {
      return None
    }
    let mut end = index + 2
    while end < template.length() && template[end] != '}' {
      end = end + 1
    }
    if end >= template.length() {
      return None
    }
    let name = template[index + 2:end].to_string()
    let capture = match lint_unique_capture(captures, name, source) {
      Some(capture) => capture
      None => return None
    }
    output.write_string(
      source[capture.node.start_byte:capture.node.end_byte].to_string(),
    )
    index = end + 1
    literal_start = index
  }
  output.write_string(template[literal_start:].to_string())
  Some(output.to_string())
}

///|
fn lint_build_fix(
  template : LintFixTemplate,
  captures : Map[String, Array[@query.CaptureResult]],
  source : String,
) -> LintFix? {
  let target = match
    lint_unique_capture(captures, template.target_capture, source) {
    Some(capture) => capture.node
    None => return None
  }
  let replacement = match
    lint_expand_template(template.template, captures, source) {
    Some(replacement) => replacement
    None => return None
  }
  let edit : LintTextEdit = match template.operation {
    Replace => {
      if source[target.start_byte:target.end_byte].to_string() == replacement {
        return None
      }
      { start_byte: target.start_byte, end_byte: target.end_byte, replacement }
    }
    Delete => {
      if target.start_byte == target.end_byte || !replacement.is_empty() {
        return None
      }
      {
        start_byte: target.start_byte,
        end_byte: target.end_byte,
        replacement: "",
      }
    }
    InsertBefore => {
      if replacement.is_empty() {
        return None
      }
      {
        start_byte: target.start_byte,
        end_byte: target.start_byte,
        replacement,
      }
    }
    InsertAfter => {
      if replacement.is_empty() {
        return None
      }
      { start_byte: target.end_byte, end_byte: target.end_byte, replacement }
    }
  }
  Some({ title: template.title, edit })
}

///|
fn lint_effective_severity(
  pack_id : String,
  rule_set : LintRuleSet,
  rule : LintRule,
  options : LintOptions,
) -> LintSeverity? {
  match options.rules.get(rule.global_id) {
    Some(LintOff) => return None
    Some(LintLevel(severity)) => return Some(severity)
    None => ()
  }
  let rule_set_id = pack_id + "/" + rule_set.id
  let rule_set_enabled = options.rule_sets
    .get(rule_set_id)
    .unwrap_or(rule_set.enabled_by_default)
  if rule_set_enabled && rule.enabled_by_default {
    Some(rule.severity)
  } else {
    None
  }
}

///|
fn lint_compare_diagnostics(
  left : LintDiagnostic,
  right : LintDiagnostic,
) -> Int {
  let by_start = left.start_byte.compare(right.start_byte)
  if by_start != 0 {
    return by_start
  }
  let by_end = left.end_byte.compare(right.end_byte)
  if by_end != 0 {
    return by_end
  }
  let by_rule = left.rule_id.compare(right.rule_id)
  if by_rule != 0 {
    return by_rule
  }
  left.message.compare(right.message)
}

///|
fn lint_same_diagnostic(left : LintDiagnostic, right : LintDiagnostic) -> Bool {
  left.rule_id == right.rule_id &&
  left.start_byte == right.start_byte &&
  left.end_byte == right.end_byte &&
  left.message == right.message
}

///|
fn lint_sort_and_deduplicate(
  diagnostics : Array[LintDiagnostic],
) -> Array[LintDiagnostic] {
  diagnostics.sort_by(lint_compare_diagnostics)
  let result : Array[LintDiagnostic] = []
  for diagnostic in diagnostics {
    if result.is_empty() ||
      !lint_same_diagnostic(result[result.length() - 1], diagnostic) {
      result.push(diagnostic)
      continue
    }
    let index = result.length() - 1
    if result[index].fix != diagnostic.fix {
      result[index] = { ..result[index], fix: None }
    }
  }
  result
}

///|
/// Execute all enabled lint rules in a Language Bundle.
pub fn lint_bundle(
  bundle : LanguageBundle,
  root : @runtime.CstNode,
  source : String,
  options? : LintOptions = LintOptions::default(),
) -> Array[LintDiagnostic] {
  if !options.enabled || !bundle.capabilities.lint {
    return []
  }
  let diagnostics : Array[LintDiagnostic] = []
  for rule_set in bundle.lint_rule_sets {
    for rule in rule_set.rules {
      let severity = match
        lint_effective_severity(bundle.pack_id, rule_set, rule, options) {
        Some(severity) => severity
        None => continue
      }
      let query = match rule.compiled_query {
        Some(query) => query
        None => continue
      }
      let captures = @query.exec(query, root, source, bundle.table)
      let (match_ids, groups) = lint_capture_groups(captures)
      for match_id in match_ids {
        let group = groups[match_id]
        let by_name = lint_captures_by_name(group)
        let diagnostic_capture = match
          lint_unique_capture(by_name, rule.diagnostic_capture, source) {
          Some(capture) => capture
          None => continue
        }
        let fix = match rule.fix {
          Some(template) => lint_build_fix(template, by_name, source)
          None => None
        }
        diagnostics.push({
          rule_id: rule.global_id,
          message: rule.message,
          severity,
          start_byte: diagnostic_capture.node.start_byte,
          end_byte: diagnostic_capture.node.end_byte,
          fix,
        })
      }
    }
  }
  lint_sort_and_deduplicate(diagnostics)
}
