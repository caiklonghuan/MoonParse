import { describe, expect, it } from "vitest";
import { DiagnosticSeverity, type Diagnostic } from "vscode-languageserver";

import { getCodeActions } from "./code-actions.js";
import type { DocumentEntry } from "./document-manager.js";
import { SymbolIndex } from "./symbol-index.js";

function entry(version = 3): DocumentEntry {
  return {
    uri: "file:///lint.json",
    text: '{"value": -0}',
    version,
    languageId: "json",
    parserHandle: -1,
    treeHandle: -1,
    lastDiagnostics: [],
    lineOffsets: new Uint32Array([0]),
  };
}

function lintDiagnostic(documentVersion = 3, withFix = true): Diagnostic {
  return {
    severity: DiagnosticSeverity.Warning,
    range: { start: { line: 0, character: 10 }, end: { line: 0, character: 12 } },
    message: "Use 0 instead of -0.",
    source: "moonparse(lint)",
    code: "json/recommended/negative-zero",
    data: {
      kind: "moonparse-lint",
      ruleId: "json/recommended/negative-zero",
      documentVersion,
      ...(withFix ? {
        fix: {
          title: "Replace -0 with 0",
          edit: {
            range: { start: { line: 0, character: 10 }, end: { line: 0, character: 12 } },
            newText: "0",
          },
        },
      } : {}),
    },
  };
}

describe("lint code actions", () => {
  it("creates a real versioned Quick Fix edit", () => {
    const diagnostic = lintDiagnostic();
    const actions = getCodeActions(entry(), [diagnostic], new SymbolIndex());
    expect(actions).toHaveLength(1);
    expect(actions[0].title).toBe("Replace -0 with 0");
    expect(actions[0].edit?.changes?.["file:///lint.json"]).toEqual([{
      range: { start: { line: 0, character: 10 }, end: { line: 0, character: 12 } },
      newText: "0",
    }]);
  });

  it("rejects stale versions, absent fixes, and invalid ranges", () => {
    expect(getCodeActions(entry(), [lintDiagnostic(2)], new SymbolIndex())).toEqual([]);
    expect(getCodeActions(entry(), [lintDiagnostic(3, false)], new SymbolIndex())).toEqual([]);
    const invalid = lintDiagnostic();
    invalid.data.fix.edit.range.end.character = 99;
    expect(getCodeActions(entry(), [invalid], new SymbolIndex())).toEqual([]);
  });

  it("keeps existing Grammar DSL Quick Fix matching", () => {
    const diagnostic: Diagnostic = {
      range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
      message: "Missing ';'",
    };
    expect(getCodeActions(entry(), [diagnostic], new SymbolIndex())[0].title).toBe("Insert ';'");
  });
});
