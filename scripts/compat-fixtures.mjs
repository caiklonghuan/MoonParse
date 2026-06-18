#!/usr/bin/env node

import assert from "node:assert/strict";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { loadMoonParse } from "../wasm/moonparse.js";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const fixturePath = resolve(root, "api/fixtures/parse-table-v3.json");
const dsl = "start document\nextras [/[ \\t\\n\\r]+/]\nrule document: number\nrule number: /[0-9]+/\n";
const source = "42";
const expectedSexp = "(document (number))";
const mp = await loadMoonParse(resolve(root, "wasm/moonparse.wasm"));

if (process.argv.includes("--write")) {
  await mkdir(dirname(fixturePath), { recursive: true });
  const parser = mp.createParser(dsl);
  try {
    const fixture = {
      fixtureSchemaVersion: 1,
      parseTableSchemaVersion: 3,
      createdWith: mp.version(),
      source,
      expectedSexp,
      tableJson: parser.tableJson(),
      tableBase64: Buffer.from(parser.tableBytes()).toString("base64"),
    };
    await writeFile(fixturePath, `${JSON.stringify(fixture, null, 2)}\n`, "utf8");
  } finally {
    parser.free();
  }
  console.log("ParseTable v3 compatibility fixture updated.");
} else {
  const fixture = JSON.parse(await readFile(fixturePath, "utf8"));
  assert.equal(fixture.parseTableSchemaVersion, 3);
  const parsers = [
    mp.createParserFromJson(fixture.tableJson),
    mp.createParserFromBytes(Buffer.from(fixture.tableBase64, "base64")),
  ];
  for (const parser of parsers) {
    const tree = parser.parse(fixture.source);
    try {
      assert.equal(tree.sexp(), fixture.expectedSexp);
    } finally {
      tree.free();
      parser.free();
    }
  }

  const builtinBundles = JSON.parse(mp.builtinBundlesJson());
  const currentBundle = JSON.parse(builtinBundles.json);
  const v3Bundle = structuredClone(currentBundle);
  v3Bundle.parseTable = {
    schemaVersion: 3,
    json: fixture.tableJson,
    binaryBase64: fixture.tableBase64,
  };
  const language = mp.loadBundle(JSON.stringify(v3Bundle));
  try {
    const tree = language.parse(fixture.source);
    try {
      assert.equal(tree.sexp(), fixture.expectedSexp);
    } finally {
      tree.free();
    }
  } finally {
    language.free();
  }

  const mixedJsonV3BinaryV4 = structuredClone(currentBundle);
  mixedJsonV3BinaryV4.parseTable.schemaVersion = 3;
  mixedJsonV3BinaryV4.parseTable.json = fixture.tableJson;
  assert.throws(
    () => mp.loadBundle(JSON.stringify(mixedJsonV3BinaryV4)),
    /PACK711|schema versions do not match/,
  );

  const mixedJsonV4BinaryV3 = structuredClone(currentBundle);
  mixedJsonV4BinaryV3.parseTable.binaryBase64 = fixture.tableBase64;
  assert.throws(
    () => mp.loadBundle(JSON.stringify(mixedJsonV4BinaryV3)),
    /PACK711|schema versions do not match/,
  );
  console.log("ParseTable v3 compatibility fixture passed.");
}
