import { describe, expect, it } from "vitest";

import { ModuleGraph, moduleInfoForUri } from "./module-graph.js";
import type { BindingGraph } from "../../wasm/moonparse.js";

function graph(uri: string): BindingGraph {
  return {
    uri,
    scopes: [
      { id: 1, parent: -1, kind: "module", start_byte: 0, end_byte: 100 },
      { id: 2, parent: 1, kind: "function", start_byte: 10, end_byte: 50 },
    ],
    definitions: [
      def(1, "main", "function", "value", 1, 0, 4),
      def(2, "User", "struct", "type", 1, 5, 9),
      def(3, "Color", "enum", "type", 1, 10, 15),
      def(4, "Show", "trait", "type", 1, 16, 20),
      def(5, "PI", "constant", "value", 1, 21, 23),
      def(6, "local", "variable", "value", 2, 30, 35),
      def(7, "field", "field", "member", 1, 40, 45),
      def(8, "method", "method", "value", 1, 46, 52),
      def(9, "param", "parameter", "value", 2, 53, 58),
    ],
    references: [],
    edges: [],
    diagnostics: [],
  };
}

function def(
  id: number,
  name: string,
  kind: string,
  ns: string,
  scope_id: number,
  start_byte: number,
  end_byte: number,
) {
  return {
    id,
    name,
    kind,
    ns,
    scope_id,
    start_byte,
    end_byte,
    declaration_start_byte: Math.max(0, start_byte - 1),
    declaration_end_byte: end_byte + 1,
  };
}

describe("ModuleGraph", () => {
  it("derives package and module ids from workspace roots", () => {
    expect(moduleInfoForUri("file:///workspace/src/main.mbt", ["file:///workspace"]))
      .toEqual({ packageId: "file:///workspace", moduleId: "src/main" });

    expect(moduleInfoForUri("file:///workspace/pkg/src/main.mbt", [
      "file:///workspace",
      "file:///workspace/pkg",
    ])).toEqual({ packageId: "file:///workspace/pkg", moduleId: "src/main" });

    expect(moduleInfoForUri("file:///workspace/src/main.mbt", []))
      .toEqual({ packageId: "workspace", moduleId: "workspace/src/main" });

    expect(moduleInfoForUri("file:///C:/Workspace/src/main.mbt", ["file:///C:/Workspace"]))
      .toEqual({
        packageId: process.platform === "win32" ? "file:///c:/workspace" : "file:///C:/Workspace",
        moduleId: "src/main",
      });
  });

  it("exports only top-level cross-file symbol kinds", () => {
    const uri = "file:///workspace/src/main.mbt";
    const modules = new ModuleGraph();
    modules.setRoots(["file:///workspace"]);
    const entry = modules.upsertFile(uri, graph(uri));

    expect(entry.packageId).toBe("file:///workspace");
    expect(entry.moduleId).toBe("src/main");
    expect(entry.imports).toEqual([]);
    expect(entry.exportedDefinitions.map((item) => item.name).sort()).toEqual([
      "Color",
      "PI",
      "Show",
      "main",
      "User",
    ].sort());
    expect(entry.exportedDefinitions.map((item) => item.globalId)).toContain(
      `${uri}#def:1`,
    );
  });

  it("queries exports by package, name, namespace, and kind", () => {
    const modules = new ModuleGraph();
    modules.setRoots(["file:///workspace", "file:///other"]);
    modules.upsertFile("file:///workspace/a.mbt", graph("file:///workspace/a.mbt"));
    modules.upsertFile("file:///workspace/b.mbt", graph("file:///workspace/b.mbt"));
    modules.upsertFile("file:///other/a.mbt", graph("file:///other/a.mbt"));

    expect(modules.findExportedDefinitions("file:///workspace", "main", "value"))
      .toHaveLength(2);
    expect(modules.findExportedDefinitions(
      "file:///workspace",
      "main",
      "value",
      "function",
    )).toHaveLength(2);
    expect(modules.findExportedDefinitions("file:///other", "main", "value"))
      .toHaveLength(1);
    expect(modules.exportedDefinitionsForPackage("file:///workspace").length)
      .toBe(10);
  });

  it("removes module exports when files leave the graph", () => {
    const modules = new ModuleGraph();
    modules.setRoots(["file:///workspace"]);
    modules.upsertFile("file:///workspace/a.mbt", graph("file:///workspace/a.mbt"));
    expect(modules.findExportedDefinitions("file:///workspace", "main", "value"))
      .toHaveLength(1);

    modules.removeFile("file:///workspace/a.mbt");
    expect(modules.findExportedDefinitions("file:///workspace", "main", "value"))
      .toEqual([]);
  });
});
