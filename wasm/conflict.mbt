///|
fn conflict_terminal_name(
  table : @tablegen.ParseTable,
  terminal : Int,
) -> String {
  if terminal == @tablegen.eoi_id {
    return "$"
  }
  match table.terminal_names.get(terminal) {
    Some(name) => name
    None => "terminal#" + terminal.to_string()
  }
}

///|
fn conflict_nonterminal_name(table : @tablegen.ParseTable, id : Int) -> String {
  if id >= 0 && id < table.symbol_metadata.length() {
    table.symbol_metadata[id].name
  } else {
    "nonterminal#" + id.to_string()
  }
}

///|
fn conflict_symbol_name(
  table : @tablegen.ParseTable,
  symbol : @tablegen.Symbol,
) -> String {
  match symbol {
    @tablegen.Symbol::Terminal(id) => conflict_terminal_name(table, id)
    @tablegen.Symbol::NonTerminal(id) => conflict_nonterminal_name(table, id)
    @tablegen.Symbol::EndOfInput => "$"
  }
}

///|
fn conflict_symbol_kind(symbol : @tablegen.Symbol) -> String {
  match symbol {
    @tablegen.Symbol::Terminal(_) => "terminal"
    @tablegen.Symbol::NonTerminal(_) => "nonterminal"
    @tablegen.Symbol::EndOfInput => "eof"
  }
}

///|
fn conflict_symbol_id(symbol : @tablegen.Symbol) -> Int {
  match symbol {
    @tablegen.Symbol::Terminal(id) => id
    @tablegen.Symbol::NonTerminal(id) => id
    @tablegen.Symbol::EndOfInput => -1
  }
}

///|
fn conflict_body_symbol_name(
  table : @tablegen.ParseTable,
  body_symbol : @tablegen.BodySymbol,
) -> String {
  let name = conflict_symbol_name(table, body_symbol.symbol)
  match body_symbol.field_name {
    Some(field) => field + ":" + name
    None => name
  }
}

///|
fn conflict_production_display(
  table : @tablegen.ParseTable,
  production : @tablegen.Production,
  dot : Int,
) -> String {
  let parts : Array[String] = []
  for index in 0..<=production.body.length() {
    if index == dot {
      parts.push("•")
    }
    if index < production.body.length() {
      parts.push(conflict_body_symbol_name(table, production.body[index]))
    }
  }
  conflict_nonterminal_name(table, production.head) + " → " + parts.join(" ")
}

///|
fn conflict_assoc_text(assoc : @grammar.PrecKind) -> String {
  match assoc {
    @grammar.PrecKind::Left => "left"
    @grammar.PrecKind::Right => "right"
    @grammar.PrecKind::Nonassoc => "nonassoc"
    @grammar.PrecKind::Dynamic => "dynamic"
  }
}

///|
fn write_conflict_body(
  buf : StringBuilder,
  table : @tablegen.ParseTable,
  production : @tablegen.Production,
) -> Unit {
  buf.write_string("\"body\":[")
  for index in 0..<production.body.length() {
    if index > 0 {
      buf.write_char(',')
    }
    write_jstr(buf, conflict_body_symbol_name(table, production.body[index]))
  }
  buf.write_char(']')
}

///|
fn write_conflict_production_fields(
  buf : StringBuilder,
  table : @tablegen.ParseTable,
  production : @tablegen.Production,
  dot : Int,
) -> Unit {
  write_kvi(buf, "productionId", production.id)
  buf.write_char(',')
  write_kvs(buf, "ruleName", production.rule_name)
  buf.write_char(',')
  write_kvs(buf, "head", conflict_nonterminal_name(table, production.head))
  buf.write_char(',')
  write_conflict_body(buf, table, production)
  buf.write_char(',')
  write_kvi(buf, "dot", dot)
  buf.write_char(',')
  write_kvs(buf, "display", conflict_production_display(table, production, dot))
  buf.write_char(',')
  write_jstr(buf, "precedence")
  buf.write_char(':')
  match production.prec {
    Some(value) => buf.write_string(value.to_string())
    None => buf.write_string("null")
  }
  buf.write_char(',')
  write_jstr(buf, "associativity")
  buf.write_char(':')
  match production.assoc {
    Some(value) => write_jstr(buf, conflict_assoc_text(value))
    None => buf.write_string("null")
  }
}

///|
fn write_conflict_action(
  buf : StringBuilder,
  table : @tablegen.ParseTable,
  action : @tablegen.Action,
  index : Int,
) -> Unit {
  buf.write_char('{')
  write_kvi(buf, "index", index)
  buf.write_char(',')
  match action {
    @tablegen.Action::Shift(state) => {
      write_kvs(buf, "kind", "shift")
      buf.write_char(',')
      write_kvi(buf, "targetState", state)
      buf.write_char(',')
      write_kvs(buf, "display", "shift → state " + state.to_string())
    }
    @tablegen.Action::Reduce(production_id) => {
      write_kvs(buf, "kind", "reduce")
      if production_id >= 0 && production_id < table.productions.length() {
        let production = table.productions[production_id]
        buf.write_char(',')
        write_conflict_production_fields(
          buf,
          table,
          production,
          production.body.length(),
        )
      } else {
        buf.write_char(',')
        write_kvi(buf, "productionId", production_id)
        buf.write_char(',')
        write_kvs(
          buf,
          "display",
          "reduce production " + production_id.to_string(),
        )
      }
    }
    @tablegen.Action::Accept => {
      write_kvs(buf, "kind", "accept")
      buf.write_char(',')
      write_kvs(buf, "display", "accept")
    }
  }
  buf.write_char('}')
}

///|
fn conflict_severity_string(severity : @tablegen.ConflictSeverity) -> String {
  match severity {
    @tablegen.ConflictSeverity::Warn(description) => "warn: " + description
    @tablegen.ConflictSeverity::Ambiguous(description) =>
      "ambiguous: " + description
    @tablegen.ConflictSeverity::DynamicConflict(id) =>
      "dynamic_conflict(id=" + id.to_string() + ")"
    @tablegen.ConflictSeverity::Declared(description) =>
      "declared: " + description
  }
}

///|
fn conflict_message(report : @tablegen.ConflictReport) -> String {
  match report.severity {
    @tablegen.ConflictSeverity::Warn(description) => description
    @tablegen.ConflictSeverity::Ambiguous(description) => description
    @tablegen.ConflictSeverity::Declared(description) => description
    @tablegen.ConflictSeverity::DynamicConflict(id) =>
      "Dynamic precedence conflict (id=" +
      id.to_string() +
      ") in state " +
      report.state.to_string() +
      " on terminal " +
      report.terminal.to_string()
  }
}

///|
fn conflict_resolution_kind(severity : @tablegen.ConflictSeverity) -> String {
  match severity {
    @tablegen.ConflictSeverity::Warn(_) => "resolved"
    @tablegen.ConflictSeverity::Declared(_) => "declared-glr"
    @tablegen.ConflictSeverity::Ambiguous(_) => "ambiguous-glr"
    @tablegen.ConflictSeverity::DynamicConflict(_) => "dynamic-precedence"
  }
}

///|
fn conflict_action_is_resolved(
  report : @tablegen.ConflictReport,
  action : @tablegen.Action,
) -> Bool {
  report.resolved_actions.any(fn(resolved) { resolved == action })
}

///|
fn conflict_branch_outcome(
  report : @tablegen.ConflictReport,
  action : @tablegen.Action,
) -> String {
  match report.severity {
    @tablegen.ConflictSeverity::Warn(_) =>
      if conflict_action_is_resolved(report, action) {
        "kept"
      } else {
        "discarded"
      }
    @tablegen.ConflictSeverity::Declared(_)
    | @tablegen.ConflictSeverity::Ambiguous(_) => "glr"
    @tablegen.ConflictSeverity::DynamicConflict(_) => "dynamic"
  }
}

///|
fn write_conflict_action_indexes(
  buf : StringBuilder,
  report : @tablegen.ConflictReport,
  keep : Bool,
) -> Unit {
  buf.write_char('[')
  let mut first = true
  for index in 0..<report.actions.length() {
    if conflict_action_is_resolved(report, report.actions[index]) == keep {
      if !first {
        buf.write_char(',')
      }
      buf.write_string(index.to_string())
      first = false
    }
  }
  buf.write_char(']')
}

///|
fn conflict_report_to_json(
  report : @tablegen.ConflictReport,
  table : @tablegen.ParseTable,
) -> String {
  let buf = StringBuilder::new()
  let message = conflict_message(report)
  buf.write_char('{')
  write_kvs(buf, "severity", conflict_severity_string(report.severity))
  buf.write_char(',')
  write_kvi(buf, "state", report.state)
  buf.write_char(',')
  write_kvi(buf, "terminal", report.terminal)
  buf.write_char(',')
  write_kvs(buf, "message", message)
  buf.write_char(',')
  write_kvs(buf, "terminalName", conflict_terminal_name(table, report.terminal))
  buf.write_char(',')
  buf.write_string("\"actions\":[")
  for index in 0..<report.actions.length() {
    if index > 0 {
      buf.write_char(',')
    }
    write_conflict_action(buf, table, report.actions[index], index)
  }
  buf.write_string("],\"items\":[")
  for index in 0..<report.items.length() {
    if index > 0 {
      buf.write_char(',')
    }
    let item = report.items[index]
    buf.write_char('{')
    if item.prod >= 0 && item.prod < table.productions.length() {
      write_conflict_production_fields(
        buf,
        table,
        table.productions[item.prod],
        item.dot,
      )
    } else {
      write_kvi(buf, "productionId", item.prod)
      buf.write_char(',')
      write_kvi(buf, "dot", item.dot)
      buf.write_char(',')
      write_kvs(buf, "display", "invalid production")
    }
    buf.write_char('}')
  }
  buf.write_string("],\"statePath\":[")
  for index in 0..<report.state_path.length() {
    if index > 0 {
      buf.write_char(',')
    }
    let step = report.state_path[index]
    buf.write_char('{')
    write_kvi(buf, "fromState", step.from_state)
    buf.write_char(',')
    write_kvi(buf, "toState", step.to_state)
    buf.write_char(',')
    write_kvs(buf, "symbolKind", conflict_symbol_kind(step.symbol))
    buf.write_char(',')
    write_kvi(buf, "symbolId", conflict_symbol_id(step.symbol))
    buf.write_char(',')
    write_kvs(buf, "symbolName", conflict_symbol_name(table, step.symbol))
    buf.write_char('}')
  }
  buf.write_string("],\"branches\":[")
  for index in 0..<report.actions.length() {
    if index > 0 {
      buf.write_char(',')
    }
    buf.write_char('{')
    write_kvi(buf, "actionIndex", index)
    buf.write_char(',')
    write_kvs(
      buf,
      "outcome",
      conflict_branch_outcome(report, report.actions[index]),
    )
    buf.write_char(',')
    write_kvs(buf, "message", message)
    buf.write_char('}')
  }
  buf.write_string("],\"resolution\":{")
  write_kvs(buf, "kind", conflict_resolution_kind(report.severity))
  buf.write_char(',')
  write_kvs(buf, "message", message)
  buf.write_char(',')
  write_jstr(buf, "keptActionIndexes")
  buf.write_char(':')
  write_conflict_action_indexes(buf, report, true)
  buf.write_char(',')
  write_jstr(buf, "discardedActionIndexes")
  buf.write_char(':')
  write_conflict_action_indexes(buf, report, false)
  buf.write_string("}}")
  buf.to_string()
}

///|
fn conflict_reports_to_json_entries(
  reports : Array[@tablegen.ConflictReport],
  table : @tablegen.ParseTable,
) -> Array[String] {
  let diagnostics : Array[String] = []
  for report in reports {
    diagnostics.push(conflict_report_to_json(report, table))
  }
  diagnostics
}
