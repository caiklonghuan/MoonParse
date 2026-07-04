import { describe, expect, it } from "vitest";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { pathToFileURL } from "node:url";

import {
  discoverMoonBitWorkspace,
  localDependencyPaths,
  parseMoonPkg,
  parseMoonWork,
} from "./moonbit-workspace.js";

describe("MoonBit workspace metadata", () => {
  it("parses moon.work members and project objects", () => {
    expect(parseMoonWork('{"members":["a",{"path":"b"}]}')).toEqual(["a", "b"]);
    expect(parseMoonWork('{"projects":["packages/c"]}')).toEqual(["packages/c"]);
  });

  it("parses moon.pkg imports, aliases, comments, and test conditions", () => {
    const imports = parseMoonPkg(`
      import {
        "moonbitlang/core/json" @json,
        // retained after comment stripping
        "acme/util",
      }
      /* separate block */
      import { "acme/testing" @testing, } for "test"
    `);
    expect(imports.map(({ source, alias, condition }) => ({ source, alias, condition })))
      .toEqual([
        { source: "moonbitlang/core/json", alias: "json", condition: "normal" },
        { source: "acme/util", alias: "util", condition: "normal" },
        { source: "acme/testing", alias: "testing", condition: "test" },
      ]);
  });

  it("collects only explicit local dependency paths", () => {
    expect(localDependencyPaths({
      deps: {
        remote: "1.0.0",
        local: { path: "../local" },
      },
      repository: { path: "not-a-dependency" },
      "test-deps": [{ path: "../testing" }],
    })).toEqual(["../local", "../testing"]);
  });

  it("discovers moon.work members and explicit local path dependencies", async () => {
    const root = await mkdtemp(join(tmpdir(), "moonparse-workspace-"));
    try {
      const workspace = join(root, "workspace");
      const app = join(workspace, "app");
      const dependency = join(root, "dep");
      await mkdir(join(app, "src"), { recursive: true });
      await mkdir(join(dependency, "pkg"), { recursive: true });
      await writeFile(join(workspace, "moon.work"), '{"members":["app"]}', "utf8");
      await writeFile(join(app, "moon.mod.json"), JSON.stringify({
        name: "acme/app",
        deps: { dep: { path: "../../dep" } },
      }), "utf8");
      await writeFile(join(dependency, "moon.mod.json"), '{"name":"acme/dep"}', "utf8");
      await writeFile(join(dependency, "pkg", "lib.mbt"), "pub fn run() {}", "utf8");
      await writeFile(join(app, "src", "main.mbt"), "@dep.run()", "utf8");
      await writeFile(join(app, "src", "moon.pkg"), `
        import { "acme/dep/pkg" @dep, "remote/lib" @remote }
        import { "acme/dep/pkg" @testing } for "test"
      `, "utf8");

      const model = await discoverMoonBitWorkspace([pathToFileURL(workspace).href]);
      expect(model.moduleRoots.map((item) => item.moduleId).sort())
        .toEqual(["acme/app", "acme/dep"]);
      const emptyData = {
        moduleName: null,
        publicExportRanges: [],
        imports: [],
        qualifiedReferences: [],
      };
      const normal = model.metadataForFile(
        pathToFileURL(join(app, "src", "main.mbt")).href,
        emptyData,
      )!;
      expect(normal.packageId).toBe("acme/app/src");
      expect(normal.imports.map((item) => ({
        alias: item.alias,
        status: item.status,
        target: item.targetPackageId,
      }))).toEqual([
        { alias: "dep", status: "resolved", target: "acme/dep/pkg" },
        { alias: "remote", status: "external", target: null },
      ]);
      const test = model.metadataForFile(
        pathToFileURL(join(app, "src", "main_test.mbt")).href,
        emptyData,
      )!;
      expect(test.imports.some((item) => item.alias === "testing")).toBe(true);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});
