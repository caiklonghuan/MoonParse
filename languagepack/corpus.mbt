///|
fn corpus_lines(text : String) -> Array[String] {
  text
  .split("\n")
  .map(fn(line) {
    let value = line.to_string()
    if value.has_suffix("\r") {
      value[:value.length() - 1].to_string()
    } else {
      value
    }
  })
  .to_array()
}

///|
fn corpus_error(
  code : String,
  message : String,
  path : String,
  line : Int,
) -> PackDiagnostic {
  pack_diagnostic(code, Error, message, path~, line~)
}

///|
pub fn parse_corpus_document(
  path : String,
  text : String,
  format : String,
) -> Result[CorpusDocument, Array[PackDiagnostic]] {
  if format != "moonparse-corpus-v1" && format != "moonparse-corpus-v2" {
    return Err([
      corpus_error(
        "PACK601",
        "unsupported corpus format '" + format + "'",
        path,
        1,
      ),
    ])
  }
  let allow_snapshot = format == "moonparse-corpus-v2"
  let lines = corpus_lines(text)
  let cases : Array[CorpusCase] = []
  let starts : Array[Int] = []
  let ends : Array[Int] = []
  let diagnostics : Array[PackDiagnostic] = []
  let mut index = 0
  while index < lines.length() {
    while index < lines.length() && lines[index].trim().is_empty() {
      index = index + 1
    }
    if index >= lines.length() {
      break
    }
    if lines[index].trim() != "====" {
      diagnostics.push(
        corpus_error(
          "PACK602",
          "expected '====' before corpus case",
          path,
          index + 1,
        ),
      )
      break
    }
    index = index + 1
    if index >= lines.length() {
      diagnostics.push(
        corpus_error("PACK602", "missing corpus case name", path, index + 1),
      )
      break
    }
    let name = lines[index].trim().to_string()
    index = index + 1
    if index >= lines.length() || lines[index].trim() != "====" {
      diagnostics.push(
        corpus_error(
          "PACK602",
          "expected '====' after corpus case name",
          path,
          index + 1,
        ),
      )
      break
    }
    index = index + 1
    let source_line = index + 1
    let source_lines : Array[String] = []
    while index < lines.length() && lines[index].trim() != "----" {
      source_lines.push(lines[index])
      index = index + 1
    }
    if index >= lines.length() {
      diagnostics.push(
        corpus_error(
          "PACK602",
          "missing '----' expectations separator",
          path,
          index + 1,
        ),
      )
      break
    }
    index = index + 1
    let expectation_line = index + 1
    let expectation_start = index
    let mut expected_error = "ok"
    let contains : Array[String] = []
    let not_contains : Array[String] = []
    let snapshot_lines : Array[String] = []
    let mut list_kind = 0
    let mut saw_snapshot = false
    while index < lines.length() && lines[index].trim() != "====" {
      let raw = lines[index]
      let trimmed = raw.trim().to_string()
      if list_kind == 3 && (raw.has_prefix(" ") || raw.has_prefix("\t")) {
        snapshot_lines.push(trimmed)
      } else if trimmed.is_empty() || trimmed.has_prefix("#") {
        list_kind = 0
      } else if trimmed.has_prefix("error:") {
        expected_error = trimmed[6:].trim().to_string()
        list_kind = 0
      } else if trimmed == "sexp-contains:" {
        list_kind = 1
      } else if trimmed == "sexp-not-contains:" {
        list_kind = 2
      } else if trimmed == "sexp:" {
        if !allow_snapshot {
          diagnostics.push(
            corpus_error(
              "PACK607",
              "sexp snapshots require moonparse-corpus-v2",
              path,
              index + 1,
            ),
          )
        } else if saw_snapshot {
          diagnostics.push(
            corpus_error("PACK608", "duplicate sexp snapshot", path, index + 1),
          )
        }
        saw_snapshot = true
        list_kind = 3
      } else if list_kind == 1 {
        contains.push(trimmed)
      } else if list_kind == 2 {
        not_contains.push(trimmed)
      } else if list_kind == 3 {
        diagnostics.push(
          corpus_error(
            "PACK609",
            "snapshot lines must be indented",
            path,
            index + 1,
          ),
        )
      } else {
        diagnostics.push(
          corpus_error(
            "PACK603",
            "unknown corpus expectation '" + trimmed + "'",
            path,
            index + 1,
          ),
        )
      }
      index = index + 1
    }
    if name.is_empty() {
      diagnostics.push(
        corpus_error(
          "PACK604", "corpus case name must not be empty", path, expectation_line,
        ),
      )
    }
    let expected_sexp = if saw_snapshot {
      Some(snapshot_lines.join("\n"))
    } else {
      None
    }
    cases.push({
      name,
      source: source_lines.join("\n"),
      expected_error,
      sexp_contains: contains,
      sexp_not_contains: not_contains,
      path,
      expected_sexp,
      source_line,
      expectation_line,
    })
    starts.push(expectation_start)
    ends.push(index)
  }
  if cases.is_empty() {
    diagnostics.push(
      pack_diagnostic("PACK605", Error, "corpus file contains no cases", path~),
    )
  }
  if has_pack_errors(diagnostics) {
    Err(diagnostics)
  } else {
    Ok({
      path,
      text,
      format,
      cases,
      expectation_starts: starts,
      expectation_ends: ends,
      newline: if text.contains("\r\n") {
        "\r\n"
      } else {
        "\n"
      },
    })
  }
}

///|
fn indent_snapshot(sexp : String, newline : String) -> String {
  "sexp:" +
  newline +
  sexp
  .split("\n")
  .map(fn(line) { "  " + line.to_string() })
  .to_array()
  .join(newline)
}

///|
pub fn rewrite_corpus_snapshots(
  document : CorpusDocument,
  updates : Array[CorpusSnapshotUpdate],
) -> Result[String, Array[PackDiagnostic]] {
  if document.format != "moonparse-corpus-v2" {
    return Err([
      corpus_error(
        "PACK607",
        "snapshot updates require moonparse-corpus-v2",
        document.path,
        1,
      ),
    ])
  }
  let by_index : Map[Int, CorpusSnapshotUpdate] = Map::new()
  for update in updates {
    if update.case_index < 0 ||
      update.case_index >= document.cases.length() ||
      document.cases[update.case_index].name != update.case_name {
      return Err([
        corpus_error(
          "PACK610",
          "snapshot update does not match corpus case",
          document.path,
          1,
        ),
      ])
    }
    by_index[update.case_index] = update
  }
  let lines = corpus_lines(document.text)
  let out : Array[String] = []
  let mut cursor = 0
  for case_index in 0..<document.cases.length() {
    let start = document.expectation_starts[case_index]
    let end = document.expectation_ends[case_index]
    while cursor < start {
      out.push(lines[cursor])
      cursor = cursor + 1
    }
    let kept : Array[String] = []
    let mut i = start
    while i < end {
      if lines[i].trim() == "sexp:" {
        i = i + 1
        while i < end && (lines[i].has_prefix(" ") || lines[i].has_prefix("\t")) {
          i = i + 1
        }
      } else {
        kept.push(lines[i])
        i = i + 1
      }
    }
    while !kept.is_empty() && kept[kept.length() - 1].trim().is_empty() {
      ignore(kept.pop())
    }
    out.push_iter(kept.iter())
    match by_index.get(case_index) {
      Some(update) => out.push(indent_snapshot(update.sexp, document.newline))
      None =>
        match document.cases[case_index].expected_sexp {
          Some(sexp) => out.push(indent_snapshot(sexp, document.newline))
          None => ()
        }
    }
    cursor = end
  }
  while cursor < lines.length() {
    out.push(lines[cursor])
    cursor = cursor + 1
  }
  Ok(out.join(document.newline))
}

///|
pub fn load_corpus(pack : LanguagePack) -> Array[CorpusCase] {
  pack.corpus
}
