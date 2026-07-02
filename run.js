#!/usr/bin/env node
// MoonParse CLI runner for the wasm-gc target.
//
// Usage:
//   node run.js <command> [args...]
//
// Build the wasm binary first:
//   moon build --target wasm-gc --release

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const WASM_PATH = path.join(
  __dirname,
  "_build/wasm-gc/release/build/cmd/main/main.wasm",
);

function normalizePath(value) {
  return value.split(path.sep).join("/");
}

function listFiles(pathStr) {
  const root = path.resolve(pathStr);
  const outputRoot = path.isAbsolute(pathStr) ? root : pathStr;
  const files = [];

  function walk(current) {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const full = path.join(current, entry.name);
      if (entry.isDirectory()) {
        walk(full);
      } else if (entry.isFile()) {
        const relative = path.relative(root, full);
        files.push(normalizePath(path.join(outputRoot, relative)));
      }
    }
  }

  walk(root);
  files.sort();
  return files;
}

function atomicWriteString(pathStr, contentStr) {
  const resolved = path.resolve(pathStr);
  const dir = path.dirname(resolved);
  const temp = path.join(dir, `.${path.basename(pathStr)}.${process.pid}.tmp`);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(temp, contentStr, "utf8");
  fs.renameSync(temp, resolved);
}

function runCommand(cwd, command) {
  const result = spawnSync(command, {
    cwd: cwd && cwd.length > 0 ? cwd : process.cwd(),
    shell: true,
    stdio: "inherit",
    env: process.env,
  });
  if (result.error) {
    return result.error.message;
  }
  if (result.status === 0) {
    return "";
  }
  return `command exited with status ${result.status}: ${command}`;
}

const __moonbit_fs_unstable = {
  begin_create_string: () => ({ s: "" }),
  string_append_char: (h, ch) => {
    h.s += String.fromCharCode(ch);
  },
  finish_create_string: (h) => h.s,

  begin_read_string: (s) => ({ s, i: 0 }),
  string_read_char: (h) =>
    h.i >= h.s.length ? -1 : h.s.charCodeAt(h.i++),
  finish_read_string: (_h) => undefined,

  begin_read_byte_array: (arr) => ({ arr, i: 0 }),
  byte_array_read_byte: (h) =>
    h.i >= h.arr.length ? -1 : h.arr[h.i++],
  finish_read_byte_array: (_h) => undefined,

  begin_create_byte_array: () => ({ arr: [] }),
  byte_array_append_byte: (h, b) => {
    h.arr.push(b & 0xff);
  },
  finish_create_byte_array: (h) => new Uint8Array(h.arr),

  begin_read_string_array: (arr) => ({ arr, i: 0 }),
  string_array_read_string: (h) => {
    if (h.i >= h.arr.length) return "ffi_end_of_/string_array";
    return h.arr[h.i++];
  },
  finish_read_string_array: (_h) => undefined,

  array_len: (arr) => arr.length,
  array_get: (arr, i) => arr[i],
  jsvalue_is_string: (v) => (typeof v === "string" ? 1 : 0),

  env_get_var: (key) => process.env[key] || "",
  args_get: () => ["moonparse", ...process.argv.slice(2)],

  read_file_to_bytes: (pathStr) => {
    try {
      return new Uint8Array(fs.readFileSync(pathStr));
    } catch (_e) {
      return new Uint8Array(0);
    }
  },

  write_string_to_file: (pathStr, contentStr) => {
    try {
      fs.mkdirSync(path.dirname(path.resolve(pathStr)), { recursive: true });
      fs.writeFileSync(pathStr, contentStr, "utf8");
      return 0;
    } catch (_e) {
      return 1;
    }
  },

  atomic_write_string_to_file: (pathStr, contentStr) => {
    try {
      atomicWriteString(pathStr, contentStr);
      return 0;
    } catch (_e) {
      return 1;
    }
  },

  write_bytes_to_file: (pathStr, data) => {
    try {
      fs.mkdirSync(path.dirname(path.resolve(pathStr)), { recursive: true });
      fs.writeFileSync(pathStr, data);
      return 0;
    } catch (_e) {
      return 1;
    }
  },

  list_files: (pathStr) => {
    try {
      return listFiles(pathStr);
    } catch (e) {
      return [`ffi_error:${e?.message || String(e)}`];
    }
  },

  run_command: (cwd, command) => runCommand(cwd, command),

  create_dir_all: (pathStr) => {
    try {
      fs.mkdirSync(pathStr, { recursive: true });
      return 0;
    } catch (_e) {
      return 1;
    }
  },

  remove_dir_all: (pathStr) => {
    try {
      fs.rmSync(pathStr, { recursive: true, force: true });
      return 0;
    } catch (_e) {
      return 1;
    }
  },
};

let stdinBuf = null;
let stdinPos = 0;

function readStdin() {
  if (stdinBuf !== null) return;
  if (process.stdin.isTTY) {
    stdinBuf = new Uint8Array(0);
    return;
  }
  try {
    stdinBuf = new Uint8Array(fs.readFileSync(0));
  } catch (_e) {
    stdinBuf = new Uint8Array(0);
  }
}

const __moonbit_io_unstable = {
  read_char: () => {
    readStdin();
    if (stdinPos >= stdinBuf.length) return -1;
    return stdinBuf[stdinPos++];
  },
  read_bytes_from_stdin: () => {
    readStdin();
    const rest = stdinBuf.slice(stdinPos);
    stdinPos = stdinBuf.length;
    return rest;
  },
  write_char: (ch) => process.stdout.write(String.fromCharCode(ch)),
  flush: () => undefined,
};

const wasi_snapshot_preview1 = {
  proc_exit: (code) => process.exit(code),
};

const spectest = {
  print_char: (ch) => process.stdout.write(String.fromCharCode(ch)),
};

async function main() {
  if (!fs.existsSync(WASM_PATH)) {
    process.stderr.write(
      `Error: wasm binary not found at:\n  ${WASM_PATH}\nRun: moon build --target wasm-gc --release\n`,
    );
    process.exit(1);
  }

  const wasmBytes = fs.readFileSync(WASM_PATH);
  const importObject = {
    __moonbit_fs_unstable,
    __moonbit_io_unstable,
    wasi_snapshot_preview1,
    spectest,
  };

  try {
    const { instance } = await WebAssembly.instantiate(wasmBytes, importObject);
    const start = instance.exports._start;
    if (typeof start !== "function") {
      process.stderr.write("Error: no _start export found in wasm binary\n");
      process.exit(1);
    }
    start();
  } catch (e) {
    if (e && e.message && e.message.includes("unreachable")) {
      process.exit(1);
    }
    process.stderr.write(`Error: ${e.message || e}\n`);
    process.exit(1);
  }
}

main();
