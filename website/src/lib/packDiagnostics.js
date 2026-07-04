import { MANIFEST_PATH } from './languagePackProject.js'

const SEVERITY_RANK = Object.freeze({
  error: 0,
  warning: 1,
  warn: 1,
  info: 2,
  information: 2,
  hint: 3,
})

function asText(value) {
  return value == null ? '' : String(value)
}

function asNumber(value, fallback = 0) {
  const number = Number(value)
  return Number.isFinite(number) ? number : fallback
}

export function diagnosticSeverity(diagnostic) {
  return asText(diagnostic?.severity).toLowerCase()
}

export function diagnosticSeverityRank(diagnostic) {
  return SEVERITY_RANK[diagnosticSeverity(diagnostic)] ?? 4
}

export function diagnosticPath(diagnostic) {
  return asText(diagnostic?.path ?? diagnostic?.file ?? diagnostic?.uri)
}

export function diagnosticLine(diagnostic) {
  if (diagnostic?.line != null) return asNumber(diagnostic.line)
  if (diagnostic?.startLine != null) return asNumber(diagnostic.startLine)
  if (diagnostic?.start_line != null) return asNumber(diagnostic.start_line)
  return 0
}

export function diagnosticColumn(diagnostic) {
  if (diagnostic?.column != null) return asNumber(diagnostic.column)
  if (diagnostic?.startColumn != null) return asNumber(diagnostic.startColumn)
  if (diagnostic?.start_col != null) return asNumber(diagnostic.start_col)
  return 0
}

export function sortPackDiagnostics(diagnostics = []) {
  return [...diagnostics]
    .map((diagnostic, index) => ({ diagnostic, index }))
    .sort((left, right) => (
      diagnosticSeverityRank(left.diagnostic) - diagnosticSeverityRank(right.diagnostic) ||
      diagnosticPath(left.diagnostic).localeCompare(diagnosticPath(right.diagnostic)) ||
      diagnosticLine(left.diagnostic) - diagnosticLine(right.diagnostic) ||
      diagnosticColumn(left.diagnostic) - diagnosticColumn(right.diagnostic) ||
      asText(left.diagnostic?.code).localeCompare(asText(right.diagnostic?.code)) ||
      asText(left.diagnostic?.message).localeCompare(asText(right.diagnostic?.message)) ||
      left.index - right.index
    ))
    .map((entry) => entry.diagnostic)
}

export function hasErrorDiagnostics(diagnostics = []) {
  return diagnostics.some((diagnostic) => diagnosticSeverity(diagnostic) === 'error')
}

export function diagnosticDisplayLocation(diagnostic) {
  const path = diagnosticPath(diagnostic)
  if (!path) return ''
  return `${path}:${diagnosticLine(diagnostic) + 1}:${diagnosticColumn(diagnostic) + 1}`
}

export function isFileDiagnostic(diagnostic, files = {}) {
  const path = diagnosticPath(diagnostic)
  return Boolean(path && path !== '<project>' && Object.prototype.hasOwnProperty.call(files, path))
}

function positionToLineColumn(text, position) {
  const bounded = Math.max(0, Math.min(position, text.length))
  let line = 0
  let column = 0
  for (let index = 0; index < bounded; index += 1) {
    const char = text[index]
    if (char === '\n') {
      line += 1
      column = 0
    } else {
      column += 1
    }
  }
  return { line, column }
}

export function createManifestJsonDiagnostic(text) {
  try {
    JSON.parse(text)
    return null
  } catch (error) {
    const message = error?.message ?? String(error)
    const match = /position\s+(\d+)/i.exec(message)
    const location = match
      ? positionToLineColumn(text, Number(match[1]))
      : { line: 0, column: 0 }
    return {
      code: 'JSON_PARSE',
      severity: 'error',
      message: `Invalid ${MANIFEST_PATH}: ${message}`,
      path: MANIFEST_PATH,
      line: location.line,
      column: location.column,
      hint: null,
      local: true,
    }
  }
}
