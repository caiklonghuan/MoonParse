import { readFile, readdir, realpath, stat } from "node:fs/promises";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import type {
  ModuleFileMetadata,
  ModuleImport,
  SourceModuleImport,
} from "./module-graph.js";
import type { ModuleQueryData } from "./module-query.js";

const ignoredDirectories = new Set([
  ".git",
  ".moon",
  "node_modules",
  "dist",
  "build",
  "out",
]);

export interface ParsedMoonPkgImport extends SourceModuleImport {}

export interface MoonBitModuleRoot {
  rootPath: string;
  rootUri: string;
  moduleId: string;
}

interface MoonBitPackage {
  directoryPath: string;
  packageId: string;
  moduleId: string;
  imports: ParsedMoonPkgImport[];
}

export interface MoonBitMetadataDiagnostic {
  path: string;
  message: string;
}

export class MoonBitWorkspaceModel {
  readonly moduleRoots: MoonBitModuleRoot[];
  readonly diagnostics: MoonBitMetadataDiagnostic[];
  private packagesByDirectory: Map<string, MoonBitPackage>;
  private packageIds: Map<string, number>;

  constructor(
    moduleRoots: MoonBitModuleRoot[] = [],
    packages: MoonBitPackage[] = [],
    diagnostics: MoonBitMetadataDiagnostic[] = [],
  ) {
    this.moduleRoots = [...moduleRoots].sort((a, b) =>
      b.rootPath.length - a.rootPath.length || a.rootPath.localeCompare(b.rootPath));
    this.diagnostics = [...diagnostics].sort((a, b) =>
      a.path.localeCompare(b.path) || a.message.localeCompare(b.message));
    this.packagesByDirectory = new Map(packages.map((item) => [
      canonicalPath(item.directoryPath),
      { ...item, imports: item.imports.map((imported) => ({ ...imported })) },
    ]));
    this.packageIds = new Map();
    for (const item of packages) {
      this.packageIds.set(item.packageId, (this.packageIds.get(item.packageId) ?? 0) + 1);
    }
    for (const root of moduleRoots) {
      if (!this.packageIds.has(root.moduleId)) this.packageIds.set(root.moduleId, 1);
    }
  }

  scanRootUris(): string[] {
    return this.moduleRoots.map((item) => item.rootUri);
  }

  metadataForFile(
    uri: string,
    moduleData: ModuleQueryData,
  ): ModuleFileMetadata | null {
    if (!uri.startsWith("file:")) return null;
    const filePath = canonicalPath(fileURLToPath(uri));
    const root = this.moduleRoots.find((item) => isPathInside(filePath, item.rootPath));
    if (!root) return null;
    const directoryPath = canonicalPath(dirname(filePath));
    const relativeDirectory = posix(relative(root.rootPath, directoryPath));
    const packageId = relativeDirectory && relativeDirectory !== "."
      ? `${root.moduleId}/${relativeDirectory}`
      : root.moduleId;
    const packageInfo = this.packagesByDirectory.get(directoryPath);
    const testFile = /_(?:wb)?test\.mbt$/i.test(filePath);
    const declared = [
      ...(packageInfo?.imports ?? []).filter((item) =>
        item.condition === "normal" || (item.condition === "test" && testFile)),
      ...moduleData.imports,
    ];
    const imports = this.resolveImports(declared);
    const fileRelative = posix(relative(root.rootPath, filePath)).replace(/\.mbt$/i, "");

    return {
      owningModuleId: root.moduleId,
      packageId,
      moduleId: fileRelative ? `${root.moduleId}/${fileRelative}` : root.moduleId,
      imports,
      publicExportRanges: moduleData.publicExportRanges,
      qualifiedReferences: moduleData.qualifiedReferences,
      resolutionMode: "strict",
    };
  }

  private resolveImports(imports: ParsedMoonPkgImport[]): ModuleImport[] {
    const aliasCounts = new Map<string, number>();
    for (const imported of imports) {
      aliasCounts.set(imported.alias, (aliasCounts.get(imported.alias) ?? 0) + 1);
    }
    return imports.map((imported) => {
      const count = this.packageIds.get(imported.source) ?? 0;
      const knownModulePrefix = this.moduleRoots.some((root) =>
        imported.source === root.moduleId || imported.source.startsWith(`${root.moduleId}/`));
      let status: ModuleImport["status"];
      let targetPackageId: string | null = null;
      if ((aliasCounts.get(imported.alias) ?? 0) > 1 || count > 1) {
        status = "ambiguous";
      } else if (count === 1) {
        status = "resolved";
        targetPackageId = imported.source;
      } else if (knownModulePrefix) {
        status = "missing";
      } else {
        status = "external";
      }
      return { ...imported, status, targetPackageId };
    });
  }
}

export async function discoverMoonBitWorkspace(
  workspaceRootUris: string[],
): Promise<MoonBitWorkspaceModel> {
  const diagnostics: MoonBitMetadataDiagnostic[] = [];
  const initialPaths = workspaceRootUris
    .filter((uri) => uri.startsWith("file:"))
    .map((uri) => fileURLToPath(uri));
  const manifestPaths = new Set<string>();

  for (const rootPath of initialPaths) {
    const workPath = join(rootPath, "moon.work");
    const work = await readTextIfFile(workPath);
    if (work != null) {
      try {
        for (const member of parseMoonWork(work)) {
          manifestPaths.add(canonicalPath(join(rootPath, member, "moon.mod.json")));
        }
      } catch (error) {
        diagnostics.push({ path: workPath, message: safeMessage(error) });
      }
    }
    if (await isFile(join(rootPath, "moon.mod.json"))) {
      manifestPaths.add(canonicalPath(join(rootPath, "moon.mod.json")));
    }
    for (const nested of await findFilesNamed(rootPath, "moon.mod.json")) {
      manifestPaths.add(canonicalPath(nested));
    }
  }

  const moduleRoots: MoonBitModuleRoot[] = [];
  const visitedManifests = new Set<string>();
  const queue = [...manifestPaths].sort();
  while (queue.length > 0) {
    const manifestPath = queue.shift()!;
    const canonicalManifest = await canonicalExistingPath(manifestPath);
    if (visitedManifests.has(canonicalManifest)) continue;
    visitedManifests.add(canonicalManifest);
    const text = await readTextIfFile(canonicalManifest);
    if (text == null) continue;
    try {
      const manifest = JSON.parse(text) as Record<string, unknown>;
      if (typeof manifest.name !== "string" || !manifest.name.trim()) {
        throw new Error("moon.mod.json must contain a non-empty string 'name'");
      }
      const rootPath = canonicalPath(dirname(canonicalManifest));
      moduleRoots.push({
        rootPath,
        rootUri: pathToFileURL(rootPath).href,
        moduleId: manifest.name.trim(),
      });
      for (const dependencyPath of localDependencyPaths(manifest)) {
        const dependencyRoot = isAbsolute(dependencyPath)
          ? dependencyPath
          : resolve(rootPath, dependencyPath);
        queue.push(canonicalPath(join(dependencyRoot, "moon.mod.json")));
      }
      queue.sort();
    } catch (error) {
      diagnostics.push({ path: canonicalManifest, message: safeMessage(error) });
    }
  }

  const packages: MoonBitPackage[] = [];
  for (const root of moduleRoots) {
    const directories = await findPackageDirectories(root.rootPath);
    for (const directoryPath of directories) {
      const relativeDirectory = posix(relative(root.rootPath, directoryPath));
      const packageId = relativeDirectory && relativeDirectory !== "."
        ? `${root.moduleId}/${relativeDirectory}`
        : root.moduleId;
      const pkgPath = join(directoryPath, "moon.pkg");
      const pkgText = await readTextIfFile(pkgPath);
      let imports: ParsedMoonPkgImport[] = [];
      if (pkgText != null) {
        try {
          imports = parseMoonPkg(pkgText);
          const aliases = new Map<string, number>();
          for (const imported of imports) {
            aliases.set(imported.alias, (aliases.get(imported.alias) ?? 0) + 1);
          }
          for (const [alias, count] of aliases) {
            if (count > 1) {
              diagnostics.push({
                path: pkgPath,
                message: `duplicate import alias '@${alias}'`,
              });
            }
          }
        } catch (error) {
          diagnostics.push({ path: pkgPath, message: safeMessage(error) });
        }
      }
      packages.push({ directoryPath, packageId, moduleId: root.moduleId, imports });
    }
  }

  return new MoonBitWorkspaceModel(deduplicateModuleRoots(moduleRoots), packages, diagnostics);
}

export function parseMoonWork(text: string): string[] {
  const parsed = JSON.parse(text) as Record<string, unknown>;
  const raw = Array.isArray(parsed.members)
    ? parsed.members
    : Array.isArray(parsed.projects) ? parsed.projects : [];
  return raw.flatMap((item) => {
    if (typeof item === "string" && item.trim()) return [item.trim()];
    if (item && typeof item === "object" &&
      typeof (item as Record<string, unknown>).path === "string") {
      return [String((item as Record<string, unknown>).path)];
    }
    return [];
  });
}

export function parseMoonPkg(text: string): ParsedMoonPkgImport[] {
  const source = stripComments(text);
  const result: ParsedMoonPkgImport[] = [];
  const blockPattern = /\bimport\s*\{([\s\S]*?)\}\s*(?:for\s*"((?:\\.|[^"\\])*)")?/g;
  for (const block of source.matchAll(blockPattern)) {
    const conditionText = unescapeQuoted(block[2] ?? "");
    const condition = conditionText === "test" ? "test" : conditionText || "normal";
    const body = block[1];
    const bodyStart = (block.index ?? 0) + block[0].indexOf(body);
    const entryPattern = /"((?:\\.|[^"\\])*)"\s*(?:@([A-Za-z_][A-Za-z0-9_]*))?/g;
    for (const entry of body.matchAll(entryPattern)) {
      const sourceValue = unescapeQuoted(entry[1]);
      if (!sourceValue) continue;
      const alias = entry[2] || sourceValue.split("/").filter(Boolean).at(-1) || sourceValue;
      const start = bodyStart + (entry.index ?? 0);
      result.push({
        source: sourceValue,
        alias,
        condition,
        sourceStartByte: Buffer.byteLength(source.slice(0, start), "utf8"),
        sourceEndByte: Buffer.byteLength(source.slice(0, start + entry[0].length), "utf8"),
      });
    }
  }
  return result;
}

export function localDependencyPaths(manifest: Record<string, unknown>): string[] {
  const containers = [
    "deps",
    "dependencies",
    "test-deps",
    "testDependencies",
    "bin-deps",
    "devDependencies",
  ];
  const paths: string[] = [];
  const visit = (value: unknown): void => {
    if (!value || typeof value !== "object") return;
    if (!Array.isArray(value)) {
      const record = value as Record<string, unknown>;
      if (typeof record.path === "string" && record.path.trim()) {
        paths.push(record.path.trim());
      }
      for (const child of Object.values(record)) visit(child);
    } else {
      for (const child of value) visit(child);
    }
  };
  for (const key of containers) visit(manifest[key]);
  return [...new Set(paths)].sort();
}

function stripComments(text: string): string {
  let result = "";
  let index = 0;
  let quote = false;
  while (index < text.length) {
    const char = text[index];
    const next = text[index + 1];
    if (quote) {
      result += char;
      if (char === "\\" && next != null) {
        result += next;
        index += 2;
        continue;
      }
      if (char === '"') quote = false;
      index++;
      continue;
    }
    if (char === '"') {
      quote = true;
      result += char;
      index++;
      continue;
    }
    if (char === "/" && next === "/") {
      while (index < text.length && text[index] !== "\n") {
        result += " ";
        index++;
      }
      continue;
    }
    if (char === "/" && next === "*") {
      result += "  ";
      index += 2;
      while (index < text.length && !(text[index] === "*" && text[index + 1] === "/")) {
        result += text[index] === "\n" ? "\n" : " ";
        index++;
      }
      if (index < text.length) {
        result += "  ";
        index += 2;
      }
      continue;
    }
    result += char;
    index++;
  }
  return result;
}

function unescapeQuoted(value: string): string {
  try {
    return JSON.parse(`"${value}"`) as string;
  } catch {
    return value;
  }
}

async function findFilesNamed(rootPath: string, fileName: string): Promise<string[]> {
  const result: string[] = [];
  const visit = async (directory: string): Promise<void> => {
    let entries;
    try {
      entries = await readdir(directory, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const path = join(directory, entry.name);
      if (entry.isDirectory() && !ignoredDirectories.has(entry.name)) await visit(path);
      else if (entry.isFile() && entry.name === fileName) result.push(path);
    }
  };
  await visit(rootPath);
  return result.sort();
}

async function findPackageDirectories(rootPath: string): Promise<string[]> {
  const result = new Set<string>();
  const visit = async (directory: string): Promise<void> => {
    let entries;
    try {
      entries = await readdir(directory, { withFileTypes: true });
    } catch {
      return;
    }
    let isPackage = false;
    for (const entry of entries) {
      if (entry.isFile() && (entry.name === "moon.pkg" || entry.name.endsWith(".mbt"))) {
        isPackage = true;
      }
    }
    if (isPackage) result.add(canonicalPath(directory));
    for (const entry of entries) {
      if (entry.isDirectory() && !ignoredDirectories.has(entry.name)) {
        await visit(join(directory, entry.name));
      }
    }
  };
  await visit(rootPath);
  return [...result].sort();
}

async function readTextIfFile(path: string): Promise<string | null> {
  try {
    return await readFile(path, "utf8");
  } catch {
    return null;
  }
}

async function isFile(path: string): Promise<boolean> {
  try {
    return (await stat(path)).isFile();
  } catch {
    return false;
  }
}

async function canonicalExistingPath(path: string): Promise<string> {
  try {
    return canonicalPath(await realpath(path));
  } catch {
    return canonicalPath(path);
  }
}

function deduplicateModuleRoots(roots: MoonBitModuleRoot[]): MoonBitModuleRoot[] {
  const seen = new Set<string>();
  return roots.filter((root) => {
    const key = canonicalPath(root.rootPath);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function canonicalPath(path: string): string {
  let value = resolve(path);
  while (value.length > 1 && value.endsWith(sep)) value = value.slice(0, -1);
  return process.platform === "win32" ? value.toLowerCase() : value;
}

function isPathInside(path: string, root: string): boolean {
  const rel = relative(root, path);
  return rel === "" || (!rel.startsWith("..") && !isAbsolute(rel));
}

function posix(path: string): string {
  return path.split(sep).join("/");
}

function safeMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
