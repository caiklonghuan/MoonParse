///|
fn conflict_symbol_order(symbol : Symbol) -> (Int, Int) {
  match symbol {
    Terminal(id) => (0, id)
    EndOfInput => (1, -1)
    NonTerminal(id) => (2, id)
  }
}

///|
fn conflict_action_order(action : Action) -> (Int, Int) {
  match action {
    Shift(state) => (0, state)
    Reduce(production) => (1, production)
    Accept => (2, 0)
  }
}

///|
fn conflict_severity_order(severity : ConflictSeverity) -> Int {
  match severity {
    Ambiguous(_) => 0
    DynamicConflict(_) => 1
    Declared(_) => 2
    Warn(_) => 3
  }
}

///|
fn sorted_conflict_actions(actions : Array[Action]) -> Array[Action] {
  let sorted : Array[Action] = []
  for action in actions {
    sorted.push(action)
  }
  sorted.sort_by(fn(left, right) {
    let (left_kind, left_id) = conflict_action_order(left)
    let (right_kind, right_id) = conflict_action_order(right)
    let by_kind = left_kind.compare(right_kind)
    if by_kind != 0 {
      by_kind
    } else {
      left_id.compare(right_id)
    }
  })
  sorted
}

///|
fn conflict_path_step_compare(
  left : ConflictStatePathStep,
  right : ConflictStatePathStep,
) -> Int {
  let (left_kind, left_id) = conflict_symbol_order(left.symbol)
  let (right_kind, right_id) = conflict_symbol_order(right.symbol)
  let by_kind = left_kind.compare(right_kind)
  if by_kind != 0 {
    return by_kind
  }
  let by_id = left_id.compare(right_id)
  if by_id != 0 {
    return by_id
  }
  left.to_state.compare(right.to_state)
}

///|
fn build_conflict_predecessors(
  state_count : Int,
  goto_map : Map[(StateId, Symbol), StateId],
) -> Array[ConflictStatePathStep?] {
  let predecessors : Array[ConflictStatePathStep?] = Array::make(
    state_count,
    None,
  )
  if state_count <= 0 {
    return predecessors
  }
  let adjacency : Map[StateId, Array[ConflictStatePathStep]] = Map([])
  for key, target in goto_map {
    let (source, symbol) = key
    if source >= 0 &&
      source < state_count &&
      target >= 0 &&
      target < state_count {
      let step = { from_state: source, to_state: target, symbol }
      match adjacency.get(source) {
        None => adjacency.set(source, [step])
        Some(steps) => steps.push(step)
      }
    }
  }
  for _, steps in adjacency {
    steps.sort_by(conflict_path_step_compare)
  }
  let visited : Array[Bool] = Array::make(state_count, false)
  let queue : Array[StateId] = [0]
  visited[0] = true
  let mut cursor = 0
  while cursor < queue.length() {
    let source = queue[cursor]
    cursor = cursor + 1
    match adjacency.get(source) {
      None => ()
      Some(steps) =>
        for step in steps {
          if !visited[step.to_state] {
            visited[step.to_state] = true
            predecessors[step.to_state] = Some(step)
            queue.push(step.to_state)
          }
        }
    }
  }
  predecessors
}

///|
fn conflict_state_path(
  state : StateId,
  predecessors : Array[ConflictStatePathStep?],
) -> Array[ConflictStatePathStep] {
  if state == 0 {
    return []
  }
  if state < 0 || state >= predecessors.length() {
    return []
  }
  let reverse_path : Array[ConflictStatePathStep] = []
  let mut current = state
  while current != 0 {
    match predecessors[current] {
      None => return []
      Some(step) => {
        reverse_path.push(step)
        current = step.from_state
      }
    }
  }
  let path : Array[ConflictStatePathStep] = []
  let mut index = reverse_path.length() - 1
  while index >= 0 {
    path.push(reverse_path[index])
    index = index - 1
  }
  path
}

///|
fn conflict_state_items(
  state : StateId,
  item_sets : Array[Set[LRItem]],
) -> Array[LRItem] {
  if state < 0 || state >= item_sets.length() {
    return []
  }
  let items = item_sets[state].to_array()
  items.sort_by(fn(left, right) {
    let by_production = left.prod.compare(right.prod)
    if by_production != 0 {
      by_production
    } else {
      left.dot.compare(right.dot)
    }
  })
  items
}

///|
fn enrich_conflict_reports(
  reports : Array[ConflictReport],
  item_sets : Array[Set[LRItem]],
  goto_map : Map[(StateId, Symbol), StateId],
) -> Array[ConflictReport] {
  let predecessors = build_conflict_predecessors(item_sets.length(), goto_map)
  let enriched : Array[ConflictReport] = []
  for report in reports {
    enriched.push({
      ..report,
      actions: sorted_conflict_actions(report.actions),
      resolved_actions: sorted_conflict_actions(report.resolved_actions),
      items: conflict_state_items(report.state, item_sets),
      state_path: conflict_state_path(report.state, predecessors),
    })
  }
  enriched.sort_by(fn(left, right) {
    let by_state = left.state.compare(right.state)
    if by_state != 0 {
      return by_state
    }
    let by_terminal = left.terminal.compare(right.terminal)
    if by_terminal != 0 {
      return by_terminal
    }
    conflict_severity_order(left.severity).compare(
      conflict_severity_order(right.severity),
    )
  })
  enriched
}
