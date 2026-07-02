import { describe, expect, it } from "vitest";

import { BindingIndex } from "./binding-index.js";
import {
  WorkspaceIndex,
  extensionFromUri,
  globalDefinitionId,
  globalReferenceId,
  parseGlobalSymbolId,
} from "./workspace-index.js";
import type { DocumentEntry } from "./document-manager.js";
import type { BindingGraph, ParseTree } from "../../wasm/moonparse.js";

const config = {
  enabled: true,
  maxFileBytes: 1024,
  maxFiles: 2,
  parseTimeoutMs: 5000,
  idleEvictMs: 300000,
};

function makeEntry(uri: string, text: string): DocumentEntry {
  return {
    uri,
    text,
    version: 1,
    languageId: "moonbit",
    parserHandle: -1,
    treeHandle: -1,
    lastDiagnostics: [],
    lineOffsets: new Uint32Array([0]),
  };
}

function makeGraph(uri: string): BindingGraph {
  return {
    uri,
    scopes: [{ id: 0, parent: -1, start_byte: 0, end_byte: 8, kind: "module" }],
    definitions: [{
      id: 1,
      name: "main",
      kind: "function",
      ns: "value",
      scope_id: 0,
      start_byte: 3,
      end_byte: 7,
      declaration_start_byte: 0,
      declaration_end_byte: 8,
    }, {
      id: 2,
      name: "local",
      kind: "variable",
      ns: "value",
      scope_id: 1,
      start_byte: 9,
      end_byte: 14,
    }],
    references: [],
    edges: [],
    diagnostics: [],
  };
}

function makeBindingIndex(entry: DocumentEntry, graph: BindingGraph): BindingIndex {
  const index = new BindingIndex();
  index.update(entry.uri, entry, graph);
  return index;
}

describe("WorkspaceIndex", () => {
  it("tracks roots, extensions, file size, and max file count", () => {
    const index = new WorkspaceIndex(config);
    index.setRoots(["file:///workspace"]);

    expect(index.shouldIndexUri("file:///workspace/src/a.mbt", 100, ["mbt"])).toBe(true);
    expect(index.shouldIndexUri("file:///other/a.mbt", 100, ["mbt"])).toBe(false);
    expect(index.shouldIndexUri("file:///workspace/src/a.txt", 100, ["mbt"])).toBe(false);
    expect(index.shouldIndexUri("file:///workspace/src/a.mbt", 1025, ["mbt"])).toBe(false);

    const tree = {} as ParseTree;
    for (const uri of ["file:///workspace/a.mbt", "file:///workspace/b.mbt"]) {
      index.upsertParsedDocument({
        uri,
        text: "",
        lineOffsets: new Uint32Array([0]),
        languageId: "moonbit",
        version: 1,
        sizeBytes: 10,
        isOpen: true,
        tree,
      });
    }
    expect(index.shouldIndexUri("file:///workspace/c.mbt", 10, ["mbt"])).toBe(false);
    expect(index.shouldIndexUri("file:///workspace/a.mbt", 10, ["mbt"])).toBe(true);
  });

  it("stores parse tree, binding graph, binding index, and closed state", () => {
    const uri = "file:///workspace/main.mbt";
    const entry = makeEntry(uri, "fn main");
    const graph = makeGraph(uri);
    const bindingIndex = makeBindingIndex(entry, graph);
    const tree = {} as ParseTree;
    const index = new WorkspaceIndex(config);

    index.upsertParsedDocument({
      uri,
      text: entry.text,
      lineOffsets: entry.lineOffsets,
      languageId: "moonbit",
      version: 7,
      mtimeMs: 123,
      sizeBytes: entry.text.length,
      isOpen: true,
      tree,
      graph,
      bindingIndex,
    });

    expect(index.tree(uri)).toBe(tree);
    expect(index.graph(uri)).toBe(graph);
    expect(index.bindingIndex(uri)).toBe(bindingIndex);
    expect(index.get(uri)?.version).toBe(7);
    expect(index.get(uri)?.text).toBe("fn main");
    expect(index.get(uri)?.lineOffsets).toEqual(new Uint32Array([0]));
    expect(index.get(uri)?.isOpen).toBe(true);
    expect(index.get(uri)?.packageId).toBe("workspace");
    expect(index.get(uri)?.moduleId).toBe("workspace/main");
    expect(index.get(uri)?.exportedDefinitions.map((item) => item.name))
      .toEqual(["main"]);

    index.markClosed(uri);
    expect(index.get(uri)?.isOpen).toBe(false);
    expect(index.bindingIndex(uri)).toBe(bindingIndex);
    expect(index.module(uri)?.exportedDefinitions.map((item) => item.name))
      .toEqual(["main"]);
  });

  it("tracks generation tokens and stale parse results", () => {
    const uri = "file:///workspace/main.mbt";
    const index = new WorkspaceIndex(config);

    const first = index.beginUpdate(uri, 10);
    const second = index.beginUpdate(uri, 20);

    expect(first).toBe(1);
    expect(second).toBe(2);
    expect(index.isCurrentGeneration(uri, first)).toBe(false);
    expect(index.isCurrentGeneration(uri, second)).toBe(true);
    expect(index.currentGeneration(uri)).toBe(2);
  });

  it("evicts closed entries by least recent access before open entries", () => {
    const index = new WorkspaceIndex(config);
    const treeA = { id: "a" } as unknown as ParseTree;
    const treeB = { id: "b" } as unknown as ParseTree;
    const freed: ParseTree[] = [];

    index.upsertParsedDocument({
      uri: "file:///workspace/a.mbt",
      text: "",
      lineOffsets: new Uint32Array([0]),
      languageId: "moonbit",
      sizeBytes: 1,
      isOpen: false,
      indexedAtMs: 10,
      tree: treeA,
    });
    index.upsertParsedDocument({
      uri: "file:///workspace/b.mbt",
      text: "",
      lineOffsets: new Uint32Array([0]),
      languageId: "moonbit",
      sizeBytes: 1,
      isOpen: true,
      indexedAtMs: 20,
      tree: treeB,
    });

    expect(index.ensureCapacityFor("file:///workspace/c.mbt", (tree) => freed.push(tree), 30))
      .toBe(true);
    expect(freed).toEqual([treeA]);
    expect(index.get("file:///workspace/a.mbt")).toBeUndefined();
    expect(index.get("file:///workspace/b.mbt")).toBeDefined();

    expect(index.ensureCapacityFor("file:///workspace/d.mbt", (tree) => freed.push(tree), 40))
      .toBe(true);
  });

  it("evicts idle closed entries and leaves recent/open entries indexed", () => {
    const index = new WorkspaceIndex({ ...config, maxFiles: 10, idleEvictMs: 50 });
    const oldTree = { id: "old" } as unknown as ParseTree;
    const recentTree = { id: "recent" } as unknown as ParseTree;
    const openTree = { id: "open" } as unknown as ParseTree;
    const freed: ParseTree[] = [];

    for (const [uri, tree, isOpen, indexedAtMs] of [
      ["file:///workspace/old.mbt", oldTree, false, 10],
      ["file:///workspace/recent.mbt", recentTree, false, 80],
      ["file:///workspace/open.mbt", openTree, true, 1],
    ] as const) {
      index.upsertParsedDocument({
        uri,
        text: "",
        lineOffsets: new Uint32Array([0]),
        languageId: "moonbit",
        sizeBytes: 1,
        isOpen,
        indexedAtMs,
        tree,
      });
    }

    expect(index.evictIdleClosed(100, (tree) => freed.push(tree)))
      .toEqual(["file:///workspace/old.mbt"]);
    expect(freed).toEqual([oldTree]);
    expect(index.get("file:///workspace/old.mbt")).toBeUndefined();
    expect(index.get("file:///workspace/recent.mbt")).toBeDefined();
    expect(index.get("file:///workspace/open.mbt")).toBeDefined();
  });

  it("queries and clears module exports with workspace entries", () => {
    const uri = "file:///workspace/src/main.mbt";
    const entry = makeEntry(uri, "fn main");
    const graph = makeGraph(uri);
    const bindingIndex = makeBindingIndex(entry, graph);
    const tree = {} as ParseTree;
    const index = new WorkspaceIndex(config);
    index.setRoots(["file:///workspace"]);

    index.upsertParsedDocument({
      uri,
      text: entry.text,
      lineOffsets: entry.lineOffsets,
      languageId: "moonbit",
      version: 1,
      sizeBytes: entry.text.length,
      isOpen: true,
      tree,
      graph,
      bindingIndex,
    });

    expect(index.module(uri)?.moduleId).toBe("src/main");
    expect(index.findExportedDefinitions("file:///workspace", "main", "value"))
      .toHaveLength(1);

    index.clearRuntime(uri);
    expect(index.findExportedDefinitions("file:///workspace", "main", "value"))
      .toEqual([]);
    expect(index.get(uri)?.exportedDefinitions).toEqual([]);

    index.upsertParsedDocument({
      uri,
      text: entry.text,
      lineOffsets: entry.lineOffsets,
      languageId: "moonbit",
      version: 2,
      sizeBytes: entry.text.length,
      isOpen: true,
      tree,
      graph,
      bindingIndex,
    });
    index.remove(uri);
    expect(index.module(uri)).toBeUndefined();
  });

  it("creates stable global symbol ids", () => {
    const def = globalDefinitionId("file:///workspace/main.mbt", 42);
    const ref = globalReferenceId("file:///workspace/main.mbt", 9);

    expect(parseGlobalSymbolId(def)).toEqual({
      uri: "file:///workspace/main.mbt",
      kind: "definition",
      localId: 42,
    });
    expect(parseGlobalSymbolId(ref)).toEqual({
      uri: "file:///workspace/main.mbt",
      kind: "reference",
      localId: 9,
    });
    expect(parseGlobalSymbolId("not-a-symbol")).toBeNull();
  });

  it("extracts extensions from file URIs", () => {
    expect(extensionFromUri("file:///workspace/src/main.mbt")).toBe("mbt");
    expect(extensionFromUri("file:///workspace/src/main.MBT?version=1")).toBe("mbt");
    expect(extensionFromUri("file:///workspace/src/README")).toBe("");
    expect(extensionFromUri("file:///workspace/src/bad.%zz")).toBe("%zz");
  });
});
