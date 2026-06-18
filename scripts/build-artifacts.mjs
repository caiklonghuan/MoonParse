#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { access, copyFile, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { constants } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const check = process.argv.includes("--check");

function commandPath() {
  if (process.env.MOON_BIN) return process.env.MOON_BIN;
  return process.platform === "win32"
    ? resolve(process.env.USERPROFILE ?? "", ".moon/bin/moon.exe")
    : "moon";
}

function run(command, args) {
  const result = spawnSync(command, args, { cwd: ROOT, stdio: "inherit" });
  if (result.status !== 0) throw new Error(`${command} ${args.join(" ")} failed (${result.status})`);
}

async function sha256(path) {
  return createHash("sha256").update(await readFile(path)).digest("hex");
}

async function gitCommit() {
  try {
    const head = (await readFile(resolve(ROOT, ".git/HEAD"), "utf8")).trim();
    if (/^[0-9a-f]{40}$/i.test(head)) return head;
    if (head.startsWith("ref: ")) {
      const ref = head.slice(5);
      const hash = (await readFile(resolve(ROOT, ".git", ref), "utf8")).trim();
      if (/^[0-9a-f]{40}$/i.test(hash)) return hash;
    }
  } catch (_) {
    // Fall back to Git for worktrees and packed references.
  }
  const candidates = process.platform === "win32"
    ? ["git.exe", "C:\\Program Files\\Git\\cmd\\git.exe", resolve(process.env.LOCALAPPDATA ?? "", "Programs/Git/cmd/git.exe")]
    : ["git"];
  for (const git of candidates) {
    const result = spawnSync(git, ["rev-parse", "HEAD"], { cwd: ROOT, encoding: "utf8" });
    if (result.status === 0) return result.stdout.trim();
  }
  return "unknown";
}

async function assembleNpmDistribution() {
  const dist = resolve(ROOT, "wasm/dist");
  await rm(dist, { recursive: true, force: true });
  await mkdir(dist, { recursive: true });
  for (const file of ["package.json", "README.md", "moonparse.js", "moonparse.d.ts", "moonparse.wasm", "build-info.json"]) {
    await copyFile(resolve(ROOT, "wasm", file), resolve(dist, file));
  }
}

export async function buildArtifacts() {
  const moon = commandPath();
  await access(moon, constants.X_OK).catch(() => {
    if (moon !== "moon") throw new Error(`MoonBit executable not found: ${moon}`);
  });
  run(process.execPath, ["scripts/embed-language-packs.mjs", "--check"]);
  run(moon, ["build", "--target", "wasm-gc", "--release", "wasm"]);

  const generated = resolve(ROOT, "_build/wasm-gc/release/build/wasm/wasm.wasm");
  const published = resolve(ROOT, "wasm/moonparse.wasm");
  await access(generated, constants.R_OK);
  await access(resolve(ROOT, "wasm/moonparse.js"), constants.R_OK);
  await access(resolve(ROOT, "wasm/moonparse.d.ts"), constants.R_OK);

  if (check) {
    const [expected, actual] = await Promise.all([sha256(generated), sha256(published)]);
    if (expected !== actual) {
      throw new Error("wasm/moonparse.wasm is stale; run npm run build and commit it");
    }
  } else {
    await copyFile(generated, published);
    const version = (await readFile(resolve(ROOT, "VERSION"), "utf8")).trim();
    const buildInfo = {
      schemaVersion: 1,
      softwareVersion: version,
      parseTableSchemaVersion: 4,
      commit: await gitCommit(),
    };
    await writeFile(resolve(ROOT, "wasm/build-info.json"), `${JSON.stringify(buildInfo, null, 2)}\n`);
    await assembleNpmDistribution();
    run(process.execPath, ["website/scripts/sync-runtime.mjs"]);
  }
  console.log(`MoonParse WASM artifact ${check ? "is fresh" : "was built"}.`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  buildArtifacts().catch((error) => {
    console.error(error instanceof Error ? error.stack : String(error));
    process.exitCode = 1;
  });
}
