import type { Diagnostic } from "vscode-languageserver";
import type { CstErrorNode } from "./runtime.js";
import type { DocumentEntry } from "./document-manager.js";
import { byteRangeToUtf16 } from "./position.js";
import type { BindingDiagnostic } from "../../wasm/moonparse.js";

// 将 CST 错误/缺失节点转换为 LSP Diagnostic 数组
// 字节范围通过 byteRangeToUtf16 映射回 LSP 行列
export function errorsToDiagnostics(
  entry: DocumentEntry,
  errors: CstErrorNode[],
  maxCount: number,
): Diagnostic[] {
  const capped = errors.slice(0, maxCount);
  return capped.map((e): Diagnostic => {
    // 确保至少占 1 字节宽度，零宽诊断在编辑器中不可见
    const endByte = Math.max(e.endByte, e.startByte + 1);
    const lspRange = byteRangeToUtf16(
      entry.text,
      entry.lineOffsets,
      e.startByte,
      endByte,
    );
    // 零宽节点（start == end）确保 end character >= start + 1
    const endChar = lspRange.start.line === lspRange.end.line &&
      lspRange.end.character <= lspRange.start.character
      ? lspRange.start.character + 1
      : lspRange.end.character;

    return {
      severity: 1, // 全部设为 Error
      range: {
        start: lspRange.start,
        end: { line: lspRange.end.line, character: endChar },
      },
      message: e.message,
      source: "moonparse",
    };
  });
}

// 将绑定诊断转换为 LSP Diagnostic 数组
// 第一版仅开启 unresolved，duplicate/ambiguous 后续再开
export function bindingDiagnosticsToDiagnostics(
  entry: DocumentEntry,
  bindingDiags: BindingDiagnostic[],
  maxCount: number,
): Diagnostic[] {
  const capped = bindingDiags.filter(
    (d) => d.kind === "unresolved", // 第一版只开 unresolved
  ).slice(0, maxCount);

  return capped.map((d): Diagnostic => {
    const endByte = Math.max(d.end_byte, d.start_byte + 1);
    const lspRange = byteRangeToUtf16(
      entry.text,
      entry.lineOffsets,
      d.start_byte,
      endByte,
    );
    const endChar = lspRange.start.line === lspRange.end.line &&
      lspRange.end.character <= lspRange.start.character
      ? lspRange.start.character + 1
      : lspRange.end.character;

    return {
      severity: 2, // Warning — 绑定问题是语义提示，不是语法错误
      range: {
        start: lspRange.start,
        end: { line: lspRange.end.line, character: endChar },
      },
      message: d.message,
      source: "moonparse(binding)",
    };
  });
}
