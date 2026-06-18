#!/usr/bin/env node

import { access, readFile, readdir } from "node:fs/promises";
import { dirname, extname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const ignored = new Set([".git", "_build", "build", "dist", "node_modules", "out"]);
const markdown = [];

async function walk(dir) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    if (entry.isDirectory() && (ignored.has(entry.name) || pathIsArchived(resolve(dir, entry.name)))) continue;
    const path = resolve(dir, entry.name);
    if (entry.isDirectory()) await walk(path);
    else if (entry.isFile() && extname(entry.name).toLowerCase() === ".md") markdown.push(path);
  }
}

function pathIsArchived(path) {
  return path === resolve(ROOT, "todo/old");
}

await walk(ROOT);
const errors = [];

const [rootReadme, packageReadme] = await Promise.all([
  readFile(resolve(ROOT, "README.md"), "utf8"),
  readFile(resolve(ROOT, "README.mbt.md"), "utf8"),
]);
function firstMoonBitExample(source) {
  return source.match(/```moonbit[^\r\n]*\r?\n([\s\S]*?)```/)?.[1]?.replace(/\r\n/g, "\n").trim();
}
const rootExample = firstMoonBitExample(rootReadme);
const packageExample = firstMoonBitExample(packageReadme);
if (!rootExample || !packageExample || rootExample !== packageExample) {
  errors.push("README.md and README.mbt.md must share the same first MoonBit API example");
}

for (const file of markdown) {
  const source = await readFile(file, "utf8");
  for (const match of source.matchAll(/\[[^\]]*\]\(([^)]+)\)/g)) {
    let target = match[1].trim();
    if (!target || target.startsWith("#") || /^[a-z][a-z0-9+.-]*:/i.test(target)) continue;
    if (target.startsWith("<") && target.endsWith(">")) target = target.slice(1, -1);
    target = target.split("#", 1)[0].split("?", 1)[0];
    if (!target) continue;
    try {
      target = decodeURIComponent(target);
    } catch (_) {
      errors.push(`${file}: invalid URL encoding in ${match[1]}`);
      continue;
    }
    const absolute = target.startsWith("/")
      ? resolve(ROOT, target.slice(1))
      : resolve(dirname(file), target);
    try {
      await access(absolute);
    } catch (_) {
      errors.push(`${file}: missing local link target ${match[1]}`);
    }
  }
}

if (errors.length) {
  console.error("MoonParse documentation link check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}
console.log(`MoonParse documentation links OK (${markdown.length} Markdown files).`);
