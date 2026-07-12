///|
pub(all) enum PackValidationError {
  Truncated
  BadMagic
  UnsupportedFormat(Int, Int)
  UnsupportedRuntimeAbi(Int)
  InvalidFileLength(Int)
  TooManySections(Int)
  InvalidToc
  ChecksumMismatch
  InvalidSectionFlags(Int)
  DuplicateSection(Int)
  UnsortedSections(Int, Int)
  UnknownRequiredSection(Int)
  MissingSection(Int)
  InvalidSectionRange(Int)
  OverlappingSections(Int, Int)
  NonZeroPadding(Int)
  InvalidSectionPayload(Int)
  UnsupportedSectionAbi(Int, Int)
  ResourceLimitExceeded(Int, Int)
  MissingRelatedSection(Int, Int)
  InconsistentSectionCount(Int, Int)
  InvalidProgramRange(Int, Int)
  OverlappingProgramRanges(Int, Int)
  InvalidManifestJson
  InvalidManifestUtf8
  DuplicateManifestKey
  NonCanonicalManifestJson
  InvalidManifestNumber
} derive(Debug, Eq)

///|
pub(all) struct PackHeader {
  format_major : Int
  format_minor : Int
  runtime_abi : Int
  file_length : Int
  section_count : Int
  toc_offset : Int
  payload_crc32 : UInt
}

///|
pub(all) struct PackTocEntry {
  kind : Int
  flags : Int
  offset : Int
  length : Int
}

///|
pub(all) struct ValidatedPack {
  header : PackHeader
  sections : Array[PackTocEntry]
  semantics : PackSemantics
}

///|
pub(all) struct PackSection {
  kind : Int
  flags : Int
  payload : Bytes
}

///|
fn encode_write_u16(out : Array[Byte], value : Int) -> Unit {
  out.push((value & 0xFF).to_byte())
  out.push(((value >> 8) & 0xFF).to_byte())
}

///|
fn encode_write_u32(out : Array[Byte], value : UInt) -> Unit {
  out.push((value & 0xFF).to_byte())
  out.push(((value >> 8) & 0xFF).to_byte())
  out.push(((value >> 16) & 0xFF).to_byte())
  out.push(((value >> 24) & 0xFF).to_byte())
}

///|
fn encode_patch_u32(out : Array[Byte], offset : Int, value : UInt) -> Unit {
  out[offset] = (value & 0xFF).to_byte()
  out[offset + 1] = ((value >> 8) & 0xFF).to_byte()
  out[offset + 2] = ((value >> 16) & 0xFF).to_byte()
  out[offset + 3] = ((value >> 24) & 0xFF).to_byte()
}

///|
fn align_eight(value : Int) -> Int {
  (value + 7) / 8 * 8
}

///|
fn canonical_sections(
  input : Array[PackSection],
) -> Result[Array[PackSection], PackValidationError] {
  if input.length() > 64 {
    return Err(TooManySections(input.length()))
  }
  let result = input.copy()
  for index in 1..<result.length() {
    let value = result[index]
    let mut cursor = index
    while cursor > 0 && result[cursor - 1].kind > value.kind {
      result[cursor] = result[cursor - 1]
      cursor = cursor - 1
    }
    result[cursor] = value
  }
  let mut previous = -1
  for section in result {
    if section.kind == previous {
      return Err(DuplicateSection(section.kind))
    }
    if section.kind <= 0 || (section.flags != 0 && section.flags != 1) {
      return Err(InvalidSectionFlags(section.flags))
    }
    previous = section.kind
  }
  Ok(result)
}

///|
pub fn encode_pack(
  input : Array[PackSection],
) -> Result[Bytes, PackValidationError] {
  let sections = match canonical_sections(input) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let required = Array::make(7, false)
  for section in sections {
    if section.kind >= 1 && section.kind <= 7 {
      required[section.kind - 1] = true
    }
  }
  for index in 0..<7 {
    if !required[index] {
      return Err(MissingSection(index + 1))
    }
  }
  let offsets : Array[Int] = []
  let mut cursor = 32 + sections.length() * 12
  for section in sections {
    cursor = align_eight(cursor)
    if section.payload.length() > 67_108_864 - cursor {
      return Err(InvalidFileLength(cursor + section.payload.length()))
    }
    offsets.push(cursor)
    cursor = cursor + section.payload.length()
  }
  let out : Array[Byte] = [0x4D, 0x50, 0x41, 0x43, 0x4B, 0x0D, 0x0A, 0x1A]
  encode_write_u16(out, 1)
  encode_write_u16(out, 0)
  encode_write_u16(out, 1)
  encode_write_u16(out, 0)
  encode_write_u32(out, cursor.reinterpret_as_uint())
  encode_write_u16(out, sections.length())
  encode_write_u16(out, 0)
  encode_write_u32(out, 32)
  encode_write_u32(out, 0)
  for index, section in sections {
    encode_write_u16(out, section.kind)
    encode_write_u16(out, section.flags)
    encode_write_u32(out, offsets[index].reinterpret_as_uint())
    encode_write_u32(out, section.payload.length().reinterpret_as_uint())
  }
  for index, section in sections {
    while out.length() < offsets[index] {
      out.push(0)
    }
    for byte in section.payload {
      out.push(byte)
    }
  }
  let provisional = Bytes::makei(out.length(), fn(index) { out[index] })
  encode_patch_u32(out, 28, crc32_iso_hdlc(provisional[32:]))
  let encoded = Bytes::makei(out.length(), fn(index) { out[index] })
  match validate_pack(encoded) {
    Ok(_) => Ok(encoded)
    Err(error) => Err(error)
  }
}

///|
fn read_u16_le(bytes : Bytes, offset : Int) -> Int {
  bytes[offset].to_int() | (bytes[offset + 1].to_int() << 8)
}

///|
fn read_u32_le(bytes : Bytes, offset : Int) -> UInt {
  bytes[offset].to_uint() |
  (bytes[offset + 1].to_uint() << 8) |
  (bytes[offset + 2].to_uint() << 16) |
  (bytes[offset + 3].to_uint() << 24)
}

///|
fn bounded_u32(value : UInt, limit : Int) -> Int? {
  if value > limit.reinterpret_as_uint() {
    None
  } else {
    Some(value.reinterpret_as_int())
  }
}

///|
pub fn crc32_iso_hdlc(bytes : BytesView) -> UInt {
  let mut crc : UInt = 0xFFFFFFFF
  for byte in bytes {
    crc = crc ^ byte.to_uint()
    for _ in 0..<8 {
      crc = if (crc & 1) == 1 { (crc >> 1) ^ 0xEDB88320 } else { crc >> 1 }
    }
  }
  crc ^ 0xFFFFFFFF
}

///|
fn padding_is_zero(bytes : Bytes, start : Int, end : Int) -> Int? {
  for offset in start..<end {
    if bytes[offset].to_int() != 0 {
      return Some(offset)
    }
  }
  None
}

///|
pub fn validate_pack(
  bytes : Bytes,
) -> Result[ValidatedPack, PackValidationError] {
  if bytes.length() < 32 {
    return Err(Truncated)
  }
  let magic : Array[Int] = [0x4D, 0x50, 0x41, 0x43, 0x4B, 0x0D, 0x0A, 0x1A]
  for index in 0..<8 {
    if bytes[index].to_int() != magic[index] {
      return Err(BadMagic)
    }
  }
  let major = read_u16_le(bytes, 8)
  let minor = read_u16_le(bytes, 10)
  if major != 1 {
    return Err(UnsupportedFormat(major, minor))
  }
  let runtime_abi = read_u16_le(bytes, 12)
  if runtime_abi != 1 {
    return Err(UnsupportedRuntimeAbi(runtime_abi))
  }
  if read_u16_le(bytes, 14) != 0 || read_u16_le(bytes, 22) != 0 {
    return Err(InvalidToc)
  }
  let file_length = match bounded_u32(read_u32_le(bytes, 16), 67_108_864) {
    Some(value) => value
    None => return Err(InvalidFileLength(bytes.length()))
  }
  if file_length != bytes.length() {
    return Err(InvalidFileLength(file_length))
  }
  let section_count = read_u16_le(bytes, 20)
  if section_count > 64 {
    return Err(TooManySections(section_count))
  }
  let toc_offset = match bounded_u32(read_u32_le(bytes, 24), file_length) {
    Some(value) => value
    None => return Err(InvalidToc)
  }
  if toc_offset != 32 || section_count > (file_length - toc_offset) / 12 {
    return Err(InvalidToc)
  }
  let expected_crc = read_u32_le(bytes, 28)
  if crc32_iso_hdlc(bytes[32:file_length]) != expected_crc {
    return Err(ChecksumMismatch)
  }
  let toc_end = toc_offset + section_count * 12
  let sections : Array[PackTocEntry] = []
  let mut previous_kind = 0
  let mut previous_end = toc_end
  let required = Array::make(7, false)
  for index in 0..<section_count {
    let entry_offset = toc_offset + index * 12
    let kind = read_u16_le(bytes, entry_offset)
    let flags = read_u16_le(bytes, entry_offset + 2)
    if flags != 0 && flags != 1 {
      return Err(InvalidSectionFlags(flags))
    }
    if kind == previous_kind {
      return Err(DuplicateSection(kind))
    }
    if kind < previous_kind {
      return Err(UnsortedSections(previous_kind, kind))
    }
    if kind > 10 && flags == 1 {
      return Err(UnknownRequiredSection(kind))
    }
    let offset = match
      bounded_u32(read_u32_le(bytes, entry_offset + 4), file_length) {
      Some(value) => value
      None => return Err(InvalidSectionRange(kind))
    }
    let length = match
      bounded_u32(read_u32_le(bytes, entry_offset + 8), file_length) {
      Some(value) => value
      None => return Err(InvalidSectionRange(kind))
    }
    if offset < toc_end || offset % 8 != 0 || length > file_length - offset {
      return Err(InvalidSectionRange(kind))
    }
    if offset < previous_end {
      return Err(OverlappingSections(previous_kind, kind))
    }
    match padding_is_zero(bytes, previous_end, offset) {
      Some(at) => return Err(NonZeroPadding(at))
      None => ()
    }
    if kind >= 1 && kind <= 7 {
      required[kind - 1] = true
    }
    sections.push({ kind, flags, offset, length })
    previous_kind = kind
    previous_end = offset + length
  }
  for index in 0..<7 {
    if !required[index] {
      return Err(MissingSection(index + 1))
    }
  }
  let semantics = match validate_section_semantics(bytes, sections) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({
    header: {
      format_major: major,
      format_minor: minor,
      runtime_abi,
      file_length,
      section_count,
      toc_offset,
      payload_crc32: expected_crc,
    },
    sections,
    semantics,
  })
}
