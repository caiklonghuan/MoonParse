import assert from "node:assert/strict";
import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { checkBoundaries, detectCycles, extractProjectImports } from "./check-boundaries.mjs";

test("extractProjectImports ignores external modules", () => {
  const source = `import {\n  "caiklonghuan/MoonParse/grammar" @grammar,\n  "moonbitlang/core/json",\n}`;
  assert.deepEqual(extractProjectImports(source, "caiklonghuan/MoonParse"), ["grammar"]);
});

test("detectCycles reports a project dependency cycle", () => {
  const graph = new Map([
    ["a", ["b"]],
    ["b", ["a"]],
  ]);
  assert.deepEqual(detectCycles(graph), [["a", "b", "a"]]);
});

async function fixture({ appImport = "core", registerExtra = false } = {}) {
  const root = await mkdtemp(join(tmpdir(), "moonparse-boundaries-"));
  await mkdir(join(root, "core"));
  await mkdir(join(root, "app"));
  await mkdir(join(root, "api"));
  await writeFile(join(root, "core", "moon.pkg"), "import {}\n");
  await writeFile(
    join(root, "app", "moon.pkg"),
    `import { "example/project/${appImport}" }\n`,
  );
  const packages = {
    core: { name: "core", layer: "stable-public", allow: [] },
    app: { name: "app", layer: "application", allow: ["core"] },
  };
  if (registerExtra) packages.missing = { name: "missing", layer: "internal", allow: [] };
  await writeFile(
    join(root, "api", "boundaries.json"),
    JSON.stringify({
      schemaVersion: 1,
      modulePrefix: "example/project",
      ignoredDirectories: [],
      packages,
    }),
  );
  return root;
}

test("valid package graph passes", async () => {
  const result = await checkBoundaries({ root: await fixture() });
  assert.deepEqual(result.errors, []);
});

test("reverse or unknown dependency fails", async () => {
  const result = await checkBoundaries({ root: await fixture({ appImport: "unknown" }) });
  assert.ok(result.errors.some((error) => error.includes("unknown project package")));
});

test("registered package without moon.pkg fails", async () => {
  const result = await checkBoundaries({ root: await fixture({ registerExtra: true }) });
  assert.ok(result.errors.some((error) => error.includes("missing moon.pkg")));
});

