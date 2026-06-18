import assert from "node:assert/strict";
import test from "node:test";

import { extractCliExitCodes, extractCliHelp, extractWasmExports } from "./api-snapshots.mjs";

test("extractWasmExports normalizes and sorts exports", () => {
  const source = `options(link: { "wasm-gc": { "exports": ["z", "a"] } })`;
  assert.equal(extractWasmExports(source), "a\nz\n");
});

test("extractCliHelp reads MoonBit block strings", () => {
  const names = [
    "global_usage", "generate_usage", "parse_usage", "check_usage", "fmt_usage",
    "query_usage", "test_usage", "build_usage", "wasm_usage", "dump_usage", "clean_usage",
    "pack_usage",
  ];
  const source = names.map((name) => `fn ${name}() -> String {\n  (\n    #|${name}\n  )\n}`).join("\n");
  const result = extractCliHelp(source);
  assert.match(result, /## global_usage\nglobal_usage/);
  assert.match(result, /## clean_usage\nclean_usage/);
  assert.match(result, /## pack_usage\npack_usage/);
});

test("extractCliExitCodes records the documented application contract", () => {
  const args = "Exit codes: 0 = all passed, 1 = test failures, 2 = load/compile error\nExit codes: 0 = ok, 1 = warnings, 2 = errors";
  const main = "match parse_args(argv) {\n  Err(msg) => {\n    print_err(msg)\n    2\n  }\n}";
  const result = JSON.parse(extractCliExitCodes(args, main));
  assert.deepEqual(result.check, { ok: 0, warnings: 1, errors: 2 });
});
