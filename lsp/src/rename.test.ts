import { describe, expect, it } from "vitest";

import { BindingIndex } from "./binding-index.js";
import { prepareRename, renameSymbol } from "./rename.js";
import type { DocumentEntry } from "./document-manager.js";
import type { BindingGraph } from "../../wasm/moonparse.js";

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

function makeIndex(entry: DocumentEntry, duplicate = false): BindingIndex {
  const graph: BindingGraph = {
    uri: entry.uri,
    scopes: [
      { id: 0, parent: -1, start_byte: 0, end_byte: entry.text.length, kind: "module" },
    ],
    definitions: [
      {
        id: 1,
        name: "x",
        kind: "variable",
        ns: "value",
        scope_id: 0,
        start_byte: 4,
        end_byte: 5,
      },
      ...(duplicate
        ? [{
          id: 3,
          name: "y",
          kind: "variable",
          ns: "value",
          scope_id: 0,
          start_byte: 10,
          end_byte: 11,
        }]
        : []),
    ],
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

const tableInfo = { literalTerminals: [], wordPattern: "[A-Za-z_][A-Za-z0-9_]*" };

describe("rename", () => {
  it("prepares and edits the single-document binding group", () => {
    const entry = makeEntry("let x\nx");
    const index = makeIndex(entry);

    expect(prepareRename(entry, index, tableInfo, 0, 4)).toEqual({
      range: {
        start: { line: 0, character: 4 },
        end: { line: 0, character: 5 },
      },
      placeholder: "x",
    });

    const edit = renameSymbol(entry, index, tableInfo, 1, 0, "renamed");
    expect(edit?.changes?.[entry.uri]).toEqual([
      {
        range: {
          start: { line: 0, character: 4 },
          end: { line: 0, character: 5 },
        },
        newText: "renamed",
      },
      {
        range: {
          start: { line: 1, character: 0 },
          end: { line: 1, character: 1 },
        },
        newText: "renamed",
      },
    ]);
  });

  it("rejects invalid words and same-scope duplicates", () => {
    const entry = makeEntry("let x\nx\nlet y");
    expect(renameSymbol(entry, makeIndex(entry), tableInfo, 0, 4, "not valid")).toBeNull();
    expect(renameSymbol(entry, makeIndex(entry, true), tableInfo, 0, 4, "y")).toBeNull();
  });
});
