import { describe, expect, it } from "vitest";

import { BindingIndex } from "./binding-index.js";
import type { DocumentEntry } from "./document-manager.js";
import type { ModuleFileMetadata, ModuleImport } from "./module-graph.js";
import { getWorkspaceDefinitionLocation } from "./navigation.js";
import {
  bindingDiagnosticsWithWorkspace,
  workspaceCandidatesForReference,
  workspaceOccurrencesForExported,
} from "./workspace-bindings.js";
import { WorkspaceIndex } from "./workspace-index.js";
import { renameWorkspaceSymbol } from "./workspace-rename.js";
import type {
  BindingDefinition,
  BindingDiagnostic,
  BindingGraph,
  BindingReference,
  ParseTree,
} from "../../wasm/moonparse.js";

function document(uri: string, text: string): DocumentEntry {
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

function definition(name: string, start = 3): BindingDefinition {
  return {
    id: 1,
    name,
    kind: "function",
    ns: "value",
    scope_id: 0,
    start_byte: start,
    end_byte: start + name.length,
    declaration_start_byte: 0,
    declaration_end_byte: start + name.length,
  };
}

function reference(
  id: number,
  name: string,
  ns: string,
  start: number,
  diagnose = true,
): BindingReference {
  return {
    id,
    name,
    kind: ns === "member" ? "field" : "variable",
    ns,
    scope_id: 0,
    start_byte: start,
    end_byte: start + name.length,
    diagnose_unresolved: diagnose,
  };
}

function unresolved(item: BindingReference): BindingDiagnostic {
  return {
    kind: "unresolved",
    message: `unresolved reference '${item.name}'`,
    reference_id: item.id,
    definition_id: -1,
    start_byte: item.start_byte,
    end_byte: item.end_byte,
  };
}

function bindingGraph(
  uri: string,
  text: string,
  definitions: BindingDefinition[],
  references: BindingReference[],
  diagnostics: BindingDiagnostic[] = [],
): BindingGraph {
  return {
    uri,
    scopes: [{ id: 0, parent: -1, kind: "module", start_byte: 0, end_byte: text.length }],
    definitions,
    references,
    edges: [],
    diagnostics,
  };
}

function metadata(
  moduleId: string,
  packageId: string,
  imports: ModuleImport[] = [],
  isPublic = false,
): ModuleFileMetadata {
  return {
    owningModuleId: moduleId,
    packageId,
    moduleId: `${packageId}/file`,
    imports,
    publicExportRanges: isPublic ? [{ startByte: 3, endByte: 6 }] : [],
    qualifiedReferences: [],
    resolutionMode: "strict",
  };
}

function add(
  workspace: WorkspaceIndex,
  entry: DocumentEntry,
  graph: BindingGraph,
  moduleMetadata: ModuleFileMetadata,
): BindingIndex {
  const index = new BindingIndex();
  index.update(entry.uri, entry, graph);
  workspace.upsertParsedDocument({
    uri: entry.uri,
    text: entry.text,
    lineOffsets: entry.lineOffsets,
    languageId: entry.languageId,
    version: entry.version,
    sizeBytes: entry.text.length,
    isOpen: true,
    tree: {} as ParseTree,
    graph,
    bindingIndex: index,
    moduleMetadata,
  });
  return index;
}

function resolvedImport(status: ModuleImport["status"] = "resolved"): ModuleImport {
  return {
    source: status === "external" ? "remote/dep" : "acme/dep",
    alias: "dep",
    condition: "normal",
    sourceStartByte: 0,
    sourceEndByte: 0,
    targetPackageId: status === "resolved" ? "acme/dep" : null,
    status,
  };
}

function strictWorkspace(publicExport = true, importStatus: ModuleImport["status"] = "resolved") {
  const workspace = new WorkspaceIndex({ enabled: true, maxFileBytes: 4096, maxFiles: 20 });
  workspace.setRoots(["file:///workspace"]);
  const exporter = document("file:///workspace/dep/foo.mbt", "fn foo");
  add(
    workspace,
    exporter,
    bindingGraph(exporter.uri, exporter.text, [definition("foo")], []),
    metadata("acme", "acme/dep", [], publicExport),
  );

  const importer = document("file:///workspace/app/main.mbt", "@dep.foo");
  const alias = reference(1, "@dep", "value", 0);
  const member = reference(2, "foo", "member", 5, false);
  const importerMetadata = metadata("acme", "acme/app", [resolvedImport(importStatus)]);
  importerMetadata.qualifiedReferences = [{
    alias: "dep",
    name: "foo",
    namespace: "value",
    aliasStartByte: 0,
    aliasEndByte: 4,
    startByte: 5,
    endByte: 8,
    referenceId: 2,
  }];
  const importerIndex = add(
    workspace,
    importer,
    bindingGraph(importer.uri, importer.text, [], [alias, member], [unresolved(alias)]),
    importerMetadata,
  );
  return { workspace, exporter, importer, importerIndex, member };
}

describe("import-aware workspace resolution", () => {
  it("resolves a qualified import only to a public target", () => {
    const { workspace, importer, importerIndex, member } = strictWorkspace(true);
    expect(workspaceCandidatesForReference(workspace, importer.uri, member)
      .map((item) => item.globalId)).toEqual(["file:///workspace/dep/foo.mbt#def:1"]);
    expect(bindingDiagnosticsWithWorkspace(importer.uri, importerIndex, workspace)).toEqual([]);
    expect(getWorkspaceDefinitionLocation(importer, importerIndex, workspace, 0, 6)?.uri)
      .toBe("file:///workspace/dep/foo.mbt");
  });

  it("rejects private imported members and reports the member range", () => {
    const { workspace, importer, importerIndex, member } = strictWorkspace(false);
    expect(workspaceCandidatesForReference(workspace, importer.uri, member)).toEqual([]);
    const diagnostics = bindingDiagnosticsWithWorkspace(importer.uri, importerIndex, workspace);
    expect(diagnostics.some((item) =>
      item.kind === "unresolved" && item.start_byte === 5 && item.end_byte === 8)).toBe(true);
  });

  it("keeps external imports quiet without inventing a definition", () => {
    const { workspace, importer, importerIndex, member } = strictWorkspace(true, "external");
    expect(workspaceCandidatesForReference(workspace, importer.uri, member)).toEqual([]);
    expect(bindingDiagnosticsWithWorkspace(importer.uri, importerIndex, workspace)).toEqual([]);
  });

  it("includes only references that resolve through a real importer edge", () => {
    const { workspace } = strictWorkspace(true);
    const exported = workspace.module("file:///workspace/dep/foo.mbt")!.exportedDefinitions[0];
    expect(workspaceOccurrencesForExported(workspace, exported, true).map((item) => ({
      uri: item.uri,
      kind: item.kind,
      start: item.item.start_byte,
    }))).toEqual([
      { uri: "file:///workspace/app/main.mbt", kind: "reference", start: 5 },
      { uri: "file:///workspace/dep/foo.mbt", kind: "definition", start: 3 },
    ]);
  });

  it("renames a public definition and only its real importer member", () => {
    const { workspace, exporter } = strictWorkspace(true);
    const outcome = renameWorkspaceSymbol(
      exporter,
      workspace.bindingIndex(exporter.uri),
      workspace,
      { literalTerminals: [], wordPattern: "[A-Za-z_][A-Za-z0-9_]*" },
      0,
      4,
      "bar",
      {
        rebuildFile(file, text) {
          const nextDocument = document(file.uri, text);
          let graph: BindingGraph;
          let moduleMetadata: ModuleFileMetadata;
          if (file.uri.endsWith("/dep/foo.mbt") && text === "fn bar") {
            graph = bindingGraph(file.uri, text, [definition("bar")], []);
            moduleMetadata = metadata("acme", "acme/dep", [], true);
          } else if (file.uri.endsWith("/app/main.mbt") && text === "@dep.bar") {
            const alias = reference(1, "@dep", "value", 0);
            const member = reference(2, "bar", "member", 5, false);
            graph = bindingGraph(file.uri, text, [], [alias, member], [unresolved(alias)]);
            moduleMetadata = metadata("acme", "acme/app", [resolvedImport()]);
            moduleMetadata.qualifiedReferences = [{
              alias: "dep",
              name: "bar",
              namespace: "value",
              aliasStartByte: 0,
              aliasEndByte: 4,
              startByte: 5,
              endByte: 8,
              referenceId: 2,
            }];
          } else {
            return null;
          }
          const bindingIndex = new BindingIndex();
          bindingIndex.update(file.uri, nextDocument, graph);
          return { graph, bindingIndex, moduleMetadata };
        },
      },
    );
    expect(outcome.applies).toBe(true);
    expect(outcome.applies && outcome.edit?.changes).toEqual({
      "file:///workspace/app/main.mbt": [{
        range: {
          start: { line: 0, character: 5 },
          end: { line: 0, character: 8 },
        },
        newText: "bar",
      }],
      "file:///workspace/dep/foo.mbt": [{
        range: {
          start: { line: 0, character: 3 },
          end: { line: 0, character: 6 },
        },
        newText: "bar",
      }],
    });
  });
});
