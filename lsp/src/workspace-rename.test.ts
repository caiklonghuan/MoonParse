import { describe, expect, it } from "vitest";

import { BindingIndex } from "./binding-index.js";
import type { DocumentEntry } from "./document-manager.js";
import { prepareWorkspaceRename, renameWorkspaceSymbol } from "./workspace-rename.js";
import { WorkspaceIndex } from "./workspace-index.js";
import type {
  BindingDefinition,
  BindingDiagnostic,
  BindingGraph,
  BindingReference,
  ParseTree,
} from "../../wasm/moonparse.js";

const tableInfo = { literalTerminals: [], wordPattern: "[A-Za-z_][A-Za-z0-9_]*" };

function entry(uri: string, text: string): DocumentEntry {
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

function lineOffsets(text: string): Uint32Array {
  const offsets = [0];
  for (let i = 0; i < text.length; i++) {
    if (text[i] === "\n") offsets.push(i + 1);
  }
  return new Uint32Array(offsets);
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

function unresolved(reference: BindingReference): BindingDiagnostic {
  return {
    kind: "unresolved",
    message: `unresolved reference '${reference.name}'`,
    reference_id: reference.id,
    definition_id: -1,
    start_byte: reference.start_byte,
    end_byte: reference.end_byte,
  };
}

function graph(
  uri: string,
  text: string,
  definitions: BindingDefinition[],
  references: BindingReference[],
  edges: Array<{ reference_id: number; definition_id: number }> = [],
  diagnostics: BindingDiagnostic[] = [],
): BindingGraph {
  return {
    uri,
    scopes: [{ id: 0, parent: -1, start_byte: 0, end_byte: text.length, kind: "module" }],
    definitions,
    references,
    edges,
    diagnostics,
  };
}

function addFile(
  workspace: WorkspaceIndex,
  document: DocumentEntry,
  graphValue: BindingGraph,
  isOpen = true,
): BindingIndex {
  const index = new BindingIndex();
  index.update(document.uri, document, graphValue);
  workspace.upsertParsedDocument({
    uri: document.uri,
    text: document.text,
    lineOffsets: document.lineOffsets,
    languageId: document.languageId,
    version: document.version,
    sizeBytes: document.text.length,
    isOpen,
    tree: {} as ParseTree,
    graph: graphValue,
    bindingIndex: index,
  });
  return index;
}

function renameGraphFor(uri: string, text: string): BindingGraph | null {
  if (text === "fn bar\nbar\n") {
    return graph(uri, text, [
      def(1, "bar", "function", "value", 3, 6),
    ], [
      ref(2, "bar", "variable", "value", 7, 10),
    ], [
      { reference_id: 2, definition_id: 1 },
    ]);
  }
  if (text === "bar\n") {
    const r = ref(1, "bar", "variable", "value", 0, 3);
    return graph(uri, text, [], [r], [], [unresolved(r)]);
  }
  if (text === "fn bar\n") {
    return graph(uri, text, [
      def(1, "bar", "function", "value", 3, 6),
    ], []);
  }
  return null;
}

function rebuildFile(fileTextToGraph = renameGraphFor) {
  return (file: { uri: string }, text: string) => {
    const graphValue = fileTextToGraph(file.uri, text);
    if (!graphValue) return null;
    const document = entry(file.uri, text);
    const index = new BindingIndex();
    index.update(file.uri, document, graphValue);
    return { graph: graphValue, bindingIndex: index };
  };
}

function baseWorkspace(): {
  workspace: WorkspaceIndex;
  a: DocumentEntry;
  b: DocumentEntry;
  aIndex: BindingIndex;
  bIndex: BindingIndex;
} {
  const workspace = new WorkspaceIndex({ enabled: true, maxFileBytes: 1024, maxFiles: 10 });
  workspace.setRoots(["file:///workspace"]);

  const a = entry("file:///workspace/a.mbt", "fn foo\nfoo\n");
  const aIndex = addFile(workspace, a, graph(a.uri, a.text, [
    def(1, "foo", "function", "value", 3, 6),
  ], [
    ref(2, "foo", "variable", "value", 7, 10),
  ], [
    { reference_id: 2, definition_id: 1 },
  ]));

  const b = entry("file:///workspace/b.mbt", "foo\n");
  const bRef = ref(1, "foo", "variable", "value", 0, 3);
  const bIndex = addFile(workspace, b, graph(b.uri, b.text, [], [bRef], [], [
    unresolved(bRef),
  ]), false);

  return { workspace, a, b, aIndex, bIndex };
}

describe("workspace rename", () => {
  it("prepares rename for exported definitions and workspace-resolved references", () => {
    const { workspace, a, bIndex, b } = baseWorkspace();

    const fromDefinition = prepareWorkspaceRename(
      a,
      workspace.bindingIndex(a.uri),
      workspace,
      tableInfo,
      0,
      4,
    );
    expect(fromDefinition.applies && fromDefinition.result?.placeholder).toBe("foo");

    const fromReference = prepareWorkspaceRename(
      b,
      bIndex,
      workspace,
      tableInfo,
      0,
      1,
    );
    expect(fromReference.applies && fromReference.result?.placeholder).toBe("foo");
  });

  it("renames an exported symbol across indexed workspace files", () => {
    const { workspace, a, aIndex, b } = baseWorkspace();

    const result = renameWorkspaceSymbol(
      a,
      aIndex,
      workspace,
      tableInfo,
      0,
      4,
      "bar",
      { rebuildFile: rebuildFile() },
    );

    expect(result.applies && result.edit?.changes?.[a.uri]).toEqual([
      {
        range: { start: { line: 0, character: 3 }, end: { line: 0, character: 6 } },
        newText: "bar",
      },
      {
        range: { start: { line: 1, character: 0 }, end: { line: 1, character: 3 } },
        newText: "bar",
      },
    ]);
    expect(result.applies && result.edit?.changes?.[b.uri]).toEqual([
      {
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 3 } },
        newText: "bar",
      },
    ]);
  });

  it("rejects invalid names, export conflicts, and stale open files", () => {
    const { workspace, a, aIndex } = baseWorkspace();
    expect(renameWorkspaceSymbol(
      a,
      aIndex,
      workspace,
      tableInfo,
      0,
      4,
      "not valid",
      { rebuildFile: rebuildFile() },
    )).toEqual({ applies: true, edit: null });

    const c = entry("file:///workspace/c.mbt", "fn bar\n");
    addFile(workspace, c, graph(c.uri, c.text, [
      def(1, "bar", "function", "value", 3, 6),
    ], []));
    expect(renameWorkspaceSymbol(
      a,
      aIndex,
      workspace,
      tableInfo,
      0,
      4,
      "bar",
      { rebuildFile: rebuildFile(), isOpenFileFresh: () => true },
    )).toEqual({ applies: true, edit: null });

    const stale = renameWorkspaceSymbol(
      a,
      aIndex,
      workspace,
      tableInfo,
      0,
      4,
      "baz",
      { rebuildFile: rebuildFile(), isOpenFileFresh: () => false },
    );
    expect(stale).toEqual({ applies: true, edit: null });
  });

  it("does not rename locally shadowed references", () => {
    const { workspace, a, aIndex } = baseWorkspace();
    const shadow = entry("file:///workspace/shadow.mbt", "let foo\nfoo\n");
    addFile(workspace, shadow, graph(shadow.uri, shadow.text, [
      def(1, "foo", "variable", "value", 4, 7),
    ], [
      ref(2, "foo", "variable", "value", 8, 11),
    ], [
      { reference_id: 2, definition_id: 1 },
    ]));

    const result = renameWorkspaceSymbol(
      a,
      aIndex,
      workspace,
      tableInfo,
      0,
      4,
      "bar",
      { rebuildFile: rebuildFile() },
    );

    expect(result.applies && result.edit?.changes?.[shadow.uri]).toBeUndefined();
  });

  it("rejects renames that would capture an unchanged unresolved reference", () => {
    const { workspace, a, aIndex } = baseWorkspace();
    const capture = entry("file:///workspace/capture.mbt", "bar\n");
    const captureRef = ref(1, "bar", "variable", "value", 0, 3);
    addFile(workspace, capture, graph(capture.uri, capture.text, [], [captureRef], [], [
      unresolved(captureRef),
    ]));

    const result = renameWorkspaceSymbol(
      a,
      aIndex,
      workspace,
      tableInfo,
      0,
      4,
      "bar",
      { rebuildFile: rebuildFile() },
    );

    expect(result).toEqual({ applies: true, edit: null });
  });
});
