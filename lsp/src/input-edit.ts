// LSP contentChange → MoonParse InputEdit 转换

import type { InputEdit } from "../../wasm/moonparse.js";
import { utf16ToByteOffset } from "./position.js";

// LSP range change（简化类型）
export interface LspRangeChange {
  range: { start: { line: number; character: number }; end: { line: number; character: number } };
  text: string;
}

export function isRangeChange(
  change: unknown,
): change is LspRangeChange {
  const c = change as Record<string, unknown>;
  return !!c && typeof c === "object" && "range" in c && !!c.range;
}

// 字符串 → UTF-8 字节长度
const encoder = new TextEncoder();
function utf8Len(s: string): number {
  return encoder.encode(s).length;
}

// LSP content change → MoonParse InputEdit
// 所有字节偏移使用 UTF-8 计算，兼容中文/emoji。
export function contentChangeToInputEdit(
  oldText: string,
  lineOffsets: Uint32Array,
  change: LspRangeChange,
): InputEdit {
  const { range, text: newText } = change;
  const startByte = utf16ToByteOffset(
    oldText, lineOffsets, range.start.line, range.start.character,
  );
  const oldEndByte = utf16ToByteOffset(
    oldText, lineOffsets, range.end.line, range.end.character,
  );
  const newEndByte = startByte + utf8Len(newText);

  const oldStartPoint = utf8Point(oldText, startByte);
  const oldEndPoint = utf8Point(oldText, oldEndByte);
  const newEndPoint = utf8PointAfterEdit(oldText, startByte, oldEndByte, newText);

  return {
    start_byte: startByte,
    old_end_byte: oldEndByte,
    new_end_byte: newEndByte,
    start_row: oldStartPoint.row,
    start_col: oldStartPoint.col,
    old_end_row: oldEndPoint.row,
    old_end_col: oldEndPoint.col,
    new_end_row: newEndPoint.row,
    new_end_col: newEndPoint.col,
  };
}

// UTF-8 字节偏移 → { row, col }（col 为 UTF-8 字节列）
function utf8Point(
  text: string,
  targetByte: number,
): { row: number; col: number } {
  let bytePos = 0;
  let row = 0;
  let col = 0;
  for (let i = 0; i < text.length && bytePos < targetByte; i++) {
    const cp = text.codePointAt(i)!;
    const len = utf8Len(String.fromCodePoint(cp));
    if (bytePos + len > targetByte) break; // target falls inside multi-byte char
    if (cp === 0x0a) { // \n
      row++;
      col = 0;
    } else {
      col += len;
    }
    bytePos += len;
    if (cp > 0xffff) i++; // skip surrogate pair
  }
  return { row, col };
}

// 计算编辑后的 new end point
function utf8PointAfterEdit(
  oldText: string,
  startByte: number,
  oldEndByte: number,
  newText: string,
): { row: number; col: number } {
  const prefix = encoder.encode(oldText.slice(0, startByte)).length;
  // 找到 startByte 对应的 code point 位置
  let startRow = 0;
  let startCol = 0;
  let bytePos = 0;
  let i = 0;
  while (i < oldText.length && bytePos < startByte) {
    const cp = oldText.codePointAt(i)!;
    if (cp === 0x0a) {
      startRow++;
      startCol = 0;
    } else {
      startCol += utf8Len(String.fromCodePoint(cp));
    }
    bytePos += utf8Len(String.fromCodePoint(cp));
    if (cp > 0xffff) i++;
    i++;
  }

  // 从 (startRow, startCol) 出发，walk through newText
  let row = startRow;
  let col = startCol;
  for (let j = 0; j < newText.length;) {
    const cp = newText.codePointAt(j)!;
    if (cp === 0x0a) {
      row++;
      col = 0;
    } else {
      col += utf8Len(String.fromCodePoint(cp));
    }
    if (cp > 0xffff) j++;
    j++;
  }
  return { row, col };
}
