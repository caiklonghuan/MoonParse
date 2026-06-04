import { describe, it, expect } from "vitest";
import { stripQuotes, isCloseDelimiter, type CstErrorNode } from "./runtime.js";
import { errorsToDiagnostics } from "./diagnostics.js";
import type { DocumentEntry } from "./document-manager.js";

// ── 工具函数：构造测试用的 DocumentEntry ──

function makeEntry(text: string): DocumentEntry {
  const offsets: number[] = [0];
  for (let i = 0; i < text.length; i++) {
    if (text[i] === "\n") offsets.push(i + 1);
  }
  return {
    uri: "file:///test",
    text,
    version: 1,
    languageId: "c",
    parserHandle: -1,
    treeHandle: -1,
    lastDiagnostics: [],
    lineOffsets: new Uint32Array(offsets),
  };
}

// ── stripQuotes ──

describe("stripQuotes", () => {
  it("去掉双引号包裹", () => {
    expect(stripQuotes('"}"')).toBe("}");
  });

  it("去掉单引号包裹", () => {
    expect(stripQuotes("';'")).toBe(";");
  });

  it("无引号时原样返回", () => {
    expect(stripQuotes("identifier")).toBe("identifier");
  });

  it("空字符串不做处理", () => {
    expect(stripQuotes("")).toBe("");
  });

  it("仅一侧有引号时不处理", () => {
    expect(stripQuotes('"a')).toBe('"a');
  });
});

// ── isCloseDelimiter ──

describe("isCloseDelimiter", () => {
  it("} ) ] 为闭合分隔符", () => {
    expect(isCloseDelimiter("}")).toBe(true);
    expect(isCloseDelimiter(")")).toBe(true);
    expect(isCloseDelimiter("]")).toBe(true);
  });

  it("end / endif / fi / done 为闭合分隔符", () => {
    expect(isCloseDelimiter("end")).toBe(true);
    expect(isCloseDelimiter("endif")).toBe(true);
    expect(isCloseDelimiter("fi")).toBe(true);
    expect(isCloseDelimiter("done")).toBe(true);
  });

  it("以 end 开头的为闭合分隔符", () => {
    expect(isCloseDelimiter("endfor")).toBe(true);
    expect(isCloseDelimiter("endwhile")).toBe(true);
  });

  it("普通标识符不是闭合分隔符", () => {
    expect(isCloseDelimiter("identifier")).toBe(false);
    expect(isCloseDelimiter(";")).toBe(false);
    expect(isCloseDelimiter("{")).toBe(false);
    expect(isCloseDelimiter("(")).toBe(false);
  });
});

// ── errorsToDiagnostics ──

describe("errorsToDiagnostics", () => {
  it("空错误列表返回空诊断", () => {
    const entry = makeEntry("");
    const result = errorsToDiagnostics(entry, [], 256);
    expect(result).toEqual([]);
  });

  it("ERROR 节点 → LSP Diagnostic（纯 ASCII）", () => {
    // "int x = @" — @ 在位置 8
    const entry = makeEntry("int x = @");
    const err: CstErrorNode = {
      message: "Unexpected token '@'",
      startByte: 8,
      endByte: 9,
      isError: true,
    };
    const result = errorsToDiagnostics(entry, [err], 256);
    expect(result).toHaveLength(1);
    expect(result[0].severity).toBe(1); // Error
    expect(result[0].message).toBe("Unexpected token '@'");
    expect(result[0].source).toBe("moonparse");
    expect(result[0].range.start).toEqual({ line: 0, character: 8 });
    expect(result[0].range.end).toEqual({ line: 0, character: 9 });
  });

  it("MISSING 节点 → LSP Diagnostic", () => {
    // "int x" — 缺少分号
    const entry = makeEntry("int x\nint y");
    // 第 0 行第 5 字节处 MISSING ';'，即字符 5（换行符前）
    const err: CstErrorNode = {
      message: "Missing ';'",
      startByte: 5, // 0-based: i(0) n(1) t(2) (3) x(4) = 行末
      endByte: 5,
      isError: false,
    };
    const result = errorsToDiagnostics(entry, [err], 256);
    expect(result).toHaveLength(1);
    expect(result[0].severity).toBe(1); // 全部 Error
    expect(result[0].message).toBe("Missing ';'");
    expect(result[0].range.start).toEqual({ line: 0, character: 5 });
  });

  it("多行文本中正确映射行列", () => {
    // "a\nb\n@"
    const entry = makeEntry("a\nb\n@");
    const err: CstErrorNode = {
      message: "Unexpected token '@'",
      startByte: 4, // 'a'(0) '\n'(1) 'b'(2) '\n'(3) '@'(4)
      endByte: 5,
      isError: true,
    };
    const result = errorsToDiagnostics(entry, [err], 256);
    expect(result[0].range.start).toEqual({ line: 2, character: 0 });
    expect(result[0].range.end).toEqual({ line: 2, character: 1 });
  });

  it("包含中文时正确映射（UTF-8 字节 → UTF-16 列）", () => {
    // "let 中 = x" — '中' 是 3 UTF-8 字节，1 个 UTF-16 code unit
    const entry = makeEntry("let 中 = x");
    // '@' 在字节偏移 9 处: l(0) e(1) t(2) ' '(3) 中(4-6, 3B) ' '(7) =(8) ' '(9) x(10)
    // UTF-16 列: (0)l (1)e (2)t (3) (4)中 (5) (6)= (7) (8)x
    // 等号没有错误，换个例子：在 '中' 后的空格处缺少操作数
    const err: CstErrorNode = {
      message: "Missing expression",
      startByte: 7, // '中'(4-6) 后的空格(7)
      endByte: 7,
      isError: false,
    };
    const result = errorsToDiagnostics(entry, [err], 256);
    expect(result[0].range.start).toEqual({ line: 0, character: 5 });
  });

  it("超过 maxCount 时截断", () => {
    const entry = makeEntry("@@@");
    const errors: CstErrorNode[] = [
      { message: "e1", startByte: 0, endByte: 1, isError: true },
      { message: "e2", startByte: 1, endByte: 2, isError: true },
      { message: "e3", startByte: 2, endByte: 3, isError: true },
    ];
    const result = errorsToDiagnostics(entry, errors, 2);
    expect(result).toHaveLength(2);
    expect(result[0].message).toBe("e1");
    expect(result[1].message).toBe("e2");
  });

  it("endByte ≤ startByte 时至少占 1 列", () => {
    const entry = makeEntry("x");
    const err: CstErrorNode = {
      message: "Missing ';'",
      startByte: 1,
      endByte: 1, // 零宽
      isError: false,
    };
    const result = errorsToDiagnostics(entry, [err], 256);
    expect(result[0].range.start).toEqual({ line: 0, character: 1 });
    expect(result[0].range.end).toEqual({ line: 0, character: 2 });
  });
});

// ── 诊断消息模式快照 ──

describe("diagnostic message patterns", () => {
  it("Unexpected token 带文本", () => {
    const entry = makeEntry("int @ x");
    const err: CstErrorNode = {
      message: "Unexpected token '@'",
      startByte: 4,
      endByte: 5,
      isError: true,
    };
    const [d] = errorsToDiagnostics(entry, [err], 256);
    expect(d.message).toMatch(/^Unexpected token '/);
    expect(d.severity).toBe(1);
  });

  it("Missing 普通 token", () => {
    const entry = makeEntry("int x");
    const err: CstErrorNode = {
      message: "Missing ';'",
      startByte: 5,
      endByte: 5,
      isError: false,
    };
    const [d] = errorsToDiagnostics(entry, [err], 256);
    expect(d.message).toMatch(/^Missing '/);
    expect(d.severity).toBe(1);
  });

  it("Unclosed construct — 缺少闭合分隔符", () => {
    const entry = makeEntry("{ body");
    const err: CstErrorNode = {
      message: "Unclosed construct — missing '}'",
      startByte: 6,
      endByte: 6,
      isError: false,
    };
    const [d] = errorsToDiagnostics(entry, [err], 256);
    expect(d.message).toMatch(/^Unclosed construct/);
    expect(d.severity).toBe(1);
  });

  it("多个错误同时输出", () => {
    const entry = makeEntry("{ @");
    const errors: CstErrorNode[] = [
      { message: "Unclosed construct — missing '}'", startByte: 2, endByte: 2, isError: false },
      { message: "Unexpected token '@'", startByte: 2, endByte: 3, isError: true },
    ];
    const result = errorsToDiagnostics(entry, errors, 256);
    expect(result).toHaveLength(2);
    expect(result[0].severity).toBe(1);
    expect(result[1].severity).toBe(1);
  });
});
