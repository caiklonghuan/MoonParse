import { describe, expect, it } from "vitest";

import { BindingIndex } from "./binding-index.js";
import type { DocumentEntry } from "./document-manager.js";
import { bindingDiagnosticsWithWorkspace } from "./workspace-bindings.js";
import { WorkspaceIndex } from "./workspace-index.js";
import type {
  BindingDefinition,
  BindingDiagnostic,
  BindingGraph,
  BindingReference,
  ParseTree,
} from "../../wasm/moonparse.js";

function entry(uri: string, text: string): DocumentEntry {
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

function exportedFoo(id = 1): BindingDefinition {
  return {
    id,
    name: "foo",
    kind: "function",
    ns: "value",
    scope_id: 0,
    start_byte: 3,
    end_byte: 6,
    declaration_start_byte: 0,
    declaration_end_byte: 6,
  };
}

function localFoo(id = 1): BindingDefinition {
  return {
    id,
    name: "foo",
    kind: "variable",
    ns: "value",
    scope_id: 0,
    start_byte: 4,
    end_byte: 7,
  };
}

function fooReference(id = 1): BindingReference {
  return {
    id,
    name: "foo",
    kind: "variable",
    ns: "value",
    scope_id: 0,
    start_byte: 0,
    end_byte: 3,
    diagnose_unresolved: true,
  };
}

function unresolvedDiagnostic(referenceId = 1): BindingDiagnostic {
  return {
    kind: "unresolved",
    message: "unresolved reference 'foo'",
    reference_id: referenceId,
    definition_id: -1,
    start_byte: 0,
    end_byte: 3,
  };
}

function graph(
  uri: string,
  text: string,
  definitions: BindingDefinition[],
  references: BindingReference[],
  diagnostics: BindingDiagnostic[],
  edges: Array<{ reference_id: number; definition_id: number }> = [],
): BindingGraph {
  return {
    uri,
    scopes: [{ id: 0, parent: -1, kind: "module", start_byte: 0, end_byte: text.length }],
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
    isOpen: true,
    tree: {} as ParseTree,
    graph: graphValue,
    bindingIndex: index,
  });
  return index;
}

describe("workspace binding diagnostics", () => {
  it("suppresses unresolved diagnostics when a unique workspace export resolves it", () => {
    const workspace = new WorkspaceIndex({ enabled: true, maxFileBytes: 1024, maxFiles: 10 });
    workspace.setRoots(["file:///workspace"]);

    const a = entry("file:///workspace/a.mbt", "fn foo");
    addFile(workspace, a, graph(a.uri, a.text, [exportedFoo()], [], []));

    const b = entry("file:///workspace/b.mbt", "foo");
    const bIndex = addFile(workspace, b, graph(b.uri, b.text, [], [fooReference()], [
      unresolvedDiagnostic(),
    ]));

    expect(bindingDiagnosticsWithWorkspace(b.uri, bIndex, workspace)).toEqual([]);
  });

  it("turns unresolved diagnostics into ambiguous when multiple exports are visible", () => {
    const workspace = new WorkspaceIndex({ enabled: true, maxFileBytes: 1024, maxFiles: 10 });
    workspace.setRoots(["file:///workspace"]);

    for (const uri of ["file:///workspace/a.mbt", "file:///workspace/c.mbt"]) {
      const document = entry(uri, "fn foo");
      addFile(workspace, document, graph(document.uri, document.text, [exportedFoo()], [], []));
    }

    const b = entry("file:///workspace/b.mbt", "foo");
    const bIndex = addFile(workspace, b, graph(b.uri, b.text, [], [fooReference()], [
      unresolvedDiagnostic(),
    ]));

    const diagnostics = bindingDiagnosticsWithWorkspace(b.uri, bIndex, workspace);
    expect(diagnostics).toHaveLength(1);
    expect(diagnostics[0].kind).toBe("ambiguous");
    expect(diagnostics[0].reference_id).toBe(1);
  });

  it("reports duplicate diagnostics for duplicate exported names in one package", () => {
    const workspace = new WorkspaceIndex({ enabled: true, maxFileBytes: 1024, maxFiles: 10 });
    workspace.setRoots(["file:///workspace"]);

    const a = entry("file:///workspace/a.mbt", "fn foo");
    const aIndex = addFile(workspace, a, graph(a.uri, a.text, [exportedFoo()], [], []));

    const b = entry("file:///workspace/b.mbt", "fn foo");
    addFile(workspace, b, graph(b.uri, b.text, [exportedFoo()], [], []));

    const diagnostics = bindingDiagnosticsWithWorkspace(a.uri, aIndex, workspace);
    expect(diagnostics).toHaveLength(1);
    expect(diagnostics[0].kind).toBe("duplicate");
    expect(diagnostics[0].definition_id).toBe(1);
  });

  it("keeps local duplicate diagnostics", () => {
    const workspace = new WorkspaceIndex({ enabled: true, maxFileBytes: 1024, maxFiles: 10 });
    workspace.setRoots(["file:///workspace"]);

    const document = entry("file:///workspace/local.mbt", "let foo");
    const duplicate: BindingDiagnostic = {
      kind: "duplicate",
      message: "duplicate definition 'foo'",
      reference_id: -1,
      definition_id: 1,
      start_byte: 4,
      end_byte: 7,
    };
    const index = addFile(workspace, document, graph(
      document.uri,
      document.text,
      [localFoo()],
      [],
      [duplicate],
    ));

    expect(bindingDiagnosticsWithWorkspace(document.uri, index, workspace)).toEqual([duplicate]);
  });
});
