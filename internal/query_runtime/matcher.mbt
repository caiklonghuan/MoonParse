///|
fn instruction_width(expr : @query_ir.QueryExpr) -> Int {
  match expr {
    Named(_, _, children) => {
      let mut width = 1
      for child in children {
        width += instruction_width(child.expr)
      }
      width
    }
    Alternation(items) => {
      let mut width = 1
      for item in items {
        width += instruction_width(item)
      }
      width
    }
    _ => 1
  }
}

///|
fn child_ordinal(
  children : Array[@query_ir.QueryChild],
  index : Int,
  root_ordinal : Int,
) -> Int {
  let mut ordinal = root_ordinal + 1
  for i in 0..<index {
    ordinal += instruction_width(children[i].expr)
  }
  ordinal
}

///|
fn child_path(parent : Array[Int], index : Int) -> Array[Int] {
  let result = parent.copy()
  result.push(index)
  result
}

///|
fn field_matches(expected : Int?, actual : Int?) -> Bool {
  match expected {
    None => true
    Some(id) => actual == Some(id)
  }
}

///|
fn node_field(node : RuntimeNode, index : Int) -> Int? {
  node.child_fields.get(index).unwrap_or(None)
}

///|
fn match_expr(
  expr : @query_ir.QueryExpr,
  node : RuntimeNode,
  path : Array[Int],
  state : MatchState,
  ordinal : Int,
) -> Array[MatchState] {
  match expr {
    Named(kind_id, _, children) =>
      if !node.named || node.kind_id != kind_id {
        []
      } else {
        let started = state.with_step(ordinal, path)
        match_children(children, 0, node, 0, path, started, ordinal)
      }
    Anonymous(token) =>
      if node.anonymous_token == Some(token) ||
        (!node.named && node.text == token) {
        [state.with_step(ordinal, path)]
      } else {
        []
      }
    Wildcard => [state.with_step(ordinal, path)]
    Alternation(items) => {
      let results : Array[MatchState] = []
      let started = state.with_step(ordinal, path)
      let mut branch_ordinal = ordinal + 1
      for item in items {
        for matched in match_expr(item, node, path, started, branch_ordinal) {
          results.push(matched)
        }
        branch_ordinal += instruction_width(item)
      }
      results
    }
  }
}

///|
fn match_one_child(
  child : @query_ir.QueryChild,
  node : RuntimeNode,
  start : Int,
  parent_path : Array[Int],
  state : MatchState,
  ordinal : Int,
  adjacent : Bool,
) -> Array[(Int, MatchState)] {
  let results : Array[(Int, MatchState)] = []
  let end = if adjacent {
    (start + 1).min(node.children.length())
  } else {
    node.children.length()
  }
  for index in start..<end {
    if field_matches(child.field_id, node_field(node, index)) {
      let path = child_path(parent_path, index)
      for
        matched in match_expr(
          child.expr,
          node.children[index],
          path,
          state,
          ordinal,
        ) {
        let captured = match child.capture_index {
          Some(declaration) =>
            matched.with_capture(declaration, node.children[index], path)
          None => matched
        }
        results.push((index + 1, captured))
      }
    }
  }
  results
}

///|
fn repetition_levels(
  child : @query_ir.QueryChild,
  node : RuntimeNode,
  start : Int,
  parent_path : Array[Int],
  state : MatchState,
  ordinal : Int,
) -> Array[Array[(Int, MatchState)]] {
  let levels : Array[Array[(Int, MatchState)]] = [[(start, state)]]
  let mut count = 0
  while count < node.children.length() - start {
    let next : Array[(Int, MatchState)] = []
    for item in levels[levels.length() - 1] {
      let (position, previous) = item
      for
        item in match_one_child(
          child,
          node,
          position,
          parent_path,
          previous,
          ordinal,
          child.anchor_before || count > 0,
        ) {
        next.push(item)
      }
    }
    if next.is_empty() {
      break
    }
    levels.push(next)
    count += 1
  }
  levels
}

///|
fn quantifier_bounds(
  quantifier : @query_ir.QueryQuantifier,
  maximum : Int,
) -> (Int, Int) {
  match quantifier {
    One => (1, if maximum < 1 { maximum } else { 1 })
    ZeroOrOne => (0, if maximum < 1 { maximum } else { 1 })
    ZeroOrMore => (0, maximum)
    OneOrMore => (1, maximum)
  }
}

///|
fn match_children(
  children : Array[@query_ir.QueryChild],
  pattern_index : Int,
  node : RuntimeNode,
  child_index : Int,
  parent_path : Array[Int],
  state : MatchState,
  root_ordinal : Int,
) -> Array[MatchState] {
  if pattern_index >= children.length() {
    return [state]
  }
  let child = children[pattern_index]
  let ordinal = child_ordinal(children, pattern_index, root_ordinal)
  let levels = repetition_levels(
    child, node, child_index, parent_path, state, ordinal,
  )
  let (minimum, maximum) = quantifier_bounds(
    child.quantifier,
    levels.length() - 1,
  )
  if maximum < minimum {
    return []
  }
  let results : Array[MatchState] = []
  let mut count = maximum
  while count >= minimum {
    for item in levels[count] {
      let (next_index, next_state) = item
      if !child.anchor_after || next_index == node.children.length() {
        for
          matched in match_children(
            children,
            pattern_index + 1,
            node,
            next_index,
            parent_path,
            next_state,
            root_ordinal,
          ) {
          results.push(matched)
        }
      }
    }
    count -= 1
  }
  results
}

///|
fn capture_texts(
  state : MatchState,
  pattern : @query_ir.QueryPattern,
  name : String,
) -> Array[String] {
  let values : Array[String] = []
  for capture in state.captures {
    if pattern.capture_names.get(capture.declaration_index) == Some(name) {
      values.push(capture.node.text)
    }
  }
  values
}

///|
fn any_equal(values : Array[String], expected : String) -> Bool {
  for value in values {
    if value == expected {
      return true
    }
  }
  false
}

///|
fn all_equal(values : Array[String], expected : String) -> Bool {
  if values.is_empty() {
    return false
  }
  for value in values {
    if value != expected {
      return false
    }
  }
  true
}

///|
fn predicate_matches(
  predicate : @query_ir.QueryPredicate,
  pattern : @query_ir.QueryPattern,
  state : MatchState,
) -> Bool {
  match predicate {
    Eq(name, expected) =>
      all_equal(capture_texts(state, pattern, name), expected)
    NotEq(name, expected) => {
      let values = capture_texts(state, pattern, name)
      !values.is_empty() && !any_equal(values, expected)
    }
    Match(name, source) => {
      let values = capture_texts(state, pattern, name)
      if values.is_empty() {
        false
      } else {
        values.all(fn(value) { regex_search(source, value) })
      }
    }
    NotMatch(name, source) => {
      let values = capture_texts(state, pattern, name)
      if values.is_empty() {
        false
      } else {
        values.all(fn(value) { !regex_search(source, value) })
      }
    }
    AnyOf(name, choices) => {
      let values = capture_texts(state, pattern, name)
      if values.is_empty() {
        false
      } else {
        values.all(fn(value) { any_equal(choices, value) })
      }
    }
  }
}

///|
fn predicates_match(
  pattern : @query_ir.QueryPattern,
  state : MatchState,
) -> Bool {
  for predicate in pattern.predicates {
    if !predicate_matches(predicate, pattern, state) {
      return false
    }
  }
  true
}

///|
fn compare_path(left : Array[Int], right : Array[Int]) -> Int {
  let length = left.length().min(right.length())
  for i in 0..<length {
    let compared = left[i].compare(right[i])
    if compared != 0 {
      return compared
    }
  }
  left.length().compare(right.length())
}

///|
fn emit_u32(out : Array[Byte], value : Int) -> Unit {
  out.push((value & 0xff).to_byte())
  out.push(((value >> 8) & 0xff).to_byte())
  out.push(((value >> 16) & 0xff).to_byte())
  out.push(((value >> 24) & 0xff).to_byte())
}

///|
fn match_key(steps : Array[MatchStep]) -> Bytes {
  let ordered = steps.copy()
  ordered.sort_by(fn(left, right) {
    let by_ordinal = left.ordinal.compare(right.ordinal)
    if by_ordinal != 0 {
      by_ordinal
    } else {
      compare_path(left.path, right.path)
    }
  })
  let bytes : Array[Byte] = []
  emit_u32(bytes, ordered.length())
  for step in ordered {
    emit_u32(bytes, step.ordinal)
    emit_u32(bytes, step.path.length())
    for index in step.path {
      emit_u32(bytes, index)
    }
  }
  Bytes::from_array(bytes)
}

///|
fn compare_bytes(left : Bytes, right : Bytes) -> Int {
  let length = left.length().min(right.length())
  for i in 0..<length {
    let compared = left[i].to_int().compare(right[i].to_int())
    if compared != 0 {
      return compared
    }
  }
  left.length().compare(right.length())
}

///|
fn compare_capture(left : RuntimeCapture, right : RuntimeCapture) -> Int {
  let comparisons = [
    left.start_byte.compare(right.start_byte),
    left.end_byte.compare(right.end_byte),
    left.pattern_index.compare(right.pattern_index),
    left.capture_declaration_index.compare(right.capture_declaration_index),
    compare_bytes(left.match_key, right.match_key),
    compare_path(left.node_preorder_path, right.node_preorder_path),
  ]
  for compared in comparisons {
    if compared != 0 {
      return compared
    }
  }
  0
}

///|
fn utf8_boundaries(source : String) -> Array[Bool] {
  let byte_length = @utf8.encode(source).length()
  let boundaries = Array::make(byte_length + 1, false)
  boundaries[0] = true
  let mut offset = 0
  for scalar in source {
    let value = scalar.to_int()
    offset += if value <= 0x7f {
      1
    } else if value <= 0x7ff {
      2
    } else if value <= 0xffff {
      3
    } else {
      4
    }
    boundaries[offset] = true
  }
  boundaries
}

///|
fn validate_tree(node : RuntimeNode, source_length : Int) -> Bool {
  if node.start_byte < 0 ||
    node.end_byte < node.start_byte ||
    node.end_byte > source_length {
    return false
  }
  if node.child_fields.length() != node.children.length() {
    return false
  }
  let mut previous_end = node.start_byte
  for child in node.children {
    if child.start_byte < previous_end ||
      child.end_byte > node.end_byte ||
      !validate_tree(child, source_length) {
      return false
    }
    previous_end = child.end_byte
  }
  true
}

///|
fn in_range(capture : PendingCapture, within : RuntimeByteRange?) -> Bool {
  match within {
    None => true
    Some(range) =>
      if capture.node.start_byte == capture.node.end_byte {
        range.start_byte <= capture.node.start_byte &&
        capture.node.start_byte < range.end_byte
      } else {
        capture.node.start_byte < range.end_byte &&
        range.start_byte < capture.node.end_byte
      }
  }
}

///|
fn collect_at_node(
  query : @query_ir.CompiledQueryIr,
  node : RuntimeNode,
  path : Array[Int],
  within : RuntimeByteRange?,
  match_limit : Int,
  match_count : Array[Int],
  output : Array[RuntimeCapture],
) -> Unit raise QueryRuntimeError {
  for pattern in query.patterns() {
    for initial in match_expr(pattern.root, node, path, MatchState::empty(), 0) {
      let state = match pattern.root_capture_index {
        Some(declaration) => initial.with_capture(declaration, node, path)
        None => initial
      }
      if predicates_match(pattern, state) {
        match_count[0] += 1
        if match_count[0] > match_limit {
          raise MatchLimitExceeded(match_limit)
        }
        let key = match_key(state.steps)
        for capture in state.captures {
          if in_range(capture, within) {
            let name = pattern.capture_names[capture.declaration_index]
            output.push({
              name,
              kind_id: capture.node.kind_id,
              start_byte: capture.node.start_byte,
              end_byte: capture.node.end_byte,
              pattern_index: pattern.index,
              capture_declaration_index: capture.declaration_index,
              match_key: key,
              node_preorder_path: capture.path.copy(),
            })
          }
        }
      }
    }
  }
  for index, child in node.children {
    collect_at_node(
      query,
      child,
      child_path(path, index),
      within,
      match_limit,
      match_count,
      output,
    )
  }
}

///|
pub fn execute_query(
  query : @query_ir.CompiledQueryIr,
  root : RuntimeNode,
  source : String,
  within? : RuntimeByteRange,
  match_limit? : Int = 100000,
) -> Array[RuntimeCapture] raise QueryRuntimeError {
  let boundaries = utf8_boundaries(source)
  if !validate_tree(root, boundaries.length() - 1) {
    raise InvalidTree("node spans or field cardinality are invalid")
  }
  match within {
    Some(range) => {
      if range.start_byte < 0 ||
        range.end_byte < range.start_byte ||
        range.end_byte >= boundaries.length() ||
        !boundaries[range.start_byte] ||
        !boundaries[range.end_byte] {
        raise InvalidRange
      }
      if range.start_byte == range.end_byte {
        return []
      }
    }
    None => ()
  }
  if match_limit <= 0 {
    raise MatchLimitExceeded(match_limit)
  }
  let output : Array[RuntimeCapture] = []
  collect_at_node(query, root, [], within, match_limit, [0], output)
  output.sort_by(compare_capture)
  output
}
