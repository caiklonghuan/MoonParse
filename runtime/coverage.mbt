///|
// 文法覆盖率统计（方案 B：解析后遍历树）

///|
priv struct GrammarCoverage {
  production_hits : Array[Int]
  branch_hits : Array[Int]
  rule_hits : Map[String, Int]
  token_hits : Map[Int, Int]
  mut error_nodes : Int
  mut missing_nodes : Int
  mut parse_failures : Int
  input_count : Int
}

///|
fn GrammarCoverage::new(
  table : @tablegen.ParseTable,
  input_count : Int,
) -> GrammarCoverage {
  {
    production_hits: Array::make(table.productions.length(), 0),
    branch_hits: Array::make(table.productions.length(), 0),
    rule_hits: Map::new(),
    token_hits: Map::new(),
    error_nodes: 0,
    missing_nodes: 0,
    parse_failures: 0,
    input_count,
  }
}

///|
fn inc_string_map(map : Map[String, Int], key : String) -> Unit {
  let next = match map.get(key) {
    Some(n) => n + 1
    None => 1
  }
  map[key] = next
}

///|
fn inc_int_map(map : Map[Int, Int], key : Int) -> Unit {
  let next = match map.get(key) {
    Some(n) => n + 1
    None => 1
  }
  map[key] = next
}

///|
fn coverage_symbol_name(
  sym : @tablegen.Symbol,
  table : @tablegen.ParseTable,
) -> String {
  match sym {
    Terminal(tid) =>
      match table.terminal_names.get(tid) {
        Some(name) => name
        None => "<t:" + tid.to_string() + ">"
      }
    NonTerminal(nt) =>
      if nt >= 0 && nt < table.symbol_metadata.length() {
        table.symbol_metadata[nt].name
      } else {
        "<nt:" + nt.to_string() + ">"
      }
    EndOfInput => "$"
  }
}

///|
fn production_body_string(
  prod : @tablegen.Production,
  table : @tablegen.ParseTable,
) -> String {
  if prod.body.is_empty() {
    return "<empty>"
  }
  let parts : Array[String] = []
  for bs in prod.body {
    parts.push(coverage_symbol_name(bs.symbol, table))
  }
  parts.join(" ")
}

///|
fn production_label(
  prod : @tablegen.Production,
  table : @tablegen.ParseTable,
) -> String {
  "[" +
  prod.id.to_string() +
  "] " +
  prod.rule_name +
  " -> " +
  production_body_string(prod, table)
}

///|
fn branch_labels(table : @tablegen.ParseTable) -> Array[String] {
  let labels : Array[String] = Array::make(table.productions.length(), "")
  let seen : Map[String, Int] = Map::new()
  for prod in table.productions {
    let idx = match seen.get(prod.rule_name) {
      Some(n) => n
      None => 0
    }
    seen[prod.rule_name] = idx + 1
    labels[prod.id] = prod.rule_name +
      "#" +
      idx.to_string() +
      " -> " +
      production_body_string(prod, table)
  }
  labels
}

///|
fn rule_order(table : @tablegen.ParseTable) -> Array[String] {
  let names : Array[String] = []
  for prod in table.productions {
    if !names.contains(prod.rule_name) {
      names.push(prod.rule_name)
    }
  }
  names
}

///|
fn token_entries(table : @tablegen.ParseTable) -> Array[(Int, String)] {
  let entries : Array[(Int, String)] = []
  for tid, name in table.terminal_names {
    if tid != sym_end && tid != sym_error {
      entries.push((tid, name))
    }
  }
  entries.sort_by(fn(a, b) { a.0.compare(b.0) })
  entries
}

///|
fn GrammarCoverage::record_tree(
  self : GrammarCoverage,
  table : @tablegen.ParseTable,
  node : CstNode,
) -> Unit {
  if node.is_error {
    self.error_nodes = self.error_nodes + 1
  }
  if node.is_missing {
    self.missing_nodes = self.missing_nodes + 1
  }

  if node.children.is_empty() {
    if node.symbol != sym_end && node.symbol != sym_error {
      inc_int_map(self.token_hits, node.symbol)
    }
    return
  }

  if node.production_id >= 0 && node.production_id < table.productions.length() {
    let prod_id = node.production_id
    self.production_hits[prod_id] = self.production_hits[prod_id] + 1
    self.branch_hits[prod_id] = self.branch_hits[prod_id] + 1
    inc_string_map(self.rule_hits, table.productions[prod_id].rule_name)
  }

  for child in node.children {
    self.record_tree(table, child)
  }
}

///|
fn collect_grammar_coverage(
  table : @tablegen.ParseTable,
  inputs : Array[String],
) -> GrammarCoverage {
  let cov = GrammarCoverage::new(table, inputs.length())
  for input in inputs {
    match parse(table, input) {
      Ok(root) => cov.record_tree(table, root)
      Err(_) => cov.parse_failures = cov.parse_failures + 1
    }
  }
  cov
}

///|
fn map_get_or_zero(map : Map[String, Int], key : String) -> Int {
  match map.get(key) {
    Some(n) => n
    None => 0
  }
}

///|
fn int_map_get_or_zero(map : Map[Int, Int], key : Int) -> Int {
  match map.get(key) {
    Some(n) => n
    None => 0
  }
}

///|
fn append_line(buf : StringBuilder, line : String) -> Unit {
  buf.write_string(line)
  buf.write_char('\n')
}

///|
pub fn grammar_coverage_report(
  table : @tablegen.ParseTable,
  inputs : Array[String],
  low_hit_threshold : Int,
) -> String {
  let cov = collect_grammar_coverage(table, inputs)
  let buf = StringBuilder::new()
  append_line(
    buf,
    "inputs=" +
    cov.input_count.to_string() +
    " parse_failures=" +
    cov.parse_failures.to_string() +
    " low_hit_threshold=" +
    low_hit_threshold.to_string(),
  )
  append_line(
    buf,
    "recovery error_nodes=" +
    cov.error_nodes.to_string() +
    " missing_nodes=" +
    cov.missing_nodes.to_string() +
    " total=" +
    (cov.error_nodes + cov.missing_nodes).to_string(),
  )

  append_line(buf, "rule_hits:")
  for name in rule_order(table) {
    append_line(
      buf,
      "  " + name + " = " + map_get_or_zero(cov.rule_hits, name).to_string(),
    )
  }

  append_line(buf, "unhit_rules:")
  for name in rule_order(table) {
    if map_get_or_zero(cov.rule_hits, name) == 0 {
      append_line(buf, "  " + name)
    }
  }

  let labels = branch_labels(table)
  append_line(buf, "branch_hits:")
  for i in 0..<labels.length() {
    append_line(buf, "  " + labels[i] + " = " + cov.branch_hits[i].to_string())
  }

  append_line(buf, "production_hits:")
  for prod in table.productions {
    append_line(
      buf,
      "  " +
      production_label(prod, table) +
      " = " +
      cov.production_hits[prod.id].to_string(),
    )
  }

  append_line(buf, "unhit_productions:")
  for prod in table.productions {
    if cov.production_hits[prod.id] == 0 {
      append_line(buf, "  " + production_label(prod, table))
    }
  }

  append_line(buf, "low_hit_productions:")
  for prod in table.productions {
    let hits = cov.production_hits[prod.id]
    if hits > 0 && hits <= low_hit_threshold {
      append_line(
        buf,
        "  " + production_label(prod, table) + " = " + hits.to_string(),
      )
    }
  }

  append_line(buf, "token_hits:")
  for entry in token_entries(table) {
    let (tid, name) = entry
    append_line(
      buf,
      "  [" +
      tid.to_string() +
      "] " +
      name +
      " = " +
      int_map_get_or_zero(cov.token_hits, tid).to_string(),
    )
  }

  append_line(buf, "unhit_tokens:")
  for entry in token_entries(table) {
    let (tid, name) = entry
    if int_map_get_or_zero(cov.token_hits, tid) == 0 {
      append_line(buf, "  [" + tid.to_string() + "] " + name)
    }
  }
  buf.to_string()
}
