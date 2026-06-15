///|
let language_pack_software_version : String = "0.1.0"

///|
fn builtin_pack_options() -> @languagepack.PackBuildOptions {
  {
    software_version: language_pack_software_version,
    known_scanners: known_pack_scanners(),
  }
}

///|
pub fn known_pack_scanners() -> Array[(String, Int)] {
  [("python-indent", 1), ("tree-sitter-rust", 1)]
}

///|
pub fn builtin_pack_scanner_provider(
  bundle : @languagepack.LanguageBundle,
) -> @languagepack.PackScannerProvider? {
  match bundle.scanner {
    Some(scanner) if scanner.id == "python-indent" && scanner.api_version == 1 =>
      Some({
        id: "python-indent",
        api_version: 1,
        create: fn(table) { python_indent_scanner(table) },
      })
    Some(scanner) if scanner.id == "tree-sitter-rust" &&
      scanner.api_version == 1 =>
      Some({
        id: "tree-sitter-rust",
        api_version: 1,
        create: fn(table) { tree_sitter_rust_scanner(table) },
      })
    _ => None
  }
}

///|
fn require_pack(
  source : @languagepack.LanguagePackSource,
) -> @languagepack.LanguagePack {
  match @languagepack.load_pack(source) {
    Ok(pack) => pack
    Err(errors) => abort("invalid embedded language pack: \{errors}")
  }
}

///|
fn require_bundle(
  source : @languagepack.LanguagePackSource,
) -> @languagepack.LanguageBundle {
  match @languagepack.build_bundle(source, builtin_pack_options()) {
    Ok(bundle) => bundle
    Err(errors) => abort("failed to build embedded language pack: \{errors}")
  }
}

///|
let builtin_json_pack : @languagepack.LanguagePack = require_pack(
  embedded_json_pack_source(),
)

///|
let builtin_python_pack : @languagepack.LanguagePack = require_pack(
  embedded_python_pack_source(),
)

///|
let builtin_moonbit_pack : @languagepack.LanguagePack = require_pack(
  embedded_moonbit_pack_source(),
)

///|
let builtin_json_bundle : @languagepack.LanguageBundle = require_bundle(
  embedded_json_pack_source(),
)

///|
let builtin_python_bundle : @languagepack.LanguageBundle = require_bundle(
  embedded_python_pack_source(),
)

///|
let builtin_moonbit_bundle : @languagepack.LanguageBundle = require_bundle(
  embedded_moonbit_pack_source(),
)

///|
pub fn json_language_pack() -> @languagepack.LanguagePack {
  builtin_json_pack
}

///|
pub fn python_language_pack() -> @languagepack.LanguagePack {
  builtin_python_pack
}

///|
pub fn moonbit_language_pack() -> @languagepack.LanguagePack {
  builtin_moonbit_pack
}

///|
pub fn json_language_bundle() -> @languagepack.LanguageBundle {
  builtin_json_bundle
}

///|
pub fn python_language_bundle() -> @languagepack.LanguageBundle {
  builtin_python_bundle
}

///|
pub fn moonbit_language_bundle() -> @languagepack.LanguageBundle {
  builtin_moonbit_bundle
}
