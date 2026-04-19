///|
// scripts/mutate_input.mbt — 共享的生成/变异 helper + mutate-input 子命令

///|
enum ScriptGrammar {
  Json
  Expression
} derive(Debug, Eq)

///|
enum MutationKind {
  DeleteChar
  DeleteToken
  ReplaceToken
  ScrambleBracket
  InsertGarbage
  TruncatePrefix
} derive(Debug, Eq)

///|
enum StabilityOutcome {
  CleanParse
  RecoveredParse
  ParseReturnedErr
} derive(Debug, Eq)

///|
enum IncrementalOutcome {
  CleanMatch
  RecoveredMatch
  ErrMatch
} derive(Debug, Eq)

///|
struct Mutation {
  name : String
  start_byte : Int
  old_end_byte : Int
  replacement : String
} derive(Debug)

///|
struct JsonToken {
  start_byte : Int
  end_byte : Int
  kind : Int
} derive(Debug)

///|
struct ExprToken {
  start_byte : Int
  end_byte : Int
  kind : Int
} derive(Debug)

///|
struct MutateInputOptions {
  grammar : ScriptGrammar
  input : String?
  seed : Int
  kind : MutationKind?
  depth : Int
  width : Int
} derive(Debug)

///|
fn grammar_name(grammar : ScriptGrammar) -> String {
  match grammar {
    Json => "json"
    Expression => "expression"
  }
}

///|
fn parse_script_grammar(text : String) -> ScriptGrammar? {
  match text {
    "json" => Some(Json)
    "expression" => Some(Expression)
    _ => None
  }
}

///|
fn mutation_kind_name(kind : MutationKind) -> String {
  match kind {
    DeleteChar => "delete-char"
    DeleteToken => "delete-token"
    ReplaceToken => "replace-token"
    ScrambleBracket => "scramble-bracket"
    InsertGarbage => "insert-garbage"
    TruncatePrefix => "truncate-prefix"
  }
}

///|
fn parse_mutation_kind(text : String) -> MutationKind? {
  match text {
    "delete-char" => Some(DeleteChar)
    "delete-token" => Some(DeleteToken)
    "replace-token" => Some(ReplaceToken)
    "scramble-bracket" => Some(ScrambleBracket)
    "scramble-paren" => Some(ScrambleBracket)
    "insert-garbage" => Some(InsertGarbage)
    "truncate-prefix" => Some(TruncatePrefix)
    _ => None
  }
}

///|
fn all_mutation_kinds() -> Array[MutationKind] {
  [
    DeleteChar,
    DeleteToken,
    ReplaceToken,
    ScrambleBracket,
    InsertGarbage,
    TruncatePrefix,
  ]
}

///|
fn mutation_kind_by_index(index : Int) -> MutationKind {
  match index {
    0 => DeleteChar
    1 => DeleteToken
    2 => ReplaceToken
    3 => ScrambleBracket
    4 => InsertGarbage
    _ => TruncatePrefix
  }
}

///|
fn parse_nonnegative_int(text : String) -> Int? {
  if text.is_empty() {
    return None
  }
  let mut value = 0
  for i in 0..<text.length() {
    let code = text[i].to_int()
    if code < '0'.to_int() || code > '9'.to_int() {
      return None
    }
    value = value * 10 + code - '0'.to_int()
  }
  Some(value)
}

///|
fn fuzz_next_seed(seed : Int) -> Int {
  let next = (seed * 48271 + 1) % 2147483647
  if next <= 0 {
    next + 2147483646
  } else {
    next
  }
}

///|
fn fuzz_pick(seed : Int, modulo : Int) -> (Int, Int) {
  let next = fuzz_next_seed(seed)
  (next, next % modulo)
}

///|
fn choose_mutation_kind(
  seed : Int,
  requested : MutationKind?,
) -> (Int, MutationKind) {
  match requested {
    Some(kind) => (seed, kind)
    None => {
      let (next, pick) = fuzz_pick(seed, 6)
      (next, mutation_kind_by_index(pick))
    }
  }
}

///|
fn point_at(input : String, pos : Int) -> @runtime.Point {
  @runtime.bytes_to_point(input, 0, { row: 0, column: 0 }, pos)
}

///|
fn point_repr(point : @runtime.Point) -> String {
  "(" + point.row.to_string() + ", " + point.column.to_string() + ")"
}

///|
fn replace_range(
  old_input : String,
  start_byte : Int,
  old_end_byte : Int,
  replacement : String,
) -> String {
  old_input[0:start_byte].to_string() +
  replacement +
  old_input[old_end_byte:old_input.length()].to_string()
}

///|
fn apply_mutation(input : String, mutation : Mutation) -> String {
  replace_range(
    input,
    mutation.start_byte,
    mutation.old_end_byte,
    mutation.replacement,
  )
}

///|
fn make_edit_from_replacement(
  old_input : String,
  start_byte : Int,
  old_end_byte : Int,
  replacement : String,
) -> (String, @runtime.InputEdit) {
  let new_input = replace_range(
    old_input, start_byte, old_end_byte, replacement,
  )
  let new_end_byte = start_byte + replacement.length()
  let edit : @runtime.InputEdit = {
    start_byte,
    old_end_byte,
    new_end_byte,
    start_point: point_at(old_input, start_byte),
    old_end_point: point_at(old_input, old_end_byte),
    new_end_point: point_at(new_input, new_end_byte),
  }
  (new_input, edit)
}

///|
fn has_error_or_missing(node : @runtime.CstNode) -> Bool {
  if node.is_error || node.is_missing {
    return true
  }
  for child in node.children {
    if has_error_or_missing(child) {
      return true
    }
  }
  false
}

///|
fn is_visible_for_compare(node : @runtime.CstNode) -> Bool {
  node.is_named || node.is_error || node.is_missing
}

///|
fn collect_visible_children(node : @runtime.CstNode) -> Array[@runtime.CstNode] {
  let out : Array[@runtime.CstNode] = []
  for child in node.children {
    if is_visible_for_compare(child) {
      out.push(child)
    } else if !child.children.is_empty() {
      for nested in collect_visible_children(child) {
        out.push(nested)
      }
    }
  }
  out
}

///|
fn diff_visible_tree_shape(
  actual : @runtime.CstNode,
  expected : @runtime.CstNode,
  path : String,
) -> String? {
  if is_visible_for_compare(actual) != is_visible_for_compare(expected) {
    return Some("visible-node mismatch at \{path}")
  }
  if actual.symbol != expected.symbol {
    return Some(
      "symbol mismatch at \{path}: \{actual.symbol} != \{expected.symbol}",
    )
  }
  if actual.is_named != expected.is_named {
    return Some("is_named mismatch at \{path}")
  }
  if actual.extra != expected.extra {
    return Some("extra mismatch at \{path}")
  }
  if actual.is_missing != expected.is_missing {
    return Some("is_missing mismatch at \{path}")
  }
  if actual.is_error != expected.is_error {
    return Some("is_error mismatch at \{path}")
  }
  if actual.start_byte != expected.start_byte ||
    actual.end_byte != expected.end_byte {
    return Some(
      "byte span mismatch at \{path}: [\{actual.start_byte}, \{actual.end_byte}) != [\{expected.start_byte}, \{expected.end_byte})",
    )
  }
  if actual.start_point != expected.start_point ||
    actual.end_point != expected.end_point {
    return Some(
      "point mismatch at \{path}: " +
      point_repr(actual.start_point) +
      ".." +
      point_repr(actual.end_point) +
      " != " +
      point_repr(expected.start_point) +
      ".." +
      point_repr(expected.end_point),
    )
  }
  let actual_children = collect_visible_children(actual)
  let expected_children = collect_visible_children(expected)
  if actual_children.length() != expected_children.length() {
    return Some(
      "children length mismatch at \{path}: \{actual_children.length()} != \{expected_children.length()}",
    )
  }
  for i in 0..<actual_children.length() {
    match
      diff_visible_tree_shape(
        actual_children[i],
        expected_children[i],
        path + "/" + i.to_string(),
      ) {
      Some(msg) => return Some(msg)
      None => ()
    }
  }
  None
}

///|
fn builtin_prefix(grammar : ScriptGrammar) -> String {
  match grammar {
    Json => "(json"
    Expression => "(expression"
  }
}

///|
fn builtin_sexp(grammar : ScriptGrammar, input : String) -> String {
  match grammar {
    Json => @grammars.json_sexp(input)
    Expression => @grammars.expression_sexp(input)
  }
}

///|
fn builtin_parse(
  grammar : ScriptGrammar,
  input : String,
) -> Result[@runtime.CstNode, @runtime.ParseError] {
  match grammar {
    Json => @grammars.parse_json(input)
    Expression => @grammars.parse_expression(input)
  }
}

///|
fn validate_clean_sample(
  grammar : ScriptGrammar,
  label : String,
  input : String,
) -> String? {
  match builtin_parse(grammar, input) {
    Ok(root) => {
      match @runtime.check_cst_invariants(root, input) {
        Some(msg) => return Some("\{label}: \{msg}")
        None => ()
      }
      if root.start_byte != 0 || root.end_byte != input.length() {
        return Some(
          "\{label}: expected root span [0, \{input.length()}) got [\{root.start_byte}, \{root.end_byte}) for \{input.escape()}",
        )
      }
      if has_error_or_missing(root) {
        return Some(
          "\{label}: expected clean parse but recovery markers were present for \{input.escape()}",
        )
      }
      let sexp = builtin_sexp(grammar, input)
      if sexp.is_empty() ||
        sexp.contains("ERROR") ||
        !sexp.has_prefix(builtin_prefix(grammar)) {
        return Some(
          "\{label}: expected clean S-expression for \{input.escape()}, got \{sexp}",
        )
      }
      None
    }
    Err(e) =>
      Some(
        "\{label}: generated invalid \{grammar_name(grammar)} \{input.escape()} -> \{e.message}",
      )
  }
}

///|
fn check_any_input_stable(
  grammar : ScriptGrammar,
  label : String,
  input : String,
) -> Result[StabilityOutcome, String] {
  let sexp = builtin_sexp(grammar, input)
  if sexp.is_empty() {
    return Err("\{label}: empty sexp output")
  }
  if !sexp.has_prefix(builtin_prefix(grammar)) && !sexp.has_prefix("ERROR: ") {
    return Err("\{label}: unexpected sexp prefix: \{sexp}")
  }
  match builtin_parse(grammar, input) {
    Ok(root) =>
      match @runtime.check_cst_invariants(root, input) {
        Some(msg) => Err("\{label}: \{msg}")
        None =>
          if root.end_byte > input.length() {
            Err(
              "\{label}: root.end_byte out of range: \{root.end_byte} > \{input.length()}",
            )
          } else if has_error_or_missing(root) {
            Ok(RecoveredParse)
          } else {
            Ok(CleanParse)
          }
      }
    Err(e) =>
      if e.message.is_empty() {
        Err("\{label}: parse returned empty error message")
      } else {
        Ok(ParseReturnedErr)
      }
  }
}

///|
fn builtin_grammar_dsl(grammar : ScriptGrammar) -> String {
  match grammar {
    Json => @grammars.json_grammar
    Expression => @grammars.expression_grammar
  }
}

///|
fn compile_builtin_table(grammar : ScriptGrammar) -> @tablegen.ParseTable {
  let parsed = match @grammar.parse_grammar(builtin_grammar_dsl(grammar)) {
    @grammar.Success(parsed) => parsed
    @grammar.Error(e) =>
      abort(
        "compile_builtin_table[\{grammar_name(grammar)}]: parse_grammar failed: \{e.message}",
      )
  }
  match @tablegen.generate_parse_table(parsed) {
    Ok((table, _)) => table
    Err(e) =>
      abort(
        "compile_builtin_table[\{grammar_name(grammar)}]: generate_parse_table failed: \{e}",
      )
  }
}

///|
fn check_incremental_mutation(
  grammar : ScriptGrammar,
  table : @tablegen.ParseTable,
  old_input : String,
  mutation : Mutation,
  label : String,
) -> Result[IncrementalOutcome, String] {
  let old_root = match @runtime.parse(table, old_input) {
    Ok(root) => root
    Err(e) => return Err("\{label}: old parse failed: \{e.message}")
  }
  let (new_input, edit) = make_edit_from_replacement(
    old_input,
    mutation.start_byte,
    mutation.old_end_byte,
    mutation.replacement,
  )
  let inc_result = @runtime.parse_with_old_tree(
    table,
    new_input,
    Some({ root: old_root, old_input }),
    Some(edit),
  )
  let full_result = @runtime.parse(table, new_input)
  match (inc_result, full_result) {
    (Ok(inc_root), Ok(full_root)) => {
      match @runtime.check_cst_invariants(inc_root, new_input) {
        Some(msg) => return Err("\{label}: \{msg}")
        None => ()
      }
      match @runtime.check_cst_invariants(full_root, new_input) {
        Some(msg) => return Err("\{label}: \{msg}")
        None => ()
      }
      let inc_recovered = has_error_or_missing(inc_root)
      let full_recovered = has_error_or_missing(full_root)
      if inc_recovered != full_recovered {
        return Err(
          "\{label}: incremental/full recovery presence mismatch on \{grammar_name(grammar)} mutation",
        )
      }
      if grammar == Json && inc_recovered {
        if inc_root.start_byte != full_root.start_byte ||
          inc_root.end_byte != full_root.end_byte {
          return Err(
            "\{label}: recovered root span mismatch: [\{inc_root.start_byte}, \{inc_root.end_byte}) != [\{full_root.start_byte}, \{full_root.end_byte})",
          )
        }
        if inc_root.start_point != full_root.start_point ||
          inc_root.end_point != full_root.end_point {
          return Err(
            "\{label}: recovered root point mismatch: " +
            point_repr(inc_root.start_point) +
            ".." +
            point_repr(inc_root.end_point) +
            " != " +
            point_repr(full_root.start_point) +
            ".." +
            point_repr(full_root.end_point),
          )
        }
        Ok(RecoveredMatch)
      } else {
        match diff_visible_tree_shape(inc_root, full_root, "root") {
          Some(msg) => Err("\{label}: \{msg}")
          None =>
            if inc_recovered {
              Ok(RecoveredMatch)
            } else {
              Ok(CleanMatch)
            }
        }
      }
    }
    (Err(inc_err), Err(full_err)) =>
      if inc_err.position != full_err.position ||
        inc_err.point != full_err.point ||
        inc_err.message != full_err.message {
        Err(
          "\{label}: incremental/full Err mismatch: inc=\{inc_err} full=\{full_err}",
        )
      } else {
        Ok(ErrMatch)
      }
    (Ok(_), Err(full_err)) =>
      Err(
        "\{label}: incremental parse succeeded but full parse failed: \{full_err}",
      )
    (Err(inc_err), Ok(_)) =>
      Err(
        "\{label}: incremental parse failed but full parse succeeded: \{inc_err}",
      )
  }
}

///|
fn print_mutation_failure_context(
  title : String,
  grammar : ScriptGrammar,
  sample : Int,
  seed : Int,
  base : String,
  mutation : Mutation,
  mutated : String,
  detail : String,
) -> Unit {
  println(title + ": " + detail)
  println("grammar: " + grammar_name(grammar))
  println("sample: " + sample.to_string())
  println("seed: " + seed.to_string())
  println("mutation: " + mutation.name)
  println("start_byte: " + mutation.start_byte.to_string())
  println("old_end_byte: " + mutation.old_end_byte.to_string())
  println("replacement: " + mutation.replacement.escape())
  println("base: " + base.escape())
  println("mutated: " + mutated.escape())
}

///|
fn print_base_failure_context(
  title : String,
  grammar : ScriptGrammar,
  sample : Int,
  seed : Int,
  input : String,
  detail : String,
) -> Unit {
  println(title + ": " + detail)
  println("grammar: " + grammar_name(grammar))
  println("sample: " + sample.to_string())
  println("seed: " + seed.to_string())
  println("input: " + input.escape())
}

///|
fn json_guided_gap(seed : Int) -> (Int, String) {
  let gaps = ["", " ", "\n", "\t", " \n "]
  let (next, index) = fuzz_pick(seed, gaps.length())
  (next, gaps[index])
}

///|
fn json_guided_digits(seed : Int, count : Int) -> (Int, String) {
  let buf = StringBuilder::new()
  let mut cur = seed
  for _ in 0..<count {
    let (next, digit) = fuzz_pick(cur, 10)
    cur = next
    buf.write_char(('0'.to_int() + digit).to_char().unwrap())
  }
  (cur, buf.to_string())
}

///|
fn json_guided_string(seed : Int, max_units : Int) -> (Int, String) {
  let raw_units = ["a", "b", "Z", "0", "_", "-", " "]
  let escaped_units = ["\\\"", "\\\\", "\\n", "\\t", "\\u4e2d"]
  let (next, count_pick) = fuzz_pick(seed, max_units + 1)
  let buf = StringBuilder::new()
  let mut cur = next
  buf.write_char('"')
  for _ in 0..<count_pick {
    let (next, kind) = fuzz_pick(cur, 4)
    cur = next
    if kind == 0 {
      let (next, index) = fuzz_pick(cur, escaped_units.length())
      cur = next
      buf.write_string(escaped_units[index])
    } else {
      let (next, index) = fuzz_pick(cur, raw_units.length())
      cur = next
      buf.write_string(raw_units[index])
    }
  }
  buf.write_char('"')
  (cur, buf.to_string())
}

///|
fn json_guided_number(seed : Int) -> (Int, String) {
  let (next, neg_pick) = fuzz_pick(seed, 2)
  let (next, int_count_pick) = fuzz_pick(next, 4)
  let (next, int_part) = json_guided_digits(next, int_count_pick + 1)
  let (next, frac_pick) = fuzz_pick(next, 3)
  let mut cur = next
  let prefix = if neg_pick == 0 { "-" } else { "" }
  let mut result = prefix + int_part
  if frac_pick == 0 {
    let (next, frac_count_pick) = fuzz_pick(cur, 3)
    let (next, frac_part) = json_guided_digits(next, frac_count_pick + 1)
    cur = next
    result = result + "." + frac_part
  }
  let (next, exp_pick) = fuzz_pick(cur, 3)
  cur = next
  if exp_pick == 0 {
    let (next, sign_pick) = fuzz_pick(cur, 3)
    let (next, exp_count_pick) = fuzz_pick(next, 3)
    let (next, exp_part) = json_guided_digits(next, exp_count_pick + 1)
    cur = next
    let sign = match sign_pick {
      0 => "+"
      1 => "-"
      _ => ""
    }
    result = result + "e" + sign + exp_part
  }
  (cur, result)
}

///|
fn json_guided_value_kind(
  seed : Int,
  kind : Int,
  depth : Int,
  width : Int,
) -> (Int, String) {
  if depth <= 0 && kind < 2 {
    return json_guided_value_kind(seed, kind + 2, depth, width)
  }
  match kind {
    0 => {
      let (next, count_pick) = fuzz_pick(seed, width + 1)
      let buf = StringBuilder::new()
      let mut cur = next
      buf.write_char('{')
      for i in 0..<count_pick {
        if i > 0 {
          buf.write_char(',')
        }
        let (next, before_key) = json_guided_gap(cur)
        let (next, key) = json_guided_string(next, 4)
        let (next, before_colon) = json_guided_gap(next)
        let (next, after_colon) = json_guided_gap(next)
        let (next, value_kind) = fuzz_pick(next, 7)
        let (next, value) = json_guided_value_kind(
          next,
          value_kind,
          depth - 1,
          width,
        )
        cur = next
        buf.write_string(before_key)
        buf.write_string(key)
        buf.write_string(before_colon)
        buf.write_char(':')
        buf.write_string(after_colon)
        buf.write_string(value)
      }
      let (cur, trailing_gap) = json_guided_gap(cur)
      buf.write_string(trailing_gap)
      buf.write_char('}')
      (cur, buf.to_string())
    }
    1 => {
      let (next, count_pick) = fuzz_pick(seed, width + 1)
      let buf = StringBuilder::new()
      let mut cur = next
      buf.write_char('[')
      for i in 0..<count_pick {
        if i > 0 {
          buf.write_char(',')
        }
        let (next, gap) = json_guided_gap(cur)
        let (next, value_kind) = fuzz_pick(next, 7)
        let (next, value) = json_guided_value_kind(
          next,
          value_kind,
          depth - 1,
          width,
        )
        cur = next
        buf.write_string(gap)
        buf.write_string(value)
      }
      let (cur, trailing_gap) = json_guided_gap(cur)
      buf.write_string(trailing_gap)
      buf.write_char(']')
      (cur, buf.to_string())
    }
    2 => json_guided_string(seed, width + 2)
    3 => json_guided_number(seed)
    4 => (seed, "true")
    5 => (seed, "false")
    _ => (seed, "null")
  }
}

///|
fn json_guided_value(seed : Int, depth : Int, width : Int) -> (Int, String) {
  let (next, kind) = fuzz_pick(seed, 7)
  json_guided_value_kind(next, kind, depth, width)
}

///|
fn json_byte_at(input : String, pos : Int) -> Char {
  input[pos].to_int().to_char().unwrap()
}

///|
fn json_is_space(ch : Char) -> Bool {
  ch == ' ' || ch == '\n' || ch == '\t' || ch == '\r'
}

///|
fn json_is_digit(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

///|
fn json_starts_with_at(input : String, start : Int, fragment : String) -> Bool {
  let end_byte = start + fragment.length()
  end_byte <= input.length() && input[start:end_byte].to_string() == fragment
}

///|
fn json_scan_string_end(input : String, start_byte : Int) -> Int {
  let mut i = start_byte + 1
  while i < input.length() {
    let ch = json_byte_at(input, i)
    if ch == '\\' {
      if i + 1 >= input.length() {
        return input.length()
      }
      i = i + 2
    } else if ch == '"' {
      return i + 1
    } else {
      i = i + 1
    }
  }
  input.length()
}

///|
fn json_scan_number_end(input : String, start_byte : Int) -> Int {
  let mut i = start_byte
  if i < input.length() && json_byte_at(input, i) == '-' {
    i = i + 1
  }
  while i < input.length() && json_is_digit(json_byte_at(input, i)) {
    i = i + 1
  }
  if i < input.length() && json_byte_at(input, i) == '.' {
    i = i + 1
    while i < input.length() && json_is_digit(json_byte_at(input, i)) {
      i = i + 1
    }
  }
  if i < input.length() {
    let ch = json_byte_at(input, i)
    if ch == 'e' || ch == 'E' {
      i = i + 1
      if i < input.length() {
        let sign = json_byte_at(input, i)
        if sign == '+' || sign == '-' {
          i = i + 1
        }
      }
      while i < input.length() && json_is_digit(json_byte_at(input, i)) {
        i = i + 1
      }
    }
  }
  i
}

///|
fn json_collect_tokens(input : String) -> Array[JsonToken] {
  let tokens : Array[JsonToken] = []
  let mut i = 0
  while i < input.length() {
    let ch = json_byte_at(input, i)
    if json_is_space(ch) {
      i = i + 1
    } else if ch == '{' ||
      ch == '}' ||
      ch == '[' ||
      ch == ']' ||
      ch == ',' ||
      ch == ':' {
      tokens.push({ start_byte: i, end_byte: i + 1, kind: 0 })
      i = i + 1
    } else if ch == '"' {
      let end_byte = json_scan_string_end(input, i)
      tokens.push({ start_byte: i, end_byte, kind: 1 })
      i = end_byte
    } else if ch == '-' || json_is_digit(ch) {
      let end_byte = json_scan_number_end(input, i)
      tokens.push({ start_byte: i, end_byte, kind: 2 })
      i = end_byte
    } else if json_starts_with_at(input, i, "true") {
      tokens.push({ start_byte: i, end_byte: i + 4, kind: 3 })
      i = i + 4
    } else if json_starts_with_at(input, i, "false") {
      tokens.push({ start_byte: i, end_byte: i + 5, kind: 3 })
      i = i + 5
    } else if json_starts_with_at(input, i, "null") {
      tokens.push({ start_byte: i, end_byte: i + 4, kind: 3 })
      i = i + 4
    } else {
      i = i + 1
    }
  }
  tokens
}

///|
fn json_mutation_garbage(seed : Int) -> (Int, String) {
  let fragments = ["!", "@@", "???", "\n!\t", "#]", "\r\n?", "\t@"]
  let (next, index) = fuzz_pick(seed, fragments.length())
  (next, fragments[index])
}

///|
fn json_token_replacement(
  seed : Int,
  input : String,
  token : JsonToken,
) -> (Int, String) {
  let current = input[token.start_byte:token.end_byte].to_string()
  match token.kind {
    0 => {
      let replacement = match current {
        "{" => "["
        "}" => ")"
        "[" => "{"
        "]" => "}"
        ":" => ","
        _ => ":"
      }
      (seed, replacement)
    }
    1 => {
      let (next, replacement) = json_guided_string(seed, 3)
      if replacement == current {
        (next, "\"mut\"")
      } else {
        (next, replacement)
      }
    }
    2 => {
      let (next, replacement) = json_guided_number(seed)
      if replacement == current {
        (next, "0")
      } else {
        (next, replacement)
      }
    }
    _ => {
      let keywords = ["true", "false", "null"]
      let (next, index) = fuzz_pick(seed, keywords.length())
      let replacement = if keywords[index] == current {
        keywords[(index + 1) % keywords.length()]
      } else {
        keywords[index]
      }
      (next, replacement)
    }
  }
}

///|
fn json_delete_char_mutation(seed : Int, input : String) -> (Int, Mutation) {
  let (next, start_byte) = fuzz_pick(seed, input.length())
  (
    next,
    {
      name: mutation_kind_name(DeleteChar),
      start_byte,
      old_end_byte: start_byte + 1,
      replacement: "",
    },
  )
}

///|
fn json_delete_token_mutation(seed : Int, input : String) -> (Int, Mutation) {
  let tokens = json_collect_tokens(input)
  if tokens.is_empty() {
    return json_delete_char_mutation(seed, input)
  }
  let (next, index) = fuzz_pick(seed, tokens.length())
  let token = tokens[index]
  (
    next,
    {
      name: mutation_kind_name(DeleteToken),
      start_byte: token.start_byte,
      old_end_byte: token.end_byte,
      replacement: "",
    },
  )
}

///|
fn json_replace_token_mutation(seed : Int, input : String) -> (Int, Mutation) {
  let tokens = json_collect_tokens(input)
  if tokens.is_empty() {
    return json_delete_char_mutation(seed, input)
  }
  let (next, index) = fuzz_pick(seed, tokens.length())
  let token = tokens[index]
  let (next, replacement) = json_token_replacement(next, input, token)
  (
    next,
    {
      name: mutation_kind_name(ReplaceToken),
      start_byte: token.start_byte,
      old_end_byte: token.end_byte,
      replacement,
    },
  )
}

///|
fn json_scramble_bracket_mutation(
  seed : Int,
  input : String,
) -> (Int, Mutation) {
  let positions : Array[Int] = []
  for i in 0..<input.length() {
    let ch = json_byte_at(input, i)
    if ch == '{' || ch == '}' || ch == '[' || ch == ']' {
      positions.push(i)
    }
  }
  if positions.is_empty() {
    return json_replace_token_mutation(seed, input)
  }
  let (next, index) = fuzz_pick(seed, positions.length())
  let start_byte = positions[index]
  let replacement = match json_byte_at(input, start_byte) {
    '{' => "]"
    '}' => "["
    '[' => "}"
    _ => "{"
  }
  (
    next,
    {
      name: mutation_kind_name(ScrambleBracket),
      start_byte,
      old_end_byte: start_byte + 1,
      replacement,
    },
  )
}

///|
fn json_insert_garbage_mutation(seed : Int, input : String) -> (Int, Mutation) {
  let (next, start_byte) = fuzz_pick(seed, input.length() + 1)
  let (next, replacement) = json_mutation_garbage(next)
  (
    next,
    {
      name: mutation_kind_name(InsertGarbage),
      start_byte,
      old_end_byte: start_byte,
      replacement,
    },
  )
}

///|
fn json_truncate_prefix_mutation(seed : Int, input : String) -> (Int, Mutation) {
  let (next, start_byte) = fuzz_pick(seed, input.length())
  (
    next,
    {
      name: mutation_kind_name(TruncatePrefix),
      start_byte,
      old_end_byte: input.length(),
      replacement: "",
    },
  )
}

///|
fn json_mutation_kind(
  seed : Int,
  input : String,
  kind : MutationKind,
) -> (Int, Mutation) {
  if input.is_empty() {
    return json_insert_garbage_mutation(seed, input)
  }
  match kind {
    DeleteChar => json_delete_char_mutation(seed, input)
    DeleteToken => json_delete_token_mutation(seed, input)
    ReplaceToken => json_replace_token_mutation(seed, input)
    ScrambleBracket => json_scramble_bracket_mutation(seed, input)
    InsertGarbage => json_insert_garbage_mutation(seed, input)
    TruncatePrefix => json_truncate_prefix_mutation(seed, input)
  }
}

///|
fn json_mutation(
  seed : Int,
  input : String,
  requested : MutationKind?,
) -> (Int, Mutation) {
  let (next, kind) = choose_mutation_kind(seed, requested)
  json_mutation_kind(next, input, kind)
}

///|
fn expr_guided_ws(seed : Int) -> (Int, String) {
  let gaps = ["", " ", "\t", "\n", " \n "]
  let (next, index) = fuzz_pick(seed, gaps.length())
  (next, gaps[index])
}

///|
fn expr_guided_identifier(seed : Int) -> (Int, String) {
  let starts = ["n", "foo", "bar", "_tmp", "value", "arg", "X"]
  let suffixes = ["", "0", "1", "_x", "_2", "Beta", "42"]
  let (next, start_index) = fuzz_pick(seed, starts.length())
  let (next, suffix_index) = fuzz_pick(next, suffixes.length())
  (next, starts[start_index] + suffixes[suffix_index])
}

///|
fn expr_guided_decimal_digits(seed : Int, count : Int) -> (Int, String) {
  let buf = StringBuilder::new()
  let mut cur = seed
  for _ in 0..<count {
    let (next, digit) = fuzz_pick(cur, 10)
    cur = next
    buf.write_char(('0'.to_int() + digit).to_char().unwrap())
  }
  (cur, buf.to_string())
}

///|
fn expr_guided_hex_digits(seed : Int, count : Int) -> (Int, String) {
  let digits = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let buf = StringBuilder::new()
  let mut cur = seed
  for _ in 0..<count {
    let (next, index) = fuzz_pick(cur, digits.length())
    cur = next
    buf.write_char(digits[index])
  }
  (cur, buf.to_string())
}

///|
fn expr_guided_number(seed : Int) -> (Int, String) {
  let (next, kind) = fuzz_pick(seed, 5)
  match kind {
    0 => {
      let (next, digits) = expr_guided_decimal_digits(next, 1 + kind % 3 + 1)
      (next, digits)
    }
    1 => {
      let (next, int_part) = expr_guided_decimal_digits(next, 1 + kind % 3 + 1)
      let (next, frac_part) = expr_guided_decimal_digits(next, 2)
      (next, int_part + "." + frac_part)
    }
    2 => {
      let (next, frac_part) = expr_guided_decimal_digits(next, 2)
      (next, "." + frac_part)
    }
    3 => {
      let (next, int_part) = expr_guided_decimal_digits(next, 2)
      let (next, sign_pick) = fuzz_pick(next, 3)
      let (next, exp_part) = expr_guided_decimal_digits(next, 2)
      let sign = match sign_pick {
        0 => "+"
        1 => "-"
        _ => ""
      }
      (next, int_part + "e" + sign + exp_part)
    }
    _ => {
      let (next, hex_part) = expr_guided_hex_digits(next, 3)
      (next, "0x" + hex_part)
    }
  }
}

///|
fn expr_guided_string(seed : Int, max_units : Int) -> (Int, String) {
  let raw_units = ["a", "b", "Z", "0", "_", " "]
  let escaped_units = ["\\n", "\\t", "\\\"", "\\\\"]
  let (next, count_pick) = fuzz_pick(seed, max_units + 1)
  let buf = StringBuilder::new()
  let mut cur = next
  buf.write_char('"')
  for _ in 0..<count_pick {
    let (next, kind) = fuzz_pick(cur, 4)
    cur = next
    if kind == 0 {
      let (next, index) = fuzz_pick(cur, escaped_units.length())
      cur = next
      buf.write_string(escaped_units[index])
    } else {
      let (next, index) = fuzz_pick(cur, raw_units.length())
      cur = next
      buf.write_string(raw_units[index])
    }
  }
  buf.write_char('"')
  (cur, buf.to_string())
}

///|
fn expr_guided_atom_kind(seed : Int, kind : Int) -> (Int, String) {
  match kind {
    0 => expr_guided_identifier(seed)
    1 => expr_guided_number(seed)
    _ => expr_guided_string(seed, 4)
  }
}

///|
fn expr_guided_parenthesized(
  seed : Int,
  depth : Int,
  width : Int,
) -> (Int, String) {
  let (next, before) = expr_guided_ws(seed)
  let (next, inner) = expr_guided_expr(next, depth - 1, width)
  let (next, after) = expr_guided_ws(next)
  (next, "(" + before + inner + after + ")")
}

///|
fn expr_guided_call(seed : Int, depth : Int, width : Int) -> (Int, String) {
  let (next, callee_kind) = fuzz_pick(seed, 2)
  let (next, callee) = match callee_kind {
    0 => expr_guided_identifier(next)
    _ => expr_guided_parenthesized(next, depth - 1, width)
  }
  let (next, argc_pick) = fuzz_pick(next, width + 1)
  let args : Array[String] = []
  let mut cur = next
  for _ in 0..<argc_pick {
    let (next, arg) = expr_guided_expr(cur, depth - 1, width)
    cur = next
    args.push(arg)
  }
  let (cur, gap) = expr_guided_ws(cur)
  (cur, callee + "(" + gap + args.join(", ") + gap + ")")
}

///|
fn expr_guided_unary(seed : Int, depth : Int, width : Int) -> (Int, String) {
  let ops = ["-", "+", "!"]
  let (next, op_index) = fuzz_pick(seed, ops.length())
  let (next, gap) = expr_guided_ws(next)
  let (next, inner_kind) = fuzz_pick(next, 6)
  let (next, inner) = if depth <= 1 {
    expr_guided_atom_kind(next, inner_kind % 3)
  } else {
    expr_guided_expr_kind(next, inner_kind, depth - 1, width)
  }
  (next, ops[op_index] + gap + inner)
}

///|
fn expr_guided_operand(seed : Int, depth : Int, width : Int) -> (Int, String) {
  let (next, kind) = fuzz_pick(seed, if depth <= 0 { 3 } else { 6 })
  if depth <= 0 {
    expr_guided_atom_kind(next, kind)
  } else {
    match kind {
      0 => expr_guided_identifier(next)
      1 => expr_guided_number(next)
      2 => expr_guided_string(next, width + 2)
      3 => expr_guided_unary(next, depth, width)
      4 => expr_guided_call(next, depth, width)
      _ => expr_guided_parenthesized(next, depth, width)
    }
  }
}

///|
fn expr_guided_binary(seed : Int, depth : Int, width : Int) -> (Int, String) {
  let ops = ["+", "-", "*", "/", "%"]
  let (next, count_pick) = fuzz_pick(seed, width + 1)
  let count = count_pick + 2
  let (next, first) = expr_guided_operand(next, depth - 1, width)
  let buf = StringBuilder::new()
  let mut cur = next
  buf.write_string(first)
  for _ in 1..<count {
    let (next, before_op) = expr_guided_ws(cur)
    let (next, op_index) = fuzz_pick(next, ops.length())
    let (next, after_op) = expr_guided_ws(next)
    let (next, rhs) = expr_guided_operand(next, depth - 1, width)
    cur = next
    buf.write_string(before_op)
    buf.write_string(ops[op_index])
    buf.write_string(after_op)
    buf.write_string(rhs)
  }
  let (cur, wrap_pick) = fuzz_pick(cur, 3)
  if wrap_pick == 0 {
    (cur, "(" + buf.to_string() + ")")
  } else {
    (cur, buf.to_string())
  }
}

///|
fn expr_guided_expr_kind(
  seed : Int,
  kind : Int,
  depth : Int,
  width : Int,
) -> (Int, String) {
  if depth <= 0 && kind >= 3 {
    return expr_guided_atom_kind(seed, kind % 3)
  }
  match kind {
    0 => expr_guided_identifier(seed)
    1 => expr_guided_number(seed)
    2 => expr_guided_string(seed, width + 2)
    3 => expr_guided_unary(seed, depth, width)
    4 => expr_guided_binary(seed, depth, width)
    5 => expr_guided_call(seed, depth, width)
    _ => expr_guided_parenthesized(seed, depth, width)
  }
}

///|
fn expr_guided_expr(seed : Int, depth : Int, width : Int) -> (Int, String) {
  let (next, kind) = fuzz_pick(seed, 7)
  expr_guided_expr_kind(next, kind, depth, width)
}

///|
fn expr_byte_at(input : String, pos : Int) -> Char {
  input[pos].to_int().to_char().unwrap()
}

///|
fn expr_is_space(ch : Char) -> Bool {
  ch == ' ' || ch == '\n' || ch == '\t' || ch == '\r'
}

///|
fn expr_is_digit(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

///|
fn expr_is_hex_digit(ch : Char) -> Bool {
  expr_is_digit(ch) || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F')
}

///|
fn expr_is_ident_start(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_'
}

///|
fn expr_is_ident_continue(ch : Char) -> Bool {
  expr_is_ident_start(ch) || expr_is_digit(ch)
}

///|
fn expr_starts_number(input : String, start_byte : Int) -> Bool {
  let ch = expr_byte_at(input, start_byte)
  expr_is_digit(ch) ||
  (
    ch == '.' &&
    start_byte + 1 < input.length() &&
    expr_is_digit(expr_byte_at(input, start_byte + 1))
  )
}

///|
fn expr_scan_string_end(input : String, start_byte : Int) -> Int {
  let mut i = start_byte + 1
  while i < input.length() {
    let ch = expr_byte_at(input, i)
    if ch == '\\' {
      if i + 1 >= input.length() {
        return input.length()
      }
      i = i + 2
    } else if ch == '"' {
      return i + 1
    } else {
      i = i + 1
    }
  }
  input.length()
}

///|
fn expr_scan_number_end(input : String, start_byte : Int) -> Int {
  let mut i = start_byte
  let first = expr_byte_at(input, start_byte)
  if first == '0' && i + 1 < input.length() {
    let second = expr_byte_at(input, i + 1)
    if second == 'x' || second == 'X' {
      i = i + 2
      while i < input.length() && expr_is_hex_digit(expr_byte_at(input, i)) {
        i = i + 1
      }
      return i
    }
  }
  if first == '.' {
    i = i + 1
    while i < input.length() && expr_is_digit(expr_byte_at(input, i)) {
      i = i + 1
    }
  } else {
    while i < input.length() && expr_is_digit(expr_byte_at(input, i)) {
      i = i + 1
    }
    if i < input.length() && expr_byte_at(input, i) == '.' {
      i = i + 1
      while i < input.length() && expr_is_digit(expr_byte_at(input, i)) {
        i = i + 1
      }
    }
  }
  if i < input.length() {
    let ch = expr_byte_at(input, i)
    if ch == 'e' || ch == 'E' {
      i = i + 1
      if i < input.length() {
        let sign = expr_byte_at(input, i)
        if sign == '+' || sign == '-' {
          i = i + 1
        }
      }
      while i < input.length() && expr_is_digit(expr_byte_at(input, i)) {
        i = i + 1
      }
    }
  }
  i
}

///|
fn expr_collect_tokens(input : String) -> Array[ExprToken] {
  let tokens : Array[ExprToken] = []
  let mut i = 0
  while i < input.length() {
    let ch = expr_byte_at(input, i)
    if expr_is_space(ch) {
      i = i + 1
    } else if expr_is_ident_start(ch) {
      let start_byte = i
      i = i + 1
      while i < input.length() && expr_is_ident_continue(expr_byte_at(input, i)) {
        i = i + 1
      }
      tokens.push({ start_byte, end_byte: i, kind: 1 })
    } else if expr_starts_number(input, i) {
      let end_byte = expr_scan_number_end(input, i)
      tokens.push({ start_byte: i, end_byte, kind: 2 })
      i = end_byte
    } else if ch == '"' {
      let end_byte = expr_scan_string_end(input, i)
      tokens.push({ start_byte: i, end_byte, kind: 3 })
      i = end_byte
    } else if ch == '(' ||
      ch == ')' ||
      ch == ',' ||
      ch == '+' ||
      ch == '-' ||
      ch == '*' ||
      ch == '/' ||
      ch == '%' ||
      ch == '!' {
      tokens.push({ start_byte: i, end_byte: i + 1, kind: 0 })
      i = i + 1
    } else {
      i = i + 1
    }
  }
  tokens
}

///|
fn expr_mutation_garbage(seed : Int) -> (Int, String) {
  let fragments = ["@", "$$", "??", "\n#\t", "/*", ")]", "\r\n!"]
  let (next, index) = fuzz_pick(seed, fragments.length())
  (next, fragments[index])
}

///|
fn expr_token_replacement(
  seed : Int,
  input : String,
  token : ExprToken,
) -> (Int, String) {
  let current = input[token.start_byte:token.end_byte].to_string()
  match token.kind {
    0 => {
      let replacement = match current {
        "(" => "]"
        ")" => "{"
        "," => "+"
        "+" => "-"
        "-" => "%"
        "*" => "/"
        "/" => "*"
        "%" => "+"
        _ => ","
      }
      (seed, replacement)
    }
    1 => {
      let (next, replacement) = expr_guided_identifier(seed)
      if replacement == current {
        (next, "mutVar")
      } else {
        (next, replacement)
      }
    }
    2 => {
      let (next, replacement) = expr_guided_number(seed)
      if replacement == current {
        (next, "1")
      } else {
        (next, replacement)
      }
    }
    _ => {
      let (next, replacement) = expr_guided_string(seed, 3)
      if replacement == current {
        (next, "\"mut\"")
      } else {
        (next, replacement)
      }
    }
  }
}

///|
fn expr_delete_char_mutation(seed : Int, input : String) -> (Int, Mutation) {
  let (next, start_byte) = fuzz_pick(seed, input.length())
  (
    next,
    {
      name: mutation_kind_name(DeleteChar),
      start_byte,
      old_end_byte: start_byte + 1,
      replacement: "",
    },
  )
}

///|
fn expr_delete_token_mutation(seed : Int, input : String) -> (Int, Mutation) {
  let tokens = expr_collect_tokens(input)
  if tokens.is_empty() {
    return expr_delete_char_mutation(seed, input)
  }
  let (next, index) = fuzz_pick(seed, tokens.length())
  let token = tokens[index]
  (
    next,
    {
      name: mutation_kind_name(DeleteToken),
      start_byte: token.start_byte,
      old_end_byte: token.end_byte,
      replacement: "",
    },
  )
}

///|
fn expr_replace_token_mutation(seed : Int, input : String) -> (Int, Mutation) {
  let tokens = expr_collect_tokens(input)
  if tokens.is_empty() {
    return expr_delete_char_mutation(seed, input)
  }
  let (next, index) = fuzz_pick(seed, tokens.length())
  let token = tokens[index]
  let (next, replacement) = expr_token_replacement(next, input, token)
  (
    next,
    {
      name: mutation_kind_name(ReplaceToken),
      start_byte: token.start_byte,
      old_end_byte: token.end_byte,
      replacement,
    },
  )
}

///|
fn expr_scramble_bracket_mutation(
  seed : Int,
  input : String,
) -> (Int, Mutation) {
  let positions : Array[Int] = []
  for i in 0..<input.length() {
    let ch = expr_byte_at(input, i)
    if ch == '(' || ch == ')' {
      positions.push(i)
    }
  }
  if positions.is_empty() {
    return expr_replace_token_mutation(seed, input)
  }
  let (next, index) = fuzz_pick(seed, positions.length())
  let start_byte = positions[index]
  let replacement = match expr_byte_at(input, start_byte) {
    '(' => "]"
    _ => "{"
  }
  (
    next,
    {
      name: mutation_kind_name(ScrambleBracket),
      start_byte,
      old_end_byte: start_byte + 1,
      replacement,
    },
  )
}

///|
fn expr_insert_garbage_mutation(seed : Int, input : String) -> (Int, Mutation) {
  let (next, start_byte) = fuzz_pick(seed, input.length() + 1)
  let (next, replacement) = expr_mutation_garbage(next)
  (
    next,
    {
      name: mutation_kind_name(InsertGarbage),
      start_byte,
      old_end_byte: start_byte,
      replacement,
    },
  )
}

///|
fn expr_truncate_prefix_mutation(seed : Int, input : String) -> (Int, Mutation) {
  let (next, start_byte) = fuzz_pick(seed, input.length())
  (
    next,
    {
      name: mutation_kind_name(TruncatePrefix),
      start_byte,
      old_end_byte: input.length(),
      replacement: "",
    },
  )
}

///|
fn expr_mutation_kind(
  seed : Int,
  input : String,
  kind : MutationKind,
) -> (Int, Mutation) {
  if input.is_empty() {
    return expr_insert_garbage_mutation(seed, input)
  }
  match kind {
    DeleteChar => expr_delete_char_mutation(seed, input)
    DeleteToken => expr_delete_token_mutation(seed, input)
    ReplaceToken => expr_replace_token_mutation(seed, input)
    ScrambleBracket => expr_scramble_bracket_mutation(seed, input)
    InsertGarbage => expr_insert_garbage_mutation(seed, input)
    TruncatePrefix => expr_truncate_prefix_mutation(seed, input)
  }
}

///|
fn expr_mutation(
  seed : Int,
  input : String,
  requested : MutationKind?,
) -> (Int, Mutation) {
  let (next, kind) = choose_mutation_kind(seed, requested)
  expr_mutation_kind(next, input, kind)
}

///|
fn generate_legal_input(
  grammar : ScriptGrammar,
  seed : Int,
  depth : Int,
  width : Int,
) -> (Int, String) {
  match grammar {
    Json => json_guided_value(seed, depth, width)
    Expression => expr_guided_expr(seed, depth, width)
  }
}

///|
fn mutate_input_for_grammar(
  grammar : ScriptGrammar,
  seed : Int,
  input : String,
  requested : MutationKind?,
) -> (Int, Mutation) {
  match grammar {
    Json => json_mutation(seed, input, requested)
    Expression => expr_mutation(seed, input, requested)
  }
}

///|
fn mutate_input_usage() -> String {
  (
    #|usage:
    #|  moon run scripts -- mutate-input --grammar json|expression [--input TEXT] [--seed N] [--kind KIND] [--depth N] [--width N]
    #|
    #|options:
    #|  --grammar   Grammar to use: json or expression.
    #|  --input     Base input. If omitted, a legal sample is generated deterministically.
    #|  --seed      RNG seed used for generation and mutation. Default: 1.
    #|  --kind      One of delete-char, delete-token, replace-token, scramble-bracket, insert-garbage, truncate-prefix.
    #|  --depth     Generator depth when --input is omitted. Default: 3.
    #|  --width     Generator width when --input is omitted. Default: 3.
  )
}

///|
fn parse_mutate_input_options(
  args : Array[String],
) -> Result[MutateInputOptions, String] {
  let mut grammar : ScriptGrammar? = None
  let mut input : String? = None
  let mut seed = 1
  let mut kind : MutationKind? = None
  let mut depth = 3
  let mut width = 3
  let mut i = 0
  while i < args.length() {
    match args[i] {
      "--grammar" => {
        if i + 1 >= args.length() {
          return Err("missing value for --grammar\n\n" + mutate_input_usage())
        }
        match parse_script_grammar(args[i + 1]) {
          Some(parsed) => grammar = Some(parsed)
          None =>
            return Err(
              "unknown grammar '\{args[i + 1]}'\n\n" + mutate_input_usage(),
            )
        }
        i = i + 2
      }
      "--input" => {
        if i + 1 >= args.length() {
          return Err("missing value for --input\n\n" + mutate_input_usage())
        }
        input = Some(args[i + 1])
        i = i + 2
      }
      "--seed" => {
        if i + 1 >= args.length() {
          return Err("missing value for --seed\n\n" + mutate_input_usage())
        }
        match parse_nonnegative_int(args[i + 1]) {
          Some(value) => seed = value
          None =>
            return Err(
              "invalid non-negative integer for --seed: \{args[i + 1]}\n\n" +
              mutate_input_usage(),
            )
        }
        i = i + 2
      }
      "--kind" => {
        if i + 1 >= args.length() {
          return Err("missing value for --kind\n\n" + mutate_input_usage())
        }
        match parse_mutation_kind(args[i + 1]) {
          Some(parsed) => kind = Some(parsed)
          None =>
            return Err(
              "unknown mutation kind '\{args[i + 1]}'\n\n" +
              mutate_input_usage(),
            )
        }
        i = i + 2
      }
      "--depth" => {
        if i + 1 >= args.length() {
          return Err("missing value for --depth\n\n" + mutate_input_usage())
        }
        match parse_nonnegative_int(args[i + 1]) {
          Some(value) => depth = value
          None =>
            return Err(
              "invalid non-negative integer for --depth: \{args[i + 1]}\n\n" +
              mutate_input_usage(),
            )
        }
        i = i + 2
      }
      "--width" => {
        if i + 1 >= args.length() {
          return Err("missing value for --width\n\n" + mutate_input_usage())
        }
        match parse_nonnegative_int(args[i + 1]) {
          Some(value) => width = value
          None =>
            return Err(
              "invalid non-negative integer for --width: \{args[i + 1]}\n\n" +
              mutate_input_usage(),
            )
        }
        i = i + 2
      }
      other =>
        return Err("unknown option '\{other}'\n\n" + mutate_input_usage())
    }
  }
  match grammar {
    Some(grammar) => Ok({ grammar, input, seed, kind, depth, width })
    None => Err("--grammar is required\n\n" + mutate_input_usage())
  }
}

///|
fn run_mutate_input(args : Array[String]) -> Int {
  if args.contains("--help") || args.contains("-h") {
    println(mutate_input_usage())
    return 0
  }
  let options = match parse_mutate_input_options(args) {
    Ok(options) => options
    Err(msg) => {
      println(msg)
      return 2
    }
  }

  let (base_seed_after, base_input) = match options.input {
    Some(input) => (options.seed, input)
    None =>
      generate_legal_input(
        options.grammar,
        options.seed,
        options.depth,
        options.width,
      )
  }
  if options.input is None {
    match
      validate_clean_sample(
        options.grammar,
        "mutate-input generated base",
        base_input,
      ) {
      Some(msg) => {
        println(msg)
        return 1
      }
      None => ()
    }
  }

  let (next_seed, mutation) = mutate_input_for_grammar(
    options.grammar,
    base_seed_after,
    base_input,
    options.kind,
  )
  let mutated = apply_mutation(base_input, mutation)
  let base_generated = match options.input {
    Some(_) => "false"
    None => "true"
  }

  println("grammar: " + grammar_name(options.grammar))
  println("base-generated: " + base_generated)
  println("seed: " + options.seed.to_string())
  println("next-seed: " + next_seed.to_string())
  println("mutation: " + mutation.name)
  println("start-byte: " + mutation.start_byte.to_string())
  println("old-end-byte: " + mutation.old_end_byte.to_string())
  println("replacement: " + mutation.replacement.escape())
  println("base: " + base_input.escape())
  println("mutated: " + mutated.escape())
  0
}
