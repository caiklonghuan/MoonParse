import assert from 'node:assert/strict'
import test from 'node:test'
import { resolve } from 'node:path'

import {
  createTreeSitterComparisonController,
  createTreeSitterRuntime,
} from '../lib/treeSitterCompare.js'

const assetBase = resolve('public/tree-sitter')

test('real Tree-sitter JSON WASM parses valid and UTF-8 JSON', async () => {
  const runtime = createTreeSitterRuntime({ assetBase })
  const valid = await runtime.compare('{"name":"MoonParse","emoji":"🌙"}', 'json')

  assert.equal(valid.status, 'ready', valid.error)
  assert.equal(valid.hasError, false)
  assert.equal(valid.errorCount, 0)
  assert.ok(valid.nodeCount > 5)
  assert.match(valid.sexp, /^\(document/)
  assert.match(valid.sexp, /\(object/)
  assert.match(valid.sexp, /\(pair/)
})

test('real Tree-sitter JSON WASM reports syntax errors', async () => {
  const runtime = createTreeSitterRuntime({ assetBase })
  const invalid = await runtime.compare('{"value": }', 'json')

  assert.equal(invalid.status, 'ready', invalid.error)
  assert.equal(invalid.hasError, true)
  assert.ok(invalid.errorCount > 0)
  assert.match(invalid.sexp, /(ERROR|MISSING)/)
})

test('unsupported languages are unavailable without loading WASM', async () => {
  let moduleLoads = 0
  const runtime = createTreeSitterRuntime({
    assetBase,
    loadModule: async () => {
      moduleLoads += 1
      throw new Error('must not load')
    },
  })

  const result = await runtime.compare('fn main {}', 'moonbit')
  assert.equal(result.status, 'unavailable')
  assert.match(result.error, /Supported: JSON/)
  assert.equal(moduleLoads, 0)
})

test('inactive comparison does not run and stale requests cannot overwrite', async () => {
  const results = []
  const timers = []
  const pending = new Map()
  const controller = createTreeSitterComparisonController({
    delay: 0,
    setTimer(callback) {
      timers.push(callback)
      return callback
    },
    clearTimer() {},
    run(source) {
      return new Promise((resolvePromise) => pending.set(source, resolvePromise))
    },
    onResult(result) {
      results.push(result)
    },
  })

  controller.update({ source: 'inactive', languageId: 'json', active: false })
  assert.equal(timers.length, 0)
  assert.equal(results.at(-1).status, 'idle')

  controller.update({ source: 'old', languageId: 'json', active: true })
  const oldRun = timers.shift()()
  controller.update({ source: 'new', languageId: 'json', active: true })
  const newRun = timers.shift()()

  pending.get('new')({ status: 'ready', languageId: 'json', sexp: '(new)' })
  await newRun
  assert.equal(results.at(-1).sexp, '(new)')

  pending.get('old')({ status: 'ready', languageId: 'json', sexp: '(old)' })
  await oldRun
  assert.equal(results.at(-1).sexp, '(new)')
  controller.dispose()
})

test('Tree-sitter load failure is isolated as an error result', async () => {
  const runtime = createTreeSitterRuntime({
    assetBase,
    loadModule: async () => { throw new Error('asset unavailable') },
  })
  const result = await runtime.compare('{}', 'json')
  assert.equal(result.status, 'error')
  assert.match(result.error, /asset unavailable/)
})
