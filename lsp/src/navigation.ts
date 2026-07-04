import type { Location } from "vscode-languageserver";

import type { DocumentEntry } from "./document-manager.js";
import type { BindingIndex } from "./binding-index.js";
import { byteRangeToUtf16 } from "./position.js";
import type { BindingDefinition, BindingReference } from "../../wasm/moonparse.js";
import type { ExportedDefinition } from "./module-graph.js";
import type { WorkspaceFileEntry, WorkspaceIndex } from "./workspace-index.js";
import {
  exportedDefinitionForLocal,
  isWorkspaceResolvableReference,
  resolveWorkspaceReference,
  workspaceOccurrencesForExported,
} from "./workspace-bindings.js";

export function getDefinitionLocation(
  entry: DocumentEntry,
  index: BindingIndex | undefined,
  line: number,
  character: number,
): Location | null {
  const resolved = index?.resolveSymbolAt(entry, line, character);
  if (!resolved) return null;
  return bindingToLocation(entry.uri, entry, resolved.definition);
}

export function getReferenceLocations(
  entry: DocumentEntry,
  index: BindingIndex | undefined,
  line: number,
  character: number,
  includeDeclaration: boolean,
): Location[] {
  const resolved = index?.resolveSymbolAt(entry, line, character);
  if (!resolved || !index) return [];
  return index
    .referencesForDefinition(resolved.definition.id, includeDeclaration)
    .map((item) => bindingToLocation(entry.uri, entry, item));
}

export function getWorkspaceDefinitionLocation(
  entry: DocumentEntry,
  index: BindingIndex | undefined,
  workspace: WorkspaceIndex,
  line: number,
  character: number,
): Location | null {
  const hit = index?.getSymbolAt(entry, line, character);
  if (!hit || !index) return null;

  const local = index.resolveSymbol(hit);
  if (local) return bindingToLocation(entry.uri, entry, local.definition);
  if (hit.kind !== "reference") return null;

  const reference = index.getReference(hit.id);
  if (!reference) return null;

  const exported = resolveWorkspaceReference(workspace, entry.uri, reference);
  return exported ? exportedToLocation(workspace, exported) : null;
}

export function getWorkspaceReferenceLocations(
  entry: DocumentEntry,
  index: BindingIndex | undefined,
  workspace: WorkspaceIndex,
  line: number,
  character: number,
  includeDeclaration: boolean,
): Location[] {
  const hit = index?.getSymbolAt(entry, line, character);
  if (!hit || !index) return [];

  const local = index.resolveSymbol(hit);
  if (local) {
    const exported = exportedDefinitionForLocal(workspace, entry.uri, local.definition);
    if (exported) {
      return workspaceReferencesForExported(workspace, exported, includeDeclaration);
    }
    return getReferenceLocations(
      entry,
      index,
      line,
      character,
      includeDeclaration,
    );
  }

  if (hit.kind !== "reference") return [];
  const reference = index.getReference(hit.id);
  if (!reference) return [];
  const exported = resolveWorkspaceReference(workspace, entry.uri, reference);
  return exported
    ? workspaceReferencesForExported(workspace, exported, includeDeclaration)
    : [];
}

function bindingToLocation(
  uri: string,
  entry: DocumentEntry,
  item: BindingDefinition | BindingReference,
): Location {
  return {
    uri,
    range: byteRangeToUtf16(
      entry.text,
      entry.lineOffsets,
      item.start_byte,
      item.end_byte,
    ),
  };
}

function workspaceReferencesForExported(
  workspace: WorkspaceIndex,
  exported: ExportedDefinition,
  includeDeclaration: boolean,
): Location[] {
  return sortUniqueLocations(
    workspaceOccurrencesForExported(workspace, exported, includeDeclaration)
      .map((occurrence) => bindingToWorkspaceLocation(occurrence.file, occurrence.item)),
  );
}

function exportedToLocation(
  workspace: WorkspaceIndex,
  exported: ExportedDefinition,
): Location | null {
  const file = workspace.get(exported.uri);
  if (!file) return null;
  return {
    uri: exported.uri,
    range: byteRangeToUtf16(
      file.text,
      file.lineOffsets,
      exported.startByte,
      exported.endByte,
    ),
  };
}

function bindingToWorkspaceLocation(
  file: WorkspaceFileEntry,
  item: BindingDefinition | BindingReference,
): Location {
  return {
    uri: file.uri,
    range: byteRangeToUtf16(
      file.text,
      file.lineOffsets,
      item.start_byte,
      item.end_byte,
    ),
  };
}

function sortUniqueLocations(locations: Location[]): Location[] {
  const sorted = locations.sort((a, b) =>
    a.uri.localeCompare(b.uri) ||
    a.range.start.line - b.range.start.line ||
    a.range.start.character - b.range.start.character ||
    a.range.end.line - b.range.end.line ||
    a.range.end.character - b.range.end.character);
  const seen = new Set<string>();
  const result: Location[] = [];
  for (const location of sorted) {
    const key = [
      location.uri,
      location.range.start.line,
      location.range.start.character,
      location.range.end.line,
      location.range.end.character,
    ].join(":");
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(location);
  }
  return result;
}
