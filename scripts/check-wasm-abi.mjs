#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { extractWasmExports } from "./api-snapshots.mjs";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const pkg = await readFile(resolve(ROOT, "wasm/moon.pkg"), "utf8");
const wrapper = await readFile(resolve(ROOT, "wasm/moonparse.js"), "utf8");
const exportsSet = new Set(extractWasmExports(pkg).trim().split("\n"));
const used = new Set(
  [...wrapper.matchAll(/\bwasm\.([A-Za-z_][A-Za-z0-9_]*)/g)].map((match) => match[1]),
);
const missing = [...used].filter((name) => !exportsSet.has(name)).sort();
if (missing.length) {
  console.error("JavaScript wrapper calls WASM functions not declared in wasm/moon.pkg exports:");
  for (const name of missing) console.error(`- ${name}`);
  process.exit(1);
}
console.log(`MoonParse WASM ABI alignment OK (${used.size} wrapper calls, ${exportsSet.size} exports).`);

