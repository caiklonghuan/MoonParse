// ── LSP UTF-16 position ↔ UTF-8 byte offset 转换 ──
//
// LSP 协议使用 UTF-16 code unit 作为列号单位。
// MoonParse 内部使用 UTF-8 byte offset。
// 对于 BMP 内字符（包括中文），1 code point = 1 UTF-16 = 1-3 UTF-8 bytes。
// 对于补充平面字符（emoji等），1 code point = 2 UTF-16 = 4 UTF-8 bytes。

// 单个 code point 占多少 UTF-8 字节
function utf8Len(cp: number): number {
  if (cp < 0x80) return 1;
  if (cp < 0x800) return 2;
  if (cp < 0x10000) return 3;
  return 4;
}

// 单个 code point 占多少 UTF-16 code unit（1 或 2）
function utf16Len(cp: number): number {
  return cp > 0xffff ? 2 : 1;
}

// LSP (line, character) → 全文字节偏移
// line/character 均为 0-based，character 按 UTF-16 code unit 计数
export function utf16ToByteOffset(
  text: string,
  lineOffsets: Uint32Array,
  line: number,
  character: number,
): number {
  if (line < 0) return 0;
  if (line >= lineOffsets.length) return text.length;

  const lineStart = lineOffsets[line];
  let bytePos = lineStart;
  let utf16Pos = 0;

  while (bytePos < text.length && utf16Pos < character) {
    const cp = text.codePointAt(bytePos)!;
    if (cp === 10) break; // 换行，不跨行
    bytePos += utf8Len(cp);
    utf16Pos += utf16Len(cp);
  }
  return bytePos;
}

// 后续多选 range：LSP (line, character, length) → Utf16Range
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

// ── 反向转换：字节偏移 → LSP (line, character) ──

export interface LspPosition {
  line: number;
  character: number;
}

// 全文字节偏移 → LSP position
export function byteOffsetToUtf16(
  text: string,
  lineOffsets: Uint32Array,
  targetByte: number,
): LspPosition {
  // 找所在行
  let line = 0;
  for (let i = lineOffsets.length - 1; i >= 0; i--) {
    if (lineOffsets[i] <= targetByte) {
      line = i;
      break;
    }
  }

  const lineStart = lineOffsets[line];
  let bytePos = lineStart;
  let utf16Pos = 0;

  while (bytePos < targetByte && bytePos < text.length) {
    const cp = text.codePointAt(bytePos)!;
    if (cp === 10) break;
    const nextByte = bytePos + utf8Len(cp);
    if (nextByte > targetByte) break; // target 落在多字节字符中间，停在字符起始处
    bytePos = nextByte;
    utf16Pos += utf16Len(cp);
  }

  return { line, character: utf16Pos };
}

// 注意：LSP Range 的 end 也按 UTF-16 计算，反向转换同理。
// 字节范围 → LSP Range
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
