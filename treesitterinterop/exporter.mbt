///|
priv struct ExportRule {
  name : String
  pattern : @grammar.Pattern
  is_token : Bool
  is_immediate : Bool
}

///|
priv struct ExportContext {
  grammar : @grammar.Grammar
  diagnostics : Array[@languagepack.PackDiagnostic]
  unsupported : Array[String]
  mono_keys : Map[String, String]
  mono_rules : Array[ExportRule]
  mono_names : Array[String]
}

///|
fn ts_export_diag(
  code : String,
  message : String,
  path : String,
  hint? : String,
) -> @languagepack.PackDiagnostic {
  match hint {
    Some(hint) =>
      ts_diag(code, @languagepack.PackSeverity::Error, message, path~, hint~)
    None => ts_diag(code, @languagepack.PackSeverity::Error, message, path~)
  }
}

///|
fn ts_symbol(name : String) -> String {
  "{\"type\":\"SYMBOL\",\"name\":" + json_string(name) + "}"
}

///|
fn ts_blank() -> String {
  "{\"type\":\"BLANK\"}"
}

///|
fn ts_node(ty : String, content : String) -> String {
  "{\"type\":" + json_string(ty) + ",\"content\":" + content + "}"
}

///|
fn ts_named_node(ty : String, name : String, content : String) -> String {
  "{\"type\":" +
  json_string(ty) +
  ",\"name\":" +
  json_string(name) +
  ",\"content\":" +
  content +
  "}"
}

///|
fn ts_prec_node(
  kind : @grammar.PrecKind,
  level : Int,
  content : String,
) -> String {
  let ty = match kind {
    @grammar.PrecKind::Left => "PREC_LEFT"
    @grammar.PrecKind::Right => "PREC_RIGHT"
    @grammar.PrecKind::Dynamic => "PREC_DYNAMIC"
    @grammar.PrecKind::Nonassoc => "PREC"
  }
  "{\"type\":" +
  json_string(ty) +
  ",\"value\":" +
  level.to_string() +
  ",\"content\":" +
  content +
  "}"
}

///|
fn export_pattern_key(pattern : @grammar.Pattern) -> String {
  @grammar.pattern_to_string(pattern)
}

///|
fn substitute_template_param(
  pattern : @grammar.Pattern,
  params : Array[String],
  args : Array[@grammar.Pattern],
) -> @grammar.Pattern {
  match pattern {
    @grammar.Pattern::RuleRef(name) => {
      let mut i = 0
      while i < params.length() {
        if params[i] == name {
          return args[i]
        }
        i = i + 1
      }
      pattern
    }
    @grammar.Pattern::Choice(items) =>
      @grammar.Pattern::Choice(
        items.map(fn(p) { substitute_template_param(p, params, args) }),
      )
    @grammar.Pattern::Seq(items) =>
      @grammar.Pattern::Seq(
        items.map(fn(p) { substitute_template_param(p, params, args) }),
      )
    @grammar.Pattern::Repeat(inner) =>
      @grammar.Pattern::Repeat(substitute_template_param(inner, params, args))
    @grammar.Pattern::Plus(inner) =>
      @grammar.Pattern::Plus(substitute_template_param(inner, params, args))
    @grammar.Pattern::Optional(inner) =>
      @grammar.Pattern::Optional(substitute_template_param(inner, params, args))
    @grammar.Pattern::Tagged(label, inner) =>
      @grammar.Pattern::Tagged(
        label,
        substitute_template_param(inner, params, args),
      )
    @grammar.Pattern::Not(inner) =>
      @grammar.Pattern::Not(substitute_template_param(inner, params, args))
    @grammar.Pattern::And(inner) =>
      @grammar.Pattern::And(substitute_template_param(inner, params, args))
    @grammar.Pattern::Field(name, inner) =>
      @grammar.Pattern::Field(
        name,
        substitute_template_param(inner, params, args),
      )
    @grammar.Pattern::RepeatRange(inner, min, max) =>
      @grammar.Pattern::RepeatRange(
        substitute_template_param(inner, params, args),
        min,
        max,
      )
    @grammar.Pattern::Prec(level, kind, inner) =>
      @grammar.Pattern::Prec(
        level,
        kind,
        substitute_template_param(inner, params, args),
      )
    @grammar.Pattern::Alias(name, inner) =>
      @grammar.Pattern::Alias(
        name,
        substitute_template_param(inner, params, args),
      )
    @grammar.Pattern::AliasWithVisibility(name, named, inner) =>
      @grammar.Pattern::AliasWithVisibility(
        name,
        named,
        substitute_template_param(inner, params, args),
      )
    @grammar.Pattern::LexicalPrec(level, inner) =>
      @grammar.Pattern::LexicalPrec(
        level,
        substitute_template_param(inner, params, args),
      )
    @grammar.Pattern::Reserved(set_name, inner) =>
      @grammar.Pattern::Reserved(
        set_name,
        substitute_template_param(inner, params, args),
      )
    @grammar.Pattern::RuleApp(name, app_args) =>
      @grammar.Pattern::RuleApp(
        name,
        app_args.map(fn(p) { substitute_template_param(p, params, args) }),
      )
    _ => pattern
  }
}

///|
fn export_rule_app(
  ctx : ExportContext,
  name : String,
  args : Array[@grammar.Pattern],
  path : String,
) -> String {
  match ctx.grammar.rules.get(name) {
    None => {
      ctx.diagnostics.push(
        ts_export_diag(
          "TS421",
          "template rule '" + name + "' is not defined",
          path,
        ),
      )
      ctx.unsupported.push("RuleApp:" + name)
      ts_blank()
    }
    Some(rule) => {
      if rule.params.is_empty() {
        ctx.diagnostics.push(
          ts_export_diag(
            "TS422",
            "rule application target '" + name + "' is not a template",
            path,
          ),
        )
        ctx.unsupported.push("RuleApp:" + name)
        return ts_blank()
      }
      if rule.params.length() != args.length() || rule.params.length() > 2 {
        ctx.diagnostics.push(
          ts_export_diag(
            "TS423",
            "template rule '" +
            name +
            "' exceeds Tree-sitter export monomorphization limits",
            path,
            hint="P1c exports only templates with at most 2 parameters",
          ),
        )
        ctx.unsupported.push("RuleApp:" + name)
        return ts_blank()
      }
      let key = name + "[" + args.map(export_pattern_key).join(",") + "]"
      match ctx.mono_keys.get(key) {
        Some(generated) => ts_symbol(generated)
        None => {
          if ctx.mono_names.length() >= 10 {
            ctx.diagnostics.push(
              ts_export_diag(
                "TS424",
                "too many unique template instantiations for Tree-sitter export",
                path,
                hint="P1c allows at most 10 unique RuleApp instantiations",
              ),
            )
            ctx.unsupported.push("RuleApp:" + name)
            return ts_blank()
          }
          let generated = "_ts_export_" + name + "_" + stable_hash(key)
          let substituted = substitute_template_param(
            rule.pattern,
            rule.params,
            args,
          )
          ctx.mono_keys[key] = generated
          ctx.mono_names.push(generated)
          ctx.mono_rules.push({
            name: generated,
            pattern: substituted,
            is_token: rule.is_token,
            is_immediate: rule.is_immediate,
          })
          ts_symbol(generated)
        }
      }
    }
  }
}

///|
fn export_pattern(
  ctx : ExportContext,
  pattern : @grammar.Pattern,
  path : String,
  in_token : Bool,
) -> String {
  match pattern {
    @grammar.Pattern::RuleRef(name) => ts_symbol(name)
    @grammar.Pattern::Literal(value) =>
      "{\"type\":\"STRING\",\"value\":" + json_string(value) + "}"
    @grammar.Pattern::Regex(value) =>
      "{\"type\":\"PATTERN\",\"value\":" + json_string(value) + "}"
    @grammar.Pattern::Choice(items) =>
      "{\"type\":\"CHOICE\",\"members\":[" +
      items.map(fn(p) { export_pattern(ctx, p, path, in_token) }).join(",") +
      "]}"
    @grammar.Pattern::Seq(items) =>
      "{\"type\":\"SEQ\",\"members\":[" +
      items.map(fn(p) { export_pattern(ctx, p, path, in_token) }).join(",") +
      "]}"
    @grammar.Pattern::Repeat(inner) =>
      ts_node("REPEAT", export_pattern(ctx, inner, path, in_token))
    @grammar.Pattern::Plus(inner) =>
      ts_node("REPEAT1", export_pattern(ctx, inner, path, in_token))
    @grammar.Pattern::Optional(inner) =>
      "{\"type\":\"CHOICE\",\"members\":[" +
      ts_blank() +
      "," +
      export_pattern(ctx, inner, path, in_token) +
      "]}"
    @grammar.Pattern::Field(name, inner) =>
      ts_named_node("FIELD", name, export_pattern(ctx, inner, path, in_token))
    @grammar.Pattern::Alias(name, inner) =>
      "{\"type\":\"ALIAS\",\"named\":true,\"value\":" +
      json_string(name) +
      ",\"content\":" +
      export_pattern(ctx, inner, path, in_token) +
      "}"
    @grammar.Pattern::AliasWithVisibility(name, named, inner) =>
      "{\"type\":\"ALIAS\",\"named\":" +
      named.to_string() +
      ",\"value\":" +
      json_string(name) +
      ",\"content\":" +
      export_pattern(ctx, inner, path, in_token) +
      "}"
    @grammar.Pattern::Prec(level, kind, inner) =>
      ts_prec_node(kind, level, export_pattern(ctx, inner, path, in_token))
    @grammar.Pattern::LexicalPrec(level, inner) =>
      if in_token {
        ts_prec_node(
          @grammar.PrecKind::Nonassoc,
          level,
          export_pattern(ctx, inner, path, true),
        )
      } else {
        ctx.diagnostics.push(
          ts_export_diag(
            "TS431", "lexical precedence outside token context cannot be exported exactly",
            path,
          ),
        )
        ctx.unsupported.push("LexicalPrec")
        ts_blank()
      }
    @grammar.Pattern::Reserved(set_name, inner) =>
      "{\"type\":\"RESERVED\",\"name\":" +
      json_string(set_name) +
      ",\"content\":" +
      export_pattern(ctx, inner, path, in_token) +
      "}"
    @grammar.Pattern::RepeatRange(inner, min, max) => {
      if min < 0 || max < min || max > 20 {
        ctx.diagnostics.push(
          ts_export_diag(
            "TS432", "RepeatRange can only be exported when 0 <= min <= max <= 20",
            path,
          ),
        )
        ctx.unsupported.push("RepeatRange")
        return ts_blank()
      }
      let members : Array[String] = []
      for _ in 0..<min {
        members.push(export_pattern(ctx, inner, path, in_token))
      }
      for _ in 0..<(max - min) {
        members.push(
          "{\"type\":\"CHOICE\",\"members\":[" +
          ts_blank() +
          "," +
          export_pattern(ctx, inner, path, in_token) +
          "]}",
        )
      }
      if members.is_empty() {
        ts_blank()
      } else if members.length() == 1 {
        members[0]
      } else {
        "{\"type\":\"SEQ\",\"members\":[" + members.join(",") + "]}"
      }
    }
    @grammar.Pattern::RuleApp(name, args) =>
      export_rule_app(ctx, name, args, path)
    @grammar.Pattern::And(_) => {
      ctx.diagnostics.push(
        ts_export_diag(
          "TS441", "positive lookahead has no equivalent Tree-sitter grammar.json export",
          path,
        ),
      )
      ctx.unsupported.push("And")
      ts_blank()
    }
    @grammar.Pattern::Not(_) => {
      ctx.diagnostics.push(
        ts_export_diag(
          "TS442", "negative lookahead has no equivalent Tree-sitter grammar.json export",
          path,
        ),
      )
      ctx.unsupported.push("Not")
      ts_blank()
    }
    @grammar.Pattern::Tagged(_, _) => {
      ctx.diagnostics.push(
        ts_export_diag(
          "TS443", "semantic tags are not represented by Tree-sitter grammar.json",
          path,
        ),
      )
      ctx.unsupported.push("Tagged")
      ts_blank()
    }
    @grammar.Pattern::AnyChar => {
      ctx.diagnostics.push(
        ts_export_diag(
          "TS444", "AnyChar cannot be exported exactly to Tree-sitter grammar.json",
          path,
        ),
      )
      ctx.unsupported.push("AnyChar")
      ts_blank()
    }
  }
}

///|
fn export_rule_json(
  ctx : ExportContext,
  rule : ExportRule,
  path : String,
) -> String {
  let content = export_pattern(ctx, rule.pattern, path, rule.is_token)
  if rule.is_immediate {
    ts_node("IMMEDIATE_TOKEN", content)
  } else if rule.is_token {
    ts_node("TOKEN", content)
  } else {
    content
  }
}

///|
fn export_grammar_json(
  grammar : @grammar.Grammar,
  name : String,
  path : String,
) -> TreeSitterExportResult {
  let ctx : ExportContext = {
    grammar,
    diagnostics: [],
    unsupported: [],
    mono_keys: Map([]),
    mono_rules: [],
    mono_names: [],
  }
  let rule_parts : Array[(String, String)] = []
  let rule_names : Array[String] = []
  for rule_name, rule in grammar.rules {
    if rule.params.is_empty() {
      rule_names.push(rule_name)
    }
  }
  rule_names.sort()
  for rule_name in rule_names {
    let rule = grammar.rules[rule_name]
    rule_parts.push(
      (
        rule_name,
        export_rule_json(
          ctx,
          {
            name: rule_name,
            pattern: rule.pattern,
            is_token: rule.is_token,
            is_immediate: rule.is_immediate,
          },
          path,
        ),
      ),
    )
  }
  let mut generated_index = 0
  while generated_index < ctx.mono_rules.length() {
    let rule = ctx.mono_rules[generated_index]
    rule_parts.push((rule.name, export_rule_json(ctx, rule, path)))
    generated_index = generated_index + 1
  }
  rule_parts.sort_by(fn(a, b) { a.0.compare(b.0) })
  let rule_json = rule_parts
    .map(fn(item) { json_string(item.0) + ":" + item.1 })
    .join(",")
  let extras_json = grammar.extras
    .map(fn(p) { export_pattern(ctx, p, path, true) })
    .join(",")
  let externals_json = grammar.externals.map(ts_symbol).join(",")
  let word_json = match grammar.word {
    Some(word) => ts_symbol(word)
    None => "null"
  }
  let conflicts_json = grammar.conflicts
    .map(fn(group) { "[" + group.map(ts_symbol).join(",") + "]" })
    .join(",")
  let supertypes_json = grammar.supertypes.map(ts_symbol).join(",")
  let reserved_names : Array[String] = []
  for set_name, _ in grammar.reserved_sets {
    reserved_names.push(set_name)
  }
  reserved_names.sort()
  let reserved_json = reserved_names
    .map(fn(set_name) {
      json_string(set_name) +
      ":[" +
      grammar.reserved_sets[set_name].map(json_string).join(",") +
      "]"
    })
    .join(",")
  let output = "{\"name\":" +
    json_string(name) +
    ",\"rules\":{" +
    rule_json +
    "},\"extras\":[" +
    extras_json +
    "],\"externals\":[" +
    externals_json +
    "],\"word\":" +
    word_json +
    ",\"conflicts\":[" +
    conflicts_json +
    "],\"supertypes\":[" +
    supertypes_json +
    "],\"reserved_sets\":{" +
    reserved_json +
    "}}\n"
  let exported = rule_parts.map(fn(item) { item.0 })
  let report : TreeSitterExportReport = {
    source_path: path,
    grammar_name: name,
    diagnostics: ctx.diagnostics,
    exported_rules: exported,
    unsupported_patterns: ctx.unsupported,
    monomorphized_rules: ctx.mono_names,
  }
  { grammar_json: output, diagnostics: ctx.diagnostics, report }
}

///|
fn default_export_name(
  grammar : @grammar.Grammar,
  options : TreeSitterExportOptions,
) -> String {
  match options.grammar_name {
    Some(name) => normalize_id(name)
    None =>
      match grammar.start {
        Some(start) => normalize_id(start)
        None => "moonparse"
      }
  }
}

///|
pub fn export_tree_sitter_grammar(
  path : String,
  grammar_text : String,
  options : TreeSitterExportOptions,
) -> TreeSitterExportResult {
  match @grammar.parse_grammar(grammar_text) {
    Success(grammar) => {
      let name = default_export_name(grammar, options)
      export_grammar_json(grammar, name, path)
    }
    Error(error) => {
      let name = options.grammar_name.map(normalize_id).unwrap_or("moonparse")
      let diagnostics = [
        ts_export_diag(
          "TS101",
          "failed to parse MoonParse grammar: " + error.message,
          path,
        ),
      ]
      let report : TreeSitterExportReport = {
        source_path: path,
        grammar_name: name,
        diagnostics,
        exported_rules: [],
        unsupported_patterns: [],
        monomorphized_rules: [],
      }
      {
        grammar_json: "{\"name\":" + json_string(name) + ",\"rules\":{}}\n",
        diagnostics,
        report,
      }
    }
  }
}

///|
pub fn export_tree_sitter_pack(
  source : @languagepack.LanguagePackSource,
  options : TreeSitterExportOptions,
) -> TreeSitterExportResult {
  match @languagepack.load_pack(source) {
    Err(errors) => {
      let name = options.grammar_name.map(normalize_id).unwrap_or("moonparse")
      let report : TreeSitterExportReport = {
        source_path: "language-pack.json",
        grammar_name: name,
        diagnostics: errors,
        exported_rules: [],
        unsupported_patterns: [],
        monomorphized_rules: [],
      }
      {
        grammar_json: "{\"name\":" + json_string(name) + ",\"rules\":{}}\n",
        diagnostics: errors,
        report,
      }
    }
    Ok(pack) => {
      let selected_name = match options.grammar_name {
        Some(name) => normalize_id(name)
        None => normalize_id(pack.manifest.id)
      }
      match pack.manifest.grammar.format {
        @languagepack.GrammarFormat::Dsl =>
          export_tree_sitter_grammar(
            pack.manifest.grammar.path,
            pack.grammar_source,
            { grammar_name: Some(selected_name) },
          )
        @languagepack.GrammarFormat::Json =>
          match @grammar.grammar_from_json(pack.grammar_source) {
            Success(grammar) =>
              export_grammar_json(
                grammar,
                selected_name,
                pack.manifest.grammar.path,
              )
            Error(error) => {
              let diagnostics = [
                ts_export_diag(
                  "TS101",
                  "failed to decode MoonParse grammar JSON: " + error.message,
                  pack.manifest.grammar.path,
                ),
              ]
              let report : TreeSitterExportReport = {
                source_path: pack.manifest.grammar.path,
                grammar_name: selected_name,
                diagnostics,
                exported_rules: [],
                unsupported_patterns: [],
                monomorphized_rules: [],
              }
              {
                grammar_json: "{\"name\":" +
                json_string(selected_name) +
                ",\"rules\":{}}\n",
                diagnostics,
                report,
              }
            }
          }
      }
    }
  }
}

///|
pub fn tree_sitter_export_report_to_json(
  report : TreeSitterExportReport,
) -> String {
  "{\"schemaVersion\":1,\"source\":{\"path\":" +
  json_string(report.source_path) +
  ",\"grammarName\":" +
  json_string(report.grammar_name) +
  "},\"diagnostics\":[" +
  report.diagnostics.map(diag_json).join(",") +
  "],\"grammar\":{\"exportedRules\":" +
  json_string_array(report.exported_rules) +
  ",\"unsupportedPatterns\":" +
  json_string_array(report.unsupported_patterns) +
  ",\"monomorphizedRules\":" +
  json_string_array(report.monomorphized_rules) +
  "}}\n"
}
