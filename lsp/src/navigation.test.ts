import { describe, expect, it } from "vitest";

import { BindingIndex } from "./binding-index.js";
import type { DocumentEntry } from "./document-manager.js";
import {
  getDefinitionLocation,
  getReferenceLocations,
  getWorkspaceDefinitionLocation,
  getWorkspaceReferenceLocations,
} from "./navigation.js";
import { WorkspaceIndex } from "./workspace-index.js";
import type { BindingDefinition, BindingGraph, BindingReference, ParseTree } from "../../wasm/moonparse.js";

function makeEntry(text: string): DocumentEntry {
  return {
    uri: "file:///nav.mbt",
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
      declaration_start_byte: 0,
      declaration_end_byte: 5,
    }],
    references: [
      {
        id: 2,
        name: "x",
        kind: "variable",
        ns: "value",
        scope_id: 0,
        start_byte: 8,
        end_byte: 9,
        diagnose_unresolved: true,
      },
      {
        id: 3,
        name: "x",
        kind: "variable",
        ns: "value",
        scope_id: 0,
        start_byte: 6,
        end_byte: 7,
        diagnose_unresolved: true,
      },
      {
        id: 4,
        name: "x",
        kind: "variable",
        ns: "value",
        scope_id: 0,
        start_byte: 8,
        end_byte: 9,
        diagnose_unresolved: true,
      },
    ],
    edges: [
      { reference_id: 2, definition_id: 1 },
      { reference_id: 3, definition_id: 1 },
      { reference_id: 4, definition_id: 1 },
    ],
    diagnostics: [],
  };
  const index = new BindingIndex();
  index.update(entry.uri, entry, graph);
  return index;
}

function workspaceEntry(uri: string, text: string): DocumentEntry {
  return {
    uri,
    text,
    version: 1,
    languageId: "moonbit",
    parserHandle: -1,
    treeHandle: -1,
    lastDiagnostics: [],
    lineOffsets: lineOffsets(text),
  };
}

function def(
  id: number,
  name: string,
  kind: string,
  ns: string,
  start: number,
  end: number,
): BindingDefinition {
  return {
    id,
    name,
    kind,
    ns,
    scope_id: 0,
    start_byte: start,
    end_byte: end,
    declaration_start_byte: Math.max(0, start - 3),
    declaration_end_byte: end,
  };
}

function ref(
  id: number,
  name: string,
  kind: string,
  ns: string,
  start: number,
  end: number,
): BindingReference {
  return {
    id,
    name,
    kind,
    ns,
    scope_id: 0,
    start_byte: start,
    end_byte: end,
    diagnose_unresolved: true,
  };
}

function graph(
  uri: string,
  text: string,
  definitions: BindingDefinition[],
  references: BindingReference[],
  edges: Array<{ reference_id: number; definition_id: number }> = [],
): BindingGraph {
  return {
    uri,
    scopes: [{ id: 0, parent: -1, start_byte: 0, end_byte: text.length, kind: "module" }],
    definitions,
    references,
    edges,
    diagnostics: [],
  };
}

function addWorkspaceFile(
  workspace: WorkspaceIndex,
  entry: DocumentEntry,
  graphValue: BindingGraph,
): BindingIndex {
  const index = new BindingIndex();
  index.update(entry.uri, entry, graphValue);
  workspace.upsertParsedDocument({
    uri: entry.uri,
    text: entry.text,
    lineOffsets: entry.lineOffsets,
    languageId: entry.languageId,
    version: entry.version,
    sizeBytes: entry.text.length,
    isOpen: true,
    tree: {} as ParseTree,
    graph: graphValue,
    bindingIndex: index,
  });
  return index;
}

describe("navigation helpers", () => {
  it("resolves definitions from both definition and reference positions", () => {
    const entry = makeEntry("let x\nx\nx");
    const index = makeIndex(entry);

    const fromDefinition = getDefinitionLocation(entry, index, 0, 4);
    const fromReference = getDefinitionLocation(entry, index, 1, 0);

    expect(fromDefinition?.range.start).toEqual({ line: 0, character: 4 });
    expect(fromReference?.range.start).toEqual({ line: 0, character: 4 });
  });

  it("sorts and deduplicates references while honoring includeDeclaration", () => {
    const entry = makeEntry("let x\nx\nx");
    const index = makeIndex(entry);

    const withoutDeclaration = getReferenceLocations(entry, index, 0, 4, false);
    expect(withoutDeclaration.map((item) => item.range.start)).toEqual([
      { line: 1, character: 0 },
      { line: 2, character: 0 },
    ]);

    const withDeclaration = getReferenceLocations(entry, index, 2, 0, true);
    expect(withDeclaration.map((item) => item.range.start)).toEqual([
      { line: 0, character: 4 },
      { line: 1, character: 0 },
      { line: 2, character: 0 },
    ]);
  });
});

describe("workspace navigation helpers", () => {
  it("resolves an unresolved top-level reference to a unique workspace export", () => {
    const workspace = new WorkspaceIndex({ enabled: true, maxFileBytes: 1024, maxFiles: 10 });
    workspace.setRoots(["file:///workspace"]);

    const a = workspaceEntry("file:///workspace/a.mbt", "fn foo\n");
    addWorkspaceFile(workspace, a, graph(a.uri, a.text, [
      def(1, "foo", "function", "value", 3, 6),
    ], []));

    const b = workspaceEntry("file:///workspace/b.mbt", "foo\n");
    const bIndex = addWorkspaceFile(workspace, b, graph(b.uri, b.text, [], [
      ref(1, "foo", "variable", "value", 0, 3),
    ]));

    const location = getWorkspaceDefinitionLocation(b, bIndex, workspace, 0, 1);
    expect(location?.uri).toBe(a.uri);
    expect(location?.range.start).toEqual({ line: 0, character: 3 });
  });

  it("returns no cross-file definition when workspace exports are ambiguous", () => {
    const workspace = new WorkspaceIndex({ enabled: true, maxFileBytes: 1024, maxFiles: 10 });
    workspace.setRoots(["file:///workspace"]);

    for (const uri of ["file:///workspace/a.mbt", "file:///workspace/c.mbt"]) {
      const entry = workspaceEntry(uri, "fn foo\n");
      addWorkspaceFile(workspace, entry, graph(entry.uri, entry.text, [
        def(1, "foo", "function", "value", 3, 6),
      ], []));
    }

    const b = workspaceEntry("file:///workspace/b.mbt", "foo\n");
    const bIndex = addWorkspaceFile(workspace, b, graph(b.uri, b.text, [], [
      ref(1, "foo", "variable", "value", 0, 3),
    ]));

    expect(getWorkspaceDefinitionLocation(b, bIndex, workspace, 0, 1)).toBeNull();
  });

  it("collects workspace references for top-level exports and honors includeDeclaration", () => {
    const workspace = new WorkspaceIndex({ enabled: true, maxFileBytes: 1024, maxFiles: 10 });
    workspace.setRoots(["file:///workspace"]);

    const a = workspaceEntry("file:///workspace/a.mbt", "fn foo\nfoo\n");
    const aIndex = addWorkspaceFile(workspace, a, graph(a.uri, a.text, [
      def(1, "foo", "function", "value", 3, 6),
    ], [
      ref(2, "foo", "variable", "value", 7, 10),
    ], [
      { reference_id: 2, definition_id: 1 },
    ]));

    const b = workspaceEntry("file:///workspace/b.mbt", "foo\n");
    addWorkspaceFile(workspace, b, graph(b.uri, b.text, [], [
      ref(1, "foo", "variable", "value", 0, 3),
    ]));
    workspace.markClosed(b.uri);

    const withoutDeclaration = getWorkspaceReferenceLocations(a, aIndex, workspace, 0, 4, false);
    expect(withoutDeclaration.map((item) => [item.uri, item.range.start])).toEqual([
      [a.uri, { line: 1, character: 0 }],
      [b.uri, { line: 0, character: 0 }],
    ]);

    const withDeclaration = getWorkspaceReferenceLocations(a, aIndex, workspace, 0, 4, true);
    expect(withDeclaration.map((item) => [item.uri, item.range.start])).toEqual([
      [a.uri, { line: 0, character: 3 }],
      [a.uri, { line: 1, character: 0 }],
      [b.uri, { line: 0, character: 0 }],
    ]);
  });

  it("does not treat locally shadowed references as references to workspace exports", () => {
    const workspace = new WorkspaceIndex({ enabled: true, maxFileBytes: 1024, maxFiles: 10 });
    workspace.setRoots(["file:///workspace"]);

    const a = workspaceEntry("file:///workspace/a.mbt", "fn foo\n");
    const aIndex = addWorkspaceFile(workspace, a, graph(a.uri, a.text, [
      def(1, "foo", "function", "value", 3, 6),
    ], []));

    const b = workspaceEntry("file:///workspace/b.mbt", "let foo\nfoo\n");
    addWorkspaceFile(workspace, b, graph(b.uri, b.text, [
      def(1, "foo", "variable", "value", 4, 7),
    ], [
      ref(2, "foo", "variable", "value", 8, 11),
    ], [
      { reference_id: 2, definition_id: 1 },
    ]));

    const locations = getWorkspaceReferenceLocations(a, aIndex, workspace, 0, 4, false);
    expect(locations).toEqual([]);
  });
});
