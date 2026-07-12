///|
/// Inclusive Unicode scalar range used by the portable regular-expression IR.
pub(all) struct CharRange {
  lo : Char
  hi : Char
} derive(Debug, Eq)

///|
/// Repetition operators supported by the v1 lexer regular-expression subset.
pub(all) enum RepeatKind {
  ZeroOrMore
  OneOrMore
  ZeroOrOne
} derive(Debug, Eq)

///|
/// Backend-independent regular-expression IR. Groups are intentionally erased:
/// they affect precedence while parsing but not matching or serialized output.
pub(all) enum RegexIr {
  Empty
  Literal(Char)
  AnyScalar
  CharClass(Array[CharRange], Bool)
  Concat(Array[RegexIr])
  Alternate(Array[RegexIr])
  Repeat(RegexIr, RepeatKind)
} derive(Debug, Eq)

///|
/// A precise parse failure. `byte_offset` is a UTF-8 byte offset in the input.
pub(all) suberror RegexParseError {
  InvalidRegex(byte_offset~ : Int, reason~ : String)
} derive(Debug, Eq)

///|
fn unicode_scalar_utf8_width(ch : Char) -> Int {
  let value = ch.to_int()
  if value <= 0x7f {
    1
  } else if value <= 0x7ff {
    2
  } else if value <= 0xffff {
    3
  } else {
    4
  }
}

///|
fn canonical_ranges(ranges : Array[CharRange]) -> Array[CharRange] {
  let sorted = ranges.copy()
  sorted.sort_by(fn(a, b) {
    let by_lo = a.lo.to_int().compare(b.lo.to_int())
    if by_lo != 0 {
      by_lo
    } else {
      a.hi.to_int().compare(b.hi.to_int())
    }
  })
  let result : Array[CharRange] = []
  for range in sorted {
    if result.length() == 0 {
      result.push(range)
    } else {
      let last = result[result.length() - 1]
      if range.lo.to_int() <= last.hi.to_int() + 1 {
        if range.hi > last.hi {
          result[result.length() - 1] = { lo: last.lo, hi: range.hi }
        }
      } else {
        result.push(range)
      }
    }
  }
  result
}

///|
fn make_concat(parts : Array[RegexIr]) -> RegexIr {
  let flat : Array[RegexIr] = []
  for part in parts {
    match part {
      Empty => ()
      Concat(nested) =>
        for child in nested {
          flat.push(child)
        }
      _ => flat.push(part)
    }
  }
  match flat {
    [] => Empty
    [only] => only
    _ => Concat(flat)
  }
}

///|
fn make_alternate(parts : Array[RegexIr]) -> RegexIr {
  let flat : Array[RegexIr] = []
  for part in parts {
    match part {
      Alternate(nested) =>
        for child in nested {
          flat.push(child)
        }
      _ => flat.push(part)
    }
  }
  match flat {
    [] => Empty
    [only] => only
    _ => Alternate(flat)
  }
}
