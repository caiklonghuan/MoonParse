///|
fn semver_numbers(version : String) -> (Int, Int, Int)? {
  let dash_parts = version.split("-").to_array()
  let plus_parts = dash_parts[0].split("+").to_array()
  let parts = plus_parts[0].split(".").to_array()
  if parts.length() != 3 {
    return None
  }
  let numbers : Array[Int] = []
  for part_view in parts {
    let part = part_view.to_string()
    let mut number = 0
    for char in part {
      if char < '0' || char > '9' {
        return None
      }
      number = number * 10 + char.to_int() - 48
    }
    numbers.push(number)
  }
  Some((numbers[0], numbers[1], numbers[2]))
}

///|
fn compare_semver(left : String, right : String) -> Int {
  match (semver_numbers(left), semver_numbers(right)) {
    (Some((la, lb, lc)), Some((ra, rb, rc))) =>
      if la != ra {
        la - ra
      } else if lb != rb {
        lb - rb
      } else {
        lc - rc
      }
    _ => 0
  }
}

///|
fn is_blocking_validation(error : @grammar.ValidationError) -> Bool {
  match error.kind {
    @grammar.ValidationErrorKind::DirectLeftRecursion(_)
    | @grammar.ValidationErrorKind::IndirectLeftRecursion(_) => false
    _ => true
  }
}

///|
fn compile_query_resource(
  role : String,
  source : String?,
  diagnostics : Array[PackDiagnostic],
) -> @query.CompiledQuery? {
  match source {
    None => None
    Some(source) =>
      match @query.compile(source) {
        Ok(query) => Some(query)
        Err(error) => {
          diagnostics.push(
            pack_diagnostic(
              "PACK401",
              Error,
              role + " query failed to compile: \{error}",
              path="queries/" + role + ".scm",
            ),
          )
          None
        }
      }
  }
}

///|
fn scanner_is_known(
  scanner : ScannerDescriptor,
  options : PackBuildOptions,
) -> Bool {
  options.known_scanners
  .iter()
  .any(fn(item) { item.0 == scanner.id && item.1 == scanner.api_version })
}

///|
fn bundle_maturity_text(value : PackMaturity) -> String {
  match value {
    Stable => "stable"
    Subset => "subset"
    Experimental => "experimental"
    Imported => "imported"
  }
}

///|
fn build_bundle_internal(
  source : LanguagePackSource,
  options : PackBuildOptions,
) -> (LanguageBundle?, Array[PackDiagnostic]) {
  let diagnostics : Array[PackDiagnostic] = []
  let pack = match load_pack(source) {
    Ok(pack) => pack
    Err(errors) => return (None, errors)
  }
  if compare_semver(
      options.software_version,
      pack.manifest.compatibility.minimum_moonparse_version,
    ) <
    0 ||
    compare_semver(
      options.software_version,
      pack.manifest.compatibility.maximum_moonparse_version_exclusive,
    ) >=
    0 {
    diagnostics.push(
      pack_diagnostic(
        "PACK701",
        Error,
        "MoonParse " +
        options.software_version +
        " is outside pack compatibility range",
      ),
    )
  }
  let grammar = match pack.manifest.grammar.format {
    Dsl =>
      match @grammar.parse_grammar(pack.grammar_source) {
        Success(grammar) => Some(grammar)
        Error(error) => {
          diagnostics.push(
            pack_diagnostic(
              "PACK301",
              Error,
              "grammar parse failed: " + error.message,
              path=pack.manifest.grammar.path,
              line=error.location.line,
              column=error.location.column,
            ),
          )
          None
        }
      }
    Json =>
      match @grammar.grammar_from_json(pack.grammar_source) {
        Success(grammar) => Some(grammar)
        Error(error) => {
          diagnostics.push(
            pack_diagnostic(
              "PACK301",
              Error,
              "grammar JSON failed: " + error.message,
              path=pack.manifest.grammar.path,
            ),
          )
          None
        }
      }
  }
  let grammar = match grammar {
    Some(grammar) => grammar
    None => return (None, diagnostics)
  }
  if grammar.rules.get(pack.manifest.entry_rule) is None {
    diagnostics.push(
      pack_diagnostic(
        "PACK302",
        Error,
        "entry rule '" + pack.manifest.entry_rule + "' is not defined",
        path=pack.manifest.grammar.path,
      ),
    )
  }
  match grammar.start {
    Some(start) if start != pack.manifest.entry_rule =>
      diagnostics.push(
        pack_diagnostic(
          "PACK303",
          Error,
          "manifest entryRule '" +
          pack.manifest.entry_rule +
          "' does not match grammar start '" +
          start +
          "'",
          path=pack.manifest.grammar.path,
        ),
      )
    _ => ()
  }
  for error in @grammar.validate_grammar(grammar) {
    let diagnostic = match error.hint {
      Some(hint) =>
        pack_diagnostic(
          if is_blocking_validation(error) {
            "PACK304"
          } else {
            "PACK305"
          },
          if is_blocking_validation(error) {
            Error
          } else {
            Warning
          },
          error.to_string(),
          path=pack.manifest.grammar.path,
          hint~,
        )
      None =>
        pack_diagnostic(
          if is_blocking_validation(error) {
            "PACK304"
          } else {
            "PACK305"
          },
          if is_blocking_validation(error) {
            Error
          } else {
            Warning
          },
          error.to_string(),
          path=pack.manifest.grammar.path,
        )
    }
    diagnostics.push(diagnostic)
  }
  let generated = match @tablegen.generate_parse_table(grammar) {
    Ok(value) => Some(value)
    Err(message) => {
      diagnostics.push(
        pack_diagnostic(
          "PACK306",
          Error,
          "ParseTable generation failed: " + message,
          path=pack.manifest.grammar.path,
        ),
      )
      None
    }
  }
  let (table, conflicts) = match generated {
    Some(value) => value
    None => return (None, diagnostics)
  }
  for conflict in conflicts {
    match conflict.severity {
      @tablegen.ConflictSeverity::Ambiguous(message) =>
        diagnostics.push(
          pack_diagnostic(
            "PACK307",
            if pack.manifest.build.allow_ambiguous_conflicts {
              Warning
            } else {
              Error
            },
            "ambiguous conflict in state " +
            conflict.state.to_string() +
            ": " +
            message,
            path=pack.manifest.grammar.path,
          ),
        )
      @tablegen.ConflictSeverity::Warn(message) =>
        diagnostics.push(
          pack_diagnostic(
            "PACK308",
            Warning,
            message,
            path=pack.manifest.grammar.path,
          ),
        )
      _ => ()
    }
  }
  let highlights = compile_query_resource(
    "highlights",
    pack.highlights_query,
    diagnostics,
  )
  let locals = compile_query_resource("locals", pack.locals_query, diagnostics)
  let bindings = compile_query_resource(
    "bindings",
    pack.bindings_query,
    diagnostics,
  )
  let folding = compile_query_resource(
    "folding",
    pack.folding_query,
    diagnostics,
  )
  let modules = compile_query_resource(
    "modules",
    pack.modules_query,
    diagnostics,
  )
  let lint_rule_sets = compile_lint_rule_sets(pack.lint_rule_sets, diagnostics)
  match pack.scanner {
    Some(scanner) if !scanner_is_known(scanner, options) =>
      diagnostics.push(
        pack_diagnostic(
          "PACK502",
          Error,
          "unknown scanner '" +
          scanner.id +
          "' API " +
          scanner.api_version.to_string(),
          hint="register the scanner id and API version in PackBuildOptions",
        ),
      )
    _ => ()
  }
  if has_pack_errors(diagnostics) {
    return (None, diagnostics)
  }
  let table_json = @tablegen.table_to_json(table)
  let table_binary = @tablegen.serialize_table(table)
  let bundle : LanguageBundle = {
    schema_version: 1,
    parse_table_schema_version: 4,
    software_version: options.software_version,
    pack_id: pack.manifest.id,
    pack_version: pack.manifest.version,
    pack_name: pack.manifest.name,
    pack_maturity: bundle_maturity_text(pack.manifest.maturity),
    pack_extensions: pack.manifest.extensions,
    grammar_json: @grammar.grammar_to_json(grammar),
    table,
    table_json,
    table_binary,
    highlights_source: pack.highlights_query,
    locals_source: pack.locals_query,
    bindings_source: pack.bindings_query,
    folding_source: pack.folding_query,
    modules_source: pack.modules_query,
    highlights_query: highlights,
    locals_query: locals,
    bindings_query: bindings,
    folding_query: folding,
    modules_query: modules,
    lint_rule_sets,
    scanner: pack.scanner,
    capabilities: {
      highlights: highlights is Some(_),
      locals: locals is Some(_),
      bindings: bindings is Some(_),
      folding: folding is Some(_),
      modules: modules is Some(_),
      lint: lint_has_rules(lint_rule_sets),
      rewrite: lint_has_rewrites(lint_rule_sets),
      scanner: pack.scanner is Some(_),
    },
  }
  (Some(bundle), diagnostics)
}

///|
pub fn check_pack(
  source : LanguagePackSource,
  options : PackBuildOptions,
) -> Array[PackDiagnostic] {
  build_bundle_internal(source, options).1
}

///|
pub fn build_bundle(
  source : LanguagePackSource,
  options : PackBuildOptions,
) -> Result[LanguageBundle, Array[PackDiagnostic]] {
  let (bundle, diagnostics) = build_bundle_internal(source, options)
  match bundle {
    Some(bundle) => Ok(bundle)
    None => Err(diagnostics)
  }
}

///|
pub fn bundle_to_json(bundle : LanguageBundle) -> String {
  let scanner = match bundle.scanner {
    Some(scanner) =>
      "{\"id\":" +
      lp_json_string(scanner.id) +
      ",\"apiVersion\":" +
      scanner.api_version.to_string() +
      ",\"config\":" +
      lp_json_optional(scanner.config) +
      "}"
    None => "null"
  }
  "{" +
  "\"schemaVersion\":" +
  bundle.schema_version.to_string() +
  "," +
  "\"softwareVersion\":" +
  lp_json_string(bundle.software_version) +
  "," +
  "\"pack\":{\"id\":" +
  lp_json_string(bundle.pack_id) +
  ",\"version\":" +
  lp_json_string(bundle.pack_version) +
  ",\"name\":" +
  lp_json_string(bundle.pack_name) +
  ",\"maturity\":" +
  lp_json_string(bundle.pack_maturity) +
  ",\"extensions\":[" +
  bundle.pack_extensions.map(lp_json_string).join(",") +
  "]" +
  "}," +
  "\"grammarJson\":" +
  lp_json_string(bundle.grammar_json) +
  "," +
  "\"parseTable\":{\"schemaVersion\":" +
  bundle.parse_table_schema_version.to_string() +
  ",\"json\":" +
  lp_json_string(bundle.table_json) +
  ",\"binaryBase64\":" +
  lp_json_string(lp_base64_encode(bundle.table_binary)) +
  "}," +
  "\"queries\":{\"highlights\":" +
  lp_json_optional(bundle.highlights_source) +
  ",\"locals\":" +
  lp_json_optional(bundle.locals_source) +
  ",\"bindings\":" +
  lp_json_optional(bundle.bindings_source) +
  ",\"folding\":" +
  lp_json_optional(bundle.folding_source) +
  ",\"modules\":" +
  lp_json_optional(bundle.modules_source) +
  "}," +
  "\"lint\":" +
  lint_rule_sets_to_json(bundle.lint_rule_sets) +
  "," +
  "\"scanner\":" +
  scanner +
  "," +
  "\"capabilities\":{\"highlights\":" +
  bundle.capabilities.highlights.to_string() +
  ",\"locals\":" +
  bundle.capabilities.locals.to_string() +
  ",\"bindings\":" +
  bundle.capabilities.bindings.to_string() +
  ",\"folding\":" +
  bundle.capabilities.folding.to_string() +
  ",\"modules\":" +
  bundle.capabilities.modules.to_string() +
  ",\"lint\":" +
  bundle.capabilities.lint.to_string() +
  ",\"rewrite\":" +
  bundle.capabilities.rewrite.to_string() +
  ",\"scanner\":" +
  bundle.capabilities.scanner.to_string() +
  "}}"
}

///|
fn bundle_optional_string(
  object : Map[String, Json],
  field : String,
) -> String? raise ManifestDecodeError {
  match object.get(field) {
    Some(String(value)) => Some(value)
    Some(Null) | None => None
    _ => raise BadType("bundle field '" + field + "' must be string or null")
  }
}

///|
fn bundle_optional_string_field(
  object : Map[String, Json],
  field : String,
  fallback : String,
) -> String raise ManifestDecodeError {
  match object.get(field) {
    Some(value) => mf_string(value)
    None => fallback
  }
}

///|
fn bundle_optional_bool_field(
  object : Map[String, Json],
  field : String,
  fallback : Bool,
) -> Bool raise ManifestDecodeError {
  match object.get(field) {
    Some(value) => mf_bool(value)
    None => fallback
  }
}

///|
fn bundle_optional_string_array(
  object : Map[String, Json],
  field : String,
) -> Array[String] raise ManifestDecodeError {
  match object.get(field) {
    Some(value) => mf_string_array(value)
    None => []
  }
}

///|
pub fn bundle_from_json(
  json : String,
) -> Result[LanguageBundle, Array[PackDiagnostic]] {
  let root = @json.parse(json) catch {
    error =>
      return Err([
        pack_diagnostic("PACK700", Error, "invalid bundle JSON: \{error}"),
      ])
  }
  let diagnostics : Array[PackDiagnostic] = []
  let decoded = try {
    let object = mf_object(root)
    let schema_version = mf_int(mf_field(object, "schemaVersion"))
    if schema_version != 1 {
      diagnostics.push(
        pack_diagnostic(
          "PACK702",
          Error,
          "unsupported bundle schemaVersion " + schema_version.to_string(),
        ),
      )
    }
    let pack = mf_object(mf_field(object, "pack"))
    let table_data = mf_object(mf_field(object, "parseTable"))
    let table_schema = mf_int(mf_field(table_data, "schemaVersion"))
    if table_schema != 3 && table_schema != 4 {
      diagnostics.push(
        pack_diagnostic(
          "PACK703",
          Error,
          "unsupported ParseTable schemaVersion " + table_schema.to_string(),
        ),
      )
    }
    let table_json = mf_string(mf_field(table_data, "json"))
    let json_table_schema = try {
      let parsed = mf_object(@json.parse(table_json))
      match parsed.get("schema_version") {
        Some(value) => mf_int(value)
        None => 3
      }
    } catch {
      _ => table_schema
    }
    if json_table_schema != table_schema {
      diagnostics.push(
        pack_diagnostic(
          "PACK710",
          Error,
          "declared and JSON ParseTable schema versions do not match",
        ),
      )
    }
    let encoded = mf_string(mf_field(table_data, "binaryBase64"))
    let table_from_json = match @tablegen.table_from_json(table_json) {
      Ok(table) => Some(table)
      Err(error) => {
        diagnostics.push(
          pack_diagnostic("PACK704", Error, "invalid JSON ParseTable: " + error),
        )
        None
      }
    }
    let binary = match lp_base64_decode(encoded) {
      Some(binary) => binary
      None => {
        diagnostics.push(
          pack_diagnostic("PACK705", Error, "invalid ParseTable Base64"),
        )
        Bytes::new(0)
      }
    }
    if binary.length() >= 4 && binary[3].to_int() != table_schema {
      diagnostics.push(
        pack_diagnostic(
          "PACK711",
          Error,
          "declared and binary ParseTable schema versions do not match",
        ),
      )
    }
    let table_from_binary = match @tablegen.deserialize_table(binary) {
      Ok(table) => Some(table)
      Err(error) => {
        diagnostics.push(
          pack_diagnostic(
            "PACK706",
            Error,
            "invalid binary ParseTable: " + error,
          ),
        )
        None
      }
    }
    match (table_from_json, table_from_binary) {
      (Some(left), Some(right)) if lp_base64_encode(
          @tablegen.serialize_table(left),
        ) !=
        lp_base64_encode(@tablegen.serialize_table(right)) =>
        diagnostics.push(
          pack_diagnostic(
            "PACK707",
            Error,
            "JSON and binary ParseTable representations do not match",
          ),
        )
      _ => ()
    }
    let queries = mf_object(mf_field(object, "queries"))
    let highlights_source = bundle_optional_string(queries, "highlights")
    let locals_source = bundle_optional_string(queries, "locals")
    let bindings_source = bundle_optional_string(queries, "bindings")
    let folding_source = bundle_optional_string(queries, "folding")
    let modules_source = bundle_optional_string(queries, "modules")
    let highlights_query = compile_query_resource(
      "highlights", highlights_source, diagnostics,
    )
    let locals_query = compile_query_resource(
      "locals", locals_source, diagnostics,
    )
    let bindings_query = compile_query_resource(
      "bindings", bindings_source, diagnostics,
    )
    let folding_query = compile_query_resource(
      "folding", folding_source, diagnostics,
    )
    let modules_query = compile_query_resource(
      "modules", modules_source, diagnostics,
    )
    let lint_rule_sets = decode_bundle_lint_rule_sets(
      object.get("lint"),
      mf_string(mf_field(pack, "id")),
      diagnostics,
    )
    let scanner = match object.get("scanner") {
      Some(Object(value)) =>
        Some({
          id: mf_string(mf_field(value, "id")),
          api_version: mf_int(mf_field(value, "apiVersion")),
          config_path: None,
          config: bundle_optional_string(value, "config"),
        })
      Some(Null) | None => None
      _ => raise BadType("scanner must be object or null")
    }
    let table = match table_from_binary {
      Some(table) => table
      None =>
        match table_from_json {
          Some(table) => table
          None => raise BadField("bundle has no usable ParseTable")
        }
    }
    let grammar_json = mf_string(mf_field(object, "grammarJson"))
    match @grammar.grammar_from_json(grammar_json) {
      Success(_) => ()
      Error(error) =>
        diagnostics.push(
          pack_diagnostic(
            "PACK709",
            Error,
            "invalid bundle Grammar JSON: " + error.message,
          ),
        )
    }
    let derived_capabilities : BundleCapabilities = {
      highlights: highlights_query is Some(_),
      locals: locals_query is Some(_),
      bindings: bindings_query is Some(_),
      folding: folding_query is Some(_),
      modules: modules_query is Some(_),
      lint: lint_has_rules(lint_rule_sets),
      rewrite: lint_has_rewrites(lint_rule_sets),
      scanner: scanner is Some(_),
    }
    let capability_data = mf_object(mf_field(object, "capabilities"))
    let declared_capabilities : BundleCapabilities = {
      highlights: mf_bool(mf_field(capability_data, "highlights")),
      locals: mf_bool(mf_field(capability_data, "locals")),
      bindings: mf_bool(mf_field(capability_data, "bindings")),
      folding: bundle_optional_bool_field(capability_data, "folding", false),
      modules: bundle_optional_bool_field(capability_data, "modules", false),
      lint: bundle_optional_bool_field(capability_data, "lint", false),
      rewrite: bundle_optional_bool_field(capability_data, "rewrite", false),
      scanner: mf_bool(mf_field(capability_data, "scanner")),
    }
    if declared_capabilities != derived_capabilities {
      diagnostics.push(
        pack_diagnostic(
          "PACK708",
          Error,
          "bundle capabilities do not match bundled resources",
        ),
      )
    }
    Some({
      schema_version,
      parse_table_schema_version: table_schema,
      software_version: mf_string(mf_field(object, "softwareVersion")),
      pack_id: mf_string(mf_field(pack, "id")),
      pack_version: mf_string(mf_field(pack, "version")),
      pack_name: bundle_optional_string_field(
        pack,
        "name",
        mf_string(mf_field(pack, "id")),
      ),
      pack_maturity: bundle_optional_string_field(
        pack, "maturity", "experimental",
      ),
      pack_extensions: bundle_optional_string_array(pack, "extensions"),
      grammar_json,
      table,
      table_json,
      table_binary: binary,
      highlights_source,
      locals_source,
      bindings_source,
      folding_source,
      modules_source,
      highlights_query,
      locals_query,
      bindings_query,
      folding_query,
      modules_query,
      lint_rule_sets,
      scanner,
      capabilities: derived_capabilities,
    })
  } catch {
    error => {
      diagnostics.push(
        pack_diagnostic("PACK700", Error, "invalid bundle structure: \{error}"),
      )
      None
    }
  }
  if has_pack_errors(diagnostics) {
    Err(diagnostics)
  } else {
    match decoded {
      Some(bundle) => Ok(bundle)
      None => Err(diagnostics)
    }
  }
}

///|
pub fn parse_bundle(
  bundle : LanguageBundle,
  source : String,
  scanner_provider? : PackScannerProvider,
) -> Result[@runtime.CstNode, PackDiagnostic] {
  match bundle.scanner {
    None =>
      match @runtime.parse(bundle.table, source) {
        Ok(root) => Ok(root)
        Err(error) =>
          Err(
            pack_diagnostic(
              "PACK710",
              Error,
              error.message,
              path="<source>",
              line=error.point.row,
              column=error.point.column,
            ),
          )
      }
    Some(scanner) =>
      match scanner_provider {
        Some(provider) if provider.id == scanner.id &&
          provider.api_version == scanner.api_version =>
          match
            @runtime.parse_with_stateful_scanner(
              bundle.table,
              source,
              (provider.create)(bundle.table),
            ) {
            Ok(root) => Ok(root)
            Err(error) =>
              Err(
                pack_diagnostic(
                  "PACK710",
                  Error,
                  error.message,
                  path="<source>",
                  line=error.point.row,
                  column=error.point.column,
                ),
              )
          }
        _ =>
          Err(
            pack_diagnostic(
              "PACK502",
              Error,
              "no compatible provider for scanner '" +
              scanner.id +
              "' API " +
              scanner.api_version.to_string(),
            ),
          )
      }
  }
}

///|
pub fn exec_bundle_query(
  bundle : LanguageBundle,
  kind : BundleQueryKind,
  root : @runtime.CstNode,
  source : String,
) -> Result[Array[@query.CaptureResult], PackDiagnostic] {
  let query = match kind {
    Highlights => bundle.highlights_query
    Locals => bundle.locals_query
    Bindings => bundle.bindings_query
    Folding => bundle.folding_query
    Modules => bundle.modules_query
  }
  match query {
    Some(query) => Ok(@query.exec(query, root, source, bundle.table))
    None =>
      Err(
        pack_diagnostic(
          "PACK402",
          Error,
          "requested Query capability is not present in bundle",
        ),
      )
  }
}
