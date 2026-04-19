// test_dist.mjs — Test: load pre-baked parser from generated dist/parser.js
import { loadMoonParse } from "./moonparse.js";
import { loadParser } from "./dist/parser.js";

const mp = await loadMoonParse(
  new URL("./moonparse.wasm", import.meta.url).href
);
const parser = await loadParser(mp);
console.log("Parser created via dist/parser.js OK");

const tree = parser.parse('{"ok": true}');
console.log("root type:", tree.root.type);
console.log("error summary:", tree.errorSummary());
console.log("sexp:", tree.sexp());

tree.free();
parser.free();
console.log("\n=== dist/parser.js approach: SUCCESS ===");
