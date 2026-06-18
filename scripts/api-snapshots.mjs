#!/usr/bin/env node

import { readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const SNAPSHOT_DIR = resolve(ROOT, "api/snapshots");

function normalizeText(text) {
  return `${text.replace(/\r\n/g, "\n").split("\n").map((line) => line.trimEnd()).join("\n").trimEnd()}\n`;
}

export function extractWasmExports(source) {
  const block = source.match(/"exports"\s*:\s*\[([\s\S]*?)\]/);
  if (!block) throw new Error("cannot find wasm-gc exports list in wasm/moon.pkg");
  return [...block[1].matchAll(/"([^"]+)"/g)]
    .map((match) => match[1])
    .sort()
    .join("\n") + "\n";
}

export function extractCliHelp(source) {
  const functions = [
    "global_usage",
    "generate_usage",
    "parse_usage",
    "check_usage",
    "fmt_usage",
    "query_usage",
    "test_usage",
    "build_usage",
    "wasm_usage",
    "dump_usage",
    "clean_usage",
    "pack_usage",
  ];
  const sections = [];
  for (const name of functions) {
    const pattern = new RegExp(`fn ${name}\\(\\) -> String \\{([\\s\\S]*?)\\n\\}`, "m");
    const match = source.match(pattern);
    if (!match) throw new Error(`cannot find CLI help function ${name}`);
    const lines = [...match[1].matchAll(/^\s*#\|(.*)$/gm)].map((item) => item[1]);
    if (!lines.length) throw new Error(`CLI help function ${name} has no block-string lines`);
    sections.push(`## ${name}\n${lines.join("\n")}`);
  }
  return `${sections.join("\n\n")}\n`;
}

export function extractCliExitCodes(argsSource, mainSource) {
  if (!argsSource.includes("Exit codes: 0 = all passed, 1 = test failures, 2 = load/compile error")) {
    throw new Error("cannot find CLI test exit-code contract");
  }
  if (!argsSource.includes("Exit codes: 0 = ok, 1 = warnings, 2 = errors")) {
    throw new Error("cannot find CLI check exit-code contract");
  }
  if (!/Err\(msg\)[\s\S]*?print_err\(msg\)[\s\S]*?\n\s*2\n/.test(mainSource)) {
    throw new Error("cannot find CLI invalid-argument exit code");
  }
  return `${JSON.stringify({
    schemaVersion: 1,
    global: { success: 0, invalidArguments: 2 },
    check: { ok: 0, warnings: 1, errors: 2 },
    test: { passed: 0, failures: 1, loadOrCompileError: 2 },
    pack: { success: 0, warningsOrTestFailures: 1, fatalError: 2 },
  }, null, 2)}\n`;
}

async function expectedSnapshots() {
  const cliArgs = await readFile(resolve(ROOT, "cmd/main/args.mbt"), "utf8");
  return new Map([
    [
      "wasm-exports.txt",
      extractWasmExports(await readFile(resolve(ROOT, "wasm/moon.pkg"), "utf8")),
    ],
    [
      "typescript-api.d.ts",
      normalizeText(await readFile(resolve(ROOT, "wasm/moonparse.d.ts"), "utf8")),
    ],
    [
      "cli-help.txt",
      extractCliHelp(cliArgs),
    ],
    [
      "cli-exit-codes.json",
      extractCliExitCodes(cliArgs, await readFile(resolve(ROOT, "cmd/main/main.mbt"), "utf8")),
    ],
  ]);
}

function firstDifference(actual, expected) {
  const a = actual.split("\n");
  const e = expected.split("\n");
  const count = Math.max(a.length, e.length);
  for (let index = 0; index < count; index += 1) {
    if (a[index] !== e[index]) {
      return `line ${index + 1}: expected ${JSON.stringify(e[index] ?? "<EOF>")}, got ${JSON.stringify(a[index] ?? "<EOF>")}`;
    }
  }
  return "unknown difference";
}

export async function updateSnapshots({ write = false } = {}) {
  const expected = await expectedSnapshots();
  const errors = [];
  for (const [name, content] of expected) {
    const path = resolve(SNAPSHOT_DIR, name);
    if (write) {
      await writeFile(path, content, "utf8");
      continue;
    }
    let actual;
    try {
      actual = normalizeText(await readFile(path, "utf8"));
    } catch (error) {
      if (error?.code === "ENOENT") {
        errors.push(`${name}: snapshot is missing; run with --write`);
        continue;
      }
      throw error;
    }
    if (actual !== content) errors.push(`${name}: ${firstDifference(actual, content)}`);
  }
  return errors;
}

async function main() {
  const write = process.argv.includes("--write");
  const errors = await updateSnapshots({ write });
  if (write) {
    console.log("MoonParse API snapshots updated.");
  } else if (errors.length) {
    console.error("MoonParse API snapshots are stale:");
    for (const error of errors) console.error(`- ${error}`);
    process.exitCode = 1;
  } else {
    console.log("MoonParse API snapshots OK.");
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.stack : String(error));
    process.exitCode = 1;
  });
}
