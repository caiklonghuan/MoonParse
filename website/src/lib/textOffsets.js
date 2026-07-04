const encoder = new TextEncoder()

function clampNumber(value, min, max) {
  const number = Number.isFinite(Number(value)) ? Number(value) : min
  return Math.max(min, Math.min(max, Math.trunc(number)))
}

export function utf8Length(text) {
  return encoder.encode(String(text ?? '')).length
}

export function clampUtf16Offset(text, offset) {
  const source = String(text ?? '')
  let result = clampNumber(offset, 0, source.length)
  if (
    result > 0 &&
    result < source.length &&
    /[\uD800-\uDBFF]/.test(source[result - 1]) &&
    /[\uDC00-\uDFFF]/.test(source[result])
  ) {
    result -= 1
  }
  return result
}

export function utf16OffsetToUtf8Byte(text, offset) {
  const source = String(text ?? '')
  const safeOffset = clampUtf16Offset(source, offset)
  return encoder.encode(source.slice(0, safeOffset)).length
}

export function utf8ByteToUtf16Offset(text, byteOffset) {
  const source = String(text ?? '')
  const target = clampNumber(byteOffset, 0, utf8Length(source))
  let bytes = 0
  let utf16 = 0

  for (const character of source) {
    const nextBytes = bytes + encoder.encode(character).length
    if (nextBytes > target) break
    bytes = nextBytes
    utf16 += character.length
  }
  return utf16
}

export function utf16OffsetToPoint(text, offset) {
  const source = String(text ?? '')
  const safeOffset = clampUtf16Offset(source, offset)
  const prefix = source.slice(0, safeOffset)
  const lineStart = prefix.lastIndexOf('\n') + 1
  return {
    row: (prefix.match(/\n/g) ?? []).length,
    column: Array.from(prefix.slice(lineStart)).length,
  }
}

export function byteRangeToUtf16Range(text, startByte, endByte) {
  const source = String(text ?? '')
  const start = utf8ByteToUtf16Offset(source, startByte)
  const end = utf8ByteToUtf16Offset(source, endByte)
  return { from: Math.min(start, end), to: Math.max(start, end) }
}

export function utf16RangeToByteRange(text, from, to) {
  const source = String(text ?? '')
  const start = utf16OffsetToUtf8Byte(source, from)
  const end = utf16OffsetToUtf8Byte(source, to)
  return { startByte: Math.min(start, end), endByte: Math.max(start, end) }
}
