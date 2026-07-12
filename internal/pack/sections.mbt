///|
/// Counts and capability facts decoded from the v1 section envelopes.
pub(all) struct PackSemantics {
  string_count : Int
  symbol_count : Int
  parser_state_count : Int
  production_count : Int
  query_program_count : Int
  query_bytecode_bytes : Int
  scanner_program_count : Int
  scanner_state_count : Int
  scanner_capabilities : Int
}

///|
fn find_section(sections : Array[PackTocEntry], kind : Int) -> PackTocEntry? {
  for section in sections {
    if section.kind == kind {
      return Some(section)
    }
  }
  None
}

///|
fn require_payload_length(
  section : PackTocEntry,
  minimum : Int,
) -> Result[Unit, PackValidationError] {
  if section.length < minimum {
    Err(InvalidSectionPayload(section.kind))
  } else {
    Ok(())
  }
}

///|
fn validate_envelope(
  bytes : Bytes,
  section : PackTocEntry,
  minimum : Int,
  expected_abi : Int,
) -> Result[Unit, PackValidationError] {
  match require_payload_length(section, minimum) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let version = read_u16_le(bytes, section.offset)
  let abi = read_u16_le(bytes, section.offset + 2)
  if version != 1 {
    return Err(InvalidSectionPayload(section.kind))
  }
  if abi != expected_abi {
    return Err(UnsupportedSectionAbi(section.kind, abi))
  }
  Ok(())
}

///|
fn read_limited_count(
  bytes : Bytes,
  section : PackTocEntry,
  relative_offset : Int,
  limit : Int,
) -> Result[Int, PackValidationError] {
  let value = read_u32_le(bytes, section.offset + relative_offset)
  match bounded_u32(value, limit) {
    Some(count) => Ok(count)
    None => Err(ResourceLimitExceeded(section.kind, limit))
  }
}

///|
fn validate_query_ranges(
  bytes : Bytes,
  index : PackTocEntry,
  bytecode : PackTocEntry?,
  item_count : Int,
) -> Result[Int, PackValidationError] {
  if item_count > (index.length - 8) / 8 {
    return Err(InvalidSectionPayload(7))
  }
  if item_count == 0 {
    return Ok(
      match bytecode {
        Some(section) => section.length - 4
        None => 0
      },
    )
  }
  let code = match bytecode {
    Some(section) => section
    None => return Err(MissingRelatedSection(7, 8))
  }
  let code_length = code.length - 4
  let ranges : Array[(Int, Int, Int)] = []
  for item in 0..<item_count {
    let entry = index.offset + 8 + item * 8
    let start = match bounded_u32(read_u32_le(bytes, entry), code_length) {
      Some(value) => value
      None => return Err(InvalidProgramRange(7, item))
    }
    let length = match bounded_u32(read_u32_le(bytes, entry + 4), code_length) {
      Some(value) => value
      None => return Err(InvalidProgramRange(7, item))
    }
    if length > code_length - start {
      return Err(InvalidProgramRange(7, item))
    }
    for range in ranges {
      let (previous_start, previous_end, _) = range
      if start < previous_end && previous_start < start + length {
        return Err(OverlappingProgramRanges(7, item))
      }
    }
    ranges.push((start, start + length, item))
  }
  Ok(code_length)
}

///|
fn validate_section_semantics(
  bytes : Bytes,
  sections : Array[PackTocEntry],
) -> Result[PackSemantics, PackValidationError] {
  let manifest = find_section(sections, 1).unwrap()
  let strings = find_section(sections, 2).unwrap()
  let symbols = find_section(sections, 3).unwrap()
  let lexer = find_section(sections, 4).unwrap()
  let parser = find_section(sections, 5).unwrap()
  let recovery = find_section(sections, 6).unwrap()
  let query_index = find_section(sections, 7).unwrap()
  let query_bytecode = find_section(sections, 8)
  let scanner_bytecode = find_section(sections, 9)
  let debug_map = find_section(sections, 10)

  for
    envelope in [
      (manifest, 8, 0),
      (strings, 8, 0),
      (symbols, 12, 0),
      (lexer, 16, 1),
      (parser, 12, 0),
      (recovery, 4, 0),
      (query_index, 8, 1),
    ] {
    let (section, minimum, abi) = envelope
    match validate_envelope(bytes, section, minimum, abi) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  match query_bytecode {
    Some(section) =>
      match validate_envelope(bytes, section, 4, 1) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    None => ()
  }
  match scanner_bytecode {
    Some(section) =>
      match validate_envelope(bytes, section, 12, 1) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    None => ()
  }
  match debug_map {
    Some(section) =>
      match validate_envelope(bytes, section, 4, 0) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    None => ()
  }

  let string_count = match read_limited_count(bytes, strings, 4, 1_000_000) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let symbol_count = match read_limited_count(bytes, symbols, 4, 262_144) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let parser_state_count = match
    read_limited_count(bytes, parser, 4, 1_000_000) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let production_count = match read_limited_count(bytes, parser, 8, 1_000_000) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let query_program_count = match
    read_limited_count(bytes, query_index, 4, 1_024) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let query_bytecode_bytes = match
    validate_query_ranges(
      bytes, query_index, query_bytecode, query_program_count,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if query_bytecode_bytes > 16_777_216 {
    return Err(ResourceLimitExceeded(8, 16_777_216))
  }

  let manifest_capabilities = read_u32_le(bytes, manifest.offset + 4)
  let lexer_capabilities = read_u32_le(bytes, lexer.offset + 4)
  if manifest_capabilities > 7 || lexer_capabilities > 7 {
    return Err(
      InvalidSectionPayload(if manifest_capabilities > 7 { 1 } else { 4 }),
    )
  }
  let scanner_capabilities = (manifest_capabilities | lexer_capabilities).reinterpret_as_int()
  let lexer_scanner_program_count = match
    read_limited_count(bytes, lexer, 8, 65_536) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let lexer_scanner_state_count = match
    read_limited_count(bytes, lexer, 12, 65_536) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let (scanner_program_count, scanner_state_count) = match scanner_bytecode {
    Some(section) => {
      let programs = match read_limited_count(bytes, section, 4, 65_536) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let states = match read_limited_count(bytes, section, 8, 65_536) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      if programs != lexer_scanner_program_count ||
        states != lexer_scanner_state_count {
        return Err(InconsistentSectionCount(4, 9))
      }
      (programs, states)
    }
    None => {
      if scanner_capabilities != 0 {
        return Err(MissingRelatedSection(1, 9))
      }
      if lexer_scanner_program_count != 0 || lexer_scanner_state_count != 0 {
        return Err(MissingRelatedSection(4, 9))
      }
      (0, 0)
    }
  }
  Ok({
    string_count,
    symbol_count,
    parser_state_count,
    production_count,
    query_program_count,
    query_bytecode_bytes,
    scanner_program_count,
    scanner_state_count,
    scanner_capabilities,
  })
}
