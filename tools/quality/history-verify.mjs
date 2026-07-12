#!/usr/bin/env node

import { execFileSync, spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";

const DEFAULTS = {
  baselineTag: "contest-baseline-2026-04-26",
  baselineSha: "68065b686857af26966f084114966c59c347a562",
  archiveTag: "archive-pre-mainline-69",
  archiveSha: "d8bffb8be6a9a387fdfdbb7812fdfaf66d89b06f",
  candidate: "HEAD",
  plan: "todo/plan.md",
  profile: "pr",
};

function git(args, { allowFailure = false } = {}) {
  const result = spawnSync("git", args, { encoding: "utf8" });
  if (result.error) throw result.error;
  if (!allowFailure && result.status !== 0) {
    throw new Error(`git ${args.join(" ")} failed: ${(result.stderr || result.stdout).trim()}`);
  }
  return { status: result.status ?? 1, stdout: result.stdout ?? "", stderr: result.stderr ?? "" };
}

function parseArgs(argv) {
  const options = { ...DEFAULTS };
  const names = new Map([
    ["--profile", "profile"], ["--candidate", "candidate"], ["--baseline-tag", "baselineTag"],
    ["--baseline-sha", "baselineSha"], ["--archive-tag", "archiveTag"], ["--archive-sha", "archiveSha"],
    ["--plan", "plan"],
  ]);
  for (let index = 0; index < argv.length; index += 1) {
    const key = names.get(argv[index]);
    if (!key) throw new Error(`unknown option: ${argv[index]}`);
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) throw new Error(`missing value for ${argv[index]}`);
    options[key] = value;
    index += 1;
  }
  if (!new Set(["pr", "nightly", "release"]).has(options.profile)) throw new Error(`invalid profile: ${options.profile}`);
  return options;
}

function peeledTag(tag) {
  if (git(["cat-file", "-t", `refs/tags/${tag}`]).stdout.trim() !== "tag") throw new Error(`${tag} must be an annotated tag`);
  return git(["rev-parse", `refs/tags/${tag}^{}`]).stdout.trim();
}

function assertAncestor(ancestor, descendant, label) {
  if (git(["merge-base", "--is-ancestor", ancestor, descendant], { allowFailure: true }).status !== 0) {
    throw new Error(`${label} is not an ancestor`);
  }
}

function commits(range) {
  const output = git(["log", "--format=%H%x00%aI%x00%s", range]).stdout.trim();
  if (!output) return [];
  return output.split("\n").map((line) => {
    const [sha, authorTime, subject] = line.split("\0");
    return { sha, author_time: authorTime, subject };
  });
}

export function verifyHistory(options = DEFAULTS) {
  const baseline = peeledTag(options.baselineTag);
  const archive = peeledTag(options.archiveTag);
  if (baseline !== options.baselineSha) throw new Error(`baseline peeled SHA mismatch: ${baseline}`);
  if (archive !== options.archiveSha) throw new Error(`archive peeled SHA mismatch: ${archive}`);
  const candidate = git(["rev-parse", options.candidate]).stdout.trim();
  assertAncestor(baseline, archive, "baseline");
  assertAncestor(archive, candidate, "archive");
  git(["diff", "--check"]);
  const ignore = git(["check-ignore", "-q", options.plan], { allowFailure: true }).status;
  if (ignore !== 1) throw new Error(`${options.plan} must be visible to Git`);
  const dirty = git(["status", "--porcelain=v1"]).stdout.split("\n").filter(Boolean);
  if (options.profile === "release" && dirty.length) throw new Error("release profile requires a clean worktree");
  return {
    gate: "V00",
    profile: options.profile,
    candidate_sha: candidate,
    baseline: { tag: options.baselineTag, sha: baseline },
    archive: { tag: options.archiveTag, sha: archive },
    worktree_dirty: dirty.length > 0,
    commits: commits(`${baseline}..${candidate}`),
  };
}

async function main() {
  const result = verifyHistory(parseArgs(process.argv.slice(2)));
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  });
}
