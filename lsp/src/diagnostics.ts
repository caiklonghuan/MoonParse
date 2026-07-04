import { DiagnosticSeverity, type Diagnostic } from "vscode-languageserver";
import type { CstErrorNode } from "./runtime.js";
import type { DocumentEntry } from "./document-manager.js";
import { byteRangeToUtf16 } from "./position.js";
import type { BindingDiagnostic, LintDiagnostic } from "../../wasm/moonparse.js";

export interface LintDiagnosticData {
  kind: "moonparse-lint";
  ruleId: string;
  documentVersion: number;
  fix?: {
    title: string;
    edit: {
      range: Diagnostic["range"];
      newText: string;
    };
  };
}

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

export function lintDiagnosticsToDiagnostics(
  entry: DocumentEntry,
  lintDiagnostics: LintDiagnostic[],
  maxCount: number,
): Diagnostic[] {
  const sourceByteLength = new TextEncoder().encode(entry.text).length;
  return lintDiagnostics.slice(0, maxCount).flatMap((diagnostic): Diagnostic[] => {
    if (!validByteRange(diagnostic.startByte, diagnostic.endByte, sourceByteLength)) {
      return [];
    }
    const range = byteRangeToUtf16(
      entry.text,
      entry.lineOffsets,
      diagnostic.startByte,
      diagnostic.endByte,
    );
    const data: LintDiagnosticData = {
      kind: "moonparse-lint",
      ruleId: diagnostic.ruleId,
      documentVersion: entry.version,
    };
    if (
      diagnostic.fix &&
      validByteRange(
        diagnostic.fix.edit.startByte,
        diagnostic.fix.edit.endByte,
        sourceByteLength,
      )
    ) {
      data.fix = {
        title: diagnostic.fix.title,
        edit: {
          range: byteRangeToUtf16(
            entry.text,
            entry.lineOffsets,
            diagnostic.fix.edit.startByte,
            diagnostic.fix.edit.endByte,
          ),
          newText: diagnostic.fix.edit.replacement,
        },
      };
    }
    return [{
      severity: lintDiagnosticSeverity(diagnostic.severity),
      range,
      message: diagnostic.message,
      source: "moonparse(lint)",
      code: diagnostic.ruleId,
      data,
    }];
  });
}

function validByteRange(start: number, end: number, byteLength: number): boolean {
  return Number.isInteger(start) && Number.isInteger(end) &&
    start >= 0 && start <= end && end <= byteLength;
}

function lintDiagnosticSeverity(severity: LintDiagnostic["severity"]): DiagnosticSeverity {
  switch (severity) {
    case "error":
      return DiagnosticSeverity.Error;
    case "warning":
      return DiagnosticSeverity.Warning;
    case "information":
      return DiagnosticSeverity.Information;
    case "hint":
      return DiagnosticSeverity.Hint;
  }
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
