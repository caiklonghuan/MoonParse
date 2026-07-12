///|
fn semantic_sections(
  manifest_capabilities? : Int = 0,
  manifest_json? : Bytes = b"{}",
  lexer_capabilities? : Int = 0,
  query_ranges? : Array[(Int, Int)] = [],
  query_code? : Bytes,
  scanner? : (Int, Int),
) -> Array[PackSection] {
  let sections = test_sections(false)
  let manifest = sections[0].payload.to_array()
  patch_u32(manifest, 4, manifest_capabilities.reinterpret_as_uint())
  while manifest.length() > 8 {
    ignore(manifest.pop())
  }
  for byte in manifest_json {
    manifest.push(byte)
  }
  sections[0] = {
    ..sections[0],
    payload: Bytes::makei(manifest.length(), fn(index) { manifest[index] }),
  }
  let lexer = sections[3].payload.to_array()
  patch_u32(lexer, 4, lexer_capabilities.reinterpret_as_uint())
  sections[3] = {
    ..sections[3],
    payload: Bytes::makei(lexer.length(), fn(index) { lexer[index] }),
  }
  if query_ranges.length() > 0 {
    let index : Array[Byte] = []
    write_u16(index, 1)
    write_u16(index, 1)
    write_u32(index, query_ranges.length().reinterpret_as_uint())
    for range in query_ranges {
      let (start, length) = range
      write_u32(index, start.reinterpret_as_uint())
      write_u32(index, length.reinterpret_as_uint())
    }
    sections[6] = {
      ..sections[6],
      payload: Bytes::makei(index.length(), fn(at) { index[at] }),
    }
  }
  match query_code {
    Some(code) => {
      let payload : Array[Byte] = []
      write_u16(payload, 1)
      write_u16(payload, 1)
      for byte in code {
        payload.push(byte)
      }
      sections.push({
        kind: 8,
        flags: 0,
        payload: Bytes::makei(payload.length(), fn(index) { payload[index] }),
      })
    }
    None => ()
  }
  match scanner {
    Some((programs, states)) => {
      let lexer = sections[3].payload.to_array()
      patch_u32(lexer, 8, programs.reinterpret_as_uint())
      patch_u32(lexer, 12, states.reinterpret_as_uint())
      sections[3] = {
        ..sections[3],
        payload: Bytes::makei(lexer.length(), fn(index) { lexer[index] }),
      }
      let payload : Array[Byte] = []
      write_u16(payload, 1)
      write_u16(payload, 1)
      write_u32(payload, programs.reinterpret_as_uint())
      write_u32(payload, states.reinterpret_as_uint())
      sections.push({
        kind: 9,
        flags: 0,
        payload: Bytes::makei(payload.length(), fn(index) { payload[index] }),
      })
    }
    None => ()
  }
  sections
}

///|
test "mpack v1 accepts bounded query and scanner semantics" {
  let bytes = match
    encode_pack(
      semantic_sections(
        manifest_capabilities=1,
        lexer_capabilities=1,
        query_ranges=[(0, 2), (2, 2)],
        query_code=b"abcd",
        scanner=(1, 4),
      ),
    ) {
    Ok(value) => value
    Err(error) => return fail("encode failed: \{to_repr(error)}")
  }
  match validate_pack(bytes) {
    Ok(pack) => {
      assert_eq(pack.semantics.query_program_count, 2)
      assert_eq(pack.semantics.query_bytecode_bytes, 4)
      assert_eq(pack.semantics.scanner_state_count, 4)
    }
    Err(error) => fail("validation failed: \{to_repr(error)}")
  }
}

///|
test "mpack v1 rejects query dependency range and overlap errors" {
  assert_true(
    encode_pack(semantic_sections(query_ranges=[(0, 1)]))
    is Err(MissingRelatedSection(7, 8)),
  )
  assert_true(
    encode_pack(semantic_sections(query_ranges=[(3, 2)], query_code=b"abcd"))
    is Err(InvalidProgramRange(7, 0)),
  )
  assert_true(
    encode_pack(
      semantic_sections(query_ranges=[(0, 3), (2, 2)], query_code=b"abcd"),
    )
    is Err(OverlappingProgramRanges(7, 1)),
  )
}

///|
test "mpack v1 requires scanner bytecode for scanner capabilities" {
  assert_true(
    encode_pack(semantic_sections(manifest_capabilities=1))
    is Err(MissingRelatedSection(1, 9)),
  )
  assert_true(
    encode_pack(semantic_sections(lexer_capabilities=4))
    is Err(MissingRelatedSection(1, 9)),
  )
}

///|
test "mpack v1 rejects scanner count mismatches across sections" {
  let sections = semantic_sections(scanner=(1, 4))
  let lexer = sections[3].payload.to_array()
  patch_u32(lexer, 12, 3)
  sections[3] = {
    ..sections[3],
    payload: Bytes::makei(lexer.length(), fn(index) { lexer[index] }),
  }
  assert_true(encode_pack(sections) is Err(InconsistentSectionCount(4, 9)))
}

///|
test "mpack v1 rejects section resource bombs before allocation" {
  let sections = semantic_sections()
  let strings = sections[1].payload.to_array()
  patch_u32(strings, 4, 1_000_001)
  sections[1] = {
    ..sections[1],
    payload: Bytes::makei(strings.length(), fn(index) { strings[index] }),
  }
  assert_true(encode_pack(sections) is Err(ResourceLimitExceeded(2, 1_000_000)))

  let scanner_bomb = semantic_sections(scanner=(1, 65_536))
  let scanner = scanner_bomb[7].payload.to_array()
  patch_u32(scanner, 8, 65_537)
  scanner_bomb[7] = {
    ..scanner_bomb[7],
    payload: Bytes::makei(scanner.length(), fn(index) { scanner[index] }),
  }
  assert_true(
    encode_pack(scanner_bomb) is Err(ResourceLimitExceeded(9, 65_536)),
  )
}

///|
test "mpack v1 rejects truncated envelopes and unsupported sub ABIs" {
  let truncated = semantic_sections()
  truncated[6] = { ..truncated[6], payload: b"\x01\x00\x01" }
  assert_true(encode_pack(truncated) is Err(InvalidSectionPayload(7)))

  let wrong_abi = semantic_sections(query_code=b"a")
  let query_code = wrong_abi[7].payload.to_array()
  query_code[2] = 2
  wrong_abi[7] = {
    ..wrong_abi[7],
    payload: Bytes::makei(query_code.length(), fn(index) { query_code[index] }),
  }
  assert_true(encode_pack(wrong_abi) is Err(UnsupportedSectionAbi(8, 2)))
}
