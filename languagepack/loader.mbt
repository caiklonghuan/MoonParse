///|
fn source_text(source : LanguagePackSource, path : String) -> String? {
  match source.files.get(path) {
    Some(bytes) => Some(@utf8.decode_lossy(bytes))
    None => None
  }
}

///|
fn resolve_optional_query(
  source : LanguagePackSource,
  declared : String?,
  default_path : String,
) -> (String?, String?) {
  match declared {
    Some(path) => (Some(path), source_text(source, path))
    None =>
      match source_text(source, default_path) {
        Some(text) => (Some(default_path), Some(text))
        None => (None, None)
      }
  }
}

///|
fn load_corpus_from_source(
  source : LanguagePackSource,
  manifest : LanguagePackManifest,
) -> (Array[CorpusCase], Array[PackDiagnostic]) {
  let cases : Array[CorpusCase] = []
  let diagnostics : Array[PackDiagnostic] = []
  let prefix = manifest.corpus.directory + "/"
  let mut found = false
  source.files.each(fn(path, bytes) {
    if path.has_prefix(prefix) && path.has_suffix(".txt") {
      found = true
      match
        parse_corpus_document(
          path,
          @utf8.decode_lossy(bytes),
          manifest.corpus.format,
        ) {
        Ok(document) => cases.push_iter(document.cases.iter())
        Err(errors) => diagnostics.push_iter(errors.iter())
      }
    }
  })
  if !found {
    diagnostics.push(
      pack_diagnostic(
        "PACK606",
        Warning,
        "pack has no corpus files",
        path=manifest.corpus.directory,
      ),
    )
  }
  (cases, diagnostics)
}

///|
pub fn load_pack(
  source : LanguagePackSource,
) -> Result[LanguagePack, Array[PackDiagnostic]] {
  let manifest = match load_manifest(source.manifest) {
    Ok(value) => value
    Err(errors) => return Err(errors)
  }
  let diagnostics : Array[PackDiagnostic] = []
  let grammar_source = match source_text(source, manifest.grammar.path) {
    Some(value) => value
    None => {
      diagnostics.push(
        pack_diagnostic(
          "PACK202",
          Error,
          "grammar resource is missing",
          path=manifest.grammar.path,
        ),
      )
      ""
    }
  }
  let (highlights_path, highlights_query) = resolve_optional_query(
    source,
    manifest.queries.highlights,
    "queries/highlights.scm",
  )
  let (locals_path, locals_query) = resolve_optional_query(
    source,
    manifest.queries.locals,
    "queries/locals.scm",
  )
  let (bindings_path, bindings_query) = resolve_optional_query(
    source,
    manifest.queries.bindings,
    "queries/bindings.scm",
  )
  let (folding_path, folding_query) = resolve_optional_query(
    source,
    manifest.queries.folding,
    "queries/folding.scm",
  )
  let (modules_path, modules_query) = resolve_optional_query(
    source,
    manifest.queries.modules,
    "queries/modules.scm",
  )
  for
    item in [
      ("highlights", highlights_path, highlights_query),
      ("locals", locals_path, locals_query),
      ("bindings", bindings_path, bindings_query),
      ("folding", folding_path, folding_query),
      ("modules", modules_path, modules_query),
    ] {
    let (label, path, text) = item
    match (path, text) {
      (Some(path), None) =>
        diagnostics.push(
          pack_diagnostic(
            "PACK203",
            Error,
            label + " query resource is missing",
            path~,
          ),
        )
      _ => ()
    }
  }
  let scanner = match manifest.scanner {
    Some(descriptor) => {
      let config = match descriptor.config_path {
        Some(path) =>
          match source_text(source, path) {
            Some(text) => Some(text)
            None => {
              diagnostics.push(
                pack_diagnostic(
                  "PACK204",
                  Error,
                  "scanner config is missing",
                  path~,
                ),
              )
              None
            }
          }
        None => None
      }
      Some({ ..descriptor, config, })
    }
    None => None
  }
  let (lint_rule_sets, lint_diagnostics) = load_lint_rule_sets(source, manifest)
  diagnostics.push_iter(lint_diagnostics.iter())
  let (corpus, corpus_diagnostics) = load_corpus_from_source(source, manifest)
  diagnostics.push_iter(corpus_diagnostics.iter())
  if has_pack_errors(diagnostics) {
    Err(diagnostics)
  } else {
    Ok({
      manifest,
      grammar_source,
      highlights_query,
      locals_query,
      bindings_query,
      folding_query,
      modules_query,
      lint_rule_sets,
      scanner,
      corpus,
    })
  }
}
