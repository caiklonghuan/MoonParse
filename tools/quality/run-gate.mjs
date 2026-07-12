#!/usr/bin/env node

import { execFileSync, spawnSync } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { verifyDeclarationScope } from "./declaration-scope.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const moon = process.env.MOON_BIN ?? (process.platform === "win32" ? resolve(process.env.USERPROFILE ?? "", ".moon/bin/moon.exe") : "moon");

function parseArgs(argv) {
  const [gate, ...rest] = argv;
  if (!gate || !/^V\d\d$/.test(gate)) throw new Error("usage: run-gate.mjs <V-ID> --profile <pr|nightly|release>");
  if (rest.length !== 2 || rest[0] !== "--profile" || !["pr", "nightly", "release"].includes(rest[1])) throw new Error("--profile <pr|nightly|release> is required");
  return { gate, profile: rest[1] };
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function git(args) {
  return execFileSync("git", args, { cwd: root, encoding: "utf8" }).trim();
}

function commandsFor(gate, profile) {
  if (gate === "V00") return [[process.execPath, [resolve(root, "tools/quality/history-verify.mjs"), "--profile", profile]]];
  const exception = profile === "release" ? null : verifyDeclarationScope({ profile });
  const warningArgs = exception?.moon_args ?? [];
  const declarationScope = [process.execPath, [resolve(root, "tools/quality/declaration-scope.mjs"), "--profile", profile]];
  if (gate === "V01") return [
    [moon, ["version", "--all"]],
    declarationScope,
    [moon, ["check", "--target", "all", "--deny-warn", ...warningArgs, "--frozen"]],
    [moon, ["build", "--target", "all", "--deny-warn", ...warningArgs, "--frozen"]],
    [moon, ["test", "--target", "all", "--deny-warn", ...warningArgs, "--frozen"]],
    [moon, ["fmt", "--check"]],
    [moon, ["info", "--target", "all", "--frozen"]],
    ["git", ["diff", "--exit-code"]],
  ];
  if (gate === "V02") return [
    declarationScope,
    [moon, ["check", "spec.mbt", "compiler/spec.mbt", "--target", "all", "--deny-warn", ...warningArgs, "--frozen"]],
    [moon, ["check", "tests/contracts", "--target", "all", "--deny-warn", ...warningArgs, "--frozen"]],
  ];
  throw new Error(`gate ${gate} is not implemented yet`);
}

function normalizedExitCode(status) {
  return Number.isInteger(status) && status >= 0 && status <= 255 ? status : 1;
}

async function main() {
  const { gate, profile } = parseArgs(process.argv.slice(2));
  const candidate = git(["rev-parse", "HEAD"]);
  const startedAt = new Date().toISOString();
  const commands = commandsFor(gate, profile);
  const results = [];
  for (const [command, args] of commands) {
    const result = spawnSync(command, args, { cwd: root, encoding: "utf8" });
    results.push({ command: [command, ...args], result });
    if (result.error || normalizedExitCode(result.status) !== 0) break;
  }
  const stdout = results.map(({ command, result }) => `> ${command.join(" ")}\n${result.stdout ?? ""}`).join("\n");
  const stderr = results.map(({ command, result }) => `> ${command.join(" ")}\n${result.stderr ?? ""}`).join("\n");
  const exitCode = normalizedExitCode(results.at(-1)?.result.status);
  const receiptDir = resolve(root, "_build", "evidence", candidate, gate);
  await mkdir(receiptDir, { recursive: true });
  await writeFile(resolve(receiptDir, "stdout.log"), stdout, "utf8");
  await writeFile(resolve(receiptDir, "stderr.log"), stderr, "utf8");
  const receipt = {
    schema_version: 1,
    gate,
    profile,
    candidate_sha: candidate,
    started_at: startedAt,
    finished_at: new Date().toISOString(),
    commands: results.map(({ command }) => command),
    exit_code: exitCode,
    worktree_dirty: git(["status", "--porcelain=v1"]).split("\n").filter(Boolean).length > 0,
    stdout_sha256: sha256(stdout),
    stderr_sha256: sha256(stderr),
  };
  await writeFile(resolve(receiptDir, "receipt.json"), `${JSON.stringify(receipt, null, 2)}\n`, "utf8");
  process.stdout.write(`${JSON.stringify(receipt, null, 2)}\n`);
  if (results.at(-1)?.result.error) throw results.at(-1).result.error;
  if (exitCode !== 0) process.exitCode = exitCode;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.stack : String(error));
    process.exitCode = 1;
  });
}
