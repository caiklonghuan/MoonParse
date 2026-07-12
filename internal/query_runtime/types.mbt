///|
/// Minimal immutable tree adapter consumed by the query VM.
///
/// M2-C14 converts red/green syntax nodes to this shape without changing VM
/// matching or ordering semantics.
pub(all) struct RuntimeNode {
  kind_id : Int
  named : Bool
  anonymous_token : String?
  text : String
  start_byte : Int
  end_byte : Int
  children : Array[RuntimeNode]
  child_fields : Array[Int?]
} derive(Debug, Eq)

///|
pub(all) struct RuntimeByteRange {
  start_byte : Int
  end_byte : Int
} derive(Debug, Eq)

///|
pub(all) struct RuntimeCapture {
  name : String
  kind_id : Int
  start_byte : Int
  end_byte : Int
  pattern_index : Int
  capture_declaration_index : Int
  match_key : Bytes
  node_preorder_path : Array[Int]
} derive(Debug, Eq)

///|
pub(all) suberror QueryRuntimeError {
  InvalidTree(String)
  InvalidRange
  MatchLimitExceeded(Int)
}

///|
priv struct PendingCapture {
  declaration_index : Int
  node : RuntimeNode
  path : Array[Int]
}

///|
priv struct MatchStep {
  ordinal : Int
  path : Array[Int]
}

///|
priv struct MatchState {
  captures : Array[PendingCapture]
  steps : Array[MatchStep]
}

///|
fn MatchState::empty() -> MatchState {
  { captures: [], steps: [] }
}

///|
fn MatchState::copy(self : MatchState) -> MatchState {
  { captures: self.captures.copy(), steps: self.steps.copy() }
}

///|
fn MatchState::with_step(
  self : MatchState,
  ordinal : Int,
  path : Array[Int],
) -> MatchState {
  let result = self.copy()
  result.steps.push({ ordinal, path: path.copy() })
  result
}

///|
fn MatchState::with_capture(
  self : MatchState,
  declaration_index : Int,
  node : RuntimeNode,
  path : Array[Int],
) -> MatchState {
  let result = self.copy()
  result.captures.push({ declaration_index, node, path: path.copy() })
  result
}
