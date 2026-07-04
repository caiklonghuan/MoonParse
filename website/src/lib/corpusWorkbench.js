import { MANIFEST_PATH } from './languagePackProject.js'

export function corpusCaseKey(testCase) {
  if (!testCase) return ''
  return `${testCase.path}\u0000${testCase.caseIndex}\u0000${testCase.name}`
}

function splitLines(text) {
  return String(text ?? '').replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n')
}

export function corpusManifestInfo(files = {}) {
  try {
    const manifest = JSON.parse(files[MANIFEST_PATH] ?? '{}')
    return {
      directory: manifest.corpus?.directory ?? 'corpus',
      format: manifest.corpus?.format ?? 'moonparse-corpus-v1',
      packId: typeof manifest.id === 'string' && manifest.id ? manifest.id : 'language-pack',
    }
  } catch {
    return {
      directory: 'corpus',
      format: 'moonparse-corpus-v1',
      packId: 'language-pack',
    }
  }
}

export function parseCorpusCases(path, text) {
  const lines = splitLines(text)
  const cases = []
  let index = 0
  while (index < lines.length) {
    while (index < lines.length && !lines[index].trim()) index += 1
    if (index >= lines.length) break
    if (lines[index].trim() !== '====') break
    index += 1
    if (index >= lines.length) break
    const name = lines[index].trim()
    index += 1
    if (index >= lines.length || lines[index].trim() !== '====') break
    index += 1
    const sourceLine = index + 1
    const sourceLines = []
    while (index < lines.length && lines[index].trim() !== '----') {
      sourceLines.push(lines[index])
      index += 1
    }
    if (index >= lines.length) break
    index += 1
    const expectationLine = index + 1
    const snapshotLines = []
    let inSnapshot = false
    let sawSnapshot = false
    while (index < lines.length && lines[index].trim() !== '====') {
      const raw = lines[index]
      const trimmed = raw.trim()
      if (inSnapshot && (raw.startsWith(' ') || raw.startsWith('\t'))) {
        snapshotLines.push(trimmed)
      } else {
        inSnapshot = false
        if (trimmed === 'sexp:') {
          sawSnapshot = true
          inSnapshot = true
        }
      }
      index += 1
    }
    cases.push({
      path,
      localCaseIndex: cases.length,
      name,
      sourceLine,
      expectationLine,
      source: sourceLines.join('\n'),
      expectedSexp: sawSnapshot ? snapshotLines.join('\n') : null,
    })
  }
  return cases
}

export function corpusSourceForCase(files, testCase) {
  const parsed = parseCorpusCases(testCase.path, files?.[testCase.path] ?? '')
  const match = parsed.find((item) =>
    item.name === testCase.name && item.sourceLine === testCase.sourceLine)
  return match?.source ?? parsed.find((item) => item.name === testCase.name)?.source ?? ''
}

export function localCorpusCaseIndex(files, testCase) {
  const parsed = parseCorpusCases(testCase.path, files?.[testCase.path] ?? '')
  const match = parsed.find((item) =>
    item.name === testCase.name && item.sourceLine === testCase.sourceLine)
  if (match) return match.localCaseIndex
  const nameMatch = parsed.find((item) => item.name === testCase.name)
  return nameMatch?.localCaseIndex ?? testCase.caseIndex
}

function firstDifferenceIndex(left, right) {
  const length = Math.max(left.length, right.length)
  for (let index = 0; index < length; index += 1) {
    if (left[index] !== right[index]) return index
  }
  return -1
}

function compactLargeDiff(expectedLines, actualLines, context) {
  const first = firstDifferenceIndex(expectedLines, actualLines)
  if (first < 0) {
    return expectedLines.map((text, index) => ({ type: 'equal', text, leftLine: index + 1, rightLine: index + 1 }))
  }
  const start = Math.max(0, first - context)
  const expectedEnd = Math.min(expectedLines.length, first + context + 1)
  const actualEnd = Math.min(actualLines.length, first + context + 1)
  const result = []
  if (start > 0) result.push({ type: 'omitted', text: `${start} unchanged line(s) omitted before first difference` })
  for (let index = start; index < first; index += 1) {
    result.push({ type: 'equal', text: expectedLines[index], leftLine: index + 1, rightLine: index + 1 })
  }
  for (let index = first; index < expectedEnd; index += 1) {
    result.push({ type: 'remove', text: expectedLines[index] ?? '', leftLine: index + 1, rightLine: null })
  }
  for (let index = first; index < actualEnd; index += 1) {
    result.push({ type: 'add', text: actualLines[index] ?? '', leftLine: null, rightLine: index + 1 })
  }
  if (expectedEnd < expectedLines.length || actualEnd < actualLines.length) {
    result.push({ type: 'omitted', text: 'remaining lines omitted' })
  }
  return result
}

export function createLineDiff(expected, actual, { maxLines = 5000, context = 100 } = {}) {
  const expectedLines = splitLines(expected)
  const actualLines = splitLines(actual)
  if (expectedLines.length + actualLines.length > maxLines) {
    return compactLargeDiff(expectedLines, actualLines, context)
  }

  const rows = expectedLines.length
  const columns = actualLines.length
  const previous = new Uint32Array(columns + 1)
  const current = new Uint32Array(columns + 1)
  const direction = new Uint8Array((rows + 1) * (columns + 1))
  const offset = (row, column) => row * (columns + 1) + column

  for (let row = 1; row <= rows; row += 1) {
    current.fill(0)
    for (let column = 1; column <= columns; column += 1) {
      if (expectedLines[row - 1] === actualLines[column - 1]) {
        current[column] = previous[column - 1] + 1
        direction[offset(row, column)] = 1
      } else if (previous[column] >= current[column - 1]) {
        current[column] = previous[column]
        direction[offset(row, column)] = 2
      } else {
        current[column] = current[column - 1]
        direction[offset(row, column)] = 3
      }
    }
    previous.set(current)
  }

  const result = []
  let row = rows
  let column = columns
  while (row > 0 || column > 0) {
    const step = row > 0 && column > 0 ? direction[offset(row, column)] : 0
    if (row > 0 && column > 0 && step === 1) {
      result.push({ type: 'equal', text: expectedLines[row - 1], leftLine: row, rightLine: column })
      row -= 1
      column -= 1
    } else if (row > 0 && (column === 0 || step === 2)) {
      result.push({ type: 'remove', text: expectedLines[row - 1], leftLine: row, rightLine: null })
      row -= 1
    } else {
      result.push({ type: 'add', text: actualLines[column - 1], leftLine: null, rightLine: column })
      column -= 1
    }
  }
  return result.reverse()
}

export function hasSexpFailure(testCase) {
  return Boolean(testCase?.failures?.some((failure) =>
    String(failure?.kind ?? '').toLowerCase() === 'sexp'))
}

export function collectSnapshotUpdates(cases, files, { selectedKey = null, all = false } = {}) {
  const selectedCases = cases.filter((testCase) => {
    if (testCase.passed || !hasSexpFailure(testCase) || !testCase.actualSexp) return false
    return all || corpusCaseKey(testCase) === selectedKey
  })
  const groups = new Map()
  for (const testCase of selectedCases) {
    if (!Object.prototype.hasOwnProperty.call(files, testCase.path)) continue
    const group = groups.get(testCase.path) ?? {
      path: testCase.path,
      text: files[testCase.path],
      updates: [],
    }
    group.updates.push({
      caseIndex: localCorpusCaseIndex(files, testCase),
      caseName: testCase.name,
      sexp: testCase.actualSexp,
    })
    groups.set(testCase.path, group)
  }
  return [...groups.values()]
}

export function sanitizeDownloadId(value) {
  return String(value ?? 'language-pack').replace(/[^A-Za-z0-9._-]+/g, '-').replace(/^-+|-+$/g, '') || 'language-pack'
}

export function bundleDownloadFileName(bundleJson) {
  try {
    const bundle = JSON.parse(bundleJson)
    return `${sanitizeDownloadId(bundle.pack?.id)}.language-bundle.json`
  } catch {
    return 'language-pack.language-bundle.json'
  }
}

export function downloadTextFile(text, fileName, type = 'application/json') {
  if (typeof document === 'undefined' || typeof URL === 'undefined') {
    throw new Error('Browser download APIs are unavailable.')
  }
  const url = URL.createObjectURL(new Blob([text], { type }))
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = fileName
  anchor.click()
  setTimeout(() => URL.revokeObjectURL(url), 0)
}
