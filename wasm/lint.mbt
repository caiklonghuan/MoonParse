///|
suberror LintWireError {
  InvalidLintOptions(String)
} derive(Debug)

///|
impl Show for LintWireError with fn output(self, logger) {
  match self {
    InvalidLintOptions(message) => logger.write_string(message)
  }
}

///|
fn lint_wire_object(
  value : Json,
  field : String,
) -> Map[String, Json] raise LintWireError {
  match value {
    Object(object) => object
    _ =>
      raise InvalidLintOptions("lint option '" + field + "' must be an object")
  }
}

///|
fn lint_wire_bool(value : Json, field : String) -> Bool raise LintWireError {
  match value {
    True => true
    False => false
    _ =>
      raise InvalidLintOptions("lint option '" + field + "' must be a boolean")
  }
}

///|
fn lint_wire_severity(
  value : Json,
  rule_id : String,
) -> @languagepack.LintRuleSetting raise LintWireError {
  let text = match value {
    String(text) => text
    _ =>
      raise InvalidLintOptions(
        "lint rule option '" + rule_id + "' must be a string",
      )
  }
  match text {
    "off" => @languagepack.LintRuleSetting::LintOff
    "hint" =>
      @languagepack.LintRuleSetting::LintLevel(
        @languagepack.LintSeverity::LintHint,
      )
    "information" =>
      @languagepack.LintRuleSetting::LintLevel(
        @languagepack.LintSeverity::LintInformation,
      )
    "warning" =>
      @languagepack.LintRuleSetting::LintLevel(
        @languagepack.LintSeverity::LintWarning,
      )
    "error" =>
      @languagepack.LintRuleSetting::LintLevel(
        @languagepack.LintSeverity::LintError,
      )
    _ =>
      raise InvalidLintOptions(
        "invalid lint rule setting '" + text + "' for '" + rule_id + "'",
      )
  }
}

///|
fn decode_lint_options(
  options_json : String,
) -> @languagepack.LintOptions raise LintWireError {
  if options_json.is_empty() {
    return @languagepack.LintOptions::default()
  }
  let value = @json.parse(options_json) catch {
    error => raise InvalidLintOptions("invalid lint options JSON: \{error}")
  }
  let object = lint_wire_object(value, "<root>")
  object.each((field, _) => {
    if field != "enabled" && field != "ruleSets" && field != "rules" {
      raise InvalidLintOptions("unknown lint option '" + field + "'")
    }
  })
  let enabled = match object.get("enabled") {
    Some(value) => lint_wire_bool(value, "enabled")
    None => true
  }
  let rule_sets : Map[String, Bool] = {}
  match object.get("ruleSets") {
    Some(value) => {
      let object = lint_wire_object(value, "ruleSets")
      object.each((id, value) => {
        rule_sets[id] = lint_wire_bool(value, "ruleSets." + id)
      })
    }
    None => ()
  }
  let rules : Map[String, @languagepack.LintRuleSetting] = {}
  match object.get("rules") {
    Some(value) => {
      let object = lint_wire_object(value, "rules")
      object.each((id, setting) => rules[id] = lint_wire_severity(setting, id))
    }
    None => ()
  }
  { enabled, rule_sets, rules }
}

///|
fn lint_severity_json_text(severity : @languagepack.LintSeverity) -> String {
  match severity {
    @languagepack.LintSeverity::LintHint => "hint"
    @languagepack.LintSeverity::LintInformation => "information"
    @languagepack.LintSeverity::LintWarning => "warning"
    @languagepack.LintSeverity::LintError => "error"
  }
}

///|
fn lint_diagnostic_json(diagnostic : @languagepack.LintDiagnostic) -> String {
  let output = StringBuilder::new()
  output.write_char('{')
  write_kvs(output, "ruleId", diagnostic.rule_id)
  output.write_char(',')
  write_kvs(output, "message", diagnostic.message)
  output.write_char(',')
  write_kvs(output, "severity", lint_severity_json_text(diagnostic.severity))
  output.write_char(',')
  write_kvi(output, "startByte", diagnostic.start_byte)
  output.write_char(',')
  write_kvi(output, "endByte", diagnostic.end_byte)
  output.write_string(",\"fix\":")
  match diagnostic.fix {
    None => output.write_string("null")
    Some(fix) => {
      output.write_char('{')
      write_kvs(output, "title", fix.title)
      output.write_string(",\"edit\":{")
      write_kvi(output, "startByte", fix.edit.start_byte)
      output.write_char(',')
      write_kvi(output, "endByte", fix.edit.end_byte)
      output.write_char(',')
      write_kvs(output, "replacement", fix.edit.replacement)
      output.write_string("}}")
    }
  }
  output.write_char('}')
  output.to_string()
}

///|
fn lint_success_envelope(
  diagnostics : Array[@languagepack.LintDiagnostic],
) -> String {
  "{\"ok\":true,\"diagnostics\":[" +
  diagnostics.map(lint_diagnostic_json).join(",") +
  "],\"error\":null}"
}

///|
fn lint_error_envelope(message : String) -> String {
  let output = StringBuilder::new()
  output.write_string("{\"ok\":false,\"diagnostics\":[],\"error\":")
  write_jstr(output, message)
  output.write_char('}')
  output.to_string()
}

///|
/// Execute a registered Language Bundle's configured lint rules against a
/// tree created by that same Bundle parser.
pub fn bundle_lint(
  bundle_id : Int,
  tree_id : Int,
  options_json : String,
) -> String {
  let bundle_entry = match bundle_registry.get(bundle_id) {
    Some(entry) => entry
    None => return lint_error_envelope("invalid bundle id")
  }
  let tree_entry = match tree_registry.get(tree_id) {
    Some(entry) => entry
    None => return lint_error_envelope("invalid tree id")
  }
  if tree_entry.parser_id != bundle_entry.parser_id {
    return lint_error_envelope("tree was not created by this Language Bundle")
  }
  let options = decode_lint_options(options_json) catch {
    error => return lint_error_envelope(error.to_string())
  }
  lint_success_envelope(
    @languagepack.lint_bundle(
      bundle_entry.bundle,
      tree_entry.root,
      tree_entry.input,
      options~,
    ),
  )
}
