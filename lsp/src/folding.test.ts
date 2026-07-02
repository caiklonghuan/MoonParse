import { describe, expect, it } from "vitest";
import { FoldingRangeKind } from "vscode-languageserver";

import { foldingRangesFromCaptures } from "./folding.js";
import type { DocumentEntry } from "./document-manager.js";
import type { CaptureResult } from "../../wasm/moonparse.js";

function makeEntry(text: string): DocumentEntry {
  const offsets = [0];
  for (let i = 0; i < text.length; i++) {
    if (text[i] === "\n") offsets.push(i + 1);
  }
  return {
    uri: "file:///test.mbt",
    text,
    version: 1,
    languageId: "moonbit",
    parserHandle: -1,
    treeHandle: -1,
    lastDiagnostics: [],
    lineOffsets: new Uint32Array(offsets),
  };
}

function capture(captureName: string, start: number, end: number): CaptureResult {
  return {
    match_id: 1,
    capture: captureName,
    start,
    end,
    start_row: 0,
    start_col: 0,
    end_row: 0,
    end_col: 0,
    text: "",
  };
}

describe("folding ranges from captures", () => {
  it("filters single-line ranges and adjusts row-start end boundaries", () => {
    const entry = makeEntry("{\n  x\n}\nnext");
    const ranges = foldingRangesFromCaptures(entry, [
      capture("fold.region", 0, 8),
      capture("fold", 0, 1),
    ]);

    expect(ranges).toEqual([{
      startLine: 0,
      endLine: 2,
      kind: FoldingRangeKind.Region,
    }]);
  });

  it("maps comment and imports capture kinds", () => {
    const entry = makeEntry("/* a\nb */\nimport x\nimport y\n");
    const ranges = foldingRangesFromCaptures(entry, [
      capture("fold.comment", 0, 9),
      capture("fold.imports", 10, entry.text.length),
    ]);

    expect(ranges.map((range) => range.kind)).toEqual([
      FoldingRangeKind.Comment,
      FoldingRangeKind.Imports,
    ]);
  });
});
