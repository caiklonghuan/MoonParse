import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";

import { loadMoonParse } from "../../wasm/moonparse.js";

const wasmPath = fileURLToPath(new URL("../../wasm/moonparse.wasm", import.meta.url));
const api = await loadMoonParse(wasmPath);
assert.match(api.version(), /^\d+\.\d+\.\d+/);

const dsl = `
start document
rule document: identifier*
rule identifier: /[a-z]+/
extras [/\\s+/]
`;

const parser = api.createParser(dsl);
const tree = parser.parse("foo bar");
const query = api.compileQuery("(identifier) @name");
const bindingQuery = api.compileQuery(`
  (document) @scope
  (identifier) @definition.variable
  (identifier) @reference.variable
`);

try {
  assert.equal(tree.root.type, "document");
  assert.equal(query.exec(tree).length, 2);
  const graph = bindingQuery.resolveBindings(tree);
  assert.ok(Array.isArray(graph.scopes));
  assert.ok(Array.isArray(graph.definitions));
  assert.ok(Array.isArray(graph.references));
} finally {
  bindingQuery.free();
  query.free();
  tree.free();
  parser.free();
}

const builtinBundles = JSON.parse(api.builtinBundlesJson());
assert.deepEqual(Object.keys(builtinBundles).sort(), ["json", "moonbit", "python"]);
const jsonLanguage = api.loadBundle(builtinBundles.json);
const jsonTree = jsonLanguage.parse('{"nested":{"value":42}}');
try {
  assert.equal(jsonLanguage.id, "json");
  assert.deepEqual(jsonLanguage.extensions, [".json"]);
  assert.equal(jsonTree.root.type, "json");
  assert.ok(jsonLanguage.highlight(jsonTree).length > 0);
} finally {
  jsonTree.free();
  jsonLanguage.free();
}

const pythonLanguage = api.loadBundle(builtinBundles.python);
const pythonTree = pythonLanguage.parse("def f():\n  return 1\n");
try {
  assert.equal(pythonLanguage.capabilities.scanner, true);
  assert.equal(pythonTree.root.type, "module");
} finally {
  pythonTree.free();
  pythonLanguage.free();
}

console.log("MoonParse Node/WASM public API smoke test passed.");
