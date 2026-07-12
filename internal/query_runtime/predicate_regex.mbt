///|
fn re_is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn re_is_word(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///|
fn re_is_space(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
fn re_skip_class(pattern : Array[Char], start : Int) -> Int {
  let mut index = start
  if index < pattern.length() && pattern[index] == '^' {
    index += 1
  }
  if index < pattern.length() && pattern[index] == ']' {
    index += 1
  }
  while index < pattern.length() && pattern[index] != ']' {
    if pattern[index] == '\\' {
      index += 1
    }
    index += 1
  }
  if index < pattern.length() {
    index += 1
  }
  index
}

///|
fn re_skip_group(pattern : Array[Char], start : Int) -> Int {
  let mut index = start
  let mut depth = 1
  while index < pattern.length() && depth > 0 {
    match pattern[index] {
      '(' => {
        depth += 1
        index += 1
      }
      ')' => {
        depth -= 1
        index += 1
      }
      '[' => index = re_skip_class(pattern, index + 1)
      '\\' => index += 2
      _ => index += 1
    }
  }
  index
}

///|
fn re_skip_atom(pattern : Array[Char], index : Int) -> Int {
  if index >= pattern.length() {
    index
  } else {
    match pattern[index] {
      '[' => re_skip_class(pattern, index + 1)
      '(' => re_skip_group(pattern, index + 1)
      '\\' => index + 2
      _ => index + 1
    }
  }
}

///|
fn re_find_alternative(pattern : Array[Char], start : Int, end : Int) -> Int {
  let mut index = start
  while index < end {
    match pattern[index] {
      '|' => return index
      '[' => index = re_skip_class(pattern, index + 1)
      '(' => index = re_skip_group(pattern, index + 1)
      '\\' => index += 2
      _ => index += 1
    }
  }
  end
}

///|
fn re_escape_matches(escape : Char, actual : Char) -> Bool {
  match escape {
    'd' => re_is_digit(actual)
    'D' => !re_is_digit(actual)
    'w' => re_is_word(actual)
    'W' => !re_is_word(actual)
    's' => re_is_space(actual)
    'S' => !re_is_space(actual)
    'n' => actual == '\n'
    't' => actual == '\t'
    'r' => actual == '\r'
    _ => actual == escape
  }
}

///|
fn re_class_matches(
  pattern : Array[Char],
  start : Int,
  after : Int,
  actual : Char,
) -> Bool {
  let mut index = start
  let negated = if index < after && pattern[index] == '^' {
    index += 1
    true
  } else {
    false
  }
  let end = after - 1
  let mut matched = false
  if index < end && pattern[index] == ']' {
    matched = actual == ']'
    index += 1
  }
  while index < end {
    if pattern[index] == '\\' && index + 1 < end {
      if re_escape_matches(pattern[index + 1], actual) {
        matched = true
      }
      index += 2
    } else if index + 2 < end && pattern[index + 1] == '-' {
      if pattern[index] <= actual && actual <= pattern[index + 2] {
        matched = true
      }
      index += 3
    } else {
      if pattern[index] == actual {
        matched = true
      }
      index += 1
    }
  }
  if negated {
    !matched
  } else {
    matched
  }
}

///|
fn re_match_sequence(
  pattern : Array[Char],
  pattern_start : Int,
  pattern_end : Int,
  text : Array[Char],
  text_start : Int,
  text_end : Int,
) -> Int {
  let alternative = re_find_alternative(pattern, pattern_start, pattern_end)
  if alternative < pattern_end {
    let left = re_match_atoms(
      pattern, pattern_start, alternative, text, text_start, text_end,
    )
    if left >= 0 {
      left
    } else {
      re_match_sequence(
        pattern,
        alternative + 1,
        pattern_end,
        text,
        text_start,
        text_end,
      )
    }
  } else {
    re_match_atoms(
      pattern, pattern_start, pattern_end, text, text_start, text_end,
    )
  }
}

///|
fn re_match_one(
  pattern : Array[Char],
  atom_start : Int,
  atom_end : Int,
  text : Array[Char],
  text_index : Int,
  text_end : Int,
) -> Int {
  if atom_start >= atom_end {
    return -1
  }
  match pattern[atom_start] {
    '.' =>
      if text_index >= text_end || text[text_index] == '\n' {
        -1
      } else {
        text_index + 1
      }
    '[' =>
      if text_index < text_end &&
        re_class_matches(pattern, atom_start + 1, atom_end, text[text_index]) {
        text_index + 1
      } else {
        -1
      }
    '(' =>
      re_match_sequence(
        pattern,
        atom_start + 1,
        atom_end - 1,
        text,
        text_index,
        text_end,
      )
    '\\' =>
      if atom_start + 1 >= pattern.length() || text_index >= text_end {
        -1
      } else if re_escape_matches(pattern[atom_start + 1], text[text_index]) {
        text_index + 1
      } else {
        -1
      }
    literal =>
      if text_index < text_end && text[text_index] == literal {
        text_index + 1
      } else {
        -1
      }
  }
}

///|
fn re_match_greedy(
  pattern : Array[Char],
  atom_start : Int,
  atom_end : Int,
  next_pattern : Int,
  pattern_end : Int,
  text : Array[Char],
  text_start : Int,
  text_end : Int,
  minimum : Int,
  maximum : Int,
) -> Int {
  let positions : Array[Int] = [text_start]
  let mut current = text_start
  while current < text_end && positions.length() - 1 < maximum {
    let next = re_match_one(
      pattern, atom_start, atom_end, text, current, text_end,
    )
    if next < 0 || next == current {
      break
    }
    positions.push(next)
    current = next
  }
  let mut count = positions.length() - 1
  while count >= minimum {
    let rest = re_match_atoms(
      pattern,
      next_pattern,
      pattern_end,
      text,
      positions[count],
      text_end,
    )
    if rest >= 0 {
      return rest
    }
    count -= 1
  }
  -1
}

///|
fn re_match_atoms(
  pattern : Array[Char],
  pattern_start : Int,
  pattern_end : Int,
  text : Array[Char],
  text_start : Int,
  text_end : Int,
) -> Int {
  let mut pattern_index = pattern_start
  let mut text_index = text_start
  while pattern_index < pattern_end {
    if pattern[pattern_index] == '$' && pattern_index + 1 == pattern_end {
      return if text_index == text_end { text_index } else { -1 }
    }
    let atom_end = re_skip_atom(pattern, pattern_index)
    if atom_end < pattern_end &&
      (
        pattern[atom_end] == '*' ||
        pattern[atom_end] == '+' ||
        pattern[atom_end] == '?'
      ) {
      return re_match_greedy(
        pattern,
        pattern_index,
        atom_end,
        atom_end + 1,
        pattern_end,
        text,
        text_index,
        text_end,
        if pattern[atom_end] == '+' {
          1
        } else {
          0
        },
        if pattern[atom_end] == '?' {
          1
        } else {
          text_end - text_index
        },
      )
    }
    let next = re_match_one(
      pattern, pattern_index, atom_end, text, text_index, text_end,
    )
    if next < 0 {
      return -1
    }
    text_index = next
    pattern_index = atom_end
  }
  text_index
}

///|
fn regex_search(source : String, input : String) -> Bool {
  let pattern : Array[Char] = []
  for scalar in source {
    pattern.push(scalar)
  }
  let text : Array[Char] = []
  for scalar in input {
    text.push(scalar)
  }
  if pattern.is_empty() {
    return true
  }
  let (anchored, start) = if pattern[0] == '^' { (true, 1) } else { (false, 0) }
  if anchored {
    re_match_sequence(pattern, start, pattern.length(), text, 0, text.length()) >=
    0
  } else {
    for index in 0..<=text.length() {
      if re_match_sequence(
          pattern,
          start,
          pattern.length(),
          text,
          index,
          text.length(),
        ) >=
        0 {
        return true
      }
    }
    false
  }
}
