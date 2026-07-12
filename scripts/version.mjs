#!/usr/bin/env node

import { readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
async function readVersion() {
  const version = (await readFile(resolve(ROOT, "VERSION"), "utf8")).trim();
  if (!/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/.test(version)) {
    throw new Error(`VERSION is not valid SemVer: ${version}`);
  }
  return version;
}

function withJsonVersion(text, version) {
  const value = JSON.parse(text);
  value.version = version;
  if (value.packages?.[""]?.version !== undefined) value.packages[""].version = version;
  return `${JSON.stringify(value, null, 2)}\n`;
}

function withMoonModVersion(text, version) {
  return replaceRequired(text, /^(version\s*=\s*)"[^"]+"/m, `$1"${version}"`, "moon.mod");
}

function replaceRequired(text, pattern, replacement, label) {
  if (!pattern.test(text)) throw new Error(`cannot find version field in ${label}`);
  return text.replace(pattern, replacement);
}

export async function expectedVersionFiles() {
  const version = await readVersion();
  const files = new Map();
  const jsonPaths = [
    "package.json",
    "wasm/package.json",
    "lsp/package.json",
    "lsp/package-lock.json",
    "website/package.json",
    "website/package-lock.json",
  ];
  for (const path of jsonPaths) {
    const source = await readFile(resolve(ROOT, path), "utf8");
    files.set(path, withJsonVersion(source, version));
  }
  const moonModPath = "moon.mod";
  files.set(moonModPath, withMoonModVersion(await readFile(resolve(ROOT, moonModPath), "utf8"), version));
  const manifestPath = "api/snapshots/api-manifest.json";
  const manifest = JSON.parse(await readFile(resolve(ROOT, manifestPath), "utf8"));
  manifest.softwareVersion = version;
  files.set(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

  const buildInfoPath = "wasm/build-info.json";
  const buildInfo = JSON.parse(await readFile(resolve(ROOT, buildInfoPath), "utf8"));
  buildInfo.softwareVersion = version;
  files.set(buildInfoPath, `${JSON.stringify(buildInfo, null, 2)}\n`);

  const wasmPath = "wasm/wasm.mbt";
  files.set(
    wasmPath,
    replaceRequired(
      await readFile(resolve(ROOT, wasmPath), "utf8"),
      /(pub fn moonparse_version\(\) -> String \{\s*\n\s*)"[^"]+"/,
      `$1"${version}"`,
      wasmPath,
    ),
  );
  const cliPath = "cmd/main/main.mbt";
  files.set(
    cliPath,
    replaceRequired(
      await readFile(resolve(ROOT, cliPath), "utf8"),
      /print_info\("moonparse [^"]+"\)/,
      `print_info("moonparse ${version}")`,
      cliPath,
    ),
  );
  const lspVersionPath = "lsp/src/version.ts";
  files.set(
    lspVersionPath,
    replaceRequired(
      await readFile(resolve(ROOT, lspVersionPath), "utf8"),
      /MOONPARSE_VERSION = "[^"]+"/,
      `MOONPARSE_VERSION = "${version}"`,
      lspVersionPath,
    ),
  );
  const languagePackVersionPath = "grammars/language_packs.mbt";
  files.set(
    languagePackVersionPath,
    replaceRequired(
      await readFile(resolve(ROOT, languagePackVersionPath), "utf8"),
      /language_pack_software_version : String = "[^"]+"/,
      `language_pack_software_version : String = "${version}"`,
      languagePackVersionPath,
    ),
  );
  const languagePackTypesPath = "languagepack/types.mbt";
  files.set(
    languagePackTypesPath,
    replaceRequired(
      await readFile(resolve(ROOT, languagePackTypesPath), "utf8"),
      /software_version: "[^"]+", known_scanners: \[\]/,
      `software_version: "${version}", known_scanners: []`,
      languagePackTypesPath,
    ),
  );
  return { version, files };
}

export async function syncVersion({ write = false } = {}) {
  const { version, files } = await expectedVersionFiles();
  const stale = [];
  for (const [path, expected] of files) {
    const actual = (await readFile(resolve(ROOT, path), "utf8")).replace(/\r\n/g, "\n");
    if (actual !== expected.replace(/\r\n/g, "\n")) {
      stale.push(path);
      if (write) await writeFile(resolve(ROOT, path), expected, "utf8");
    }
  }
  return { version, stale };
}

async function main() {
  const write = process.argv.includes("--write");
  const { version, stale } = await syncVersion({ write });
  if (write) {
    console.log(`MoonParse version ${version} synchronized (${stale.length} file(s) updated).`);
  } else if (stale.length) {
    console.error(`MoonParse version ${version} is not synchronized:`);
    for (const path of stale) console.error(`- ${path}`);
    process.exitCode = 1;
  } else {
    console.log(`MoonParse version ${version} is synchronized.`);
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.stack : String(error));
    process.exitCode = 1;
  });
}
