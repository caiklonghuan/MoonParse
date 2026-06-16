///|
fn json_string(s : String) -> String {
  let b = StringBuilder::new()
  b.write_char('"')
  for c in s {
    match c {
      '"' => b.write_string("\\\"")
      '\\' => b.write_string("\\\\")
      '\n' => b.write_string("\\n")
      '\r' => b.write_string("\\r")
      '\t' => b.write_string("\\t")
      _ => b.write_char(c)
    }
  }
  b.write_char('"')
  b.to_string()
}

///|
fn json_optional_string(value : String?) -> String {
  match value {
    Some(v) => json_string(v)
    None => "null"
  }
}

///|
fn json_string_array(values : Array[String]) -> String {
  "[" + values.map(json_string).join(",") + "]"
}

///|
fn diag_json(d : @languagepack.PackDiagnostic) -> String {
  "{\"code\":" +
  json_string(d.code) +
  ",\"severity\":" +
  json_string(d.severity.to_string()) +
  ",\"message\":" +
  json_string(d.message) +
  ",\"path\":" +
  json_string(d.path) +
  ",\"line\":" +
  d.line.to_string() +
  ",\"column\":" +
  d.column.to_string() +
  ",\"hint\":" +
  json_optional_string(d.hint) +
  "}"
}

///|
fn obj_get_string(object : Map[String, Json], name : String) -> String? {
  match object.get(name) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn obj_get_object(
  object : Map[String, Json],
  name : String,
) -> Map[String, Json]? {
  match object.get(name) {
    Some(Object(value)) => Some(value)
    _ => None
  }
}

///|
fn obj_get_array(object : Map[String, Json], name : String) -> Array[Json]? {
  match object.get(name) {
    Some(Array(value)) => Some(value)
    _ => None
  }
}

///|
fn json_string_values(values : Array[Json]) -> Array[String] {
  let out : Array[String] = []
  for value in values {
    match value {
      String(text) => out.push(text)
      _ => ()
    }
  }
  out
}

///|
fn parse_json_object(text : String) -> Result[Map[String, Json], String] {
  let root = @json.parse(text) catch { error => return Err("\{error}") }
  match root {
    Object(object) => Ok(object)
    _ => Err("expected JSON object")
  }
}

///|
fn parse_optional_json_object(text : String?) -> Map[String, Json]? {
  match text {
    Some(value) =>
      match parse_json_object(value) {
        Ok(object) => Some(object)
        Err(_) => None
      }
    None => None
  }
}

///|
fn strip_tree_sitter_prefix(name : String) -> String {
  let scoped = if name.contains("/") {
    let parts = name.split("/").to_array()
    parts[parts.length() - 1].to_string()
  } else {
    name
  }
  if scoped.has_prefix("tree-sitter-") {
    scoped[12:].to_string()
  } else {
    scoped
  }
}

///|
fn normalize_id(raw : String) -> String {
  let input = strip_tree_sitter_prefix(raw)
  let b = StringBuilder::new()
  let mut last_dash = false
  let mut wrote = false
  for c in input {
    let mut out = '\u0000'
    if c >= 'A' && c <= 'Z' {
      out = Int::unsafe_to_char(c.to_int() + 32)
    } else if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') {
      out = c
    } else {
      out = '-'
    }
    if out == '-' {
      if !last_dash && wrote {
        b.write_char('-')
        last_dash = true
      }
    } else {
      b.write_char(out)
      wrote = true
      last_dash = false
    }
  }
  let value = b.to_string().trim_end(chars=['-']).to_string()
  if value.is_empty() {
    "tree-sitter-import"
  } else {
    value
  }
}

///|
fn title_case_id(id : String) -> String {
  let b = StringBuilder::new()
  let mut cap = true
  for c in id {
    if c == '-' {
      b.write_char(' ')
      cap = true
    } else if cap && c >= 'a' && c <= 'z' {
      b.write_char(Int::unsafe_to_char(c.to_int() - 32))
      cap = false
    } else {
      b.write_char(c)
      cap = false
    }
  }
  b.to_string()
}

///|
fn normalize_extension(value : String) -> String {
  if value.has_prefix(".") {
    value
  } else {
    "." + value
  }
}

///|
fn stable_hash(text : String) -> String {
  let mut h = 2166136261L
  for c in text {
    h = h ^ c.to_int().to_int64()
    h = h * 16777619L
  }
  let v = if h < 0L { -h } else { h }
  v.to_string()
}
