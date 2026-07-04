// LSP positions use UTF-16 code units while MoonParse uses UTF-8 byte offsets.

const encoder = new TextEncoder();

function utf8ByteLength(text: string): number {
  return encoder.encode(text).length;
}

function clampUtf16Boundary(text: string, offset: number): number {
  let value = Math.max(0, Math.min(text.length, Math.trunc(offset)));
  if (
    value > 0 && value < text.length &&
    /[\uD800-\uDBFF]/.test(text[value - 1]) &&
    /[\uDC00-\uDFFF]/.test(text[value])
  ) value -= 1;
  return value;
}

export function utf16ToByteOffset(
  text: string,
  lineOffsets: Uint32Array,
  line: number,
  character: number,
): number {
  if (line < 0) return 0;
  if (line >= lineOffsets.length) return utf8ByteLength(text);
  const lineStart = lineOffsets[line];
  const utf16Offset = clampUtf16Boundary(text, lineStart + Math.max(0, character));
  const lineEnd = line + 1 < lineOffsets.length
    ? Math.max(lineStart, lineOffsets[line + 1] - 1)
    : text.length;
  return utf8ByteLength(text.slice(0, Math.min(utf16Offset, lineEnd)));
}

export interface Utf16Range {
  startByte: number;
  endByte: number;
}

export function utf16RangeToByteRange(
  text: string,
  lineOffsets: Uint32Array,
  line: number,
  character: number,
  length: number,
): Utf16Range {
  const start = utf16ToByteOffset(text, lineOffsets, line, character);
  const end = length > 0
    ? utf16ToByteOffset(text, lineOffsets, line, character + length)
    : start;
  return { startByte: start, endByte: end };
}

export interface LspPosition {
  line: number;
  character: number;
}

export function byteOffsetToUtf16(
  text: string,
  _lineOffsets: Uint32Array,
  targetByte: number,
): LspPosition {
  const safeTarget = Math.max(0, Math.min(Math.trunc(targetByte), utf8ByteLength(text)));
  let bytes = 0;
  let line = 0;
  let character = 0;
  for (const value of text) {
    const width = utf8ByteLength(value);
    if (bytes + width > safeTarget) break;
    bytes += width;
    if (value === "\n") {
      line += 1;
      character = 0;
    } else {
      character += value.length;
    }
  }
  return { line, character };
}

export interface LspRange {
  start: LspPosition;
  end: LspPosition;
}

export function byteRangeToUtf16(
  text: string,
  lineOffsets: Uint32Array,
  startByte: number,
  endByte: number,
): LspRange {
  return {
    start: byteOffsetToUtf16(text, lineOffsets, startByte),
    end: byteOffsetToUtf16(text, lineOffsets, endByte),
  };
}
