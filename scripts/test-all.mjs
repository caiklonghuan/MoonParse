#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const windows = process.platform === "win32";
const moon = process.env.MOON_BIN ?? (windows
  ? resolve(process.env.USERPROFILE ?? "", ".moon/bin/moon.exe")
  : "moon");
const npmCli = resolve(dirname(process.execPath), "node_modules/npm/bin/npm-cli.js");
const npm = existsSync(npmCli) ? [process.execPath, npmCli] : [windows ? "npm.cmd" : "npm"];

function run(command, args, cwd = root) {
  console.log(`\n> ${command} ${args.join(" ")}`);
  const result = spawnSync(command, args, { cwd, stdio: "inherit" });
  if (result.status !== 0) process.exit(result.status ?? 1);
}

function runNpm(args, cwd = root) {
  run(npm[0], [...npm.slice(1), ...args], cwd);
}

run(moon, ["check"]);
run(moon, ["test"]);
run(moon, ["fmt", "--check"]);
run(moon, ["info"]);
runNpm(["run", "test:scripts"]);
for (const script of ["check-boundaries.mjs", "api-snapshots.mjs", "check-wasm-abi.mjs", "compat-fixtures.mjs", "embed-language-packs.mjs", "version.mjs", "check-docs.mjs"]) {
  run(process.execPath, [`scripts/${script}`, ...(script === "api-snapshots.mjs" || script === "version.mjs" ? ["--check"] : [])]);
}
run(process.execPath, ["scripts/build-artifacts.mjs", "--check"]);
run(moon, ["test", "wasm"]);
run(process.execPath, ["examples/api_smoke/node-smoke.mjs"]);
runNpm(["run", "build"], resolve(root, "lsp"));
runNpm(["test"], resolve(root, "lsp"));
runNpm(["run", "test:corpus"], resolve(root, "website"));
runNpm(["run", "build"], resolve(root, "website"));
runNpm(["run", "test:smoke"], resolve(root, "website"));
