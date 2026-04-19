#!/usr/bin/env node
// run.js — MoonParse CLI runner for the wasm-gc target
//
// Usage:
//   node run.js <command> [args...]
//
// Examples:
//   node run.js help
//   node run.js check test.grammar
//   node run.js parse test.grammar < source.txt
//   node run.js generate test.grammar -o ./out
//
// Build the wasm binary first:
//   moon build --target wasm-gc

'use strict';

const fs   = require('fs');
const path = require('path');

const WASM_PATH = path.join(__dirname, '_build/wasm-gc/debug/build/cmd/main/main.wasm');

// ─── __moonbit_fs_unstable ────────────────────────────────────────────────────
// Mirrors the string/byte helpers built into moonrun, and ADDS file I/O.

const __moonbit_fs_unstable = {
  // String creation
  begin_create_string:  ()        => ({ s: '' }),
  string_append_char:   (h, ch)   => { h.s += String.fromCharCode(ch); },
  finish_create_string: (h)       => h.s,

  // String reading
  begin_read_string:    (s)       => ({ s, i: 0 }),
  string_read_char:     (h)       => h.i >= h.s.length ? -1 : h.s.charCodeAt(h.i++),
  finish_read_string:   (_h)      => undefined,

  // Byte array reading
  begin_read_byte_array:  (arr)   => ({ arr, i: 0 }),
  byte_array_read_byte:   (h)     => h.i >= h.arr.length ? -1 : h.arr[h.i++],
  finish_read_byte_array: (_h)    => undefined,

  // Byte array creation
  begin_create_byte_array:  ()        => ({ arr: [] }),
  byte_array_append_byte:   (h, b)    => { h.arr.push(b & 0xff); },
  finish_create_byte_array: (h)       => new Uint8Array(h.arr),

  // String array reading  (used by @env.args())
  begin_read_string_array:  (arr)  => ({ arr, i: 0 }),
  string_array_read_string: (h)    => {
    if (h.i >= h.arr.length) return 'ffi_end_of_/string_array';
    return h.arr[h.i++];
  },
  finish_read_string_array: (_h)   => undefined,

  // Misc
  array_len:       (arr)     => arr.length,
  array_get:       (arr, i)  => arr[i],
  jsvalue_is_string:(v)      => typeof v === 'string' ? 1 : 0,

  // Env / args
  env_get_var: (key) => process.env[key] || '',
  // Return argv[0] as "moonparse" so the MoonBit main can skip it with all_args[1:]
  args_get:    ()    => ['moonparse', ...process.argv.slice(2)],

  // ── FILE I/O (added by run.js; not provided by moonrun) ──────────────────

  read_file_to_bytes: (pathStr) => {
    try {
      return new Uint8Array(fs.readFileSync(pathStr));
    } catch (_e) {
      return new Uint8Array(0);
    }
  },

  // Returns 0 on success, 1 on error
  write_string_to_file: (pathStr, contentStr) => {
    try {
      fs.mkdirSync(path.dirname(path.resolve(pathStr)), { recursive: true });
      fs.writeFileSync(pathStr, contentStr, 'utf8');
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

  create_dir_all: (pathStr) => {
    try { fs.mkdirSync(pathStr, { recursive: true }); return 0; }
    catch (_e) { return 1; }
  },

  remove_dir_all: (pathStr) => {
    try { fs.rmSync(pathStr, { recursive: true, force: true }); return 0; }
    catch (_e) { return 1; }
  },
};

// ─── __moonbit_io_unstable ────────────────────────────────────────────────────

let _stdinBuf = null;
let _stdinPos = 0;

function _readStdin() {
  if (_stdinBuf !== null) return;
  if (process.stdin.isTTY) {
    _stdinBuf = new Uint8Array(0);
    return;
  }
  try { _stdinBuf = new Uint8Array(fs.readFileSync(0)); }
  catch (_e) { _stdinBuf = new Uint8Array(0); }
}

const __moonbit_io_unstable = {
  read_char: () => {
    _readStdin();
    if (_stdinPos >= _stdinBuf.length) return -1;
    return _stdinBuf[_stdinPos++];
  },
  read_bytes_from_stdin: () => {
    _readStdin();
    const rest = _stdinBuf.slice(_stdinPos);
    _stdinPos = _stdinBuf.length;
    return rest;
  },
  write_char: (ch) => process.stdout.write(String.fromCharCode(ch)),
  flush:      ()   => { /* stdout auto-flushes in Node.js */ },
};

// ─── wasi_snapshot_preview1 ──────────────────────────────────────────────────

const wasi_snapshot_preview1 = {
  proc_exit: (code) => process.exit(code),
};

// ─── spectest (MoonBit uses this for print output) ───────────────────────────

const spectest = {
  print_char: (ch) => process.stdout.write(String.fromCharCode(ch)),
};

// ─── Load and run ─────────────────────────────────────────────────────────────

async function main() {
  if (!fs.existsSync(WASM_PATH)) {
    process.stderr.write(
      `Error: wasm binary not found at:\n  ${WASM_PATH}\nRun: moon build --target wasm-gc\n`
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
    if (typeof start !== 'function') {
      process.stderr.write('Error: no _start export found in wasm binary\n');
      process.exit(1);
    }
    start();
  } catch (e) {
    // proc_exit(0) causes process.exit(0) before reaching here.
    // Non-zero exits are already handled inside proc_exit.
    // Any other error is unexpected.
    if (e && e.message && e.message.includes('unreachable')) {
      // Wasm trap from panic() — already printed stack trace via moonrun demangler
      process.exit(1);
    }
    process.stderr.write(`Error: ${e.message || e}\n`);
    process.exit(1);
  }
}

main();
