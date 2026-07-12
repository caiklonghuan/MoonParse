///|
pub fn tree_sitter_rust_scanner(
  table : @tablegen.ParseTable,
) -> &@runtime.StatefulScanner {
  RustTreeSitterScanner::new(table) as &@runtime.StatefulScanner
}

///|
pub struct RustTreeSitterScanner {
  raw_string_id : Int?
}

///|
fn rust_has_tid(tids : Array[Int], target : Int) -> Bool {
  for tid in tids {
    if tid == target {
      return true
    }
  }
  false
}

///|
fn rust_find_raw_string_id(table : @tablegen.ParseTable) -> Int? {
  for tid in table.external_token_ids {
    match table.terminal_names.get(tid) {
      Some(name) =>
        if name.contains("raw") && name.contains("string") {
          return Some(tid)
        }
      None => ()
    }
  }
  match table.external_token_ids {
    [] => None
    [first, ..] => Some(first)
  }
}

///|
pub fn RustTreeSitterScanner::new(
  table : @tablegen.ParseTable,
) -> RustTreeSitterScanner {
  { raw_string_id: rust_find_raw_string_id(table) }
}

///|
fn scan_rust_raw_string(input : String, pos : Int) -> Int? {
  if pos + 1 >= input.length() || input[pos] != 'r' {
    return None
  }
  let mut cursor = pos + 1
  let mut hashes = 0
  while cursor < input.length() && input[cursor] == '#' {
    hashes = hashes + 1
    cursor = cursor + 1
  }
  if cursor >= input.length() || input[cursor] != '"' {
    return None
  }
  cursor = cursor + 1
  while cursor < input.length() {
    if input[cursor] == '"' {
      let mut matched = true
      let mut h = 0
      while h < hashes {
        if cursor + 1 + h >= input.length() || input[cursor + 1 + h] != '#' {
          matched = false
          break
        }
        h = h + 1
      }
      if matched {
        return Some(cursor + 1 + hashes)
      }
    }
    cursor = cursor + 1
  }
  Some(input.length())
}

///|
impl @runtime.StatefulScanner for RustTreeSitterScanner with fn scan(
  self,
  input,
  pos,
  ext_tids,
) {
  match self.raw_string_id {
    Some(raw_id) if rust_has_tid(ext_tids, raw_id) =>
      match scan_rust_raw_string(input, pos) {
        Some(end) if end > pos => Some((raw_id, end))
        _ => None
      }
    _ => None
  }
}

///|
impl @runtime.StatefulScanner for RustTreeSitterScanner with fn clone_scanner(
  self,
) {
  ({ raw_string_id: self.raw_string_id } : RustTreeSitterScanner)
  as &@runtime.StatefulScanner
}
