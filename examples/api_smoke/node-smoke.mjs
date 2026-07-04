import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

import { loadMoonParse } from "../../wasm/moonparse.js";
import {
  createMinimalProject,
  createPresetProject,
} from "../../website/src/lib/languagePackProject.js";

const wasmPath = fileURLToPath(new URL("../../wasm/moonparse.wasm", import.meta.url));
const api = await loadMoonParse(wasmPath);
assert.match(api.version(), /^\d+\.\d+\.\d+/);

for (const project of [
  createMinimalProject(),
  createPresetProject("json"),
  createPresetProject("python"),
  createPresetProject("moonbit"),
]) {
  const result = api.buildPack(project.files);
  assert.equal(result.ok, true);
  result.language.free();
}

const jsonPackFiles = {};
for (const path of [
  "language-pack.json",
  "grammar/main.grammar",
  "queries/highlights.scm",
  "queries/lint/negative-zero.scm",
  "queries/lint/empty-object-key.scm",
  "lint/recommended.json",
  "corpus/valid.txt",
]) {
  jsonPackFiles[path] = await readFile(
    new URL(`../../languages/json/${path}`, import.meta.url),
    "utf8",
  );
}

const packCheck = api.checkPack(jsonPackFiles);
assert.equal(packCheck.ok, true);
assert.equal(packCheck.diagnostics.some((item) => item.severity === "error"), false);

const packBuild = api.buildPack(jsonPackFiles);
assert.equal(packBuild.ok, true);
assert.match(packBuild.bundleJson, /"id":"json"/);
const builtTree = packBuild.language.parse('{"from":"source pack"}');
try {
  assert.equal(builtTree.root.type, "json");
} finally {
  builtTree.free();
}

const lintTree = packBuild.language.parse('{"": -0}');
try {
  const diagnostics = packBuild.language.lint(lintTree);
  assert.deepEqual(
    diagnostics.map((item) => item.ruleId),
    ["json/recommended/empty-object-key", "json/recommended/negative-zero"],
  );
  const negativeZero = diagnostics.find((item) => item.ruleId.endsWith("negative-zero"));
  assert.equal(negativeZero.fix.title, "Replace -0 with 0");
  assert.equal(negativeZero.fix.edit.replacement, "0");
  assert.equal(
    packBuild.language.lint(lintTree, {
      rules: { "json/recommended/negative-zero": "off" },
    }).length,
    1,
  );
} finally {
  lintTree.free();
}
packBuild.language.free();

const corpusRun = api.runCorpus(jsonPackFiles);
assert.equal(corpusRun.ok, true);
assert.ok(corpusRun.cases.length > 0);
assert.equal(corpusRun.cases.every((item) => item.passed), true);

const snapshotText = "====\nexample\n====\n42\n----\nerror: ok\nsexp:\n  (old)\n";
const snapshotResult = api.rewriteCorpusSnapshots({
  path: "corpus/basic.txt",
  text: snapshotText,
  format: "moonparse-corpus-v2",
  updates: [{ caseIndex: 0, caseName: "example", sexp: "(document (number))" }],
});
assert.equal(snapshotResult.ok, true);
assert.match(snapshotResult.updatedText, /\(document \(number\)\)/);

const rustPackFiles = { ...jsonPackFiles };
const rustManifest = JSON.parse(rustPackFiles["language-pack.json"]);
rustManifest.scanner = { id: "tree-sitter-rust", apiVersion: 1 };
rustPackFiles["language-pack.json"] = JSON.stringify(rustManifest);
const rustBuild = api.buildPack(rustPackFiles);
assert.equal(rustBuild.ok, true);
rustBuild.language.free();

for (let index = 0; index < 5; index += 1) {
  const result = api.buildPack(jsonPackFiles);
  assert.equal(result.ok, true);
  result.language.free();
}

const dsl = `
start document
rule document: identifier*
rule identifier: /[a-z]+/
extras [/\\s+/]
`;

const parser = api.createParser(dsl);
const tree = parser.parse("foo bar");
const traceParser = api.createParser("start s\nrule s: /[a-z]/ /[a-z]/");
const traceOldTree = traceParser.parse("ab");
const traceResult = traceParser.parseIncrementalTrace("ad", traceOldTree, {
  start_byte: 1,
  old_end_byte: 2,
  new_end_byte: 2,
  start_row: 0,
  start_col: 1,
  old_end_row: 0,
  old_end_col: 2,
  new_end_row: 0,
  new_end_col: 2,
});
assert.equal(traceOldTree.handle, -1);
assert.equal(traceResult.tree.root.type, "s");
assert.equal(traceResult.trace.sourceByteLength, 2);
assert.ok(traceResult.trace.reusedNodeCount >= 1);
assert.ok(traceResult.trace.incrementalElapsedMs >= 0);
traceResult.tree.free();
traceParser.free();
const query = api.compileQuery("(identifier) @name");
const bindingQuery = api.compileQuery(`
  (document) @scope
  (identifier) @definition.variable
  (identifier) @reference.variable
`);
const softBindingQuery = api.compileQuery(
  "(identifier) @reference.soft.variable",
);

try {
  assert.equal(tree.root.type, "document");
  assert.equal(query.exec(tree).length, 2);
  const graph = bindingQuery.resolveBindings(tree);
  assert.ok(Array.isArray(graph.scopes));
  assert.ok(Array.isArray(graph.definitions));
  assert.ok(Array.isArray(graph.references));
  assert.equal(graph.definitions[0].declaration_start_byte, graph.definitions[0].start_byte);
  const softGraph = softBindingQuery.resolveBindings(tree);
  assert.equal(softGraph.references[0].diagnose_unresolved, false);
  assert.equal(softGraph.diagnostics.length, 0);
} finally {
  softBindingQuery.free();
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

const moonbitLanguage = api.loadBundle(builtinBundles.moonbit);
const moonbitTree = moonbitLanguage.parse(
  "pub fn main() {\n  let value = @json.parse(input)\n}\n",
);
try {
  assert.equal(moonbitLanguage.capabilities.folding, true);
  const folds = moonbitLanguage.fold(moonbitTree);
  assert.ok(folds.some((capture) => capture.capture === "fold.region"));
  const bindings = moonbitLanguage.resolveBindings(moonbitTree);
  const mainDefinition = bindings.definitions.find((definition) => definition.name === "main");
  assert.ok(mainDefinition.declaration_end_byte > mainDefinition.end_byte);
  assert.deepEqual(
    moonbitLanguage.modules(moonbitTree).map((capture) => [capture.capture, capture.text]),
    [
      ["module.export", "main"],
      ["module.reference", "@json"],
      ["module.member.value", "parse"],
    ],
  );
} finally {
  moonbitTree.free();
  moonbitLanguage.free();
}

console.log("MoonParse Node/WASM public API smoke test passed.");
