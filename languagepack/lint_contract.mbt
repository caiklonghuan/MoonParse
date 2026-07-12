///|
fn lint_json_array(value : Json) -> Array[Json] raise ManifestDecodeError {
  match value {
    Array(values) => values
    _ => raise BadType("expected array")
  }
}

///|
fn lint_optional_bool(
  object : Map[String, Json],
  name : String,
  fallback : Bool,
) -> Bool raise ManifestDecodeError {
  match object.get(name) {
    Some(value) => mf_bool(value)
    None => fallback
  }
}

///|
fn lint_valid_capture_name(name : String) -> Bool {
  if name.is_empty() || name[0] == '@' {
    return false
  }
  for char in name {
    let valid = (char >= 'a' && char <= 'z') ||
      (char >= 'A' && char <= 'Z') ||
      (char >= '0' && char <= '9') ||
      char == '_' ||
      char == '-' ||
      char == '.'
    if !valid {
      return false
    }
  }
  true
}

///|
fn lint_valid_id(id : String) -> Bool {
  if id.is_empty() || id[0] == '-' || id[id.length() - 1] == '-' {
    return false
  }
  let mut previous_hyphen = false
  for char in id {
    if char == '-' {
      if previous_hyphen {
        return false
      }
      previous_hyphen = true
    } else if (char >= 'a' && char <= 'z') || (char >= '0' && char <= '9') {
      previous_hyphen = false
    } else {
      return false
    }
  }
  true
}

///|
fn lint_parse_severity(
  value : String,
) -> LintSeverity raise ManifestDecodeError {
  match value {
    "hint" => LintHint
    "information" => LintInformation
    "warning" => LintWarning
    "error" => LintError
    _ => raise BadField("unknown lint severity '" + value + "'")
  }
}

///|
fn lint_severity_text(value : LintSeverity) -> String {
  match value {
    LintHint => "hint"
    LintInformation => "information"
    LintWarning => "warning"
    LintError => "error"
  }
}

///|
fn lint_parse_operation(
  value : String,
) -> LintFixOperation raise ManifestDecodeError {
  match value {
    "replace" => Replace
    "delete" => Delete
    "insertBefore" => InsertBefore
    "insertAfter" => InsertAfter
    _ => raise BadField("unknown lint fix operation '" + value + "'")
  }
}

///|
fn lint_operation_text(value : LintFixOperation) -> String {
  match value {
    Replace => "replace"
    Delete => "delete"
    InsertBefore => "insertBefore"
    InsertAfter => "insertAfter"
  }
}

///|
/// Validate the v1 interpolation grammar and return referenced captures.
fn lint_template_captures(template : String) -> Result[Array[String], String] {
  let captures : Array[String] = []
  let mut index = 0
  while index < template.length() {
    if template[index] != '$' {
      index = index + 1
      continue
    }
    if index + 1 >= template.length() {
      return Err("a trailing '$' must be escaped as '$$'")
    }
    if template[index + 1] == '$' {
      index = index + 2
      continue
    }
    if template[index + 1] != '{' {
      return Err("'$' must be followed by '$' or '{capture}'")
    }
    let mut cursor = index + 2
    while cursor < template.length() && template[cursor] != '}' {
      cursor = cursor + 1
    }
    if cursor >= template.length() {
      return Err("unterminated '${capture}' interpolation")
    }
    let capture = template[index + 2:cursor].to_owned()
    if !lint_valid_capture_name(capture) {
      return Err("invalid template capture '" + capture + "'")
    }
    captures.push(capture)
    index = cursor + 1
  }
  Ok(captures)
}

///|
fn lint_parse_fix(value : Json) -> LintFixTemplate raise ManifestDecodeError {
  let object = mf_object(value)
  let title = mf_string(mf_field(object, "title"))
  let target_capture = mf_string(mf_field(object, "targetCapture"))
  let template = mf_string(mf_field(object, "template"))
  if title.is_empty() {
    raise BadField("lint fix title must not be empty")
  }
  if !lint_valid_capture_name(target_capture) {
    raise BadField("invalid lint fix targetCapture '" + target_capture + "'")
  }
  match lint_template_captures(template) {
    Ok(_) => ()
    Err(message) => raise BadField("invalid lint fix template: " + message)
  }
  let operation = lint_parse_operation(mf_string(mf_field(object, "operation")))
  if operation == Delete && !template.is_empty() {
    raise BadField("lint delete fix template must be empty")
  }
  { title, operation, target_capture, template }
}

///|
fn lint_parse_rule(
  pack_id : String,
  rule_set_id : String,
  value : Json,
  query_path : String?,
  query_source : String,
) -> LintRule raise ManifestDecodeError {
  let object = mf_object(value)
  let id = mf_string(mf_field(object, "id"))
  if !lint_valid_id(id) {
    raise BadField("invalid lint rule id '" + id + "'")
  }
  let message = mf_string(mf_field(object, "message"))
  if message.is_empty() {
    raise BadField("lint rule message must not be empty")
  }
  let diagnostic_capture = mf_string(mf_field(object, "diagnosticCapture"))
  if !lint_valid_capture_name(diagnostic_capture) {
    raise BadField(
      "invalid lint diagnosticCapture '" + diagnostic_capture + "'",
    )
  }
  let fix = match object.get("fix") {
    Some(Null) => None
    Some(value) => Some(lint_parse_fix(value))
    None => None
  }
  {
    id,
    global_id: pack_id + "/" + rule_set_id + "/" + id,
    query_path,
    query_source,
    compiled_query: None,
    enabled_by_default: lint_optional_bool(object, "enabledByDefault", true),
    severity: lint_parse_severity(mf_string(mf_field(object, "severity"))),
    message,
    diagnostic_capture,
    fix,
  }
}

///|
fn load_lint_rule_set(
  source : LanguagePackSource,
  pack_id : String,
  path : String,
) -> Result[LintRuleSet, Array[PackDiagnostic]] {
  let text = match source_text(source, path) {
    Some(text) => text
    None =>
      return Err([
        pack_diagnostic(
          "PACK205",
          Error,
          "lint ruleset resource is missing",
          path~,
        ),
      ])
  }
  let root = @json.parse(text) catch {
    error =>
      return Err([
        pack_diagnostic(
          "PACK108",
          Error,
          "invalid lint ruleset JSON: \{error}",
          path~,
        ),
      ])
  }
  let diagnostics : Array[PackDiagnostic] = []
  let decoded = try {
    let object = mf_object(root)
    let schema_version = mf_int(mf_field(object, "schemaVersion"))
    if schema_version != 1 {
      raise BadField(
        "unsupported lint ruleset schemaVersion " + schema_version.to_string(),
      )
    }
    let id = mf_string(mf_field(object, "id"))
    if !lint_valid_id(id) {
      raise BadField("invalid lint ruleset id '" + id + "'")
    }
    let rules : Array[LintRule] = []
    let seen : Map[String, Bool] = {}
    for rule_value in lint_json_array(mf_field(object, "rules")) {
      let rule_object = mf_object(rule_value)
      let query_path = mf_string(mf_field(rule_object, "query"))
      if !valid_pack_path(query_path) {
        raise BadField("invalid lint query path '" + query_path + "'")
      }
      let query_source = match source_text(source, query_path) {
        Some(query_source) => query_source
        None => {
          diagnostics.push(
            pack_diagnostic(
              "PACK203",
              Error,
              "lint query resource is missing",
              path=query_path,
            ),
          )
          ""
        }
      }
      let rule = lint_parse_rule(
        pack_id,
        id,
        rule_value,
        Some(query_path),
        query_source,
      )
      if seen.contains(rule.id) {
        raise BadField("duplicate lint rule id '" + rule.id + "'")
      }
      seen[rule.id] = true
      rules.push(rule)
    }
    Some({
      id,
      enabled_by_default: lint_optional_bool(object, "enabledByDefault", true),
      rules,
    })
  } catch {
    error => {
      diagnostics.push(
        pack_diagnostic(
          "PACK108",
          Error,
          "invalid lint ruleset: \{error}",
          path~,
        ),
      )
      None
    }
  }
  if has_pack_errors(diagnostics) {
    Err(diagnostics)
  } else {
    Ok(decoded.unwrap())
  }
}

///|
fn load_lint_rule_sets(
  source : LanguagePackSource,
  manifest : LanguagePackManifest,
) -> (Array[LintRuleSet], Array[PackDiagnostic]) {
  let rule_sets : Array[LintRuleSet] = []
  let diagnostics : Array[PackDiagnostic] = []
  let seen : Map[String, Bool] = {}
  for path in manifest.lint.rule_sets {
    match load_lint_rule_set(source, manifest.id, path) {
      Ok(rule_set) =>
        if seen.contains(rule_set.id) {
          diagnostics.push(
            pack_diagnostic(
              "PACK109",
              Error,
              "duplicate lint ruleset id '" + rule_set.id + "'",
              path~,
            ),
          )
        } else {
          seen[rule_set.id] = true
          rule_sets.push(rule_set)
        }
      Err(errors) => diagnostics.push_iter(errors.iter())
    }
  }
  (rule_sets, diagnostics)
}

///|
fn lint_collect_pattern_captures(
  pattern : @query.QueryPattern,
  captures : Map[String, Bool],
) -> Unit {
  match pattern {
    @query.NodePattern(_, children) =>
      for child in children {
        match child.capture {
          Some(capture) => captures[capture] = true
          None => ()
        }
        lint_collect_pattern_captures(child.pattern, captures)
      }
    @query.Alternation(patterns) =>
      for pattern in patterns {
        lint_collect_pattern_captures(pattern, captures)
      }
    _ => ()
  }
}

///|
fn lint_query_captures(query : @query.CompiledQuery) -> Map[String, Bool] {
  let captures : Map[String, Bool] = {}
  for item in query.patterns {
    lint_collect_pattern_captures(item.0, captures)
    match item.1 {
      Some(capture) => captures[capture] = true
      None => ()
    }
  }
  captures
}

///|
fn compile_lint_rule_sets(
  rule_sets : Array[LintRuleSet],
  diagnostics : Array[PackDiagnostic],
) -> Array[LintRuleSet] {
  let compiled_sets : Array[LintRuleSet] = []
  for rule_set in rule_sets {
    let compiled_rules : Array[LintRule] = []
    for rule in rule_set.rules {
      match @query.compile(rule.query_source) {
        Err(error) =>
          diagnostics.push(
            pack_diagnostic(
              "PACK401",
              Error,
              "lint rule '" +
              rule.global_id +
              "' query failed to compile: \{error}",
              path=rule.query_path.unwrap_or("lint/" + rule.global_id),
            ),
          )
        Ok(query) => {
          let captures = lint_query_captures(query)
          let required : Array[String] = [rule.diagnostic_capture]
          match rule.fix {
            Some(fix) => {
              required.push(fix.target_capture)
              match lint_template_captures(fix.template) {
                Ok(names) => required.push_iter(names.iter())
                Err(_) => ()
              }
            }
            None => ()
          }
          let mut valid = true
          for capture in required {
            if !captures.contains(capture) {
              valid = false
              diagnostics.push(
                pack_diagnostic(
                  "PACK403",
                  Error,
                  "lint rule '" +
                  rule.global_id +
                  "' references missing capture @" +
                  capture,
                  path=rule.query_path.unwrap_or("lint/" + rule.global_id),
                ),
              )
            }
          }
          if valid {
            compiled_rules.push({ ..rule, compiled_query: Some(query) })
          }
        }
      }
    }
    compiled_sets.push({ ..rule_set, rules: compiled_rules })
  }
  compiled_sets
}

///|
fn lint_fix_to_json(fix : LintFixTemplate) -> String {
  "{" +
  "\"title\":" +
  lp_json_string(fix.title) +
  "," +
  "\"operation\":" +
  lp_json_string(lint_operation_text(fix.operation)) +
  "," +
  "\"targetCapture\":" +
  lp_json_string(fix.target_capture) +
  "," +
  "\"template\":" +
  lp_json_string(fix.template) +
  "}"
}

///|
fn lint_rule_to_json(rule : LintRule) -> String {
  let fix = match rule.fix {
    Some(fix) => lint_fix_to_json(fix)
    None => "null"
  }
  "{" +
  "\"id\":" +
  lp_json_string(rule.id) +
  "," +
  "\"enabledByDefault\":" +
  rule.enabled_by_default.to_string() +
  "," +
  "\"severity\":" +
  lp_json_string(lint_severity_text(rule.severity)) +
  "," +
  "\"message\":" +
  lp_json_string(rule.message) +
  "," +
  "\"diagnosticCapture\":" +
  lp_json_string(rule.diagnostic_capture) +
  "," +
  "\"querySource\":" +
  lp_json_string(rule.query_source) +
  "," +
  "\"fix\":" +
  fix +
  "}"
}

///|
fn lint_rule_sets_to_json(rule_sets : Array[LintRuleSet]) -> String {
  let encoded = rule_sets.map(fn(rule_set) {
    "{" +
    "\"id\":" +
    lp_json_string(rule_set.id) +
    "," +
    "\"enabledByDefault\":" +
    rule_set.enabled_by_default.to_string() +
    "," +
    "\"rules\":[" +
    rule_set.rules.map(lint_rule_to_json).join(",") +
    "]}"
  })
  "{\"ruleSets\":[" + encoded.join(",") + "]}"
}

///|
fn decode_bundle_lint_rule_sets(
  value : Json?,
  pack_id : String,
  diagnostics : Array[PackDiagnostic],
) -> Array[LintRuleSet] raise ManifestDecodeError {
  let lint = match value {
    None | Some(Null) => return []
    Some(value) => mf_object(value)
  }
  let values = match lint.get("ruleSets") {
    Some(value) => lint_json_array(value)
    None => return []
  }
  let rule_sets : Array[LintRuleSet] = []
  let seen_sets : Map[String, Bool] = {}
  for value in values {
    let object = mf_object(value)
    let id = mf_string(mf_field(object, "id"))
    if !lint_valid_id(id) || seen_sets.contains(id) {
      raise BadField(
        "invalid or duplicate bundled lint ruleset id '" + id + "'",
      )
    }
    seen_sets[id] = true
    let rules : Array[LintRule] = []
    let seen_rules : Map[String, Bool] = {}
    for rule_value in lint_json_array(mf_field(object, "rules")) {
      let rule_object = mf_object(rule_value)
      let query_source = mf_string(mf_field(rule_object, "querySource"))
      let rule = lint_parse_rule(pack_id, id, rule_value, None, query_source)
      if seen_rules.contains(rule.id) {
        raise BadField("duplicate bundled lint rule id '" + rule.id + "'")
      }
      seen_rules[rule.id] = true
      rules.push(rule)
    }
    rule_sets.push({
      id,
      enabled_by_default: lint_optional_bool(object, "enabledByDefault", true),
      rules,
    })
  }
  compile_lint_rule_sets(rule_sets, diagnostics)
}

///|
fn lint_has_rules(rule_sets : Array[LintRuleSet]) -> Bool {
  rule_sets.any(fn(rule_set) { !rule_set.rules.is_empty() })
}

///|
fn lint_has_rewrites(rule_sets : Array[LintRuleSet]) -> Bool {
  rule_sets.any(fn(rule_set) {
    rule_set.rules.any(fn(rule) { rule.fix is Some(_) })
  })
}
