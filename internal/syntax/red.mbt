///|
pub(all) struct SyntaxSpan {
  start_byte : Int
  end_byte : Int
  start_point : SourcePoint
  end_point : SourcePoint
} derive(Debug, Eq)

///|
/// Immutable owner for one source and one green root. Construction snapshots
/// the parse-local arena, so later interning cannot mutate an older tree.
pub struct SyntaxTree {
  source : SourceIndex
  arena : GreenArena
  root : GreenId
}

///|
pub fn SyntaxTree::new(
  source : String,
  arena : GreenArena,
  root : GreenId,
) -> SyntaxTree? {
  let index = SourceIndex::new(source)
  match arena.byte_width(root) {
    Some(width) if width == index.byte_length() =>
      Some({ source: index, arena: arena.snapshot_copy(), root })
    _ => None
  }
}

///|
pub fn SyntaxTree::root(self : SyntaxTree) -> RedNode {
  { tree: self, green: self.root, start_byte: 0, path: [], field_id: None }
}

///|
pub fn SyntaxTree::source_length(self : SyntaxTree) -> Int {
  self.source.byte_length()
}

///|
fn SyntaxTree::node_at_path(self : SyntaxTree, path : Array[Int]) -> RedNode? {
  let mut current = self.root()
  for index in path {
    current = match current.child(index) {
      Some(child) => child
      None => return None
    }
  }
  Some(current)
}

///|
/// A red view. Parent context is represented by a root-relative child path;
/// green data remains position-free and independently shareable.
pub struct RedNode {
  tree : SyntaxTree
  green : GreenId
  start_byte : Int
  path : Array[Int]
  field_id : Int?
}

///|
pub fn RedNode::green_id(self : RedNode) -> GreenId {
  self.green
}

///|
pub fn RedNode::path(self : RedNode) -> Array[Int] {
  self.path.copy()
}

///|
pub fn RedNode::kind_id(self : RedNode) -> Int {
  match self.tree.arena.get(self.green) {
    Some(Token(token)) => token.kind_id
    Some(Node(node)) => node.kind_id
    None => -1
  }
}

///|
pub fn RedNode::production_id(self : RedNode) -> Int? {
  match self.tree.arena.get(self.green) {
    Some(Node(node)) => Some(node.production_id)
    _ => None
  }
}

///|
pub fn RedNode::field_id(self : RedNode) -> Int? {
  self.field_id
}

///|
pub fn RedNode::byte_width(self : RedNode) -> Int {
  self.tree.arena.byte_width(self.green).unwrap_or(0)
}

///|
pub fn RedNode::start_byte(self : RedNode) -> Int {
  self.start_byte
}

///|
pub fn RedNode::end_byte(self : RedNode) -> Int {
  self.start_byte + self.byte_width()
}

///|
pub fn RedNode::flags(self : RedNode) -> GreenFlags? {
  match self.tree.arena.get(self.green) {
    Some(Token(token)) => Some(token.flags)
    Some(Node(node)) => Some(node.flags)
    None => None
  }
}

///|
pub fn RedNode::child_count(self : RedNode) -> Int {
  match self.tree.arena.get(self.green) {
    Some(Node(node)) => node.children.length()
    _ => 0
  }
}

///|
pub fn RedNode::child(self : RedNode, index : Int) -> RedNode? {
  let children = match self.tree.arena.get(self.green) {
    Some(Node(node)) => node.children
    _ => return None
  }
  if index < 0 || index >= children.length() {
    return None
  }
  let mut start = self.start_byte
  for previous in 0..<index {
    start = start +
      self.tree.arena.byte_width(children[previous].green).unwrap_or(0)
  }
  let path = self.path.copy()
  path.push(index)
  let child = children[index]
  Some({
    tree: self.tree,
    green: child.green,
    start_byte: start,
    path,
    field_id: child.field_id,
  })
}

///|
pub fn RedNode::child_by_field_id(self : RedNode, field_id : Int) -> RedNode? {
  if field_id < 0 {
    return None
  }
  for index in 0..<self.child_count() {
    match self.child(index) {
      Some(child) if child.field_id() == Some(field_id) => return Some(child)
      _ => ()
    }
  }
  None
}

///|
pub fn RedNode::parent(self : RedNode) -> RedNode? {
  if self.path.is_empty() {
    return None
  }
  let parent_path : Array[Int] = []
  for index in 0..<(self.path.length() - 1) {
    parent_path.push(self.path[index])
  }
  self.tree.node_at_path(parent_path)
}

///|
pub fn RedNode::text(self : RedNode) -> String {
  @utf8.decode_lossy(self.tree.source.bytes[self.start_byte():self.end_byte()])
}

///|
pub fn RedNode::span(self : RedNode) -> SyntaxSpan? {
  match
    (
      self.tree.source.point_at(self.start_byte()),
      self.tree.source.point_at(self.end_byte()),
    ) {
    (Some(start_point), Some(end_point)) =>
      Some({
        start_byte: self.start_byte(),
        end_byte: self.end_byte(),
        start_point,
        end_point,
      })
    _ => None
  }
}

///|
pub struct TreeCursor {
  tree : SyntaxTree
  path : Array[Int]
}

///|
pub fn TreeCursor::new(tree : SyntaxTree) -> TreeCursor {
  { tree, path: [] }
}

///|
pub fn TreeCursor::node(self : TreeCursor) -> RedNode {
  self.tree.node_at_path(self.path).unwrap()
}

///|
pub fn TreeCursor::goto_first_child(self : TreeCursor) -> Bool {
  if self.node().child_count() == 0 {
    false
  } else {
    self.path.push(0)
    true
  }
}

///|
pub fn TreeCursor::goto_next_sibling(self : TreeCursor) -> Bool {
  if self.path.is_empty() {
    return false
  }
  let last = self.path.length() - 1
  let next = self.path[last] + 1
  let parent_path : Array[Int] = []
  for index in 0..<last {
    parent_path.push(self.path[index])
  }
  let parent = self.tree.node_at_path(parent_path).unwrap()
  if next >= parent.child_count() {
    false
  } else {
    self.path[last] = next
    true
  }
}

///|
pub fn TreeCursor::goto_parent(self : TreeCursor) -> Bool {
  if self.path.is_empty() {
    false
  } else {
    ignore(self.path.pop())
    true
  }
}
