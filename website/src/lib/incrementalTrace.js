export function isValidRange(range) {
  return Boolean(range) &&
    Number.isFinite(range.startByte) &&
    Number.isFinite(range.endByte) &&
    range.startByte <= range.endByte
}

export function rangeOverlapsNode(range, nodeStart, nodeEnd) {
  if (!isValidRange(range)) return false
  if (nodeStart > nodeEnd) return false
  if (range.startByte === range.endByte) {
    return range.startByte >= nodeStart && range.startByte <= nodeEnd
  }
  return range.startByte < nodeEnd && range.endByte > nodeStart
}

export function rangeContainsNode(range, nodeStart, nodeEnd) {
  if (!isValidRange(range)) return false
  if (nodeStart >= nodeEnd) return false
  return range.startByte <= nodeStart && range.endByte >= nodeEnd
}

export function traceReuseRate(trace) {
  const total = Number(trace?.sourceByteLength ?? 0)
  if (total <= 0) return 0
  return Math.max(0, Math.min(1, Number(trace?.reusedByteCount ?? 0) / total))
}

export function formatTraceMs(value) {
  if (value == null || !Number.isFinite(Number(value))) return '—'
  return `${Number(value).toFixed(2)} ms`
}

export function formatTraceRange(range) {
  if (!isValidRange(range)) return '—'
  return `${range.startByte}–${range.endByte} bytes · ${range.startRow}:${range.startCol}–${range.endRow}:${range.endCol}`
}

export function classifyTraceNode(trace, nodeStart, nodeEnd) {
  const edit = trace?.edit?.newRange ?? null
  const reparse = trace?.reparseRange ?? null
  const reusedRanges = Array.isArray(trace?.reusedRanges) ? trace.reusedRanges : []
  return {
    edit: rangeOverlapsNode(edit, nodeStart, nodeEnd),
    reparse: rangeOverlapsNode(reparse, nodeStart, nodeEnd),
    reused: reusedRanges.some((range) => rangeContainsNode(range, nodeStart, nodeEnd)),
  }
}

export function traceDecorationRanges(trace) {
  if (!trace) return []
  const ranges = []
  for (const range of trace.reusedRanges ?? []) {
    if (isValidRange(range) && range.startByte < range.endByte) {
      ranges.push({ ...range, role: 'reused' })
    }
  }
  if (isValidRange(trace.reparseRange) && trace.reparseRange.startByte < trace.reparseRange.endByte) {
    ranges.push({ ...trace.reparseRange, role: 'reparse' })
  }
  const edit = trace.edit?.newRange
  if (isValidRange(edit) && edit.startByte < edit.endByte) {
    ranges.push({ ...edit, role: 'edit' })
  }
  return ranges
}
