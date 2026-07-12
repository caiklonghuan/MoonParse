///|
/// Transition labels in a Thompson NFA. Character classes remain compact and
/// are never expanded by enumerating Unicode scalar values.
pub(all) enum NfaLabel {
  Epsilon
  Scalar(Char)
  ScalarRange(Char, Char)
  AnyScalar
  ScalarClass(Array[CharRange], Bool)
} derive(Debug, Eq)

///|
pub(all) struct NfaEdge {
  label : NfaLabel
  target : Int
} derive(Debug, Eq)

///|
/// State IDs and edge order are assigned solely by normalized IR traversal.
pub(all) struct Nfa {
  start : Int
  accept : Int
  states : Array[Array[NfaEdge]]
} derive(Debug, Eq)

///|
priv struct NfaFragment {
  start : Int
  accept : Int
}

///|
priv struct NfaBuilder {
  states : Array[Array[NfaEdge]]
}

///|
fn NfaBuilder::new() -> NfaBuilder {
  { states: [] }
}

///|
fn NfaBuilder::state(self : NfaBuilder) -> Int {
  let id = self.states.length()
  self.states.push([])
  id
}

///|
fn NfaBuilder::edge(
  self : NfaBuilder,
  source : Int,
  label : NfaLabel,
  target : Int,
) -> Unit {
  self.states[source].push({ label, target })
}

///|
fn NfaBuilder::empty_fragment(self : NfaBuilder) -> NfaFragment {
  let start = self.state()
  let accept = self.state()
  self.edge(start, Epsilon, accept)
  { start, accept }
}

///|
fn NfaBuilder::build(self : NfaBuilder, ir : RegexIr) -> NfaFragment {
  match ir {
    Empty => self.empty_fragment()
    Literal(ch) => {
      let start = self.state()
      let accept = self.state()
      self.edge(start, Scalar(ch), accept)
      { start, accept }
    }
    AnyScalar => {
      let start = self.state()
      let accept = self.state()
      self.edge(start, AnyScalar, accept)
      { start, accept }
    }
    CharClass(ranges, negated) => {
      let start = self.state()
      let accept = self.state()
      self.edge(start, ScalarClass(ranges, negated), accept)
      { start, accept }
    }
    Concat(parts) =>
      if parts.length() == 0 {
        self.empty_fragment()
      } else {
        let first = self.build(parts[0])
        let mut accept = first.accept
        for index in 1..<parts.length() {
          let next = self.build(parts[index])
          self.edge(accept, Epsilon, next.start)
          accept = next.accept
        }
        { start: first.start, accept }
      }
    Alternate(branches) => {
      let start = self.state()
      let accept = self.state()
      if branches.length() == 0 {
        self.edge(start, Epsilon, accept)
      } else {
        for branch in branches {
          let child = self.build(branch)
          self.edge(start, Epsilon, child.start)
          self.edge(child.accept, Epsilon, accept)
        }
      }
      { start, accept }
    }
    Repeat(inner, kind) => {
      let start = self.state()
      let accept = self.state()
      let child = self.build(inner)
      match kind {
        ZeroOrMore => {
          self.edge(start, Epsilon, child.start)
          self.edge(start, Epsilon, accept)
          self.edge(child.accept, Epsilon, child.start)
          self.edge(child.accept, Epsilon, accept)
        }
        OneOrMore => {
          self.edge(start, Epsilon, child.start)
          self.edge(child.accept, Epsilon, child.start)
          self.edge(child.accept, Epsilon, accept)
        }
        ZeroOrOne => {
          self.edge(start, Epsilon, child.start)
          self.edge(start, Epsilon, accept)
          self.edge(child.accept, Epsilon, accept)
        }
      }
      { start, accept }
    }
  }
}

///|
/// Compile normalized regex IR using deterministic Thompson construction.
pub fn compile(ir : RegexIr) -> Nfa {
  let builder = NfaBuilder::new()
  let fragment = builder.build(ir)
  { start: fragment.start, accept: fragment.accept, states: builder.states }
}

///|
/// Parse and compile a source regex in one operation.
pub fn compile_source(source : String) -> Nfa raise RegexParseError {
  compile(parse(source))
}

///|
fn empty_state_set(size : Int) -> Array[Bool] {
  let result : Array[Bool] = []
  for _ in 0..<size {
    result.push(false)
  }
  result
}

///|
fn epsilon_closure(nfa : Nfa, seeds : Array[Bool]) -> Array[Bool] {
  let result = seeds.copy()
  let queue : Array[Int] = []
  for state, active in result {
    if active {
      queue.push(state)
    }
  }
  let mut cursor = 0
  while cursor < queue.length() {
    let state = queue[cursor]
    cursor += 1
    for edge in nfa.states[state] {
      if edge.label is Epsilon && !result[edge.target] {
        result[edge.target] = true
        queue.push(edge.target)
      }
    }
  }
  result
}

///|
fn range_contains(range : CharRange, ch : Char) -> Bool {
  range.lo <= ch && ch <= range.hi
}

///|
fn label_matches(label : NfaLabel, ch : Char) -> Bool {
  match label {
    Epsilon => false
    Scalar(expected) => expected == ch
    ScalarRange(lo, hi) => lo <= ch && ch <= hi
    AnyScalar => true
    ScalarClass(ranges, negated) => {
      let mut included = false
      for range in ranges {
        if range_contains(range, ch) {
          included = true
        }
      }
      if negated {
        !included
      } else {
        included
      }
    }
  }
}

///|
fn Nfa::start_set(self : Nfa) -> Array[Bool] {
  let seeds = empty_state_set(self.states.length())
  seeds[self.start] = true
  epsilon_closure(self, seeds)
}

///|
fn Nfa::step(self : Nfa, active : Array[Bool], ch : Char) -> Array[Bool] {
  let moved = empty_state_set(self.states.length())
  for state, is_active in active {
    if is_active {
      for edge in self.states[state] {
        if label_matches(edge.label, ch) {
          moved[edge.target] = true
        }
      }
    }
  }
  epsilon_closure(self, moved)
}

///|
fn any_state_active(states : Array[Bool]) -> Bool {
  for active in states {
    if active {
      return true
    }
  }
  false
}

///|
/// Full-match semantics used by regex compiler oracles.
pub fn Nfa::matches(self : Nfa, input : String) -> Bool {
  let mut active = self.start_set()
  for ch in input {
    active = self.step(active, ch)
  }
  active[self.accept]
}

///|
/// Return the longest accepted UTF-8 byte prefix, or `None` when no prefix is
/// accepted. Empty matches return `Some(0)`.
pub fn Nfa::longest_prefix(self : Nfa, input : String) -> Int? {
  let mut active = self.start_set()
  let mut byte_offset = 0
  let mut best : Int? = if active[self.accept] { Some(0) } else { None }
  for ch in input {
    active = self.step(active, ch)
    byte_offset += unicode_scalar_utf8_width(ch)
    if active[self.accept] {
      best = Some(byte_offset)
    }
    if !any_state_active(active) {
      break
    }
  }
  best
}

///|
fn ranges_key(ranges : Array[CharRange]) -> String {
  let parts : Array[String] = []
  for range in ranges {
    parts.push("\{range.lo.to_int()}-\{range.hi.to_int()}")
  }
  parts.join(",")
}

///|
fn label_key(label : NfaLabel) -> String {
  match label {
    Epsilon => "e"
    Scalar(ch) => "c\{ch.to_int()}"
    ScalarRange(lo, hi) => "r\{lo.to_int()}-\{hi.to_int()}"
    AnyScalar => "a"
    ScalarClass(ranges, negated) =>
      "k\{if negated { 1 } else { 0 }}:\{ranges_key(ranges)}"
  }
}

///|
/// Stable textual form used by determinism tests and future pack encoding.
pub fn Nfa::canonical_key(self : Nfa) -> String {
  let states : Array[String] = []
  for state, edges in self.states {
    let encoded : Array[String] = []
    for edge in edges {
      encoded.push("\{label_key(edge.label)}>\{edge.target}")
    }
    states.push("\{state}[\{encoded.join(",")}]")
  }
  "s\{self.start};a\{self.accept};\{states.join(";")}"
}
