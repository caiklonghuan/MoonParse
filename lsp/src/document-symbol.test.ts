import { describe, expect, it } from "vitest";
import { SymbolKind } from "vscode-languageserver";

import { BindingIndex } from "./binding-index.js";
import { extractDocumentSymbols } from "./document-symbol.js";
import type { DocumentEntry } from "./document-manager.js";
import type { BindingGraph, ParseTree } from "../../wasm/moonparse.js";

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

describe("document symbols from BindingGraph", () => {
  it("uses declaration ranges and nests symbols by declaration containment", () => {
    const entry = makeEntry("fn foo(x) {\n}\n");
    const graph: BindingGraph = {
      uri: entry.uri,
      scopes: [
        { id: 0, parent: -1, start_byte: 0, end_byte: entry.text.length, kind: "module" },
        { id: 1, parent: 0, start_byte: 0, end_byte: 13, kind: "function" },
      ],
      definitions: [
        {
          id: 1,
          name: "foo",
          kind: "function",
          ns: "value",
          scope_id: 0,
          start_byte: 3,
          end_byte: 6,
          declaration_start_byte: 0,
          declaration_end_byte: 13,
        },
        {
          id: 2,
          name: "x",
          kind: "parameter",
          ns: "value",
          scope_id: 1,
          start_byte: 7,
          end_byte: 8,
        },
      ],
      references: [],
      edges: [],
      diagnostics: [],
    };
    const index = new BindingIndex();
    index.update(entry.uri, entry, graph);

    const symbols = extractDocumentSymbols(entry, {} as ParseTree, index);
    expect(symbols).toHaveLength(1);
    expect(symbols[0].name).toBe("foo");
    expect(symbols[0].kind).toBe(SymbolKind.Function);
    expect(symbols[0].range.start).toEqual({ line: 0, character: 0 });
    expect(symbols[0].selectionRange.start).toEqual({ line: 0, character: 3 });
    expect(symbols[0].children?.[0].name).toBe("x");
    expect(symbols[0].children?.[0].kind).toBe(SymbolKind.Variable);
  });
});
