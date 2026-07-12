///|
priv struct GrammarBuildState {
  diagnostics : Array[@languagepack.PackDiagnostic]
  inline_rules : Array[(String, String, Bool)]
  generated_inline_tokens : Array[String]
  unsupported_nodes : Array[String]
}

///|
fn gj_type(object : Map[String, Json]) -> String {
  obj_get_string(object, "type").unwrap_or("")
}

///|
fn gj_member_array(object : Map[String, Json], field : String) -> Array[Json] {
  obj_get_array(object, field).unwrap_or([])
}

///|
fn ts_symbol_name(value : Json) -> String? {
  match value {
    String(name) => Some(name)
    Object(object) => obj_get_string(object, "name")
    _ => None
  }
}

///|
fn ts_pattern_to_dsl(
  value : Json,
  state : GrammarBuildState,
  parent_rule : String,
  path : String,
  in_token : Bool,
) -> String {
  match value {
    Object(object) => {
      let ty = gj_type(object)
      match ty {
        "BLANK" => "\"\""
        "STRING" => json_string(obj_get_string(object, "value").unwrap_or(""))
        "PATTERN" => "/" + obj_get_string(object, "value").unwrap_or("") + "/"
        "SYMBOL" => obj_get_string(object, "name").unwrap_or("_missing_symbol")
        "CHOICE" => {
          let parts = gj_member_array(object, "members").map(fn(item) {
            ts_pattern_to_dsl(item, state, parent_rule, path + "_c", in_token)
          })
          if parts.is_empty() {
            "\"\""
          } else {
            parts.join(" | ")
          }
        }
        "SEQ" => {
          let parts = gj_member_array(object, "members").map(fn(item) {
            let inner = ts_pattern_to_dsl(
              item,
              state,
              parent_rule,
              path + "_s",
              in_token,
            )
            if inner.contains(" | ") {
              "(" + inner + ")"
            } else {
              inner
            }
          })
          if parts.is_empty() {
            "\"\""
          } else {
            parts.join(" ")
          }
        }
        "REPEAT" => {
          let inner = match object.get("content") {
            Some(content) =>
              ts_pattern_to_dsl(
                content,
                state,
                parent_rule,
                path + "_r",
                in_token,
              )
            None => "\"\""
          }
          "(" + inner + ")*"
        }
        "REPEAT1" => {
          let inner = match object.get("content") {
            Some(content) =>
              ts_pattern_to_dsl(
                content,
                state,
                parent_rule,
                path + "_r1",
                in_token,
              )
            None => "\"\""
          }
          "(" + inner + ")+"
        }
        "TOKEN" => {
          let immediate = false
          let content = object.get("content")
          if in_token {
            match content {
              Some(content) =>
                ts_pattern_to_dsl(
                  content,
                  state,
                  parent_rule,
                  path + "_t",
                  true,
                )
              None => "\"\""
            }
          } else {
            let content_text = match content {
              Some(content) =>
                ts_pattern_to_dsl(
                  content,
                  state,
                  parent_rule,
                  path + "_t",
                  true,
                )
              None => "\"\""
            }
            let name = "_ts_" +
              parent_rule +
              "_" +
              stable_hash(path) +
              "_" +
              stable_hash(content_text)
            state.inline_rules.push((name, content_text, immediate))
            state.generated_inline_tokens.push(name)
            name
          }
        }
        "IMMEDIATE_TOKEN" => {
          let immediate = true
          let content = object.get("content")
          if in_token {
            match content {
              Some(content) =>
                ts_pattern_to_dsl(
                  content,
                  state,
                  parent_rule,
                  path + "_t",
                  true,
                )
              None => "\"\""
            }
          } else {
            let content_text = match content {
              Some(content) =>
                ts_pattern_to_dsl(
                  content,
                  state,
                  parent_rule,
                  path + "_t",
                  true,
                )
              None => "\"\""
            }
            let name = "_ts_" +
              parent_rule +
              "_" +
              stable_hash(path) +
              "_" +
              stable_hash(content_text)
            state.inline_rules.push((name, content_text, immediate))
            state.generated_inline_tokens.push(name)
            name
          }
        }
        "PREC" => {
          let level = match object.get("value") {
            Some(Number(n, ..)) => n.to_int()
            _ => 0
          }
          let inner = match object.get("content") {
            Some(content) =>
              ts_pattern_to_dsl(
                content,
                state,
                parent_rule,
                path + "_p",
                in_token,
              )
            None => "\"\""
          }
          if in_token {
            "lex.prec(" + level.to_string() + ", " + inner + ")"
          } else {
            "prec(" + level.to_string() + ", " + inner + ")"
          }
        }
        "PREC_LEFT" => {
          let level = match object.get("value") {
            Some(Number(n, ..)) => n.to_int()
            _ => 0
          }
          let inner = match object.get("content") {
            Some(content) =>
              ts_pattern_to_dsl(
                content,
                state,
                parent_rule,
                path + "_p",
                in_token,
              )
            None => "\"\""
          }
          if in_token {
            "lex.prec(" + level.to_string() + ", " + inner + ")"
          } else {
            "prec.left(" + level.to_string() + ", " + inner + ")"
          }
        }
        "PREC_RIGHT" => {
          let level = match object.get("value") {
            Some(Number(n, ..)) => n.to_int()
            _ => 0
          }
          let inner = match object.get("content") {
            Some(content) =>
              ts_pattern_to_dsl(
                content,
                state,
                parent_rule,
                path + "_p",
                in_token,
              )
            None => "\"\""
          }
          if in_token {
            "lex.prec(" + level.to_string() + ", " + inner + ")"
          } else {
            "prec.right(" + level.to_string() + ", " + inner + ")"
          }
        }
        "PREC_DYNAMIC" => {
          let level = match object.get("value") {
            Some(Number(n, ..)) => n.to_int()
            _ => 0
          }
          let inner = match object.get("content") {
            Some(content) =>
              ts_pattern_to_dsl(
                content,
                state,
                parent_rule,
                path + "_p",
                in_token,
              )
            None => "\"\""
          }
          if in_token {
            "lex.prec(" + level.to_string() + ", " + inner + ")"
          } else {
            "prec.dynamic(" + level.to_string() + ", " + inner + ")"
          }
        }
        "FIELD" => {
          let name = obj_get_string(object, "name").unwrap_or("field")
          let inner = match object.get("content") {
            Some(content) =>
              ts_pattern_to_dsl(
                content,
                state,
                parent_rule,
                path + "_f",
                in_token,
              )
            None => "\"\""
          }
          name + ": " + inner
        }
        "ALIAS" => {
          let name = obj_get_string(object, "value").unwrap_or(
            obj_get_string(object, "name").unwrap_or("alias"),
          )
          let named = match object.get("named") {
            Some(True) => true
            Some(False) => false
            _ => true
          }
          let inner = match object.get("content") {
            Some(content) =>
              ts_pattern_to_dsl(
                content,
                state,
                parent_rule,
                path + "_a",
                in_token,
              )
            None => "\"\""
          }
          let prefix = if named { "alias.named" } else { "alias.anonymous" }
          prefix + "(" + json_string(name) + ", " + inner + ")"
        }
        "RESERVED" => {
          let name = obj_get_string(object, "name").unwrap_or("default")
          let inner = match object.get("content") {
            Some(content) =>
              ts_pattern_to_dsl(
                content,
                state,
                parent_rule,
                path + "_res",
                in_token,
              )
            None => "\"\""
          }
          "reserved(" + json_string(name) + ", " + inner + ")"
        }
        _ => {
          state.unsupported_nodes.push(ty)
          state.diagnostics.push(
            ts_diag(
              "TS201",
              @languagepack.PackSeverity::Error,
              "unsupported Tree-sitter grammar node '" + ty + "'",
            ),
          )
          "\"\""
        }
      }
    }
    String(text) => json_string(text)
    _ => {
      state.diagnostics.push(
        ts_diag(
          "TS202",
          @languagepack.PackSeverity::Error,
          "expected Tree-sitter grammar node object",
        ),
      )
      "\"\""
    }
  }
}

///|
fn top_rule_to_dsl(
  name : String,
  value : Json,
  state : GrammarBuildState,
) -> String {
  let (prefix, body) = match value {
    Object(object) => {
      let ty = gj_type(object)
      if ty == "TOKEN" || ty == "IMMEDIATE_TOKEN" {
        let body = match object.get("content") {
          Some(content) => ts_pattern_to_dsl(content, state, name, name, true)
          None => "\"\""
        }
        (
          if ty == "IMMEDIATE_TOKEN" {
            "token.immediate "
          } else {
            "token "
          },
          body,
        )
      } else {
        ("", ts_pattern_to_dsl(value, state, name, name, false))
      }
    }
    _ => ("", ts_pattern_to_dsl(value, state, name, name, false))
  }
  prefix + "rule " + name + ": " + body
}

///|
fn symbol_list(values : Array[Json]) -> Array[String] {
  let out : Array[String] = []
  for value in values {
    match ts_symbol_name(value) {
      Some(name) => out.push(name)
      None => ()
    }
  }
  out
}

///|
fn extras_to_dsl(
  root : Map[String, Json],
  state : GrammarBuildState,
) -> String? {
  match obj_get_array(root, "extras") {
    Some(values) if !values.is_empty() => {
      let parts = values.map(fn(value) {
        ts_pattern_to_dsl(value, state, "_extras", "_extras", true)
      })
      Some("extras [" + parts.join(", ") + "]")
    }
    _ => None
  }
}

///|
fn externals(root : Map[String, Json]) -> Array[String] {
  match obj_get_array(root, "externals") {
    Some(values) => symbol_list(values)
    None => []
  }
}

///|
fn word_name(root : Map[String, Json]) -> String? {
  match root.get("word") {
    Some(String(name)) => Some(name)
    Some(Object(object)) => obj_get_string(object, "name")
    _ => None
  }
}

///|
fn conflicts(root : Map[String, Json]) -> Array[Array[String]] {
  let out : Array[Array[String]] = []
  match obj_get_array(root, "conflicts") {
    Some(groups) =>
      for group in groups {
        match group {
          Array(values) => out.push(symbol_list(values))
          _ => ()
        }
      }
    None => ()
  }
  out
}

///|
fn reserved_sets(root : Map[String, Json]) -> Array[String] {
  let out : Array[String] = []
  match obj_get_object(root, "reserved_sets") {
    Some(sets) =>
      for name, words in sets {
        match words {
          Array(values) => {
            let strings = json_string_values(values)
            out.push(
              "reserved " +
              name +
              " [" +
              strings.map(json_string).join(", ") +
              "]",
            )
          }
          _ => ()
        }
      }
    None => ()
  }
  out.sort()
  out
}

///|
fn tree_sitter_grammar_to_dsl(
  path : String,
  json : String,
) -> (
  String,
  String,
  Array[String],
  Array[String],
  Array[@languagepack.PackDiagnostic],
) {
  let diagnostics : Array[@languagepack.PackDiagnostic] = []
  let root = match parse_json_object(json) {
    Err(error) => {
      diagnostics.push(
        ts_diag(
          "TS101",
          @languagepack.PackSeverity::Error,
          "invalid grammar.json: " + error,
          path~,
        ),
      )
      return ("", "", [], [], diagnostics)
    }
    Ok(value) => value
  }
  let grammar_name = obj_get_string(root, "name").unwrap_or(
    "tree-sitter-import",
  )
  let rules = match obj_get_object(root, "rules") {
    Some(value) => value
    None => {
      diagnostics.push(
        ts_diag(
          "TS102",
          @languagepack.PackSeverity::Error,
          "grammar.json is missing rules object",
          path~,
        ),
      )
      return (grammar_name, "", [], [], diagnostics)
    }
  }
  let state : GrammarBuildState = {
    diagnostics,
    inline_rules: [],
    generated_inline_tokens: [],
    unsupported_nodes: [],
  }
  let rule_names : Array[String] = []
  for name, _ in rules {
    rule_names.push(name)
  }
  rule_names.sort()
  let entry = if rules.contains(grammar_name) {
    grammar_name
  } else if rule_names.contains("source_file") {
    "source_file"
  } else if rule_names.contains("program") {
    "program"
  } else if rule_names.contains("document") {
    "document"
  } else if !rule_names.is_empty() {
    rule_names[0]
  } else {
    diagnostics.push(
      ts_diag(
        "TS103",
        @languagepack.PackSeverity::Error,
        "grammar.json rules object is empty",
        path~,
      ),
    )
    grammar_name
  }
  let lines : Array[String] = ["start " + entry]
  match extras_to_dsl(root, state) {
    Some(line) => lines.push(line)
    None => ()
  }
  let ext = externals(root)
  if !ext.is_empty() {
    lines.push("externals [" + ext.join(", ") + "]")
  }
  match word_name(root) {
    Some(name) => lines.push("word " + name)
    None => ()
  }
  let conf = conflicts(root)
  if !conf.is_empty() {
    lines.push(
      "conflicts [" +
      conf.map(fn(group) { "[" + group.join(", ") + "]" }).join(", ") +
      "]",
    )
  }
  match obj_get_array(root, "supertypes") {
    Some(values) => {
      let names = symbol_list(values)
      if !names.is_empty() {
        lines.push("supertypes [" + names.join(", ") + "]")
      }
    }
    None => ()
  }
  for line in reserved_sets(root) {
    lines.push(line)
  }
  for name in rule_names {
    lines.push(top_rule_to_dsl(name, rules[name], state))
  }
  for item in state.inline_rules {
    let (name, body, immediate) = item
    lines.push(
      "@hide " +
      (if immediate { "token.immediate " } else { "token " }) +
      "rule " +
      name +
      ": " +
      body,
    )
  }
  (
    grammar_name,
    lines.join("\n") + "\n",
    state.unsupported_nodes,
    state.generated_inline_tokens,
    state.diagnostics,
  )
}

///|
pub fn import_tree_sitter_grammar(
  path : String,
  json : String,
  options : TreeSitterImportOptions,
) -> TreeSitterImportResult {
  let (grammar_name, dsl, unsupported, generated, diagnostics) = tree_sitter_grammar_to_dsl(
    path, json,
  )
  let files : Map[String, Bytes] = Map([])
  files["grammar/main.grammar"] = @utf8.encode(dsl)
  let report : TreeSitterCompatibilityReport = {
    grammar_path: path,
    grammar_name,
    diagnostics,
    unsupported_nodes: unsupported,
    generated_inline_tokens: generated,
    highlights_status: "missing",
    locals_status: "missing",
    tags_status: "missing",
    scanner_required: false,
    scanner_id: None,
    scanner_status: "none",
  }
  ignore(options)
  { files, diagnostics, report }
}
