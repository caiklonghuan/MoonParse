#!/usr/bin/env node

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdir, readFile, readdir, rm, stat } from "node:fs/promises";
import { existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const work = resolve(root, ".tmp/generated-tools-smoke");
const windows = process.platform === "win32";
const moon = process.env.MOON_BIN ?? (windows
  ? resolve(process.env.USERPROFILE ?? "", ".moon/bin/moon.exe")
  : "moon");

function run(command, args, cwd = root) {
  console.log(`\n> ${command} ${args.join(" ")}`);
  const result = spawnSync(command, args, { cwd, stdio: "inherit" });
  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(" ")} failed with ${result.status}`);
  }
}

async function filesUnder(dir) {
  const result = [];
  async function visit(current) {
    for (const entry of await readdir(current, { withFileTypes: true })) {
      const path = join(current, entry.name);
      if (entry.isDirectory()) await visit(path);
      else if (entry.isFile()) result.push(path);
    }
  }
  await visit(dir);
  return result.sort();
}

function readUInt32LE(buffer, offset) {
  return buffer[offset] |
    (buffer[offset + 1] << 8) |
    (buffer[offset + 2] << 16) |
    (buffer[offset + 3] << 24);
}

function readUInt16LE(buffer, offset) {
  return buffer[offset] | (buffer[offset + 1] << 8);
}

function zipEntries(buffer) {
  let eocd = -1;
  for (let i = buffer.length - 22; i >= Math.max(0, buffer.length - 65557); i--) {
    if (readUInt32LE(buffer, i) === 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw new Error("VSIX is missing ZIP end-of-central-directory");

  const count = readUInt16LE(buffer, eocd + 10);
  const offset = readUInt32LE(buffer, eocd + 16);
  const names = [];
  let cursor = offset;
  for (let i = 0; i < count; i++) {
    assert.equal(readUInt32LE(buffer, cursor), 0x02014b50, "invalid ZIP central directory");
    const fileNameLength = readUInt16LE(buffer, cursor + 28);
    const extraLength = readUInt16LE(buffer, cursor + 30);
    const commentLength = readUInt16LE(buffer, cursor + 32);
    const start = cursor + 46;
    names.push(buffer.subarray(start, start + fileNameLength).toString("utf8"));
    cursor = start + fileNameLength + extraLength + commentLength;
  }
  return names;
}

async function main() {
  run(moon, ["build", "--target", "wasm-gc", "--release", "cmd/main"]);

  await rm(work, { recursive: true, force: true });
  await mkdir(work, { recursive: true });

  const lspRoot = resolve(work, "lsp-target");
  run(process.execPath, [
    "run.js",
    "pack",
    "build",
    "languages/json",
    "--target",
    "lsp",
    "--out-dir",
    lspRoot,
  ]);

  const lspSrc = resolve(lspRoot, "lsp/src");
  for (const file of [
    "server.ts",
    "capabilities.ts",
    "document-highlight.ts",
    "folding.ts",
    "navigation.ts",
    "parse-table-info.ts",
    "rename.ts",
  ]) {
    assert.equal(existsSync(resolve(lspSrc, file)), true, `generated LSP missing ${file}`);
  }
  const generatedLspSources = await filesUnder(lspSrc);
  assert.equal(
    generatedLspSources.some((file) => file.endsWith(".test.ts") || file.endsWith(".spec.ts")),
    false,
    "generated LSP must not include tests",
  );

  const vscodeRoot = resolve(work, "vscode-target");
  run(process.execPath, [
    "run.js",
    "pack",
    "build",
    "languages/json",
    "--target",
    "vscode",
    "--out-dir",
    vscodeRoot,
  ]);

  const extensionRoot = resolve(vscodeRoot, "vscode");
  const vsixFiles = (await readdir(extensionRoot)).filter((file) => file.endsWith(".vsix"));
  assert.equal(vsixFiles.length, 1, "expected one generated VSIX");
  const vsixPath = resolve(extensionRoot, vsixFiles[0]);
  assert.ok((await stat(vsixPath)).size > 0, "generated VSIX must be non-empty");

  const capabilitiesPath = resolve(extensionRoot, "server/dist/capabilities.js");
  assert.equal(existsSync(capabilitiesPath), true, "generated server capabilities.js missing");
  const { createServerCapabilities } = await import(pathToFileURL(capabilitiesPath).href);
  const capabilities = createServerCapabilities();
  assert.equal(capabilities.documentHighlightProvider, true);
  assert.equal(capabilities.foldingRangeProvider, true);
  assert.equal(capabilities.renameProvider?.prepareProvider, true);

  const entries = zipEntries(await readFile(vsixPath));
  assert.equal(
    entries.includes("extension/server/dist/capabilities.js"),
    true,
    "VSIX must include generated server/dist/capabilities.js",
  );

  console.log("Generated LSP/VS Code smoke test passed.");
}

main().catch((error) => {
  console.error(error instanceof Error ? error.stack : String(error));
  process.exitCode = 1;
});
