///|
fn adapt_green_element(
  arena : @syntax.GreenArena,
  green : @syntax.GreenId,
  start_byte : Int,
) -> RuntimeNode raise QueryRuntimeError {
  match arena.get(green) {
    None => raise InvalidTree("green ID is not present in its arena")
    Some(Token(token)) =>
      {
        kind_id: token.kind_id,
        named: token.flags.named,
        anonymous_token: if token.flags.named {
          None
        } else {
          Some(token.text)
        },
        text: token.text,
        start_byte,
        end_byte: start_byte + token.byte_width,
        children: [],
        child_fields: [],
      }
    Some(Node(node)) => {
      let children : Array[RuntimeNode] = []
      let fields : Array[Int?] = []
      let mut cursor = start_byte
      for child in node.children {
        let adapted = adapt_green_element(arena, child.green, cursor)
        children.push(adapted)
        fields.push(child.field_id)
        cursor = adapted.end_byte
      }
      if cursor - start_byte != node.byte_width {
        raise InvalidTree("green child widths disagree with their parent")
      }
      let text = match arena.lossless_text(green) {
        Some(value) => value
        None => raise InvalidTree("green text reconstruction failed")
      }
      {
        kind_id: node.kind_id,
        named: node.flags.named,
        anonymous_token: None,
        text,
        start_byte,
        end_byte: cursor,
        children,
        child_fields: fields,
      }
    }
  }
}

///|
/// Convert an immutable green root into the read-only VM node adapter.
/// Positions are derived exclusively from lossless byte widths.
pub fn adapt_green_tree(
  arena : @syntax.GreenArena,
  root : @syntax.GreenId,
  start_byte? : Int = 0,
) -> RuntimeNode raise QueryRuntimeError {
  if start_byte < 0 {
    raise InvalidTree("green root start byte is negative")
  }
  adapt_green_element(arena, root, start_byte)
}

///|
fn adapt_red_node(node : @syntax.RedNode) -> RuntimeNode {
  let children : Array[RuntimeNode] = []
  let fields : Array[Int?] = []
  for index in 0..<node.child_count() {
    let child = node.child(index).unwrap()
    children.push(adapt_red_node(child))
    fields.push(child.field_id())
  }
  let flags = node.flags().unwrap_or(@syntax.GreenFlags::plain())
  let text = node.text()
  {
    kind_id: node.kind_id(),
    named: flags.named,
    anonymous_token: if flags.named || !children.is_empty() {
      None
    } else {
      Some(text)
    },
    text,
    start_byte: node.start_byte(),
    end_byte: node.end_byte(),
    children,
    child_fields: fields,
  }
}

///|
/// Convert the frozen M2-C14 red view into the VM's immutable adapter.
pub fn adapt_red_tree(root : @syntax.RedNode) -> RuntimeNode {
  adapt_red_node(root)
}
