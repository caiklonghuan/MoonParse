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
  })
}
