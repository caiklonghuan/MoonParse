#!/usr/bin/env node

import { readFileSync, readdirSync } from "node:fs";
import { resolve, relative, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = resolve(fileURLToPath(new URL("../..", import.meta.url)));
const defaultConfig = resolve(root, "evidence/control/warning-exceptions.contract.json");
const ignoredDirectories = new Set([".git", ".moon", "_build", "build", "dist", "node_modules", "out"]);
const declarationLine = /^\s*declare\s+(?:pub\s+)?/;

function pathFromRoot(path) {
  return relative(root, path).split(sep).join("/");
}

function moonBitFiles(directory = root) {
  const files = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      if (!ignoredDirectories.has(entry.name)) files.push(...moonBitFiles(resolve(directory, entry.name)));
    } else if (entry.isFile() && entry.name.endsWith(".mbt")) {
      files.push(resolve(directory, entry.name));
    }
  }
  return files.sort();
}

function fail(message) {
  throw new Error(`declaration-scope: ${message}`);
}

export function readContractException(configPath = defaultConfig) {
  let config;
  try {
    config = JSON.parse(readFileSync(configPath, "utf8"));
  } catch (error) {
    fail(`cannot read ${pathFromRoot(configPath)}: ${error instanceof Error ? error.message : String(error)}`);
  }
  if (config.schema_version !== 1 || !Array.isArray(config.allowed) || config.allowed.length !== 1) {
    fail("requires schema_version 1 and exactly one allowed exception");
  }
  if (config.release_policy !== "reject_all_exceptions" || config.forbid_additional_paths !== true || config.forbid_additional_warning_codes !== true) {
    fail("requires the frozen reject-all release policy and extension guards");
  }
  const [exception] = config.allowed;
  const expectedPaths = ["compiler/spec.mbt", "spec.mbt"];
  const paths = Array.isArray(exception.paths) ? [...exception.paths].sort() : [];
  const profiles = Array.isArray(exception.profiles) ? [...exception.profiles].sort() : [];
  if (
    exception.warning_code !== 68 ||
    exception.warning_name !== "declaration_unimplemented" ||
    exception.expiry_work_package !== "M2-C12" ||
    JSON.stringify(paths) !== JSON.stringify(expectedPaths) ||
    JSON.stringify(profiles) !== JSON.stringify(["nightly", "pr"])
  ) {
    fail("does not match the frozen warning-68 scope, profiles, paths, and expiry");
  }
  return { paths: new Set(paths), profiles: new Set(profiles) };
}

export function declarationsInRepository(directory = root) {
  const declarations = [];
  for (const file of moonBitFiles(directory)) {
    const source = readFileSync(file, "utf8");
    source.split(/\r?\n/).forEach((line, index) => {
      if (declarationLine.test(line)) declarations.push({ path: pathFromRoot(file), line: index + 1 });
    });
  }
  return declarations;
}

export function verifyDeclarationScope({ configPath = defaultConfig, profile = "pr", directory = root } = {}) {
  if (!["pr", "nightly", "release"].includes(profile)) fail(`unsupported profile ${profile}`);
  const exception = readContractException(configPath);
  if (profile === "release") fail("release rejects every warning exception");
  if (!exception.profiles.has(profile)) fail(`profile ${profile} is not allowed by the exception`);
  const declarations = declarationsInRepository(directory);
  const unexpected = declarations.filter(({ path }) => !exception.paths.has(path));
  const missing = [...exception.paths].filter((path) => !declarations.some((entry) => entry.path === path));
  if (unexpected.length > 0 || missing.length > 0) {
    const details = [
      ...unexpected.map(({ path, line }) => `unexpected ${path}:${line}`),
      ...missing.map((path) => `missing ${path}`),
    ];
    fail(details.join(", "));
  }
  return {
    schema_version: 1,
    profile,
    warning_code: 68,
    allowed_paths: [...exception.paths].sort(),
    declarations: declarations.sort((left, right) => left.path.localeCompare(right.path) || left.line - right.line),
    moon_args: ["--warn-list", "-68"],
  };
}

function parseArgs(argv) {
  let configPath = defaultConfig;
  let profile = "pr";
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (flag === "--config") configPath = resolve(root, value);
    else if (flag === "--profile") profile = value;
    else fail("usage: declaration-scope.mjs [--config <path>] [--profile <pr|nightly|release>]");
  }
  return { configPath, profile };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  try {
    process.stdout.write(`${JSON.stringify(verifyDeclarationScope(parseArgs(process.argv.slice(2))), null, 2)}\n`);
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}
