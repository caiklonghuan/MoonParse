import {
  DocumentHighlightKind,
  type DocumentHighlight,
} from "vscode-languageserver";

import type { DocumentEntry } from "./document-manager.js";
import type { BindingIndex } from "./binding-index.js";
import { byteOffsetToUtf16 } from "./position.js";

export function getDocumentHighlights(
  entry: DocumentEntry,
  index: BindingIndex | undefined,
  line: number,
  character: number,
): DocumentHighlight[] {
  if (!index || index.isEmpty()) return [];
  const hit = index.getSymbolAt(entry, line, character);
  if (!hit) return [];
  const resolved = index.resolveSymbol(hit);
  if (!resolved) return [];

  const definition = resolved.definition;
  const items: DocumentHighlight[] = [{
    range: {
      start: byteToPosition(entry, definition.start_byte),
      end: byteToPosition(entry, definition.end_byte),
    },
    kind: DocumentHighlightKind.Write,
  }];

  for (const ref of index.findReferences(definition.id)) {
    items.push({
      range: {
        start: byteToPosition(entry, ref.start_byte),
        end: byteToPosition(entry, ref.end_byte),
      },
      kind: DocumentHighlightKind.Read,
    });
  }

  return sortUniqueHighlights(items);
}

function byteToPosition(entry: DocumentEntry, byte: number): { line: number; character: number } {
  return byteOffsetToUtf16(entry.text, entry.lineOffsets, byte);
}

function sortUniqueHighlights(items: DocumentHighlight[]): DocumentHighlight[] {
  const sorted = items.sort((a, b) =>
    a.range.start.line - b.range.start.line ||
    a.range.start.character - b.range.start.character ||
    a.range.end.line - b.range.end.line ||
    a.range.end.character - b.range.end.character ||
    (a.kind ?? 0) - (b.kind ?? 0));
  const seen = new Set<string>();
  const result: DocumentHighlight[] = [];
  for (const item of sorted) {
    const key = `${item.range.start.line}:${item.range.start.character}:` +
      `${item.range.end.line}:${item.range.end.character}:${item.kind ?? 0}`;
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(item);
  }
  return result;
}
