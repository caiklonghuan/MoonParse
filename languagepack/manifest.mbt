///|
suberror ManifestDecodeError {
  BadField(String)
  BadType(String)
} derive(Debug)

///|
impl Show for ManifestDecodeError with output(self, logger) {
  match self {
    BadField(message) => logger.write_string(message)
    BadType(message) => logger.write_string(message)
  }
}

///|
fn mf_field(
  object : Map[String, Json],
  name : String,
) -> Json raise ManifestDecodeError {
  match object.get(name) {
    Some(value) => value
    None => raise BadField("missing required field '" + name + "'")
  }
}

///|
fn mf_object(value : Json) -> Map[String, Json] raise ManifestDecodeError {
  match value {
    Object(object) => object
    _ => raise BadType("expected object")
  }
}

///|
fn mf_string(value : Json) -> String raise ManifestDecodeError {
  match value {
    String(text) => text
    _ => raise BadType("expected string")
  }
}

///|
fn mf_int(value : Json) -> Int raise ManifestDecodeError {
  match value {
    Number(number, ..) => number.to_int()
    _ => raise BadType("expected integer")
  }
}

///|
fn mf_bool(value : Json) -> Bool raise ManifestDecodeError {
  match value {
    True => true
    False => false
    _ => raise BadType("expected boolean")
  }
}

///|
fn mf_string_array(value : Json) -> Array[String] raise ManifestDecodeError {
  match value {
    Array(values) => values.map(mf_string)
    _ => raise BadType("expected string array")
  }
}

///|
fn mf_optional_string(
  object : Map[String, Json],
  name : String,
) -> String? raise ManifestDecodeError {
  match object.get(name) {
    Some(value) => Some(mf_string(value))
    None => None
  }
}

///|
fn parse_maturity(value : String) -> PackMaturity raise ManifestDecodeError {
  match value {
    "stable" => Stable
    "subset" => Subset
    "experimental" => Experimental
    "imported" => Imported
    _ => raise BadField("unknown maturity '" + value + "'")
  }
}

///|
fn parse_grammar_format(
  value : String,
) -> GrammarFormat raise ManifestDecodeError {
  match value {
    "dsl" => Dsl
    "json" => Json
    _ => raise BadField("unknown grammar format '" + value + "'")
  }
}

///|
fn parse_manifest_value(
  root : Json,
) -> LanguagePackManifest raise ManifestDecodeError {
  let object = mf_object(root)
  let compatibility = match object.get("compatibility") {
    Some(value) => {
      let value = mf_object(value)
      {
        minimum_moonparse_version: mf_string(
          mf_field(value, "minimumMoonParseVersion"),
        ),
        maximum_moonparse_version_exclusive: mf_string(
          mf_field(value, "maximumMoonParseVersionExclusive"),
        ),
      }
    }
    None =>
      {
        minimum_moonparse_version: "0.1.0",
        maximum_moonparse_version_exclusive: "0.2.0",
      }
  }
  let grammar = match object.get("grammar") {
    Some(value) => {
      let value = mf_object(value)
      {
        path: match value.get("path") {
          Some(path) => mf_string(path)
          None => "grammar/main.grammar"
        },
        format: match value.get("format") {
          Some(format) => parse_grammar_format(mf_string(format))
          None => Dsl
        },
      }
    }
    None => { path: "grammar/main.grammar", format: Dsl }
  }
  let queries = match object.get("queries") {
    Some(value) => {
      let value = mf_object(value)
      {
        highlights: mf_optional_string(value, "highlights"),
        locals: mf_optional_string(value, "locals"),
        bindings: mf_optional_string(value, "bindings"),
        folding: mf_optional_string(value, "folding"),
        modules: mf_optional_string(value, "modules"),
      }
    }
    None =>
      {
        highlights: None,
        locals: None,
        bindings: None,
        folding: None,
        modules: None,
      }
  }
  let lint = match object.get("lint") {
    Some(value) => {
      let value = mf_object(value)
      {
        rule_sets: match value.get("ruleSets") {
          Some(paths) => mf_string_array(paths)
          None => []
        },
      }
    }
    None => { rule_sets: [] }
  }
  let scanner = match object.get("scanner") {
    Some(value) => {
      let value = mf_object(value)
      Some({
        id: mf_string(mf_field(value, "id")),
        api_version: mf_int(mf_field(value, "apiVersion")),
        config_path: mf_optional_string(value, "config"),
        config: None,
      })
    }
    None => None
  }
  let corpus = match object.get("corpus") {
    Some(value) => {
      let value = mf_object(value)
      {
        directory: match value.get("directory") {
          Some(path) => mf_string(path)
          None => "corpus"
        },
        format: match value.get("format") {
          Some(format) => mf_string(format)
          None => "moonparse-corpus-v1"
        },
      }
    }
    None => { directory: "corpus", format: "moonparse-corpus-v1" }
  }
  let build = match object.get("build") {
    Some(value) => {
      let value = mf_object(value)
      {
        allow_ambiguous_conflicts: match value.get("allowAmbiguousConflicts") {
          Some(value) => mf_bool(value)
          None => false
        },
      }
    }
    None => { allow_ambiguous_conflicts: false }
  }
  {
    schema_version: mf_int(mf_field(object, "schemaVersion")),
    id: mf_string(mf_field(object, "id")),
    name: mf_string(mf_field(object, "name")),
    version: mf_string(mf_field(object, "version")),
    maturity: parse_maturity(mf_string(mf_field(object, "maturity"))),
    entry_rule: mf_string(mf_field(object, "entryRule")),
    extensions: mf_string_array(mf_field(object, "extensions")),
    compatibility,
    grammar,
    queries,
    lint,
    scanner,
    corpus,
    build,
  }
}

///|
fn valid_pack_id(id : String) -> Bool {
  if id.is_empty() {
    return false
  }
  for index in 0..<id.length() {
    let char = id[index]
    let valid = (char >= 'a' && char <= 'z') ||
      (char >= '0' && char <= '9') ||
      char == '-'
    if !valid || ((index == 0 || index == id.length() - 1) && char == '-') {
      return false
    }
  }
  true
}

///|
fn valid_semver(version : String) -> Bool {
  let dash_parts = version.split("-").to_array()
  let plus_parts = dash_parts[0].split("+").to_array()
  let parts = plus_parts[0].split(".").to_array()
  if parts.length() != 3 {
    return false
  }
  for part_view in parts {
    let part = part_view.to_string()
    if part.is_empty() {
      return false
    }
    if part.length() > 1 && part[0] == '0' {
      return false
    }
    for char in part {
      if char < '0' || char > '9' {
        return false
      }
    }
  }
  true
}

///|
pub fn valid_pack_path(path : String) -> Bool {
  if path.is_empty() ||
    path[0] == '/' ||
    path.contains("\\") ||
    path.contains(":") {
    return false
  }
  for part in path.split("/") {
    if part.is_empty() || part == "." || part == ".." {
      return false
    }
  }
  true
}

///|
fn validate_manifest(manifest : LanguagePackManifest) -> Array[PackDiagnostic] {
  let diagnostics : Array[PackDiagnostic] = []
  if manifest.schema_version != 1 {
    diagnostics.push(
      pack_diagnostic(
        "PACK101",
        Error,
        "unsupported manifest schemaVersion " +
        manifest.schema_version.to_string(),
        hint="supported schemaVersion is 1",
      ),
    )
  }
  if !valid_pack_id(manifest.id) {
    diagnostics.push(
      pack_diagnostic(
        "PACK102",
        Error,
        "invalid pack id '" + manifest.id + "'",
        hint="use lowercase letters, digits, and internal hyphens",
      ),
    )
  }
  if !valid_semver(manifest.version) {
    diagnostics.push(
      pack_diagnostic(
        "PACK103",
        Error,
        "invalid pack SemVer '" + manifest.version + "'",
      ),
    )
  }
  if !valid_semver(manifest.compatibility.minimum_moonparse_version) ||
    !valid_semver(manifest.compatibility.maximum_moonparse_version_exclusive) {
    diagnostics.push(
      pack_diagnostic(
        "PACK104",
        Error,
        "invalid MoonParse compatibility version",
      ),
    )
  }
  if manifest.entry_rule.is_empty() {
    diagnostics.push(
      pack_diagnostic("PACK105", Error, "entryRule must not be empty"),
    )
  }
  let seen : Map[String, Bool] = Map::new()
  for extension in manifest.extensions {
    if extension.length() < 2 || extension[0] != '.' {
      diagnostics.push(
        pack_diagnostic(
          "PACK106",
          Error,
          "invalid extension '" + extension + "'",
        ),
      )
    } else if seen.contains(extension) {
      diagnostics.push(
        pack_diagnostic(
          "PACK107",
          Error,
          "duplicate extension '" + extension + "'",
        ),
      )
    } else {
      seen[extension] = true
    }
  }
  let paths : Array[(String, String?)] = [
    ("grammar", Some(manifest.grammar.path)),
    ("highlights", manifest.queries.highlights),
    ("locals", manifest.queries.locals),
    ("bindings", manifest.queries.bindings),
    ("folding", manifest.queries.folding),
    ("modules", manifest.queries.modules),
    ("corpus", Some(manifest.corpus.directory)),
  ]
  for path in manifest.lint.rule_sets {
    paths.push(("lint ruleset", Some(path)))
  }
  match manifest.scanner {
    Some(scanner) => paths.push(("scanner config", scanner.config_path))
    None => ()
  }
  for item in paths {
    let (label, path) = item
    match path {
      Some(path) if !valid_pack_path(path) =>
        diagnostics.push(
          pack_diagnostic(
            "PACK201",
            Error,
            "invalid " + label + " path '" + path + "'",
            hint="paths must be relative, use '/', and may not contain '.' or '..' segments",
          ),
        )
      _ => ()
    }
  }
  if manifest.corpus.format != "moonparse-corpus-v1" &&
    manifest.corpus.format != "moonparse-corpus-v2" {
    diagnostics.push(
      pack_diagnostic(
        "PACK601",
        Error,
        "unsupported corpus format '" + manifest.corpus.format + "'",
      ),
    )
  }
  match manifest.scanner {
    Some(scanner) if scanner.id.is_empty() || scanner.api_version <= 0 =>
      diagnostics.push(
        pack_diagnostic(
          "PACK501",
          Error,
          "scanner id and apiVersion must be valid",
        ),
      )
    _ => ()
  }
  diagnostics
}

///|
pub fn load_manifest(
  json : String,
) -> Result[LanguagePackManifest, Array[PackDiagnostic]] {
  let root = @json.parse(json) catch {
    error =>
      return Err([
        pack_diagnostic("PACK100", Error, "invalid manifest JSON: \{error}"),
      ])
  }
  let manifest = parse_manifest_value(root) catch {
    error =>
      return Err([
        pack_diagnostic("PACK100", Error, "invalid manifest: \{error}"),
      ])
  }
  let diagnostics = validate_manifest(manifest)
  if has_pack_errors(diagnostics) {
    Err(diagnostics)
  } else {
    Ok(manifest)
  }
}
