#!/usr/bin/env node

import { readFile, readdir } from "node:fs/promises";
import { dirname, relative, resolve, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const DEFAULT_ROOT = resolve(SCRIPT_DIR, "..");

function toPosix(path) {
  return path.split(sep).join("/");
}

async function findPackageFiles(root, ignored) {
  const result = [];
  async function visit(dir) {
    for (const entry of await readdir(dir, { withFileTypes: true })) {
      if (entry.isDirectory() && ignored.has(entry.name)) continue;
      const full = resolve(dir, entry.name);
      if (entry.isDirectory()) await visit(full);
      else if (entry.isFile() && entry.name === "moon.pkg") result.push(full);
    }
  }
  await visit(root);
  return result;
}

export function extractProjectImports(source, modulePrefix) {
  const imports = new Set();
  const quoted = /"([^"]+)"/g;
  for (const match of source.matchAll(quoted)) {
    const value = match[1];
    if (value === modulePrefix) imports.add(".");
    else if (value.startsWith(`${modulePrefix}/`)) {
      imports.add(value.slice(modulePrefix.length + 1));
    }
  }
  return [...imports].sort();
}

export function detectCycles(graph) {
  const visiting = new Set();
  const visited = new Set();
  const stack = [];
  const cycles = [];

  function visit(node) {
    if (visiting.has(node)) {
      const start = stack.indexOf(node);
      cycles.push([...stack.slice(start), node]);
      return;
    }
    if (visited.has(node)) return;
    visiting.add(node);
    stack.push(node);
    for (const next of graph.get(node) ?? []) visit(next);
    stack.pop();
    visiting.delete(node);
    visited.add(node);
  }

  for (const node of graph.keys()) visit(node);
  return cycles;
}

export async function checkBoundaries({ root = DEFAULT_ROOT, configPath } = {}) {
  const absoluteRoot = resolve(root);
  const boundaryPath = resolve(configPath ?? resolve(absoluteRoot, "api/boundaries.json"));
  const config = JSON.parse(await readFile(boundaryPath, "utf8"));
  const registered = config.packages;
  const ignored = new Set(config.ignoredDirectories ?? []);
  const packageFiles = await findPackageFiles(absoluteRoot, ignored);
  const discovered = new Map();
  const errors = [];

  for (const file of packageFiles) {
    const relDir = toPosix(relative(absoluteRoot, dirname(file))) || ".";
    discovered.set(
      relDir,
      extractProjectImports(await readFile(file, "utf8"), config.modulePrefix),
    );
  }

  for (const path of discovered.keys()) {
    if (!registered[path]) errors.push(`unregistered MoonBit package: ${path}`);
  }
  for (const path of Object.keys(registered)) {
    if (!discovered.has(path)) errors.push(`registered package is missing moon.pkg: ${path}`);
  }

  for (const [path, imports] of discovered) {
    const spec = registered[path];
    if (!spec) continue;
    const allowed = new Set(spec.allow ?? []);
    for (const target of imports) {
      if (!registered[target]) {
        errors.push(`${path} imports unknown project package ${target}`);
      } else if (!allowed.has(target)) {
        errors.push(
          `${path} (${spec.layer}) may not import ${target}; allowed: ${[...allowed].join(", ") || "none"}`,
        );
      }
    }
  }

  const graph = new Map(
    [...discovered].map(([path, imports]) => [
      path,
      imports.filter((target) => discovered.has(target)),
    ]),
  );
  for (const cycle of detectCycles(graph)) {
    errors.push(`dependency cycle: ${cycle.join(" -> ")}`);
  }

  return { errors, packageCount: discovered.size, graph };
}

async function main() {
  const rootArg = process.argv.find((arg) => arg.startsWith("--root="));
  const configArg = process.argv.find((arg) => arg.startsWith("--config="));
  const result = await checkBoundaries({
    root: rootArg ? rootArg.slice("--root=".length) : DEFAULT_ROOT,
    configPath: configArg ? configArg.slice("--config=".length) : undefined,
  });
  if (result.errors.length) {
    console.error("MoonParse dependency boundary check failed:");
    for (const error of result.errors) console.error(`- ${error}`);
    process.exitCode = 1;
  } else {
    console.log(`MoonParse dependency boundaries OK (${result.packageCount} packages).`);
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.stack : String(error));
    process.exitCode = 1;
  });
}

