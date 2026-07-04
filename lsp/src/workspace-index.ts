import type { BindingGraph, ParseTree } from "../../wasm/moonparse.js";
import type { BindingIndex } from "./binding-index.js";
import {
  ModuleGraph,
  type ExportedDefinition,
  type ModuleFileMetadata,
  type ModuleEntry,
  type ModuleImport,
  type ModuleResolutionMode,
  type QualifiedModuleReference,
} from "./module-graph.js";
import { workspaceUriKey } from "./uri-key.js";

export interface WorkspaceIndexConfig {
  enabled: boolean;
  maxFileBytes: number;
  maxFiles: number;
  parseTimeoutMs?: number;
  idleEvictMs?: number;
}

export interface WorkspaceFileEntry {
  uri: string;
  text: string;
  lineOffsets: Uint32Array;
  languageId: string;
  version?: number;
  mtimeMs?: number;
  sizeBytes: number;
  isOpen: boolean;
  generation: number;
  lastAccessMs: number;
  lastIndexedAtMs: number;
  skipReason?: string;
  packageId: string;
  moduleId: string;
  owningModuleId: string;
  imports: ModuleImport[];
  qualifiedReferences: QualifiedModuleReference[];
  resolutionMode: ModuleResolutionMode;
  exportedDefinitions: ExportedDefinition[];
  tree: ParseTree | null;
  graph: BindingGraph | null;
  bindingIndex: BindingIndex | null;
}

export interface ParsedWorkspaceDocument {
  uri: string;
  text: string;
  lineOffsets: Uint32Array;
  languageId: string;
  version?: number;
  mtimeMs?: number;
  sizeBytes: number;
  isOpen: boolean;
  generation?: number;
  indexedAtMs?: number;
  tree: ParseTree;
  graph?: BindingGraph | null;
  bindingIndex?: BindingIndex | null;
  moduleMetadata?: ModuleFileMetadata | null;
}

export type GlobalSymbolKind = "definition" | "reference";

export interface GlobalSymbolId {
  uri: string;
  kind: GlobalSymbolKind;
  localId: number;
}

export function globalDefinitionId(uri: string, localId: number): string {
  return `${uri}#def:${localId}`;
}

export function globalReferenceId(uri: string, localId: number): string {
  return `${uri}#ref:${localId}`;
}

export function parseGlobalSymbolId(value: string): GlobalSymbolId | null {
  const marker = value.lastIndexOf("#");
  if (marker < 0) return null;
  const uri = value.slice(0, marker);
  const rest = value.slice(marker + 1);
  const match = /^(def|ref):(\d+)$/.exec(rest);
  if (!uri || !match) return null;
  return {
    uri,
    kind: match[1] === "def" ? "definition" : "reference",
    localId: Number(match[2]),
  };
}

export class WorkspaceIndex {
  private roots: string[] = [];
  private controlledRoots: string[] = [];
  private files = new Map<string, WorkspaceFileEntry>();
  private generations = new Map<string, number>();
  private modules = new ModuleGraph();

  constructor(private config: WorkspaceIndexConfig) {}

  updateConfig(config: WorkspaceIndexConfig): void {
    this.config = config;
  }

  setRoots(roots: string[]): void {
    this.roots = roots.map(workspaceUriKey).filter(Boolean).sort();
    this.modules.setRoots(this.roots);
    this.rebuildModuleEntries();
  }

  getRoots(): string[] {
    return [...this.roots];
  }

  setControlledRoots(roots: string[]): void {
    this.controlledRoots = roots.map(workspaceUriKey).filter(Boolean).sort();
  }

  isInWorkspace(uri: string): boolean {
    if (this.roots.length === 0 && this.controlledRoots.length === 0) return true;
    const value = workspaceUriKey(uri);
    return [...this.roots, ...this.controlledRoots]
      .some((root) => value === root || value.startsWith(`${root}/`));
  }

  shouldIndexUri(
    uri: string,
    sizeBytes: number,
    enabledExtensions: string[],
  ): boolean {
    return this.indexSkipReason(uri, sizeBytes, enabledExtensions) === null;
  }

  indexSkipReason(
    uri: string,
    sizeBytes: number,
    enabledExtensions: string[],
  ): string | null {
    if (!this.config.enabled) return "disabled";
    if (sizeBytes > this.config.maxFileBytes) return "maxFileBytes";
    if (!this.isInWorkspace(uri)) return "outsideWorkspace";
    if (!enabledExtensions.includes(extensionFromUri(uri))) return "extension";
    if (!this.files.has(workspaceUriKey(uri)) && this.files.size >= this.config.maxFiles) {
      return "maxFiles";
    }
    return null;
  }

  beginUpdate(uri: string, nowMs: number = Date.now()): number {
    const key = workspaceUriKey(uri);
    const next = this.currentGeneration(uri) + 1;
    this.generations.set(key, next);
    const entry = this.files.get(key);
    if (entry) {
      entry.generation = next;
      entry.lastAccessMs = nowMs;
      entry.skipReason = undefined;
    }
    return next;
  }

  currentGeneration(uri: string): number {
    const key = workspaceUriKey(uri);
    return this.generations.get(key) ?? this.files.get(key)?.generation ?? 0;
  }

  isCurrentGeneration(uri: string, generation: number): boolean {
    return this.currentGeneration(uri) === generation;
  }

  markSkipped(uri: string, reason: string, nowMs: number = Date.now()): void {
    const entry = this.files.get(workspaceUriKey(uri));
    if (!entry) return;
    entry.skipReason = reason;
    entry.lastAccessMs = nowMs;
  }

  touch(uri: string, nowMs: number = Date.now()): void {
    const entry = this.files.get(workspaceUriKey(uri));
    if (entry) entry.lastAccessMs = nowMs;
  }

  ensureCapacityFor(
    uri: string,
    freeTree?: (tree: ParseTree) => void,
    nowMs: number = Date.now(),
  ): boolean {
    if (this.files.has(workspaceUriKey(uri))) return true;
    if (this.config.maxFiles <= 0) return false;
    if (this.files.size < this.config.maxFiles) return true;
    this.evictClosedUntilCapacity(freeTree, nowMs);
    return this.files.size < this.config.maxFiles;
  }

  evictIdleClosed(
    nowMs: number = Date.now(),
    freeTree?: (tree: ParseTree) => void,
  ): string[] {
    const idleMs = this.config.idleEvictMs ?? 0;
    if (idleMs <= 0) return [];
    const cutoff = nowMs - idleMs;
    const evicted: string[] = [];
    for (const entry of this.closedEntriesByAccess()) {
      if (entry.lastAccessMs > cutoff) continue;
      this.remove(entry.uri, freeTree);
      evicted.push(entry.uri);
    }
    return evicted;
  }

  evictClosedUntilCapacity(
    freeTree?: (tree: ParseTree) => void,
    _nowMs: number = Date.now(),
  ): string[] {
    const evicted: string[] = [];
    for (const entry of this.closedEntriesByAccess()) {
      if (this.files.size < this.config.maxFiles) break;
      this.remove(entry.uri, freeTree);
      evicted.push(entry.uri);
    }
    return evicted;
  }

  upsertParsedDocument(document: ParsedWorkspaceDocument): void {
    const key = workspaceUriKey(document.uri);
    const nowMs = document.indexedAtMs ?? Date.now();
    const generation = document.generation ?? this.currentGeneration(document.uri);
    const moduleEntry = this.modules.upsertFile(
      document.uri,
      document.graph ?? null,
      document.moduleMetadata,
    );
    this.generations.set(key, generation);
    this.files.set(key, {
      uri: document.uri,
      text: document.text,
      lineOffsets: cloneLineOffsets(document.lineOffsets),
      languageId: document.languageId,
      version: document.version,
      mtimeMs: document.mtimeMs,
      sizeBytes: document.sizeBytes,
      isOpen: document.isOpen,
      generation,
      lastAccessMs: nowMs,
      lastIndexedAtMs: nowMs,
      skipReason: undefined,
      packageId: moduleEntry.packageId,
      moduleId: moduleEntry.moduleId,
      owningModuleId: moduleEntry.owningModuleId,
      imports: moduleEntry.imports,
      qualifiedReferences: moduleEntry.qualifiedReferences,
      resolutionMode: moduleEntry.resolutionMode,
      exportedDefinitions: moduleEntry.exportedDefinitions,
      tree: document.tree,
      graph: document.graph ?? null,
      bindingIndex: document.bindingIndex ?? null,
    });
  }

  markClosed(uri: string): void {
    const entry = this.files.get(workspaceUriKey(uri));
    if (entry) {
      entry.isOpen = false;
      entry.lastAccessMs = Date.now();
    }
  }

  remove(uri: string, freeTree?: (tree: ParseTree) => void): void {
    const key = workspaceUriKey(uri);
    const entry = this.files.get(key);
    if (entry?.tree && freeTree) freeTree(entry.tree);
    this.files.delete(key);
    this.modules.removeFile(uri);
  }

  clearRuntime(uri: string): void {
    const entry = this.files.get(workspaceUriKey(uri));
    if (!entry) return;
    entry.tree = null;
    entry.graph = null;
    entry.bindingIndex = null;
    entry.imports = [];
    entry.exportedDefinitions = [];
    this.modules.removeFile(uri);
  }

  get(uri: string): WorkspaceFileEntry | undefined {
    return this.files.get(workspaceUriKey(uri));
  }

  tree(uri: string): ParseTree | undefined {
    return this.files.get(workspaceUriKey(uri))?.tree ?? undefined;
  }

  graph(uri: string): BindingGraph | undefined {
    return this.files.get(workspaceUriKey(uri))?.graph ?? undefined;
  }

  bindingIndex(uri: string): BindingIndex | undefined {
    return this.files.get(workspaceUriKey(uri))?.bindingIndex ?? undefined;
  }

  module(uri: string): ModuleEntry | undefined {
    return this.modules.getModuleByUri(uri);
  }

  exportedDefinitionsForPackage(packageId: string): ExportedDefinition[] {
    return this.modules.exportedDefinitionsForPackage(packageId);
  }

  findExportedDefinitions(
    packageId: string,
    name: string,
    ns: string,
    kind?: string,
  ): ExportedDefinition[] {
    return this.modules.findExportedDefinitions(packageId, name, ns, kind);
  }

  findQualifiedDefinitions(
    uri: string,
    qualified: QualifiedModuleReference,
  ): ExportedDefinition[] {
    return this.modules.findQualifiedDefinitions(uri, qualified);
  }

  qualifiedReferenceForBinding(
    uri: string,
    referenceId: number,
    startByte?: number,
    endByte?: number,
  ): QualifiedModuleReference | null {
    return this.modules.qualifiedReferenceForBinding(uri, referenceId, startByte, endByte);
  }

  qualifiedReferenceAt(
    uri: string,
    startByte: number,
    endByte: number,
  ): QualifiedModuleReference | null {
    return this.modules.qualifiedReferenceAt(uri, startByte, endByte);
  }

  importsForAlias(uri: string, alias: string): ModuleImport[] {
    return this.modules.importsForAlias(uri, alias);
  }

  entriesForPackage(packageId: string): WorkspaceFileEntry[] {
    return [...this.files.values()]
      .filter((entry) => entry.packageId === packageId)
      .sort((a, b) => a.uri.localeCompare(b.uri));
  }

  isOpenEntryFresh(uri: string, text: string, version: number): boolean {
    const entry = this.files.get(workspaceUriKey(uri));
    return !!entry && entry.isOpen && entry.text === text && entry.version === version;
  }

  get size(): number {
    return this.files.size;
  }

  *entries(): IterableIterator<[string, WorkspaceFileEntry]> {
    for (const entry of this.files.values()) yield [entry.uri, entry];
  }

  dispose(freeTree?: (tree: ParseTree) => void): void {
    if (freeTree) {
      for (const entry of this.files.values()) {
        if (entry.tree) freeTree(entry.tree);
      }
    }
    this.files.clear();
    this.modules.clear();
    this.generations.clear();
  }

  private rebuildModuleEntries(): void {
    this.modules.clear();
    for (const entry of this.files.values()) {
      const moduleEntry = this.modules.upsertFile(
        entry.uri,
        entry.graph,
        metadataForEntry(entry),
      );
      entry.packageId = moduleEntry.packageId;
      entry.moduleId = moduleEntry.moduleId;
      entry.owningModuleId = moduleEntry.owningModuleId;
      entry.imports = moduleEntry.imports;
      entry.qualifiedReferences = moduleEntry.qualifiedReferences;
      entry.resolutionMode = moduleEntry.resolutionMode;
      entry.exportedDefinitions = moduleEntry.exportedDefinitions;
    }
  }

  private closedEntriesByAccess(): WorkspaceFileEntry[] {
    return [...this.files.values()]
      .filter((entry) => !entry.isOpen)
      .sort((a, b) =>
        a.lastAccessMs - b.lastAccessMs ||
        a.uri.localeCompare(b.uri));
  }
}

function metadataForEntry(entry: WorkspaceFileEntry): ModuleFileMetadata {
  return {
    owningModuleId: entry.owningModuleId,
    packageId: entry.packageId,
    moduleId: entry.moduleId,
    imports: entry.imports.map((item) => ({ ...item })),
    publicExportRanges: entry.exportedDefinitions
      .filter((item) => item.visibility === "public")
      .map((item) => ({ startByte: item.startByte, endByte: item.endByte })),
    qualifiedReferences: entry.qualifiedReferences.map((item) => ({ ...item })),
    resolutionMode: entry.resolutionMode,
  };
}

function cloneLineOffsets(offsets: Uint32Array): Uint32Array {
  return new Uint32Array(offsets);
}

export function extensionFromUri(uri: string): string {
  const clean = uri.split(/[?#]/, 1)[0];
  const slash = clean.lastIndexOf("/");
  const fileName = slash >= 0 ? clean.slice(slash + 1) : clean;
  const dot = fileName.lastIndexOf(".");
  if (dot < 0 || dot === fileName.length - 1) return "";
  const extension = fileName.slice(dot + 1);
  try {
    return decodeURIComponent(extension).toLowerCase();
  } catch {
    return extension.toLowerCase();
  }
}
