import type { BindingDefinition, BindingGraph } from "../../wasm/moonparse.js";

export interface ModuleImport {
  moduleId: string;
  source: string;
}

export interface ExportedDefinition {
  globalId: string;
  uri: string;
  packageId: string;
  moduleId: string;
  localId: number;
  name: string;
  kind: string;
  ns: string;
  startByte: number;
  endByte: number;
  declarationStartByte: number;
  declarationEndByte: number;
}

export interface ModuleEntry {
  uri: string;
  packageId: string;
  moduleId: string;
  imports: ModuleImport[];
  exportedDefinitions: ExportedDefinition[];
}

const exportedKinds = new Set([
  "function",
  "type",
  "struct",
  "enum",
  "trait",
  "constant",
]);

export class ModuleGraph {
  private roots: string[] = [];
  private files = new Map<string, ModuleEntry>();
  private packageExports = new Map<string, Map<string, ExportedDefinition[]>>();

  setRoots(roots: string[]): void {
    this.roots = roots.map(normalizeUri).filter(Boolean).sort((a, b) =>
      b.length - a.length || a.localeCompare(b));
    this.rebuild();
  }

  rootsSnapshot(): string[] {
    return [...this.roots];
  }

  upsertFile(uri: string, graph: BindingGraph | null): ModuleEntry {
    this.removeFile(uri);
    const moduleInfo = moduleInfoForUri(uri, this.roots);
    const entry: ModuleEntry = {
      uri,
      packageId: moduleInfo.packageId,
      moduleId: moduleInfo.moduleId,
      imports: [],
      exportedDefinitions: graph ? exportedDefinitionsForGraph(uri, graph, moduleInfo) : [],
    };
    this.files.set(uri, entry);
    this.indexExports(entry);
    return cloneModuleEntry(entry);
  }

  removeFile(uri: string): void {
    const existing = this.files.get(uri);
    if (!existing) return;
    this.unindexExports(existing);
    this.files.delete(uri);
  }

  getModuleByUri(uri: string): ModuleEntry | undefined {
    const entry = this.files.get(uri);
    return entry ? cloneModuleEntry(entry) : undefined;
  }

  exportedDefinitionsForPackage(packageId: string): ExportedDefinition[] {
    const byKey = this.packageExports.get(packageId);
    if (!byKey) return [];
    return sortExports([...byKey.values()].flat().map(cloneExportedDefinition));
  }

  findExportedDefinitions(
    packageId: string,
    name: string,
    ns: string,
    kind?: string,
  ): ExportedDefinition[] {
    const byKey = this.packageExports.get(packageId);
    const exports = byKey?.get(exportKey(name, ns)) ?? [];
    const filtered = kind ? exports.filter((item) => item.kind === kind) : exports;
    return sortExports(filtered.map(cloneExportedDefinition));
  }

  clear(): void {
    this.files.clear();
    this.packageExports.clear();
  }

  private rebuild(): void {
    const entries = [...this.files.values()].map((entry) => ({
      uri: entry.uri,
      graph: definitionsToGraph(entry.uri, entry.exportedDefinitions),
    }));
    this.clear();
    for (const entry of entries) {
      this.upsertFile(entry.uri, entry.graph);
    }
  }

  private indexExports(entry: ModuleEntry): void {
    let byKey = this.packageExports.get(entry.packageId);
    if (!byKey) {
      byKey = new Map();
      this.packageExports.set(entry.packageId, byKey);
    }
    for (const exported of entry.exportedDefinitions) {
      const key = exportKey(exported.name, exported.ns);
      const list = byKey.get(key);
      if (list) {
        list.push(exported);
      } else {
        byKey.set(key, [exported]);
      }
    }
  }

  private unindexExports(entry: ModuleEntry): void {
    const byKey = this.packageExports.get(entry.packageId);
    if (!byKey) return;
    for (const exported of entry.exportedDefinitions) {
      const key = exportKey(exported.name, exported.ns);
      const list = byKey.get(key);
      if (!list) continue;
      const next = list.filter((item) => item.globalId !== exported.globalId);
      if (next.length === 0) {
        byKey.delete(key);
      } else {
        byKey.set(key, next);
      }
    }
    if (byKey.size === 0) this.packageExports.delete(entry.packageId);
  }
}

export function moduleInfoForUri(
  uri: string,
  roots: string[],
): { packageId: string; moduleId: string } {
  const normalizedUri = normalizeUri(uri);
  const normalizedRoots = roots.map(normalizeUri).filter(Boolean).sort((a, b) =>
    b.length - a.length || a.localeCompare(b));
  const root = normalizedRoots.find((candidate) =>
    normalizedUri === candidate || normalizedUri.startsWith(`${candidate}/`));
  const packageId = root ?? "workspace";
  const relative = root
    ? normalizedUri === root ? lastPathSegment(normalizedUri) : normalizedUri.slice(root.length + 1)
    : uriPath(normalizedUri);
  return {
    packageId,
    moduleId: stripExtension(relative).replace(/\\/g, "/"),
  };
}

function exportedDefinitionsForGraph(
  uri: string,
  graph: BindingGraph,
  moduleInfo: { packageId: string; moduleId: string },
): ExportedDefinition[] {
  const moduleScopes = new Set(
    graph.scopes
      .filter((scope) => scope.parent < 0 || scope.kind === "module")
      .map((scope) => scope.id),
  );
  return sortExports(graph.definitions
    .filter((definition) =>
      moduleScopes.has(definition.scope_id) && exportedKinds.has(definition.kind))
    .map((definition) => exportedDefinition(uri, moduleInfo, definition)));
}

function exportedDefinition(
  uri: string,
  moduleInfo: { packageId: string; moduleId: string },
  definition: BindingDefinition,
): ExportedDefinition {
  return {
    globalId: `${uri}#def:${definition.id}`,
    uri,
    packageId: moduleInfo.packageId,
    moduleId: moduleInfo.moduleId,
    localId: definition.id,
    name: definition.name,
    kind: definition.kind,
    ns: definition.ns,
    startByte: definition.start_byte,
    endByte: definition.end_byte,
    declarationStartByte: definition.declaration_start_byte ?? definition.start_byte,
    declarationEndByte: definition.declaration_end_byte ?? definition.end_byte,
  };
}

function definitionsToGraph(uri: string, definitions: ExportedDefinition[]): BindingGraph {
  return {
    uri,
    scopes: [{ id: 0, parent: -1, start_byte: 0, end_byte: 0, kind: "module" }],
    definitions: definitions.map((definition) => ({
      id: definition.localId,
      name: definition.name,
      kind: definition.kind,
      ns: definition.ns,
      scope_id: 0,
      start_byte: definition.startByte,
      end_byte: definition.endByte,
      declaration_start_byte: definition.declarationStartByte,
      declaration_end_byte: definition.declarationEndByte,
    })),
    references: [],
    edges: [],
    diagnostics: [],
  };
}

function exportKey(name: string, ns: string): string {
  return `${ns}\u0000${name}`;
}

function sortExports(definitions: ExportedDefinition[]): ExportedDefinition[] {
  return definitions.sort((a, b) =>
    a.packageId.localeCompare(b.packageId) ||
    a.moduleId.localeCompare(b.moduleId) ||
    a.name.localeCompare(b.name) ||
    a.startByte - b.startByte ||
    a.localId - b.localId);
}

function cloneModuleEntry(entry: ModuleEntry): ModuleEntry {
  return {
    uri: entry.uri,
    packageId: entry.packageId,
    moduleId: entry.moduleId,
    imports: entry.imports.map((item) => ({ ...item })),
    exportedDefinitions: entry.exportedDefinitions.map(cloneExportedDefinition),
  };
}

function cloneExportedDefinition(definition: ExportedDefinition): ExportedDefinition {
  return { ...definition };
}

function stripExtension(path: string): string {
  const clean = path.split(/[?#]/, 1)[0];
  const slash = clean.lastIndexOf("/");
  const dot = clean.lastIndexOf(".");
  if (dot <= slash) return clean;
  return clean.slice(0, dot);
}

function lastPathSegment(uri: string): string {
  const slash = uri.lastIndexOf("/");
  return slash >= 0 ? uri.slice(slash + 1) : uri;
}

function uriPath(uri: string): string {
  try {
    const parsed = new URL(uri);
    if (parsed.protocol === "file:") {
      return parsed.pathname.replace(/^\/([a-z]:)/i, "$1").replace(/^\/+/, "");
    }
  } catch {
    // Fall through to string-based path extraction.
  }
  const withoutQuery = uri.split(/[?#]/, 1)[0];
  const marker = withoutQuery.indexOf("://");
  return marker >= 0 ? withoutQuery.slice(marker + 3) : withoutQuery;
}

function normalizeUri(uri: string): string {
  let value = uri.trim().replace(/\\/g, "/");
  while (value.endsWith("/")) value = value.slice(0, -1);
  return process.platform === "win32" ? value.toLowerCase() : value;
}
