import { describe, it, expect } from "vitest";
import { isRangeChange, contentChangeToInputEdit, type LspRangeChange } from "./input-edit.js";

function lineOffsets(text: string): Uint32Array {
  const offsets: number[] = [0];
  for (let i = 0; i < text.length; i++) {
    if (text[i] === "\n") offsets.push(i + 1);
  }
  return new Uint32Array(offsets);
}

function makeChange(
  startLine: number, startChar: number,
  endLine: number, endChar: number,
  text: string,
): LspRangeChange {
  return {
    range: {
      start: { line: startLine, character: startChar },
      end: { line: endLine, character: endChar },
    },
    text,
  };
}

describe("isRangeChange", () => {
  it("range-based change 返回 true", () => {
    expect(isRangeChange(makeChange(0, 0, 0, 1, "x"))).toBe(true);
  });

  it("full document change 返回 false", () => {
    expect(isRangeChange({ text: "hello" })).toBe(false);
  });

  it("null 返回 false", () => {
    expect(isRangeChange(null)).toBe(false);
  });
});

describe("contentChangeToInputEdit", () => {
  it("单行替换", () => {
    const oldText = "int x = 1;";
    const lo = lineOffsets(oldText);
    // 替换 x 为 y：range(0,4)→(0,5)，newText "y"
    const edit = contentChangeToInputEdit(oldText, lo, makeChange(0, 4, 0, 5, "y"));
    expect(edit).not.toBeNull();
    expect(edit!.start_byte).toBe(4);  // 'x' at byte 4
    expect(edit!.old_end_byte).toBe(5); // before '='
    expect(edit!.new_end_byte).toBe(5); // 4 + 1 ("y")
  });

  it("单行插入", () => {
    const oldText = "ab";
    const lo = lineOffsets(oldText);
    // 在 ab 中间插入 c：range(0,1)→(0,1)，newText "c"
    const edit = contentChangeToInputEdit(oldText, lo, makeChange(0, 1, 0, 1, "c"));
    expect(edit).not.toBeNull();
    expect(edit!.start_byte).toBe(1);
    expect(edit!.old_end_byte).toBe(1); // 零宽
    expect(edit!.new_end_byte).toBe(2); // 1 + 1
  });

  it("单行删除", () => {
    const oldText = "abc";
    const lo = lineOffsets(oldText);
    // 删除 b：range(0,1)→(0,2)，newText ""
    const edit = contentChangeToInputEdit(oldText, lo, makeChange(0, 1, 0, 2, ""));
    expect(edit).not.toBeNull();
    expect(edit!.start_byte).toBe(1);
    expect(edit!.old_end_byte).toBe(2);
    expect(edit!.new_end_byte).toBe(1); // start + 0
  });

  it("跨行替换", () => {
    const oldText = "a\nb\nc";
    const lo = lineOffsets(oldText);
    // 替换 "a\nb" 为 "x"：range(0,0)→(1,1)
    const edit = contentChangeToInputEdit(oldText, lo, makeChange(0, 0, 1, 1, "x"));
    expect(edit).not.toBeNull();
    expect(edit!.start_byte).toBe(0);
    expect(edit!.old_end_byte).toBe(3); // a\nb = 3 bytes
    expect(edit!.new_end_byte).toBe(1); // 0 + 1
    // start point: row 0, col 0
    expect(edit!.start_row).toBe(0);
    expect(edit!.start_col).toBe(0);
  });

  it("中文 UTF-16 到字节转换", () => {
    const oldText = "let 中 = x";
    // '中' 是 3 UTF-8 字节，1 个 UTF-16 code unit
    // 字节: l(0) e(1) t(2) ' '(3) 中(4-6) ' '(7) =(8) ' '(9) x(10)
    // UTF-16 列: (0)l (1)e (2)t (3)' ' (4)中 (5)' ' (6)= (7)' ' (8)x
    const lo = lineOffsets(oldText);
    // 替换 '中' → 'abc'：range(0, 4)→(0, 5)
    const edit = contentChangeToInputEdit(oldText, lo, makeChange(0, 4, 0, 5, "abc"));
    expect(edit).not.toBeNull();
    expect(edit!.start_byte).toBe(4); // 中 starts at byte 4
    expect(edit!.old_end_byte).toBe(7); // 中 ends at byte 7, char(5) → byte 7
    expect(edit!.new_end_byte).toBe(7); // 4 + 3 ("abc")
  });

  it("emoji UTF-16 到字节转换", () => {
    const oldText = "a😀b";
    // 😀 是 4 UTF-8 字节，2 个 UTF-16 code unit
    // 字节: a(0) 😀(1-4) b(5)
    // UTF-16 列: (0)a (1-2)😀 (3)b
    const lo = lineOffsets(oldText);
    // 替换 😀 → x：range(0, 1)→(0, 3)
    const edit = contentChangeToInputEdit(oldText, lo, makeChange(0, 1, 0, 3, "x"));
    expect(edit).not.toBeNull();
    expect(edit!.start_byte).toBe(1); // 😀 starts at byte 1
    expect(edit!.old_end_byte).toBe(5); // 😀 ends at byte 5
    expect(edit!.new_end_byte).toBe(2); // 1 + 1 ("x")
  });

  it("text 包含换行符", () => {
    const oldText = "a\nc";
    const lo = lineOffsets(oldText);
    // 在 a 和 c 之间插入 "b\n"：range(1,0)→(1,0)
    const edit = contentChangeToInputEdit(oldText, lo, makeChange(1, 0, 1, 0, "b\n"));
    expect(edit).not.toBeNull();
    expect(edit!.start_byte).toBe(2); // after "a\n"
    expect(edit!.old_end_byte).toBe(2);
    expect(edit!.new_end_byte).toBe(4); // 2 + 2 ("b\n")
  });

  it("全量替换（无 range 的 change 不适用此函数）", () => {
    // isRangeChange 应在前置检查中拦住，此处不测
    expect(true).toBe(true);
  });
});
