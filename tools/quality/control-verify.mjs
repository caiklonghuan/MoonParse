#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const requiredFiles = [
  "evidence/control/acceptance.v1.json",
  "evidence/control/differentiation.v1.json",
  "evidence/control/proposal-contract.v1.json",
  "evidence/control/thresholds.v1.json",
  "evidence/control/toolchain.lock.json",
  "evidence/control/warning-exceptions.contract.json",
  "evidence/control/work-packages.v1.json",
  "evidence/manifests/benchmark.v1.json",
  "evidence/manifests/corpus.v1.json",
  "evidence/manifests/differential.v1.json",
  "evidence/manifests/digest.v1.json",
  "evidence/manifests/size.v1.json",
  "evidence/manifests/source-provenance.v1.json",
];

function fail(message) {
  throw new Error(`control-verify: ${message}`);
}

function readJson(path) {
  let value;
  try {
    value = JSON.parse(readFileSync(resolve(root, path), "utf8"));
  } catch (error) {
    fail(`cannot read ${path}: ${error instanceof Error ? error.message : String(error)}`);
  }
  if (value.schema_version !== 1) fail(`${path} must use schema_version 1`);
  return value;
}

function unique(values, label) {
  if (!Array.isArray(values) || new Set(values).size !== values.length) fail(`${label} must be a unique array`);
}

export function verifyControlPlane() {
  const documents = Object.fromEntries(requiredFiles.map((path) => [path, readJson(path)]));
  const toolchain = documents["evidence/control/toolchain.lock.json"];
  if (toolchain.moon?.version !== "0.1.20260703" || toolchain.moon?.commit !== "6fbf8c3" || toolchain.node?.ci_major !== 22) {
    fail("toolchain lock must match the CI MoonBit release and Node 22");
  }

  const acceptance = documents["evidence/control/acceptance.v1.json"];
  if (acceptance.status !== "external_required" || !Array.isArray(acceptance.requirements) || acceptance.requirements.length < 18) {
    fail("acceptance control must remain an explicit external-required requirements template");
  }
  unique(acceptance.requirements.map(({ id }) => id), "acceptance requirement IDs");
  for (const requirement of acceptance.requirements) {
    if (!requirement.claim || !["prepublish", "postpublish"].includes(requirement.phase) || !Array.isArray(requirement.commands) || Object.hasOwn(requirement, "observed")) {
      fail(`invalid or stateful acceptance requirement ${requirement.id}`);
    }
  }

  const proposal = documents["evidence/control/proposal-contract.v1.json"];
  if (proposal.status !== "external_required" || !Array.isArray(proposal.promises) || proposal.promises.length === 0) {
    fail("proposal control must remain an explicit external-required requirements template");
  }
  unique(proposal.promises.map(({ id }) => id), "proposal promise IDs");
  if (toolchain.brotli?.quality !== 11 || toolchain.brotli?.lgwin !== 22 || toolchain.brotli?.mode !== "generic") {
    fail("toolchain lock must freeze deterministic Brotli parameters");
  }

  const thresholds = documents["evidence/control/thresholds.v1.json"];
  if (thresholds.promotion_gate !== "M1-G02" || !Array.isArray(thresholds.thresholds) || thresholds.thresholds.length === 0) {
    fail("threshold control must declare M1-G02 and non-empty thresholds");
  }
  unique(thresholds.thresholds.map(({ id }) => id), "threshold IDs");
  for (const threshold of thresholds.thresholds) {
    if (!["candidate", "hard"].includes(threshold.status) || !["<=", ">="].includes(threshold.operator) || !Number.isFinite(threshold.value)) {
      fail(`invalid threshold ${threshold.id}`);
    }
  }

  const workPackages = documents["evidence/control/work-packages.v1.json"].packages;
  unique(workPackages.map(({ id }) => id), "work package IDs");
  const packageIds = new Set(workPackages.map(({ id }) => id));
  for (const workPackage of workPackages) {
    if (!Array.isArray(workPackage.depends_on) || workPackage.depends_on.some((id) => id.startsWith("M1-") && !packageIds.has(id))) {
      fail(`invalid dependency declaration for ${workPackage.id}`);
    }
  }

  const differential = documents["evidence/manifests/differential.v1.json"];
  if (differential.profiles?.pr?.minimum_edits < 20000 || differential.profiles?.nightly?.minimum_edits < 1000000 || differential.profiles?.release?.minimum_edits < 1000000) {
    fail("differential profiles do not meet the frozen edit minima");
  }
  unique(differential.operations, "differential operations");
  unique(differential.hard_zeroes, "differential hard-zero outcomes");

  const digest = documents["evidence/manifests/digest.v1.json"];
  if (digest.encoding !== "canonical-json-lines" || digest.hash_algorithm !== "sha256" || !digest.required_fields?.includes("pack-fingerprint")) {
    fail("digest manifest does not freeze canonical cross-backend input");
  }

  const benchmark = documents["evidence/manifests/benchmark.v1.json"];
  if (benchmark.reference_profile?.warmup !== 20 || benchmark.reference_profile?.samples !== 50 || JSON.stringify(benchmark.sizes_bytes) !== JSON.stringify([10240, 102400, 1048576])) {
    fail("benchmark manifest must freeze profile, samples, and corpus sizes");
  }

  const size = documents["evidence/manifests/size.v1.json"];
  if (size.rebuilds?.pack_clean_processes !== 3 || size.rebuilds?.wasm_clean_builds !== 2 || size.compression?.quality !== 11) {
    fail("size manifest must freeze repeated-build and compression requirements");
  }

  return { schema_version: 1, checked_files: requiredFiles, threshold_statuses: thresholds.thresholds.map(({ id, status }) => ({ id, status })) };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  try {
    process.stdout.write(`${JSON.stringify(verifyControlPlane(), null, 2)}\n`);
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}
