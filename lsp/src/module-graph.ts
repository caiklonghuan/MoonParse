import type { BindingDefinition, BindingGraph } from "../../wasm/moonparse.js";
import { workspaceUriKey } from "./uri-key.js";

export type ModuleResolutionMode = "strict" | "legacy";
export type DefinitionVisibility = "package" | "public";
export type ModuleImportStatus = "resolved" | "external" | "missing" | "ambiguous";

export interface SourceModuleImport {
  source: string;
  alias: string;
  condition: "normal" | "test" | string;
  sourceStartByte: number;
  sourceEndByte: number;
}

export interface ModuleImport extends SourceModuleImport {
  targetPackageId: string | null;
  status: ModuleImportStatus;
}

export interface QualifiedModuleReference {
  alias: string;
  name: string;
  namespace: "value" | "type";
  aliasStartByte: number;
  aliasEndByte: number;
  startByte: number;
  endByte: number;
  referenceId: number | null;
}

export interface ModuleFileMetadata {
  owningModuleId: string;
  packageId: string;
  moduleId?: string;
  imports: ModuleImport[];
  publicExportRanges: Array<{ startByte: number; endByte: number }>;
  qualifiedReferences: QualifiedModuleReference[];
  resolutionMode: ModuleResolutionMode;
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
  visibility: DefinitionVisibility;
  startByte: number;
  endByte: number;
  declarationStartByte: number;
  declarationEndByte: number;
}

export interface ModuleEntry {
  uri: string;
  owningModuleId: string;
  packageId: string;
  moduleId: string;
  imports: ModuleImport[];
  qualifiedReferences: QualifiedModuleReference[];
  resolutionMode: ModuleResolutionMode;
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
  private importers = new Map<string, Set<string>>();

  setRoots(roots: string[]): void {
    this.roots = roots.map(workspaceUriKey).filter(Boolean).sort((a, b) =>
      b.length - a.length || a.localeCompare(b));
    this.rebuild();
  }

  rootsSnapshot(): string[] {
    return [...this.roots];
  }

  upsertFile(
    uri: string,
    graph: BindingGraph | null,
    metadata?: ModuleFileMetadata | null,
  ): ModuleEntry {
    const key = workspaceUriKey(uri);
    this.removeFile(uri);
    const fallback = moduleInfoForUri(uri, this.roots);
    const entry: ModuleEntry = {
      uri,
      owningModuleId: metadata?.owningModuleId ?? fallback.packageId,
      packageId: metadata?.packageId ?? fallback.packageId,
      moduleId: metadata?.moduleId ?? fallback.moduleId,
      imports: metadata?.imports.map(cloneModuleImport) ?? [],
      qualifiedReferences: metadata?.qualifiedReferences.map((item) => ({ ...item })) ?? [],
      resolutionMode: metadata?.resolutionMode ?? "legacy",
      exportedDefinitions: graph
        ? exportedDefinitionsForGraph(uri, graph, {
          packageId: metadata?.packageId ?? fallback.packageId,
          moduleId: metadata?.moduleId ?? fallback.moduleId,
        }, metadata)
        : [],
    };
    this.files.set(key, entry);
    this.indexExports(entry);
    this.refreshImportEdges();
    return cloneModuleEntry(entry);
  }

  removeFile(uri: string): void {
    const key = workspaceUriKey(uri);
    const existing = this.files.get(key);
    if (!existing) return;
    this.unindexExports(existing);
    this.files.delete(key);
    this.refreshImportEdges();
  }

  getModuleByUri(uri: string): ModuleEntry | undefined {
    const entry = this.files.get(workspaceUriKey(uri));
    return entry ? cloneModuleEntry(entry) : undefined;
  }

  entries(): ModuleEntry[] {
    return [...this.files.values()].map(cloneModuleEntry).sort((a, b) =>
      a.uri.localeCompare(b.uri));
  }

  importersForPackage(packageId: string): string[] {
    return [...(this.importers.get(packageId) ?? [])].sort();
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

  qualifiedReferenceForBinding(
    uri: string,
    referenceId: number,
    startByte?: number,
    endByte?: number,
  ): QualifiedModuleReference | null {
    const entry = this.files.get(workspaceUriKey(uri));
    if (!entry || entry.resolutionMode !== "strict") return null;
    const exactId = entry.qualifiedReferences.filter((item) => item.referenceId === referenceId);
    if (exactId.length === 1) return { ...exactId[0] };
    const exactRange = entry.qualifiedReferences.filter((item) =>
      item.startByte === startByte && item.endByte === endByte);
    return exactRange.length === 1 ? { ...exactRange[0] } : null;
  }

  qualifiedReferenceAt(
    uri: string,
    startByte: number,
    endByte: number,
  ): QualifiedModuleReference | null {
    const entry = this.files.get(workspaceUriKey(uri));
    if (!entry || entry.resolutionMode !== "strict") return null;
    const matches = entry.qualifiedReferences.filter((item) =>
      (item.startByte <= startByte && endByte <= item.endByte) ||
      (item.aliasStartByte <= startByte && endByte <= item.aliasEndByte));
    matches.sort((a, b) =>
      (a.endByte - a.startByte) - (b.endByte - b.startByte) ||
      a.startByte - b.startByte);
    return matches[0] ? { ...matches[0] } : null;
  }

  importsForAlias(uri: string, alias: string): ModuleImport[] {
    const entry = this.files.get(workspaceUriKey(uri));
    if (!entry) return [];
    return entry.imports.filter((item) => item.alias === alias).map(cloneModuleImport);
  }

  findQualifiedDefinitions(
    uri: string,
    qualified: QualifiedModuleReference,
  ): ExportedDefinition[] {
    const imports = this.importsForAlias(uri, qualified.alias);
    if (imports.length !== 1) return [];
    const imported = imports[0];
    if (imported.status !== "resolved" || !imported.targetPackageId) return [];
    return this.findExportedDefinitions(
      imported.targetPackageId,
      qualified.name,
      qualified.namespace,
    ).filter((definition) => definition.visibility === "public");
  }

  clear(): void {
    this.files.clear();
    this.packageExports.clear();
    this.importers.clear();
  }

  private rebuild(): void {
    const entries = [...this.files.values()].map(cloneModuleEntry);
    this.clear();
    for (const entry of entries) {
      const graph = definitionsToGraph(entry.uri, entry.exportedDefinitions);
      this.upsertFile(entry.uri, graph, metadataFromEntry(entry));
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
      if (list) list.push(exported);
      else byKey.set(key, [exported]);
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
      if (next.length === 0) byKey.delete(key);
      else byKey.set(key, next);
    }
    if (byKey.size === 0) this.packageExports.delete(entry.packageId);
  }

  private indexImports(entry: ModuleEntry): void {
    for (const imported of entry.imports) {
      if (imported.status !== "resolved" || !imported.targetPackageId) continue;
      let uris = this.importers.get(imported.targetPackageId);
      if (!uris) {
        uris = new Set();
        this.importers.set(imported.targetPackageId, uris);
      }
      uris.add(entry.uri);
    }
  }

  private unindexImports(entry: ModuleEntry): void {
    for (const imported of entry.imports) {
      if (!imported.targetPackageId) continue;
      const uris = this.importers.get(imported.targetPackageId);
      uris?.delete(entry.uri);
      if (uris?.size === 0) this.importers.delete(imported.targetPackageId);
    }
  }

  private refreshImportEdges(): void {
    this.importers.clear();
    const packageIds = new Set([...this.files.values()].map((entry) => entry.packageId));
    const owningModules = new Set([...this.files.values()].map((entry) => entry.owningModuleId));
    for (const entry of this.files.values()) {
      const aliasCounts = new Map<string, number>();
      for (const imported of entry.imports) {
        aliasCounts.set(imported.alias, (aliasCounts.get(imported.alias) ?? 0) + 1);
      }
      for (const imported of entry.imports) {
        const targets = [...packageIds].filter((packageId) => packageId === imported.source);
        if (imported.status === "ambiguous" ||
          (aliasCounts.get(imported.alias) ?? 0) > 1 || targets.length > 1) {
          imported.status = "ambiguous";
          imported.targetPackageId = null;
        } else if (targets.length === 1) {
          imported.status = "resolved";
          imported.targetPackageId = targets[0];
        } else {
          imported.targetPackageId = null;
          imported.status = [...owningModules].some((moduleId) =>
            imported.source === moduleId || imported.source.startsWith(`${moduleId}/`))
            ? "missing"
            : "external";
        }
      }
      this.indexImports(entry);
    }
  }
}

export function moduleInfoForUri(
  uri: string,
  roots: string[],
): { packageId: string; moduleId: string } {
  const normalizedUri = workspaceUriKey(uri);
  const normalizedRoots = roots.map(workspaceUriKey).filter(Boolean).sort((a, b) =>
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
  metadata?: ModuleFileMetadata | null,
): ExportedDefinition[] {
  const moduleScopes = new Set(
    graph.scopes
      .filter((scope) => scope.parent < 0 || scope.kind === "module")
      .map((scope) => scope.id),
  );
  return sortExports(graph.definitions
    .filter((definition) =>
      moduleScopes.has(definition.scope_id) && exportedKinds.has(definition.kind))
    .map((definition) => exportedDefinition(uri, moduleInfo, definition, metadata)));
}

function exportedDefinition(
  uri: string,
  moduleInfo: { packageId: string; moduleId: string },
  definition: BindingDefinition,
  metadata?: ModuleFileMetadata | null,
): ExportedDefinition {
  const isPublic = metadata?.publicExportRanges.some((range) =>
    range.startByte === definition.start_byte && range.endByte === definition.end_byte) ?? false;
  return {
    globalId: `${uri}#def:${definition.id}`,
    uri,
    packageId: moduleInfo.packageId,
    moduleId: moduleInfo.moduleId,
    localId: definition.id,
    name: definition.name,
    kind: definition.kind,
    ns: definition.ns,
    visibility: metadata?.resolutionMode === "strict"
      ? isPublic ? "public" : "package"
      : "public",
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

function metadataFromEntry(entry: ModuleEntry): ModuleFileMetadata {
  return {
    owningModuleId: entry.owningModuleId,
    packageId: entry.packageId,
    moduleId: entry.moduleId,
    imports: entry.imports.map(cloneModuleImport),
    publicExportRanges: entry.exportedDefinitions
      .filter((item) => item.visibility === "public")
      .map((item) => ({ startByte: item.startByte, endByte: item.endByte })),
    qualifiedReferences: entry.qualifiedReferences.map((item) => ({ ...item })),
    resolutionMode: entry.resolutionMode,
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
    owningModuleId: entry.owningModuleId,
    packageId: entry.packageId,
    moduleId: entry.moduleId,
    imports: entry.imports.map(cloneModuleImport),
    qualifiedReferences: entry.qualifiedReferences.map((item) => ({ ...item })),
    resolutionMode: entry.resolutionMode,
    exportedDefinitions: entry.exportedDefinitions.map(cloneExportedDefinition),
  };
}

function cloneModuleImport(imported: ModuleImport): ModuleImport {
  return { ...imported };
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
