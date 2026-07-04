function numberOr(value, fallback = 0) {
  const number = Number(value)
  return Number.isFinite(number) ? number : fallback
}

export function captureRange(capture) {
  const startByte = numberOr(capture?.startByte ?? capture?.start_byte ?? capture?.start)
  const endByte = numberOr(capture?.endByte ?? capture?.end_byte ?? capture?.end, startByte)
  return {
    startByte: Math.min(startByte, endByte),
    endByte: Math.max(startByte, endByte),
  }
}

export function normalizeCapture(capture, index = 0) {
  const range = captureRange(capture)
  return {
    ...capture,
    capture: String(capture?.capture ?? ''),
    text: String(capture?.text ?? ''),
    startByte: range.startByte,
    endByte: range.endByte,
    startRow: numberOr(capture?.startRow ?? capture?.start_row),
    startCol: numberOr(capture?.startCol ?? capture?.start_col),
    endRow: numberOr(capture?.endRow ?? capture?.end_row),
    endCol: numberOr(capture?.endCol ?? capture?.end_col),
    resultIndex: index,
  }
}

export function groupQueryCaptures(captures = []) {
  const groups = []
  const byMatchId = new Map()

  captures.forEach((rawCapture, index) => {
    const capture = normalizeCapture(rawCapture, index)
    const hasMatchId = rawCapture?.match_id !== undefined && rawCapture?.match_id !== null
    const key = hasMatchId ? `match:${rawCapture.match_id}` : `result:${index}`
    let group = byMatchId.get(key)
    if (!group) {
      group = {
        key,
        matchId: hasMatchId ? rawCapture.match_id : null,
        captures: [],
      }
      byMatchId.set(key, group)
      groups.push(group)
    }
    group.captures.push(capture)
  })

  return groups
}

export function markLocalCaptures(groups, localReferenceMap = {}) {
  const localOffsets = new Set(
    Object.entries(localReferenceMap ?? {})
      .filter(([, isLocal]) => Boolean(isLocal))
      .map(([offset]) => Number(offset)),
  )
  return groups.map((group) => ({
    ...group,
    captures: group.captures.map((capture) => ({
      ...capture,
      isLocalReference: localOffsets.has(capture.startByte),
    })),
  }))
}

export function normalizeFoldingRanges(groups) {
  return groups.map((group) => ({
    ...group,
    captures: group.captures.map((capture) => ({
      ...capture,
      foldingRange: {
        startByte: capture.startByte,
        endByte: capture.endByte,
        startRow: capture.startRow,
        endRow: capture.endRow,
      },
    })),
  }))
}

export function updateQueryModePattern(patterns, mode, text) {
  return { ...(patterns ?? {}), [mode]: String(text ?? '') }
}

export function executeQueryMode(runtime, tree, pattern, mode = 'query') {
  let query = null
  try {
    query = runtime.compileQuery(pattern)
    const captures = query.exec(tree)
    const baseGroups = groupQueryCaptures(captures)
    if (mode === 'locals') {
      const localsMap = query.resolveLocals(tree) ?? {}
      return { groups: markLocalCaptures(baseGroups, localsMap), localsMap, bindingGraph: null }
    }
    if (mode === 'bindings') {
      const bindingGraph = query.resolveBindings(tree) ?? null
      return { groups: baseGroups, localsMap: {}, bindingGraph }
    }
    if (mode === 'folding') {
      return { groups: normalizeFoldingRanges(baseGroups), localsMap: {}, bindingGraph: null }
    }
    return { groups: baseGroups, localsMap: {}, bindingGraph: null }
  } finally {
    query?.free?.()
  }
}

function nodeRange(node) {
  const startByte = numberOr(node?.startByte ?? node?.start_byte)
  const endByte = numberOr(node?.endByte ?? node?.end_byte, startByte)
  return { startByte, endByte, span: Math.max(0, endByte - startByte) }
}

export function findBestCstNode(root, selectedRange) {
  if (!root || !selectedRange) return null
  const targetStart = numberOr(selectedRange.startByte)
  const targetEnd = numberOr(selectedRange.endByte, targetStart)
  const startByte = Math.min(targetStart, targetEnd)
  const endByte = Math.max(targetStart, targetEnd)
  let best = null

  function visit(node, path, depth) {
    const range = nodeRange(node)
    const contains = startByte === endByte
      ? range.startByte <= startByte && startByte <= range.endByte
      : range.startByte <= startByte && endByte <= range.endByte
    if (!contains) return

    const exact = range.startByte === startByte && range.endByte === endByte
    const candidate = { node, path, depth, exact, ...range }
    if (
      !best ||
      (candidate.exact && !best.exact) ||
      (candidate.exact === best.exact && candidate.span < best.span) ||
      (candidate.exact === best.exact && candidate.span === best.span && candidate.depth > best.depth)
    ) {
      best = candidate
    }

    for (let index = 0; index < (node.children ?? []).length; index += 1) {
      visit(node.children[index], `${path}.${index}`, depth + 1)
    }
  }

  visit(root, '0', 0)
  return best
}

export function ancestorNodeIds(nodeId) {
  if (!nodeId) return []
  const parts = String(nodeId).split('.')
  const ids = []
  for (let index = 1; index <= parts.length; index += 1) {
    ids.push(parts.slice(0, index).join('.'))
  }
  return ids
}
