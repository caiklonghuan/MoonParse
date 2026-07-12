///|
fn ts_lines(text : String) -> Array[String] {
  text
  .split("\n")
  .map(fn(line) {
    let value = line.to_owned()
    if value.has_suffix("\r") {
      value[:value.length() - 1].to_owned()
    } else {
      value
    }
  })
  .to_array()
}

///|
fn ts_is_eq_separator(line : String) -> Bool {
  let value = line.trim()
  if value.length() < 3 {
    return false
  }
  for c in value {
    if c != '=' {
      return false
    }
  }
  true
}

///|
fn ts_is_dash_separator(line : String) -> Bool {
  let value = line.trim()
  if value.length() < 3 {
    return false
  }
  for c in value {
    if c != '-' {
      return false
    }
  }
  true
}

///|
fn trim_blank_edges(lines : Array[String]) -> Array[String] {
  let mut start = 0
  while start < lines.length() && lines[start].trim().is_empty() {
    start = start + 1
  }
  let mut end = lines.length()
  while end > start && lines[end - 1].trim().is_empty() {
    end = end - 1
  }
  lines[start:end].to_owned()
}

///|
pub fn convert_tree_sitter_corpus(
  path : String,
  text : String,
  _options : TreeSitterImportOptions,
) -> (String, Array[@languagepack.PackDiagnostic]) {
  let lines = ts_lines(text)
  let out : Array[String] = []
  let diagnostics : Array[@languagepack.PackDiagnostic] = []
  let mut index = 0
  let mut cases = 0
  while index < lines.length() {
    while index < lines.length() && !ts_is_eq_separator(lines[index]) {
      if !lines[index].trim().is_empty() {
        diagnostics.push(
          ts_diag(
            "TS601",
            @languagepack.PackSeverity::Warning,
            "ignoring text before Tree-sitter corpus case",
            path~,
            line=index + 1,
          ),
        )
      }
      index = index + 1
    }
    if index >= lines.length() {
      break
    }
    index = index + 1
    if index >= lines.length() {
      diagnostics.push(
        ts_diag(
          "TS602",
          @languagepack.PackSeverity::Error,
          "missing corpus case name",
          path~,
          line=index,
        ),
      )
      break
    }
    let name = lines[index].trim().to_owned()
    index = index + 1
    if index >= lines.length() || !ts_is_eq_separator(lines[index]) {
      diagnostics.push(
        ts_diag(
          "TS602",
          @languagepack.PackSeverity::Error,
          "expected Tree-sitter corpus separator after case name",
          path~,
          line=index + 1,
        ),
      )
      break
    }
    index = index + 1
    let source_lines : Array[String] = []
    while index < lines.length() && !ts_is_dash_separator(lines[index]) {
      source_lines.push(lines[index])
      index = index + 1
    }
    if index >= lines.length() {
      diagnostics.push(
        ts_diag(
          "TS602",
          @languagepack.PackSeverity::Error,
          "missing Tree-sitter corpus expectation separator",
          path~,
          line=index + 1,
        ),
      )
      break
    }
    index = index + 1
    let expected_lines : Array[String] = []
    while index < lines.length() && !ts_is_eq_separator(lines[index]) {
      expected_lines.push(lines[index])
      index = index + 1
    }
    let source = trim_blank_edges(source_lines).join("\n")
    let expected = trim_blank_edges(expected_lines)
    out.push("====")
    out.push(name)
    out.push("====")
    out.push(source)
    out.push("----")
    out.push("error: ok")
    out.push("sexp:")
    if expected.is_empty() {
      diagnostics.push(
        ts_diag(
          "TS603",
          @languagepack.PackSeverity::Error,
          "corpus case has empty expected S-expression",
          path~,
        ),
      )
    } else {
      for line in expected {
        out.push("  " + line)
      }
    }
    cases = cases + 1
  }
  if cases == 0 {
    diagnostics.push(
      ts_diag(
        "TS604",
        @languagepack.PackSeverity::Error,
        "Tree-sitter corpus contains no cases",
        path~,
      ),
    )
  }
  (out.join("\n") + "\n", diagnostics)
}
