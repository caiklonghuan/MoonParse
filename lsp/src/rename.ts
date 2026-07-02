import type {
  Range,
  TextEdit,
  WorkspaceEdit,
} from "vscode-languageserver";

import type {
  BindingDefinition,
  BindingReference,
} from "../../wasm/moonparse.js";
import type { BindingIndex, SymbolHit } from "./binding-index.js";
import type { DocumentEntry } from "./document-manager.js";
import type { ParseTableInfo } from "./parse-table-info.js";
import { isValidWordForTable } from "./parse-table-info.js";
import { byteRangeToUtf16 } from "./position.js";

export interface PrepareRenameResult {
  range: Range;
  placeholder: string;
}

export type RebuildBindingIndex = (text: string) => BindingIndex | null;

export function prepareRename(
  entry: DocumentEntry,
  index: BindingIndex | undefined,
  tableInfo: ParseTableInfo,
  line: number,
  character: number,
): PrepareRenameResult | null {
  const target = resolveRenameTarget(entry, index, line, character);
  if (!target) return null;
  if (!isValidWordForTable(tableInfo, target.definition.name)) return null;
  return {
    range: rangeForBytes(entry, target.hit.startByte, target.hit.endByte),
    placeholder: target.definition.name,
  };
}

export function renameSymbol(
  entry: DocumentEntry,
  index: BindingIndex | undefined,
  tableInfo: ParseTableInfo,
  line: number,
  character: number,
  newName: string,
  rebuildIndex?: RebuildBindingIndex,
): WorkspaceEdit | null {
  const target = resolveRenameTarget(entry, index, line, character);
  if (!target || !index) return null;
  const { definition } = target;

  if (!isValidWordForTable(tableInfo, newName)) return null;
  if (newName === definition.name) return { changes: { [entry.uri]: [] } };
  if (hasBlockingDiagnostic(index, definition)) return null;
  if (hasSameScopeDuplicate(index, definition, newName)) return null;

  const references = index.findReferences(definition.id);
  for (const ref of references) {
    if (!index.wouldResolveNameToDefinition(
      ref.scope_id,
      newName,
      definition.ns,
      definition.id,
    )) {
      return null;
    }
  }

  const renamedRefIds = new Set(references.map((ref) => ref.id));
  for (const ref of index.allReferences()) {
    if (renamedRefIds.has(ref.id)) continue;
    if (ref.name !== newName || ref.ns !== definition.ns) continue;
    if (index.wouldNameBeCapturedByDefinition(
      ref.scope_id,
      newName,
      definition.ns,
      definition.id,
    )) {
      return null;
    }
  }

  const occurrences = uniqueOccurrences([definition, ...references]);
  if (rebuildIndex) {
    const newText = applyRename(entry.text, occurrences, newName);
    const nextIndex = rebuildIndex(newText);
    if (!nextIndex || dryRunHasBlockingDiagnostic(nextIndex, newText, newName)) {
      return null;
    }
  }

  const edits: TextEdit[] = occurrences.map((occurrence) => ({
    range: rangeForBytes(entry, occurrence.start_byte, occurrence.end_byte),
    newText: newName,
  }));
  return { changes: { [entry.uri]: edits } };
}

function resolveRenameTarget(
  entry: DocumentEntry,
  index: BindingIndex | undefined,
  line: number,
  character: number,
): { hit: SymbolHit; definition: BindingDefinition } | null {
  if (!index || index.isEmpty()) return null;
  const hit = index.getSymbolAt(entry, line, character);
  if (!hit) return null;
  return index.resolveSymbol(hit);
}

function hasBlockingDiagnostic(
  index: BindingIndex,
  definition: BindingDefinition,
): boolean {
  const references = index.findReferences(definition.id);
  const refIds = new Set(references.map((ref) => ref.id));
  for (const diagnostic of index.diagnostics()) {
    if (diagnostic.kind !== "duplicate" &&
      diagnostic.kind !== "ambiguous" &&
      diagnostic.kind !== "unresolved") {
      continue;
    }
    if (diagnostic.definition_id === definition.id) return true;
    if (refIds.has(diagnostic.reference_id)) return true;
    if (overlaps(
      diagnostic.start_byte,
      diagnostic.end_byte,
      definition.start_byte,
      definition.end_byte,
    )) {
      return true;
    }
  }
  return false;
}

function hasSameScopeDuplicate(
  index: BindingIndex,
  definition: BindingDefinition,
  newName: string,
): boolean {
  return index.definitionsInScope(definition.scope_id).some((candidate) =>
    candidate.id !== definition.id &&
    candidate.ns === definition.ns &&
    candidate.name === newName);
}

function dryRunHasBlockingDiagnostic(
  index: BindingIndex,
  text: string,
  newName: string,
): boolean {
  for (const diagnostic of index.diagnostics()) {
    if (diagnostic.kind !== "duplicate" &&
      diagnostic.kind !== "ambiguous" &&
      diagnostic.kind !== "unresolved") {
      continue;
    }
    if (text.slice(diagnostic.start_byte, diagnostic.end_byte) === newName) {
      return true;
    }
  }
  return false;
}

function uniqueOccurrences(
  occurrences: Array<BindingDefinition | BindingReference>,
): Array<BindingDefinition | BindingReference> {
  const sorted = occurrences.sort((a, b) =>
    a.start_byte - b.start_byte ||
    a.end_byte - b.end_byte);
  const seen = new Set<string>();
  const result: Array<BindingDefinition | BindingReference> = [];
  for (const occurrence of sorted) {
    const key = `${occurrence.start_byte}:${occurrence.end_byte}`;
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(occurrence);
  }
  return result;
}

function applyRename(
  text: string,
  occurrences: Array<BindingDefinition | BindingReference>,
  newName: string,
): string {
  let result = text;
  const descending = [...occurrences].sort((a, b) => b.start_byte - a.start_byte);
  for (const occurrence of descending) {
    result = result.slice(0, occurrence.start_byte) +
      newName +
      result.slice(occurrence.end_byte);
  }
  return result;
}

function rangeForBytes(entry: DocumentEntry, startByte: number, endByte: number): Range {
  return byteRangeToUtf16(entry.text, entry.lineOffsets, startByte, endByte);
}

function overlaps(aStart: number, aEnd: number, bStart: number, bEnd: number): boolean {
  return aStart < bEnd && bStart < aEnd;
}
