import { DiagnosticSeverity, type Diagnostic } from "vscode-languageserver";
import type { CstErrorNode } from "./runtime.js";
import type { DocumentEntry } from "./document-manager.js";
import { byteRangeToUtf16 } from "./position.js";
import type { BindingDiagnostic } from "../../wasm/moonparse.js";

export function errorsToDiagnostics(
  entry: DocumentEntry,
  errors: CstErrorNode[],
  maxCount: number,
): Diagnostic[] {
  const capped = errors.slice(0, maxCount);
  return capped.map((e): Diagnostic => {
    const endByte = Math.max(e.endByte, e.startByte + 1);
    const lspRange = byteRangeToUtf16(
      entry.text,
      entry.lineOffsets,
      e.startByte,
      endByte,
    );
    const endChar = lspRange.start.line === lspRange.end.line &&
      lspRange.end.character <= lspRange.start.character
      ? lspRange.start.character + 1
      : lspRange.end.character;

    return {
      severity: 1,
      range: {
        start: lspRange.start,
        end: { line: lspRange.end.line, character: endChar },
      },
      message: e.message,
      source: "moonparse",
    };
  });
}

export function bindingDiagnosticsToDiagnostics(
  entry: DocumentEntry,
  bindingDiags: BindingDiagnostic[],
  maxCount: number,
): Diagnostic[] {
  const capped = bindingDiags.filter(
    (d) =>
      d.kind === "unresolved" ||
      d.kind === "duplicate" ||
      d.kind === "ambiguous",
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
      severity: bindingDiagnosticSeverity(d.kind),
      range: {
        start: lspRange.start,
        end: { line: lspRange.end.line, character: endChar },
      },
      message: d.message,
      source: "moonparse(binding)",
      code: bindingDiagnosticCode(d.kind),
    };
  });
}

function bindingDiagnosticSeverity(kind: string): DiagnosticSeverity {
  return kind === "unresolved"
    ? DiagnosticSeverity.Warning
    : DiagnosticSeverity.Error;
}

function bindingDiagnosticCode(kind: string): string {
  switch (kind) {
    case "unresolved":
      return "MP_BIND_UNRESOLVED";
    case "duplicate":
      return "MP_BIND_DUPLICATE";
    case "ambiguous":
      return "MP_BIND_AMBIGUOUS";
    default:
      return "MP_BIND_UNKNOWN";
  }
}
