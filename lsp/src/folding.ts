import {
  FoldingRangeKind,
  type FoldingRange,
} from "vscode-languageserver";

import type { CaptureResult } from "../../wasm/moonparse.js";
import type { DocumentEntry } from "./document-manager.js";
import { byteOffsetToUtf16 } from "./position.js";

export function foldingRangesFromCaptures(
  entry: DocumentEntry,
  captures: CaptureResult[],
): FoldingRange[] {
  const ranges: FoldingRange[] = [];
  const seen = new Set<string>();

  for (const capture of captures) {
    if (!isFoldCapture(capture.capture)) continue;
    const start = byteOffsetToUtf16(entry.text, entry.lineOffsets, capture.start);
    const rawEnd = byteOffsetToUtf16(entry.text, entry.lineOffsets, capture.end);
    const endLine = rawEnd.character === 0 && rawEnd.line > start.line
      ? rawEnd.line - 1
      : rawEnd.line;
    if (start.line >= endLine) continue;

    const kind = foldingKind(capture.capture);
    const key = `${start.line}:${endLine}:${kind ?? ""}`;
    if (seen.has(key)) continue;
    seen.add(key);
    ranges.push({
      startLine: start.line,
      endLine,
      kind,
    });
  }

  return ranges.sort((a, b) =>
    a.startLine - b.startLine ||
    a.endLine - b.endLine ||
    String(a.kind ?? "").localeCompare(String(b.kind ?? "")));
}

function isFoldCapture(capture: string): boolean {
  return capture === "fold" ||
    capture === "fold.region" ||
    capture === "fold.comment" ||
    capture === "fold.imports";
}

function foldingKind(capture: string): FoldingRangeKind | undefined {
  if (capture === "fold.comment") return FoldingRangeKind.Comment;
  if (capture === "fold.imports") return FoldingRangeKind.Imports;
  if (capture === "fold.region") return FoldingRangeKind.Region;
  return undefined;
}
