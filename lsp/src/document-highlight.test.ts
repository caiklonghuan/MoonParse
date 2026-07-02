import { describe, expect, it } from "vitest";
import { DocumentHighlightKind } from "vscode-languageserver";

import { BindingIndex } from "./binding-index.js";
import { getDocumentHighlights } from "./document-highlight.js";
import type { DocumentEntry } from "./document-manager.js";
import type { BindingGraph } from "../../wasm/moonparse.js";

function makeEntry(text: string): DocumentEntry {
  return {
    uri: "file:///test.mbt",
    text,
    version: 1,
    languageId: "moonbit",
    parserHandle: -1,
    treeHandle: -1,
    lastDiagnostics: [],
    lineOffsets: lineOffsets(text),
  };
}

function lineOffsets(text: string): Uint32Array {
  const offsets = [0];
  for (let i = 0; i < text.length; i++) {
    if (text[i] === "\n") offsets.push(i + 1);
  }
  return new Uint32Array(offsets);
}

function makeIndex(entry: DocumentEntry): BindingIndex {
  const graph: BindingGraph = {
    uri: entry.uri,
    scopes: [{ id: 0, parent: -1, start_byte: 0, end_byte: entry.text.length, kind: "module" }],
    definitions: [{
      id: 1,
      name: "x",
      kind: "variable",
      ns: "value",
      scope_id: 0,
      start_byte: 4,
      end_byte: 5,
    }],
    references: [{
      id: 2,
      name: "x",
      kind: "variable",
      ns: "value",
      scope_id: 0,
      start_byte: 6,
      end_byte: 7,
    }],
    edges: [{ reference_id: 2, definition_id: 1 }],
    diagnostics: [],
  };
  const index = new BindingIndex();
  index.update(entry.uri, entry, graph);
  return index;
}

describe("document highlight from BindingIndex", () => {
  it("returns Write for the definition and Read for resolved references", () => {
    const entry = makeEntry("let x\nx");
    const highlights = getDocumentHighlights(entry, makeIndex(entry), 0, 4);

    expect(highlights).toHaveLength(2);
    expect(highlights[0].kind).toBe(DocumentHighlightKind.Write);
    expect(highlights[0].range.start).toEqual({ line: 0, character: 4 });
    expect(highlights[1].kind).toBe(DocumentHighlightKind.Read);
    expect(highlights[1].range.start).toEqual({ line: 1, character: 0 });
  });

  it("returns no highlights for unresolved references", () => {
    const entry = makeEntry("let x\nx");
    const index = makeIndex(entry);
    index.clear();
    expect(getDocumentHighlights(entry, index, 1, 0)).toEqual([]);
  });
});
