import type { BindingGraph, ParseTree } from "../../wasm/moonparse.js";
import type { BindingIndex } from "./binding-index.js";
import {
  ModuleGraph,
  type ExportedDefinition,
  type ModuleEntry,
  type ModuleImport,
} from "./module-graph.js";

export interface WorkspaceIndexConfig {
  enabled: boolean;
  maxFileBytes: number;
  maxFiles: number;
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
  packageId: string;
  moduleId: string;
  imports: ModuleImport[];
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
  tree: ParseTree;
  graph?: BindingGraph | null;
  bindingIndex?: BindingIndex | null;
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
  private files = new Map<string, WorkspaceFileEntry>();
  private modules = new ModuleGraph();

  constructor(private config: WorkspaceIndexConfig) {}

  updateConfig(config: WorkspaceIndexConfig): void {
    this.config = config;
  }

  setRoots(roots: string[]): void {
    this.roots = roots.map(normalizeUri).filter(Boolean).sort();
    this.modules.setRoots(this.roots);
    this.rebuildModuleEntries();
  }

  getRoots(): string[] {
    return [...this.roots];
  }

  isInWorkspace(uri: string): boolean {
    if (this.roots.length === 0) return true;
    const value = normalizeUri(uri);
    return this.roots.some((root) => value === root || value.startsWith(`${root}/`));
  }

  shouldIndexUri(
    uri: string,
    sizeBytes: number,
    enabledExtensions: string[],
  ): boolean {
    if (!this.config.enabled) return false;
    if (sizeBytes > this.config.maxFileBytes) return false;
    if (!this.isInWorkspace(uri)) return false;
    if (!enabledExtensions.includes(extensionFromUri(uri))) return false;
    if (!this.files.has(uri) && this.files.size >= this.config.maxFiles) return false;
    return true;
  }

  upsertParsedDocument(document: ParsedWorkspaceDocument): void {
    const moduleEntry = this.modules.upsertFile(document.uri, document.graph ?? null);
    this.files.set(document.uri, {
      uri: document.uri,
      text: document.text,
      lineOffsets: cloneLineOffsets(document.lineOffsets),
      languageId: document.languageId,
      version: document.version,
      mtimeMs: document.mtimeMs,
      sizeBytes: document.sizeBytes,
      isOpen: document.isOpen,
      packageId: moduleEntry.packageId,
      moduleId: moduleEntry.moduleId,
      imports: moduleEntry.imports,
      exportedDefinitions: moduleEntry.exportedDefinitions,
      tree: document.tree,
      graph: document.graph ?? null,
      bindingIndex: document.bindingIndex ?? null,
    });
  }

  markClosed(uri: string): void {
    const entry = this.files.get(uri);
    if (entry) entry.isOpen = false;
  }

  remove(uri: string, freeTree?: (tree: ParseTree) => void): void {
    const entry = this.files.get(uri);
    if (entry?.tree && freeTree) freeTree(entry.tree);
    this.files.delete(uri);
    this.modules.removeFile(uri);
  }

  clearRuntime(uri: string): void {
    const entry = this.files.get(uri);
    if (!entry) return;
    entry.tree = null;
    entry.graph = null;
    entry.bindingIndex = null;
    entry.imports = [];
    entry.exportedDefinitions = [];
    this.modules.removeFile(uri);
  }

  get(uri: string): WorkspaceFileEntry | undefined {
    return this.files.get(uri);
  }

  tree(uri: string): ParseTree | undefined {
    return this.files.get(uri)?.tree ?? undefined;
  }

  graph(uri: string): BindingGraph | undefined {
    return this.files.get(uri)?.graph ?? undefined;
  }

  bindingIndex(uri: string): BindingIndex | undefined {
    return this.files.get(uri)?.bindingIndex ?? undefined;
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

  entriesForPackage(packageId: string): WorkspaceFileEntry[] {
    return [...this.files.values()]
      .filter((entry) => entry.packageId === packageId)
      .sort((a, b) => a.uri.localeCompare(b.uri));
  }

  isOpenEntryFresh(uri: string, text: string, version: number): boolean {
    const entry = this.files.get(uri);
    return !!entry && entry.isOpen && entry.text === text && entry.version === version;
  }

  get size(): number {
    return this.files.size;
  }

  entries(): IterableIterator<[string, WorkspaceFileEntry]> {
    return this.files.entries();
  }

  dispose(freeTree?: (tree: ParseTree) => void): void {
    if (freeTree) {
      for (const entry of this.files.values()) {
        if (entry.tree) freeTree(entry.tree);
      }
    }
    this.files.clear();
    this.modules.clear();
  }

  private rebuildModuleEntries(): void {
    this.modules.clear();
    for (const entry of this.files.values()) {
      const moduleEntry = this.modules.upsertFile(entry.uri, entry.graph);
      entry.packageId = moduleEntry.packageId;
      entry.moduleId = moduleEntry.moduleId;
      entry.imports = moduleEntry.imports;
      entry.exportedDefinitions = moduleEntry.exportedDefinitions;
    }
  }
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

function normalizeUri(uri: string): string {
  let value = uri.trim();
  while (value.endsWith("/")) value = value.slice(0, -1);
  return process.platform === "win32" ? value.toLowerCase() : value;
}
