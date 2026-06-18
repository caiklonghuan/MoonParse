#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const baseArg = process.argv.find((arg) => arg.startsWith("--base="));

if (!baseArg) {
  console.error("Usage: node scripts/check-api-change.mjs --base=<git-ref>");
  process.exit(2);
}

const base = baseArg.slice("--base=".length);
const git = process.platform === "win32" ? "git.exe" : "git";
const result = spawnSync(git, ["diff", "--name-only", `${base}...HEAD`], {
  cwd: ROOT,
  encoding: "utf8",
});
if (result.status !== 0) {
  process.stderr.write(result.stderr || `unable to diff against ${base}\n`);
  process.exit(result.status ?? 1);
}

const changed = new Set(result.stdout.split(/\r?\n/).filter(Boolean));
const apiSources = [...changed].filter((path) =>
  path.endsWith("pkg.generated.mbti") ||
  path === "wasm/moon.pkg" ||
  path === "wasm/moonparse.d.ts" ||
  path === "cmd/main/args.mbt"
);

if (!apiSources.length) {
  console.log("No public API source changes detected.");
  process.exit(0);
}

const required = ["CHANGELOG.md", "docs/migrations.md"];
const missing = required.filter((path) => !changed.has(path));
const snapshotChanged = [...changed].some((path) => path.startsWith("api/snapshots/"));
if (!snapshotChanged) missing.push("api/snapshots/*");

if (missing.length) {
  console.error(`Public API changed (${apiSources.join(", ")}) but required governance files are missing:`);
  for (const path of missing) console.error(`- ${path}`);
  process.exit(1);
}

console.log(`Public API governance OK for changes: ${apiSources.join(", ")}`);

