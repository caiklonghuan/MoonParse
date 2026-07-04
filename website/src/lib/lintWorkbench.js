import {
  byteRangeToUtf16Range,
  utf16OffsetToUtf8Byte,
  utf8Length,
} from './textOffsets.js'

export const LINT_SEVERITIES = Object.freeze(['error', 'warning', 'information', 'hint'])

export function lintRuleInventory(language) {
  const packId = String(language?.id ?? language?.bundle?.pack?.id ?? '')
  const ruleSets = language?.bundle?.lint?.ruleSets
  if (!packId || !Array.isArray(ruleSets)) return []
  return ruleSets.map((ruleSet) => ({
    id: `${packId}/${ruleSet.id}`,
    localId: String(ruleSet.id ?? ''),
    enabledByDefault: ruleSet.enabledByDefault !== false,
    rules: Array.isArray(ruleSet.rules)
      ? ruleSet.rules.map((rule) => ({
          id: `${packId}/${ruleSet.id}/${rule.id}`,
          localId: String(rule.id ?? ''),
          enabledByDefault: rule.enabledByDefault !== false,
          severity: LINT_SEVERITIES.includes(rule.severity) ? rule.severity : 'warning',
          message: String(rule.message ?? ''),
          hasFix: Boolean(rule.fix),
        }))
      : [],
  }))
}

export function normalizeLintOptions(value = {}) {
  const options = value && typeof value === 'object' && !Array.isArray(value) ? value : {}
  const ruleSets = {}
  const rules = {}
  for (const [id, enabled] of Object.entries(options.ruleSets ?? {})) {
    if (typeof enabled === 'boolean') ruleSets[id] = enabled
  }
  for (const [id, setting] of Object.entries(options.rules ?? {})) {
    if (setting === 'off' || LINT_SEVERITIES.includes(setting)) rules[id] = setting
  }
  return { enabled: options.enabled !== false, ruleSets, rules }
}

export function setLintRuleSetOption(options, id, setting) {
  const next = normalizeLintOptions(options)
  const ruleSets = { ...next.ruleSets }
  if (setting === 'default') delete ruleSets[id]
  else ruleSets[id] = setting === 'on'
  return { ...next, ruleSets }
}

export function setLintRuleOption(options, id, setting) {
  const next = normalizeLintOptions(options)
  const rules = { ...next.rules }
  if (setting === 'default') delete rules[id]
  else if (setting === 'off' || LINT_SEVERITIES.includes(setting)) rules[id] = setting
  return { ...next, rules }
}

export function lintDiagnosticCounts(diagnostics = []) {
  const counts = { error: 0, warning: 0, information: 0, hint: 0 }
  for (const item of diagnostics) {
    if (Object.hasOwn(counts, item?.severity)) counts[item.severity] += 1
  }
  return counts
}

export function validatedLintEdit(source, edit) {
  const text = String(source ?? '')
  const startByte = Number(edit?.startByte)
  const endByte = Number(edit?.endByte)
  if (!Number.isInteger(startByte) || !Number.isInteger(endByte)) return null
  if (startByte < 0 || startByte > endByte || endByte > utf8Length(text)) return null
  if (typeof edit?.replacement !== 'string') return null
  const { from, to } = byteRangeToUtf16Range(text, startByte, endByte)
  if (
    utf16OffsetToUtf8Byte(text, from) !== startByte ||
    utf16OffsetToUtf8Byte(text, to) !== endByte
  ) return null
  return { from, to, insert: edit.replacement }
}

export function applyLintTextEdit(source, edit) {
  const change = validatedLintEdit(source, edit)
  if (!change) throw new Error('Lint fix contains an invalid UTF-8 byte range.')
  const text = String(source ?? '')
  return text.slice(0, change.from) + change.insert + text.slice(change.to)
}

export function createLintController({
  delay = 150,
  onState = () => {},
  setTimer = (callback, timeout) => setTimeout(callback, timeout),
  clearTimer = (timer) => clearTimeout(timer),
} = {}) {
  let timer = null
  let requestId = 0
  let disposed = false

  function cancel() {
    requestId += 1
    if (timer != null) clearTimer(timer)
    timer = null
  }

  function update({ active, language, tree, source, options, immediate = false }) {
    cancel()
    if (!active || !language || !tree) return
    const current = requestId
    onState({ running: true, stale: true, error: null })
    const execute = async () => {
      timer = null
      try {
        const diagnostics = await Promise.resolve(language.lint(tree, normalizeLintOptions(options)))
        if (!disposed && current === requestId) {
          onState({ diagnostics, running: false, stale: false, error: null, sourceSnapshot: source })
        }
      } catch (error) {
        if (!disposed && current === requestId) {
          onState({ diagnostics: [], running: false, stale: true, error: error?.message ?? String(error) })
        }
      }
    }
    if (immediate) void execute()
    else timer = setTimer(execute, delay)
  }

  function dispose() {
    disposed = true
    cancel()
  }

  return { update, cancel, dispose }
}
