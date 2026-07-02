import { describe, expect, it } from "vitest";
import { CompletionItemKind } from "vscode-languageserver";

import { BindingIndex } from "./binding-index.js";
import { getCompletions } from "./completion.js";
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

function makeIndex(entry: DocumentEntry): BindingIndex {
  const graph: BindingGraph = {
    uri: entry.uri,
    scopes: [{ id: 0, parent: -1, start_byte: 0, end_byte: entry.text.length, kind: "module" }],
    definitions: [{
      id: 1,
      name: "foo",
      kind: "function",
      ns: "value",
      scope_id: 0,
      start_byte: 0,
      end_byte: 3,
    }],
    references: [],
    edges: [],
    diagnostics: [],
  };
  const index = new BindingIndex();
  index.update(entry.uri, entry, graph);
  return index;
}

describe("generic completions", () => {
  it("combines visible definitions with parse table literal terminals", () => {
    const entry = makeEntry("foo ");
    const items = getCompletions(
      entry,
      {} as ParseTree,
      makeIndex(entry),
      { literalTerminals: ["+", "if"] },
      0,
      4,
    );

    expect(items?.map((item) => item.label)).toEqual(["foo", "+", "if"]);
    expect(items?.[0].kind).toBe(CompletionItemKind.Function);
    expect(items?.[1].kind).toBe(CompletionItemKind.Operator);
    expect(items?.[2].kind).toBe(CompletionItemKind.Keyword);
  });

  it("does not fall back to CST node type completions", () => {
    const entry = makeEntry(" ");
    const items = getCompletions(
      entry,
      { walk: () => { throw new Error("generic path must not walk CST"); } } as unknown as ParseTree,
      undefined,
      { literalTerminals: [] },
      0,
      1,
    );

    expect(items).toEqual([]);
  });
});
