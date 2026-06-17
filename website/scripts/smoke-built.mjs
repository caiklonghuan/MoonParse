#!/usr/bin/env node

import { access, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

for (const path of ["dist/index.html", "public/moonparse.js", "public/moonparse.wasm", "src/data/precompiledTables.js"]) {
  await access(new URL(`../${path}`, import.meta.url));
}

const html = await readFile(new URL("../dist/index.html", import.meta.url), "utf8");
if (!html.includes('<div id="app"></div>')) throw new Error("Website dist/index.html has no app mount");

const { PRECOMPILED_TABLES } = await import("../src/data/precompiledTables.js");
for (const id of ["json", "json5", "c", "python", "moonbit"]) {
  if (typeof PRECOMPILED_TABLES[id] !== "string" || PRECOMPILED_TABLES[id].length === 0) {
    throw new Error(`Website precompiled table is missing: ${id}`);
  }
}

const { loadMoonParse } = await import("../public/moonparse.js");
const mp = await loadMoonParse(fileURLToPath(new URL("../public/moonparse.wasm", import.meta.url)));
if (!/^\d+\.\d+\.\d+/.test(mp.version())) throw new Error("Website WASM version is invalid");
console.log("MoonParse Website built-resource smoke test passed.");
