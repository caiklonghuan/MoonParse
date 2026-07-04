import assert from 'node:assert/strict'
import test from 'node:test'

import {
  applyLintTextEdit,
  createLintController,
  lintDiagnosticCounts,
  lintRuleInventory,
  normalizeLintOptions,
  setLintRuleOption,
  setLintRuleSetOption,
  validatedLintEdit,
} from '../lib/lintWorkbench.js'

test('normalizes lint rule inventory and option overrides', () => {
  const language = {
    id: 'json',
    bundle: {
      lint: {
        ruleSets: [{
          id: 'recommended',
          enabledByDefault: true,
          rules: [{
            id: 'negative-zero',
            enabledByDefault: true,
            severity: 'warning',
            message: 'Use 0.',
            fix: { title: 'Replace' },
          }],
        }],
      },
    },
  }
  const inventory = lintRuleInventory(language)
  assert.equal(inventory[0].id, 'json/recommended')
  assert.equal(inventory[0].rules[0].id, 'json/recommended/negative-zero')
  assert.equal(inventory[0].rules[0].hasFix, true)

  let options = setLintRuleSetOption({}, 'json/recommended', 'off')
  options = setLintRuleOption(options, 'json/recommended/negative-zero', 'error')
  assert.deepEqual(options, {
    enabled: true,
    ruleSets: { 'json/recommended': false },
    rules: { 'json/recommended/negative-zero': 'error' },
  })
  assert.deepEqual(normalizeLintOptions({ rules: { bad: 'fatal' } }).rules, {})
})

test('validates UTF-8 lint edits and applies exact replacement', () => {
  const source = '😀值 = -0'
  const startByte = new TextEncoder().encode('😀值 = ').length
  const edit = { startByte, endByte: startByte + 2, replacement: '0' }
  assert.deepEqual(validatedLintEdit(source, edit), { from: 6, to: 8, insert: '0' })
  assert.equal(applyLintTextEdit(source, edit), '😀值 = 0')
  assert.equal(validatedLintEdit(source, { startByte: 1, endByte: 4, replacement: '' }), null)
  assert.throws(() => applyLintTextEdit(source, { startByte: -1, endByte: 0, replacement: '' }))
})

test('counts severities and ignores unknown values', () => {
  assert.deepEqual(lintDiagnosticCounts([
    { severity: 'error' },
    { severity: 'warning' },
    { severity: 'warning' },
    { severity: 'unknown' },
  ]), { error: 1, warning: 2, information: 0, hint: 0 })
})

test('lint controller is lazy and ignores superseded runs', async () => {
  const timers = []
  const states = []
  const pending = []
  const controller = createLintController({
    onState: (state) => states.push(state),
    setTimer(callback) {
      timers.push(callback)
      return callback
    },
    clearTimer() {},
  })
  const language = {
    lint(_tree, options) {
      return new Promise((resolve) => pending.push({ options, resolve }))
    },
  }
  controller.update({ active: false, language, tree: {}, source: 'old', options: {} })
  assert.equal(timers.length, 0)
  controller.update({ active: true, language, tree: {}, source: 'old', options: {} })
  timers.shift()()
  await Promise.resolve()
  controller.update({ active: true, language, tree: {}, source: 'new', options: { enabled: false } })
  timers.shift()()
  await Promise.resolve()
  pending[0].resolve([{ message: 'old' }])
  await Promise.resolve()
  pending[1].resolve([{ message: 'new' }])
  await Promise.resolve()
  assert.equal(states.at(-1).diagnostics[0].message, 'new')
  assert.equal(states.at(-1).sourceSnapshot, 'new')
  assert.equal(pending[1].options.enabled, false)
  controller.dispose()
})
