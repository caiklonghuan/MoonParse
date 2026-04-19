import { StateField } from '@codemirror/state'
import { Decoration, EditorView } from '@codemirror/view'

const GRAMMAR_KEYWORDS = new Set([
  'start',
  'extras',
  'precedence',
  'rule',
  'token',
  'word',
  'conflicts',
  'supertypes',
  'externals',
  'left',
  'right',
  'nonassoc',
  'dynamic',
  'prec',
  'alias',
])

const GRAMMAR_ATTRIBUTES = new Set([
  'inline',
  'hide',
  'deprecated',
])

const QUERY_PREDICATES = new Set([
  '#eq?',
  '#match?',
])

const GRAMMAR_OPERATORS = new Set([':', '|', '*', '+', '?', '(', ')', '[', ']', '{', '}', ',', '!', '&', '.'])
const QUERY_OPERATORS = new Set(['(', ')', ':'])

function isWhitespace(char) {
  return char === ' ' || char === '\t' || char === '\n' || char === '\r'
}

function isDigit(char) {
  if (!char) return false
  return char >= '0' && char <= '9'
}

function isIdentStart(char) {
  if (!char) return false
  return (char >= 'a' && char <= 'z') || (char >= 'A' && char <= 'Z') || char === '_'
}

function isIdentPart(char) {
  return isIdentStart(char) || isDigit(char) || char === '-'
}

function isCapturePart(char) {
  return isIdentPart(char) || char === '.'
}

function isPredicatePart(char) {
  return isIdentPart(char) || char === '?' || char === '!'
}

function readWhile(text, start, predicate) {
  let index = start
  while (index < text.length && predicate(text[index])) {
    index += 1
  }
  return index
}

function skipWhitespace(text, start) {
  return readWhile(text, start, isWhitespace)
}

function readString(text, start, quote = '"') {
  let index = start + 1
  let escaped = false

  while (index < text.length) {
    const char = text[index]
    if (escaped) {
      escaped = false
    } else if (char === '\\') {
      escaped = true
    } else if (char === quote) {
      return { end: index + 1, terminated: true }
    }
    index += 1
  }

  return { end: text.length, terminated: false }
}

function pushRange(ranges, from, to, className) {
  if (to > from) {
    ranges.push({ from, to, className })
  }
}

function scanLineComment(text, start, prefixLength, ranges) {
  let end = start + prefixLength
  while (end < text.length && text[end] !== '\n') {
    end += 1
  }
  pushRange(ranges, start, end, 'cm-dsl-comment')
  return end
}

function scanBlockComment(text, start, ranges) {
  let index = start + 2
  while (index + 1 < text.length) {
    if (text[index] === '*' && text[index + 1] === '/') {
      const end = index + 2
      pushRange(ranges, start, end, 'cm-dsl-comment')
      return end
    }
    index += 1
  }

  pushRange(ranges, start, text.length, 'cm-dsl-error')
  return text.length
}

function scanRegexLiteral(text, start, ranges) {
  let index = start + 1
  let charClassStart = -1

  while (index < text.length) {
    const char = text[index]

    if (char === '\\') {
      if (index + 1 >= text.length) {
        pushRange(ranges, start, text.length, 'cm-dsl-error')
        return text.length
      }
      pushRange(ranges, index, index + 2, 'cm-dsl-regex-escape')
      index += 2
      continue
    }

    if (char === '[' && charClassStart < 0) {
      charClassStart = index
      index += 1
      continue
    }

    if (char === ']' && charClassStart >= 0) {
      pushRange(ranges, charClassStart, index + 1, 'cm-dsl-regex-charclass')
      charClassStart = -1
      index += 1
      continue
    }

    if (char === '\n' || char === '\r') {
      pushRange(ranges, start, index, 'cm-dsl-error')
      return index
    }

    if (char === '/' && charClassStart < 0) {
      const end = index + 1
      pushRange(ranges, start, end, 'cm-dsl-regex')
      return end
    }

    index += 1
  }

  pushRange(ranges, start, text.length, 'cm-dsl-error')
  return text.length
}

function scanGrammar(text) {
  const ranges = []
  let index = 0
  let expectRuleName = false

  while (index < text.length) {
    const char = text[index]

    if (char === '\n' || char === '\r') {
      expectRuleName = false
      index += 1
      continue
    }

    if (isWhitespace(char)) {
      index += 1
      continue
    }

    if (char === '/' && text[index + 1] === '/') {
      index = scanLineComment(text, index, 2, ranges)
      continue
    }

    if (char === '/' && text[index + 1] === '*') {
      index = scanBlockComment(text, index, ranges)
      continue
    }

    if (char === '"') {
      const { end, terminated } = readString(text, index, '"')
      pushRange(ranges, index, end, terminated ? 'cm-dsl-string' : 'cm-dsl-error')
      index = end
      continue
    }

    if (char === "'") {
      const { end } = readString(text, index, "'")
      pushRange(ranges, index, end, 'cm-dsl-error')
      index = end
      continue
    }

    if (char === '/') {
      index = scanRegexLiteral(text, index, ranges)
      continue
    }

    if (char === '@') {
      const end = readWhile(text, index + 1, isIdentPart)
      if (end === index + 1) {
        pushRange(ranges, index, index + 1, 'cm-dsl-error')
        index += 1
        continue
      }

      const name = text.slice(index + 1, end)
      pushRange(ranges, index, end, GRAMMAR_ATTRIBUTES.has(name) ? 'cm-dsl-attribute' : 'cm-dsl-tag')
      index = end
      continue
    }

    if ((char === '-' && isDigit(text[index + 1])) || isDigit(char)) {
      const start = index
      index += char === '-' ? 1 : 0
      index = readWhile(text, index, isDigit)
      pushRange(ranges, start, index, 'cm-dsl-number')
      continue
    }

    if (isIdentStart(char)) {
      const start = index
      const end = readWhile(text, index + 1, isIdentPart)
      const word = text.slice(start, end)
      const nextChar = text[skipWhitespace(text, end)]

      let className = 'cm-dsl-name'
      if (expectRuleName) {
        className = 'cm-dsl-rule-name'
        expectRuleName = false
      } else if (GRAMMAR_KEYWORDS.has(word)) {
        className = 'cm-dsl-keyword'
        if (word === 'rule') {
          expectRuleName = true
        }
      } else if (nextChar === ':') {
        className = 'cm-dsl-field'
      }

      pushRange(ranges, start, end, className)
      index = end
      continue
    }

    if (GRAMMAR_OPERATORS.has(char)) {
      pushRange(ranges, index, index + 1, 'cm-dsl-operator')
      index += 1
      continue
    }

    pushRange(ranges, index, index + 1, 'cm-dsl-error')
    index += 1
  }

  return ranges
}

function scanQuery(text) {
  const ranges = []
  let index = 0

  while (index < text.length) {
    const char = text[index]

    if (isWhitespace(char)) {
      index += 1
      continue
    }

    if (char === ';') {
      index = scanLineComment(text, index, 1, ranges)
      continue
    }

    if (char === '"') {
      const { end, terminated } = readString(text, index, '"')
      pushRange(ranges, index, end, terminated ? 'cm-dsl-string' : 'cm-dsl-error')
      index = end
      continue
    }

    if (char === "'") {
      const { end } = readString(text, index, "'")
      pushRange(ranges, index, end, 'cm-dsl-error')
      index = end
      continue
    }

    if (char === '@') {
      const end = readWhile(text, index + 1, isCapturePart)
      if (end === index + 1) {
        pushRange(ranges, index, index + 1, 'cm-dsl-error')
        index += 1
        continue
      }

      pushRange(ranges, index, end, 'cm-dsl-capture')
      index = end
      continue
    }

    if (char === '#') {
      const end = readWhile(text, index + 1, isPredicatePart)
      if (end === index + 1) {
        pushRange(ranges, index, index + 1, 'cm-dsl-error')
        index += 1
        continue
      }

      const predicate = text.slice(index, end)
      pushRange(ranges, index, end, QUERY_PREDICATES.has(predicate) ? 'cm-dsl-predicate' : 'cm-dsl-error')
      index = end
      continue
    }

    if ((char === '-' && isDigit(text[index + 1])) || isDigit(char)) {
      const start = index
      index += char === '-' ? 1 : 0
      index = readWhile(text, index, isDigit)
      pushRange(ranges, start, index, 'cm-dsl-number')
      continue
    }

    if (char === '_') {
      pushRange(ranges, index, index + 1, 'cm-dsl-keyword')
      index += 1
      continue
    }

    if (isIdentStart(char)) {
      const start = index
      const end = readWhile(text, index + 1, isIdentPart)
      const nextChar = text[skipWhitespace(text, end)]
      pushRange(ranges, start, end, nextChar === ':' ? 'cm-dsl-field' : 'cm-dsl-name')
      index = end
      continue
    }

    if (QUERY_OPERATORS.has(char)) {
      pushRange(ranges, index, index + 1, 'cm-dsl-operator')
      index += 1
      continue
    }

    pushRange(ranges, index, index + 1, 'cm-dsl-error')
    index += 1
  }

  return ranges
}

function buildDecorationSet(docText, scanner) {
  const marks = scanner(docText).map((range) =>
    Decoration.mark({ class: range.className }).range(range.from, range.to),
  )
  marks.sort((left, right) => left.from - right.from || left.to - right.to)
  return marks.length ? Decoration.set(marks, true) : Decoration.none
}

function createDslSyntaxField(scanner) {
  return StateField.define({
    create(state) {
      return buildDecorationSet(state.doc.toString(), scanner)
    },
    update(decorations, transaction) {
      if (transaction.docChanged) {
        return buildDecorationSet(transaction.state.doc.toString(), scanner)
      }
      return decorations.map(transaction.changes)
    },
    provide: (field) => EditorView.decorations.from(field),
  })
}

export const moonGrammarSyntax = createDslSyntaxField(scanGrammar)
export const moonQuerySyntax = createDslSyntaxField(scanQuery)