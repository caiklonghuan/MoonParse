import { readdir, readFile } from "node:fs/promises";
import { loadMoonParse } from "../../../wasm/moonparse.js";

const repoRoot = new URL("../../../", import.meta.url);
const manifestUrl = new URL("grammars/manifest.json", repoRoot);
const wasmUrl = new URL(
  "_build/wasm-gc/debug/build/wasm/wasm.wasm",
  repoRoot,
).href;

const requestedLanguageIds = new Set(process.argv.slice(2));

function parseCaseExpectations(raw) {
  const lines = raw.replace(/\r\n/g, "\n").split("\n");
  const expectations = {
    error: "ok",
    sexpContains: [],
    sexpNotContains: [],
  };
  let list = null;

  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed === "" || trimmed.startsWith("#")) continue;

    if (trimmed.startsWith("error:")) {
      expectations.error = trimmed.slice("error:".length).trim();
      list = null;
      continue;
    }
    if (trimmed === "sexp-contains:") {
      list = expectations.sexpContains;
      continue;
    }
    if (trimmed === "sexp-not-contains:") {
      list = expectations.sexpNotContains;
      continue;
    }
    if (list) {
      list.push(trimmed);
      continue;
    }

    throw new Error(`unknown corpus expectation line: ${line}`);
  }

  return expectations;
}

function parseCorpusCases(text) {
  const normalized = text.replace(/\r\n/g, "\n").trim();
  if (normalized === "") return [];

  const cases = [];
  const casePattern = /^====\n([\s\S]*?)\n====\n([\s\S]*?)\n----\n([\s\S]*?)(?=^====\n|$)/gm;
  let match;
  while ((match = casePattern.exec(normalized)) !== null) {
    cases.push({
      name: match[1].trim(),
      source: match[2],
      expectations: parseCaseExpectations(match[3]),
    });
  }

  if (cases.length === 0) {
    throw new Error("corpus file does not contain any valid cases");
  }
  return cases;
}

function assertContains(haystack, needle, context) {
  if (!haystack.includes(needle)) {
    throw new Error(`${context}: expected S-expression to contain "${needle}"`);
  }
}

function assertNotContains(haystack, needle, context) {
  if (haystack.includes(needle)) {
    throw new Error(`${context}: expected S-expression not to contain "${needle}"`);
  }
}

async function loadCorpusFiles(language) {
  if (!language.corpus) return [];

  const corpusDir = new URL(`grammars/${language.corpus}/`, repoRoot);
  let entries;
  try {
    entries = await readdir(corpusDir, { withFileTypes: true });
  } catch (err) {
    if (err?.code === "ENOENT") return [];
    throw err;
  }

  return entries
    .filter((entry) => entry.isFile() && entry.name.endsWith(".txt"))
    .map((entry) => new URL(entry.name, corpusDir));
}

async function runLanguage(mp, language) {
  const corpusFiles = await loadCorpusFiles(language);
  if (corpusFiles.length === 0) {
    return { passed: 0, skipped: 1 };
  }

  const dsl = await readFile(
    new URL(`grammars/${language.grammar}`, repoRoot),
    "utf8",
  );
  const parser = mp.createParser(dsl);
  let passed = 0;

  try {
    for (const corpusFile of corpusFiles) {
      const cases = parseCorpusCases(await readFile(corpusFile, "utf8"));
      for (const testCase of cases) {
        const context = `${language.id}/${corpusFile.pathname.split("/").pop()}/${testCase.name}`;
        let tree;
        try {
          tree = parser.parse(testCase.source);
        } catch (error) {
          throw new Error(`${context}: ${error instanceof Error ? error.message : String(error)}`, { cause: error });
        }
        try {
          const errorSummary = tree.errorSummary();
          if (errorSummary !== testCase.expectations.error) {
            throw new Error(
              `${context}: expected error "${testCase.expectations.error}", got "${errorSummary}"`,
            );
          }

          const sexp = tree.sexp();
          for (const needle of testCase.expectations.sexpContains) {
            assertContains(sexp, needle, context);
          }
          for (const needle of testCase.expectations.sexpNotContains) {
            assertNotContains(sexp, needle, context);
          }
        } finally {
          tree.free();
        }
        passed += 1;
      }
    }
  } finally {
    parser.free();
  }

  return { passed, skipped: 0 };
}

const manifest = JSON.parse(await readFile(manifestUrl, "utf8"));
const languages = manifest.languages.filter((language) => (
  requestedLanguageIds.size === 0 || requestedLanguageIds.has(language.id)
));

if (languages.length === 0) {
  throw new Error(
    `no matching corpus languages: ${[...requestedLanguageIds].join(", ")}`,
  );
}

const mp = await loadMoonParse(wasmUrl);
let totalPassed = 0;
let totalSkipped = 0;

for (const language of languages) {
  const result = await runLanguage(mp, language);
  totalPassed += result.passed;
  totalSkipped += result.skipped;

  if (result.skipped) {
    console.log(`SKIP ${language.id}: no corpus files`);
  } else {
    console.log(`PASS ${language.id}: ${result.passed} corpus case(s)`);
  }
}

console.log(
  `Corpus complete: ${totalPassed} passed, ${totalSkipped} language(s) skipped`,
);
