///|
fn write_u16(bytes : Array[Byte], value : Int) -> Unit {
  bytes.push((value & 0xFF).to_byte())
  bytes.push(((value >> 8) & 0xFF).to_byte())
}

///|
fn write_u32(bytes : Array[Byte], value : UInt) -> Unit {
  bytes.push((value & 0xFF).to_byte())
  bytes.push(((value >> 8) & 0xFF).to_byte())
  bytes.push(((value >> 16) & 0xFF).to_byte())
  bytes.push(((value >> 24) & 0xFF).to_byte())
}

///|
fn patch_u32(bytes : Array[Byte], offset : Int, value : UInt) -> Unit {
  bytes[offset] = (value & 0xFF).to_byte()
  bytes[offset + 1] = ((value >> 8) & 0xFF).to_byte()
  bytes[offset + 2] = ((value >> 16) & 0xFF).to_byte()
  bytes[offset + 3] = ((value >> 24) & 0xFF).to_byte()
}

///|
fn bytes_with_crc(raw : Array[Byte]) -> Bytes {
  let provisional = Bytes::makei(raw.length(), fn(index) { raw[index] })
  patch_u32(raw, 28, crc32_iso_hdlc(provisional[32:]))
  Bytes::makei(raw.length(), fn(index) { raw[index] })
}

///|
fn structural_pack() -> Bytes {
  match encode_pack(test_sections(false)) {
    Ok(bytes) => bytes
    Err(error) => abort("fixture encode failed: \{to_repr(error)}")
  }
}

///|
fn section_payload(kind : Int) -> Bytes {
  let out : Array[Byte] = []
  write_u16(out, 1)
  write_u16(out, if kind == 4 || kind == 7 { 1 } else { 0 })
  match kind {
    1 | 2 => write_u32(out, 0)
    3 => {
      write_u32(out, 0)
      write_u32(out, 0)
    }
    4 => {
      write_u32(out, 0)
      write_u32(out, 0)
      write_u32(out, 0)
    }
    5 => {
      write_u32(out, 0)
      write_u32(out, 0)
    }
    6 => ()
    7 => write_u32(out, 0)
    _ => abort("unsupported test section")
  }
  Bytes::makei(out.length(), fn(index) { out[index] })
}

///|
test "mpack v1 validates header TOC CRC and required sections" {
  match validate_pack(structural_pack()) {
    Ok(pack) => {
      assert_eq(pack.header.section_count, 7)
      assert_eq(pack.sections.length(), 7)
    }
    Err(error) => fail("validation failed: \{to_repr(error)}")
  }
}

///|
test "mpack v1 rejects bad magic and stale CRC" {
  let bad_magic = structural_pack().to_array()
  bad_magic[0] = 0
  let bad_magic = Bytes::makei(bad_magic.length(), fn(index) {
    bad_magic[index]
  })
  assert_true(validate_pack(bad_magic) is Err(BadMagic))
  let bad_crc = structural_pack().to_array()
  bad_crc[bad_crc.length() - 1] = 0xFF
  let bad_crc = Bytes::makei(bad_crc.length(), fn(index) { bad_crc[index] })
  assert_true(validate_pack(bad_crc) is Err(ChecksumMismatch))
}

///|
test "mpack v1 rejects duplicate section kinds after checksum validation" {
  let raw = structural_pack().to_array()
  raw[44] = 1
  raw[45] = 0
  let duplicate = bytes_with_crc(raw)
  assert_true(validate_pack(duplicate) is Err(DuplicateSection(1)))
}

///|
test "mpack v1 rejects overlap nonzero padding and unknown required sections" {
  let overlap = structural_pack().to_array()
  patch_u32(overlap, 48, 120)
  assert_true(
    validate_pack(bytes_with_crc(overlap)) is Err(OverlappingSections(1, 2)),
  )

  let padding = structural_pack().to_array()
  padding[116] = 1
  assert_true(
    validate_pack(bytes_with_crc(padding)) is Err(NonZeroPadding(116)),
  )

  let unknown = structural_pack().to_array()
  unknown[104] = 11
  unknown[105] = 0
  assert_true(
    validate_pack(bytes_with_crc(unknown)) is Err(UnknownRequiredSection(11)),
  )
}

///|
fn test_sections(reverse : Bool) -> Array[PackSection] {
  let sections : Array[PackSection] = []
  if reverse {
    for kind = 7; kind >= 1; kind = kind - 1 {
      sections.push({ kind, flags: 1, payload: section_payload(kind) })
    }
  } else {
    for kind in 1..<=7 {
      sections.push({ kind, flags: 1, payload: section_payload(kind) })
    }
  }
  sections
}

///|
test "mpack v1 encoder is canonical across input section order" {
  let first = match encode_pack(test_sections(false)) {
    Ok(bytes) => bytes
    Err(error) => return fail("encode failed: \{to_repr(error)}")
  }
  let second = match encode_pack(test_sections(true)) {
    Ok(bytes) => bytes
    Err(error) => return fail("encode failed: \{to_repr(error)}")
  }
  assert_true(first == second)
  match validate_pack(first) {
    Ok(pack) => assert_eq(pack.sections.length(), 7)
    Err(error) => fail("round trip failed: \{to_repr(error)}")
  }
}
