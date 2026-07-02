import type {
  Range,
  TextEdit,
  WorkspaceEdit,
} from "vscode-languageserver";

import type {
  BindingGraph,
  BindingReference,
} from "../../wasm/moonparse.js";
import type { BindingIndex } from "./binding-index.js";
import type { DocumentEntry } from "./document-manager.js";
import type { ExportedDefinition } from "./module-graph.js";
import { ModuleGraph } from "./module-graph.js";
import type { ParseTableInfo } from "./parse-table-info.js";
import { isValidWordForTable } from "./parse-table-info.js";
import { byteRangeToUtf16 } from "./position.js";
import type { PrepareRenameResult } from "./rename.js";
import type { WorkspaceFileEntry, WorkspaceIndex } from "./workspace-index.js";
import {
  exportedDefinitionForLocal,
  isWorkspaceResolvableReference,
  workspaceCandidatesForReference,
  workspaceOccurrencesForExported,
} from "./workspace-bindings.js";

export type PrepareWorkspaceRenameOutcome =
  | { applies: false }
  | { applies: true; result: PrepareRenameResult | null };

export type WorkspaceRenameOutcome =
  | { applies: false }
  | { applies: true; edit: WorkspaceEdit | null };

export interface RebuiltWorkspaceFile {
  graph: BindingGraph | null;
  bindingIndex: BindingIndex | null;
}

export type RebuildWorkspaceFile = (
  file: WorkspaceFileEntry,
  text: string,
) => RebuiltWorkspaceFile | null;

export interface WorkspaceRenameOptions {
  rebuildFile?: RebuildWorkspaceFile;
  isOpenFileFresh?: (file: WorkspaceFileEntry) => boolean;
}

interface WorkspaceRenameTarget {
  exported: ExportedDefinition;
  hitStartByte: number;
  hitEndByte: number;
}

interface ByteEdit {
  startByte: number;
  endByte: number;
  newText: string;
}

export function prepareWorkspaceRename(
  entry: DocumentEntry,
  index: BindingIndex | undefined,
  workspace: WorkspaceIndex,
  tableInfo: ParseTableInfo,
  line: number,
  character: number,
): PrepareWorkspaceRenameOutcome {
  const resolved = resolveWorkspaceRenameTarget(entry, index, workspace, line, character);
  if (!resolved.applies) return resolved;
  if (!resolved.target) return { applies: true, result: null };
  if (!isValidWordForTable(tableInfo, resolved.target.exported.name)) {
    return { applies: true, result: null };
  }
  return {
    applies: true,
    result: {
      range: rangeForBytes(entry, resolved.target.hitStartByte, resolved.target.hitEndByte),
      placeholder: resolved.target.exported.name,
    },
  };
}

export function renameWorkspaceSymbol(
  entry: DocumentEntry,
  index: BindingIndex | undefined,
  workspace: WorkspaceIndex,
  tableInfo: ParseTableInfo,
  line: number,
  character: number,
  newName: string,
  options: WorkspaceRenameOptions = {},
): WorkspaceRenameOutcome {
  const resolved = resolveWorkspaceRenameTarget(entry, index, workspace, line, character);
  if (!resolved.applies) return resolved;
  const target = resolved.target;
  if (!target) return { applies: true, edit: null };

  const exported = target.exported;
  if (!isValidWordForTable(tableInfo, newName)) return { applies: true, edit: null };
  if (newName === exported.name) return { applies: true, edit: { changes: {} } };
  if (!isUniqueExport(workspace, exported)) return { applies: true, edit: null };
  if (hasExportNameConflict(workspace, exported, newName)) {
    return { applies: true, edit: null };
  }

  const occurrences = workspaceOccurrencesForExported(workspace, exported, true);
  if (!occurrences.some((occurrence) => occurrence.kind === "definition")) {
    return { applies: true, edit: null };
  }

  const byteEditsByUri = groupByteEdits(occurrences.map((occurrence) => ({
    uri: occurrence.uri,
    file: occurrence.file,
    edit: {
      startByte: occurrence.item.start_byte,
      endByte: occurrence.item.end_byte,
      newText: newName,
    },
  })));
  const affectedFiles = [...byteEditsByUri.values()].map((group) => group.file);

  if (!affectedFiles.every((file) => isRenameReadyFile(file, options))) {
    return { applies: true, edit: null };
  }
  if (!options.rebuildFile) return { applies: true, edit: null };
  if (!dryRunWorkspaceRename(workspace, exported, byteEditsByUri, options.rebuildFile)) {
    return { applies: true, edit: null };
  }

  const changes: Record<string, TextEdit[]> = {};
  for (const [uri, group] of byteEditsByUri) {
    changes[uri] = group.edits.map((edit) => ({
      range: byteRangeToUtf16(
        group.file.text,
        group.file.lineOffsets,
        edit.startByte,
        edit.endByte,
      ),
      newText: edit.newText,
    }));
  }
  return { applies: true, edit: { changes } };
}

function resolveWorkspaceRenameTarget(
  entry: DocumentEntry,
  index: BindingIndex | undefined,
  workspace: WorkspaceIndex,
  line: number,
  character: number,
): { applies: false } | { applies: true; target: WorkspaceRenameTarget | null } {
  if (!index) return { applies: false };
  const hit = index.getSymbolAt(entry, line, character);
  if (!hit) return { applies: false };

  const local = index.resolveSymbol(hit);
  if (local) {
    const exported = exportedDefinitionForLocal(workspace, entry.uri, local.definition);
    if (!exported) return { applies: false };
    return {
      applies: true,
      target: isUniqueExport(workspace, exported)
        ? { exported, hitStartByte: hit.startByte, hitEndByte: hit.endByte }
        : null,
    };
  }

  if (hit.kind !== "reference") return { applies: false };
  const reference = index.getReference(hit.id);
  if (!reference || !isWorkspaceResolvableReference(reference)) {
    return { applies: false };
  }
  const candidates = workspaceCandidatesForReference(workspace, entry.uri, reference);
  if (candidates.length === 0) return { applies: false };
  if (candidates.length > 1) return { applies: true, target: null };
  return {
    applies: true,
    target: {
      exported: candidates[0],
      hitStartByte: hit.startByte,
      hitEndByte: hit.endByte,
    },
  };
}

function isUniqueExport(workspace: WorkspaceIndex, exported: ExportedDefinition): boolean {
  const candidates = workspace.findExportedDefinitions(
    exported.packageId,
    exported.name,
    exported.ns,
  );
  return candidates.length === 1 && candidates[0].globalId === exported.globalId;
}

function hasExportNameConflict(
  workspace: WorkspaceIndex,
  exported: ExportedDefinition,
  newName: string,
): boolean {
  return workspace.findExportedDefinitions(exported.packageId, newName, exported.ns)
    .some((candidate) => candidate.globalId !== exported.globalId);
}

function isRenameReadyFile(
  file: WorkspaceFileEntry,
  options: WorkspaceRenameOptions,
): boolean {
  if (!file.text || !file.lineOffsets || !file.tree || !file.graph || !file.bindingIndex) {
    return false;
  }
  if (file.isOpen && options.isOpenFileFresh && !options.isOpenFileFresh(file)) {
    return false;
  }
  return true;
}

function groupByteEdits(
  items: Array<{ uri: string; file: WorkspaceFileEntry; edit: ByteEdit }>,
): Map<string, { file: WorkspaceFileEntry; edits: ByteEdit[] }> {
  const result = new Map<string, { file: WorkspaceFileEntry; edits: ByteEdit[] }>();
  for (const item of items) {
    let group = result.get(item.uri);
    if (!group) {
      group = { file: item.file, edits: [] };
      result.set(item.uri, group);
    }
    if (!group.edits.some((edit) =>
      edit.startByte === item.edit.startByte && edit.endByte === item.edit.endByte
    )) {
      group.edits.push(item.edit);
    }
  }
  for (const group of result.values()) {
    group.edits.sort((a, b) => a.startByte - b.startByte || a.endByte - b.endByte);
  }
  return result;
}

function dryRunWorkspaceRename(
  workspace: WorkspaceIndex,
  exported: ExportedDefinition,
  byteEditsByUri: Map<string, { file: WorkspaceFileEntry; edits: ByteEdit[] }>,
  rebuildFile: RebuildWorkspaceFile,
): boolean {
  const packageEntries = workspace.entriesForPackage(exported.packageId);
  if (packageEntries.length === 0) return false;

  const rebuilt = new Map<string, RebuiltWorkspaceFile>();
  for (const [uri, group] of byteEditsByUri) {
    const newText = applyByteEdits(group.file.text, group.edits);
    const next = rebuildFile(group.file, newText);
    if (!next?.graph || !next.bindingIndex) return false;
    rebuilt.set(uri, next);
  }

  for (const file of packageEntries) {
    const next = rebuilt.get(file.uri);
    if (!(next?.graph ?? file.graph) || !(next?.bindingIndex ?? file.bindingIndex)) {
      return false;
    }
  }

  const originalModuleGraph = new ModuleGraph();
  originalModuleGraph.setRoots(workspace.getRoots());
  for (const file of packageEntries) {
    originalModuleGraph.upsertFile(file.uri, file.graph);
  }

  const moduleGraph = new ModuleGraph();
  moduleGraph.setRoots(workspace.getRoots());
  for (const file of packageEntries) {
    moduleGraph.upsertFile(file.uri, rebuilt.get(file.uri)?.graph ?? file.graph);
  }

  if (moduleGraph.findExportedDefinitions(
    exported.packageId,
    byteEditsByUri.get(exported.uri)?.edits[0]?.newText ?? exported.name,
    exported.ns,
  ).length !== 1) {
    return false;
  }

  if (hasBlockingVirtualDiagnostics(packageEntries, rebuilt, moduleGraph, exported.packageId)) {
    return false;
  }

  return unchangedReferencesKeepTargets(
    packageEntries,
    rebuilt,
    byteEditsByUri,
    originalModuleGraph,
    moduleGraph,
  );
}

function hasBlockingVirtualDiagnostics(
  files: WorkspaceFileEntry[],
  rebuilt: Map<string, RebuiltWorkspaceFile>,
  moduleGraph: ModuleGraph,
  packageId: string,
): boolean {
  for (const file of files) {
    const index = rebuilt.get(file.uri)?.bindingIndex ?? file.bindingIndex;
    if (!index) return true;
    for (const diagnostic of index.diagnostics()) {
      if (diagnostic.kind === "duplicate" || diagnostic.kind === "ambiguous") {
        return true;
      }
      if (diagnostic.kind === "unresolved" && diagnostic.reference_id >= 0) {
        const reference = index.getReference(diagnostic.reference_id);
        if (!reference || virtualWorkspaceCandidates(moduleGraph, file.uri, reference).length !== 1) {
          return true;
        }
      }
    }
  }

  for (const exported of moduleGraph.exportedDefinitionsForPackage(packageId)) {
    if (moduleGraph.findExportedDefinitions(packageId, exported.name, exported.ns).length > 1) {
      return true;
    }
  }
  return false;
}

function unchangedReferencesKeepTargets(
  files: WorkspaceFileEntry[],
  rebuilt: Map<string, RebuiltWorkspaceFile>,
  byteEditsByUri: Map<string, { file: WorkspaceFileEntry; edits: ByteEdit[] }>,
  originalModuleGraph: ModuleGraph,
  moduleGraph: ModuleGraph,
): boolean {
  for (const file of files) {
    const oldIndex = file.bindingIndex;
    const nextIndex = rebuilt.get(file.uri)?.bindingIndex ?? oldIndex;
    if (!oldIndex || !nextIndex) return false;
    const edits = byteEditsByUri.get(file.uri)?.edits ?? [];

    for (const oldReference of oldIndex.allReferences()) {
      if (overlapsAnyEdit(oldReference, edits)) continue;
      const oldTarget = virtualReferenceTarget(
        originalModuleGraph,
        file.uri,
        oldIndex,
        oldReference,
      );
      const mappedStart = mapOffsetThroughEdits(oldReference.start_byte, edits);
      const mappedEnd = mappedStart + (oldReference.end_byte - oldReference.start_byte);
      const nextReference = nextIndex.allReferences().find((candidate) =>
        candidate.start_byte === mappedStart &&
        candidate.end_byte === mappedEnd &&
        candidate.name === oldReference.name &&
        candidate.ns === oldReference.ns);
      if (!nextReference) return false;
      const nextTarget = virtualReferenceTarget(moduleGraph, file.uri, nextIndex, nextReference);
      if (oldTarget !== nextTarget) return false;
    }
  }
  return true;
}

function virtualReferenceTarget(
  moduleGraph: ModuleGraph,
  uri: string,
  index: BindingIndex,
  reference: BindingReference,
): string {
  const local = index.findDefinition(reference.id);
  if (local) return `${uri}#def:${local.id}`;
  const candidates = virtualWorkspaceCandidates(moduleGraph, uri, reference);
  if (candidates.length === 1) return candidates[0].globalId;
  return candidates.length > 1 ? "ambiguous" : "unresolved";
}

function virtualWorkspaceCandidates(
  moduleGraph: ModuleGraph,
  uri: string,
  reference: BindingReference,
): ExportedDefinition[] {
  if (!isWorkspaceResolvableReference(reference)) return [];
  const module = moduleGraph.getModuleByUri(uri);
  if (!module) return [];
  return moduleGraph.findExportedDefinitions(module.packageId, reference.name, reference.ns);
}

function applyByteEdits(text: string, edits: ByteEdit[]): string {
  let result = text;
  const descending = [...edits].sort((a, b) => b.startByte - a.startByte);
  for (const edit of descending) {
    result = result.slice(0, edit.startByte) + edit.newText + result.slice(edit.endByte);
  }
  return result;
}

function overlapsAnyEdit(reference: BindingReference, edits: ByteEdit[]): boolean {
  return edits.some((edit) =>
    reference.start_byte < edit.endByte && edit.startByte < reference.end_byte);
}

function mapOffsetThroughEdits(offset: number, edits: ByteEdit[]): number {
  let delta = 0;
  for (const edit of edits) {
    if (offset <= edit.startByte) break;
    if (offset >= edit.endByte) {
      delta += edit.newText.length - (edit.endByte - edit.startByte);
    }
  }
  return offset + delta;
}

function rangeForBytes(entry: DocumentEntry, startByte: number, endByte: number): Range {
  return byteRangeToUtf16(entry.text, entry.lineOffsets, startByte, endByte);
}
