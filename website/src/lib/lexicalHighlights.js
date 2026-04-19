const PYTHON_KEYWORDS = new Set([
  'and',
  'as',
  'assert',
  'async',
  'await',
  'break',
  'class',
  'continue',
  'def',
  'del',
  'elif',
  'else',
  'except',
  'finally',
  'for',
  'from',
  'global',
  'if',
  'import',
  'in',
  'is',
  'lambda',
  'nonlocal',
  'not',
  'or',
  'pass',
  'raise',
  'return',
  'try',
  'while',
  'with',
  'yield',
])

const PYTHON_CONSTANTS = new Set(['True', 'False', 'None'])

function isIdentStart(char) {
  if (!char) return false
  return (char >= 'a' && char <= 'z') || (char >= 'A' && char <= 'Z') || char === '_'
}

function isIdentPart(char) {
  return isIdentStart(char) || (char >= '0' && char <= '9')
}

function isStringPrefixChar(char) {
  return char === 'r' || char === 'R' || char === 'b' || char === 'B' || char === 'f' || char === 'F' || char === 'u' || char === 'U'
}

function pushRange(ranges, start, end, highlight) {
  if (end <= start) return
  ranges.push({
    highlight,
    start_byte: start,
    end_byte: end,
  })
}

function fillMask(maskChars, start, end) {
  for (let i = start; i < end; i += 1) {
    if (maskChars[i] !== '\n' && maskChars[i] !== '\r') {
      maskChars[i] = ' '
    }
  }
}

function detectPythonStringStart(source, index) {
  const direct = source[index]
  if (direct === '"' || direct === "'") {
    const triple = source.slice(index, index + 3) === direct.repeat(3)
    return {
      start: index,
      quote: direct,
      triple,
      endOffset: index + (triple ? 3 : 1),
    }
  }

  let probe = index
  while (probe < source.length && probe - index < 2 && isStringPrefixChar(source[probe])) {
    probe += 1
  }

  if (probe === index) return null

  const quote = source[probe]
  if (quote !== '"' && quote !== "'") return null

  const triple = source.slice(probe, probe + 3) === quote.repeat(3)
  return {
    start: index,
    quote,
    triple,
    endOffset: probe + (triple ? 3 : 1),
  }
}

function readPythonStringEnd(source, startInfo) {
  const delimiter = startInfo.triple ? startInfo.quote.repeat(3) : startInfo.quote
  let index = startInfo.endOffset

  while (index < source.length) {
    if (startInfo.triple) {
      if (source.slice(index, index + 3) === delimiter) {
        return index + 3
      }
      index += 1
      continue
    }

    const char = source[index]
    if (char === '\\') {
      index += 2
      continue
    }
    if (char === startInfo.quote) {
      return index + 1
    }
    if (char === '\n' || char === '\r') {
      return index
    }
    index += 1
  }

  return source.length
}

function maskPythonLiterals(source) {
  const maskChars = Array.from(source)
  const ranges = []
  let index = 0

  while (index < source.length) {
    const stringStart = detectPythonStringStart(source, index)
    if (stringStart) {
      const end = readPythonStringEnd(source, stringStart)
      pushRange(ranges, stringStart.start, end, 'string')
      fillMask(maskChars, stringStart.start, end)
      index = Math.max(end, index + 1)
      continue
    }

    if (source[index] === '#') {
      let end = index
      while (end < source.length && source[end] !== '\n' && source[end] !== '\r') {
        end += 1
      }
      pushRange(ranges, index, end, 'comment')
      fillMask(maskChars, index, end)
      index = end
      continue
    }

    index += 1
  }

  return {
    masked: maskChars.join(''),
    ranges,
  }
}

function collectLineStarts(source) {
  const starts = [0]
  for (let i = 0; i < source.length; i += 1) {
    if (source[i] === '\n') {
      starts.push(i + 1)
    }
  }
  return starts
}

function addRegexCaptureRanges(ranges, text, lineOffset, regex, groupIndex, highlight) {
  regex.lastIndex = 0
  let match = regex.exec(text)
  while (match) {
    const whole = match[0]
    const group = match[groupIndex]
    const groupOffset = whole.indexOf(group)
    if (groupOffset >= 0) {
      const start = lineOffset + match.index + groupOffset
      pushRange(ranges, start, start + group.length, highlight)
    }
    match = regex.exec(text)
  }
}

function addTypeHintRanges(ranges, line, lineOffset) {
  const typeHintRegex = /(:|->)\s*([A-Za-z_][A-Za-z0-9_]*)(\s*\[[^\]\n]+\])?/g
  let match = typeHintRegex.exec(line)

  while (match) {
    const fullMatch = match[0]
    const outerType = match[2]
    const outerOffset = fullMatch.indexOf(outerType)
    pushRange(
      ranges,
      lineOffset + match.index + outerOffset,
      lineOffset + match.index + outerOffset + outerType.length,
      'type',
    )

    const genericPart = match[3]
    if (genericPart) {
      const genericBase = lineOffset + match.index + fullMatch.indexOf(genericPart)
      const identRegex = /[A-Za-z_][A-Za-z0-9_]*/g
      let innerMatch = identRegex.exec(genericPart)
      while (innerMatch) {
        pushRange(
          ranges,
          genericBase + innerMatch.index,
          genericBase + innerMatch.index + innerMatch[0].length,
          'type',
        )
        innerMatch = identRegex.exec(genericPart)
      }
    }

    match = typeHintRegex.exec(line)
  }
}

function computePythonLexicalHighlightRanges(source) {
  if (!source?.trim()) return []

  const { masked, ranges } = maskPythonLiterals(source)
  const lineStarts = collectLineStarts(masked)

  for (let lineIndex = 0; lineIndex < lineStarts.length; lineIndex += 1) {
    const start = lineStarts[lineIndex]
    const end = lineIndex + 1 < lineStarts.length ? lineStarts[lineIndex + 1] - 1 : masked.length
    const line = masked.slice(start, end)

    addRegexCaptureRanges(ranges, line, start, /\bdef\s+([A-Za-z_][A-Za-z0-9_]*)/g, 1, 'function')
    addRegexCaptureRanges(ranges, line, start, /\bclass\s+([A-Za-z_][A-Za-z0-9_]*)/g, 1, 'type')
    addRegexCaptureRanges(ranges, line, start, /\bfrom\s+[A-Za-z_][A-Za-z0-9_.]*\s+import\s+([A-Za-z_][A-Za-z0-9_]*)/g, 1, 'type')
    addRegexCaptureRanges(ranges, line, start, /\.([A-Za-z_][A-Za-z0-9_]*)/g, 1, 'property')

    if (/\bdef\b|\bclass\b|->/.test(line)) {
      addTypeHintRanges(ranges, line, start)
    }
  }

  for (let index = 0; index < masked.length; ) {
    const char = masked[index]

    if (isIdentStart(char)) {
      const start = index
      index += 1
      while (index < masked.length && isIdentPart(masked[index])) {
        index += 1
      }
      const word = masked.slice(start, index)
      if (PYTHON_KEYWORDS.has(word)) {
        pushRange(ranges, start, index, 'keyword')
      } else if (PYTHON_CONSTANTS.has(word)) {
        pushRange(ranges, start, index, 'constant')
      }
      continue
    }

    if (char >= '0' && char <= '9') {
      const start = index
      index += 1
      while (index < masked.length && masked[index] >= '0' && masked[index] <= '9') {
        index += 1
      }
      if (masked[index] === '.') {
        index += 1
        while (index < masked.length && masked[index] >= '0' && masked[index] <= '9') {
          index += 1
        }
      }
      pushRange(ranges, start, index, 'number')
      continue
    }

    index += 1
  }

  ranges.sort((left, right) => {
    if (left.start_byte !== right.start_byte) return left.start_byte - right.start_byte
    if (left.end_byte !== right.end_byte) return left.end_byte - right.end_byte
    return left.highlight.localeCompare(right.highlight)
  })

  return ranges
}

export function computeLexicalHighlightRanges(presetId, source) {
  if (presetId === 'python') {
    return computePythonLexicalHighlightRanges(source)
  }
  return []
}

export function mergeHighlightRanges(primaryRanges, fallbackRanges) {
  if (!primaryRanges?.length) return fallbackRanges ?? []
  if (!fallbackRanges?.length) return primaryRanges ?? []

  const merged = [...primaryRanges]
  const seen = new Set(primaryRanges.map((range) => `${range.start_byte}:${range.end_byte}:${range.highlight}`))

  for (const range of fallbackRanges) {
    const key = `${range.start_byte}:${range.end_byte}:${range.highlight}`
    if (!seen.has(key)) {
      seen.add(key)
      merged.push(range)
    }
  }

  merged.sort((left, right) => {
    if (left.start_byte !== right.start_byte) return left.start_byte - right.start_byte
    if (left.end_byte !== right.end_byte) return left.end_byte - right.end_byte
    return left.highlight.localeCompare(right.highlight)
  })

  return merged
}