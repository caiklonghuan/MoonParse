// test_runtime.mjs — Test: load MoonParse runtime + binary parse table
import { readFile } from "node:fs/promises";
import { loadMoonParse } from "./moonparse.js";

const mp = await loadMoonParse(
  new URL("./moonparse.wasm", import.meta.url).href
);
console.log("MoonParse version:", mp.version());

const tableBytes = new Uint8Array(
  await readFile(new URL("./json.parse_table", import.meta.url))
);
const parser = mp.createParserFromBytes(tableBytes);
console.log("Parser created OK, dsl:", parser.dsl.slice(0, 40) + "...");

const tree = parser.parse('{"ok": true}');
console.log("root type:", tree.root.type);
console.log("error summary:", tree.errorSummary());
console.log("sexp:", tree.sexp());

tree.free();
parser.free();
console.log("\n=== runtime + parse_table approach: SUCCESS ===");
