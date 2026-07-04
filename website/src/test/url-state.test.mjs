import assert from 'node:assert/strict'
import test from 'node:test'

import {
  decodePlaygroundState,
  encodePlaygroundState,
  normalizeLoadedState,
} from '../composables/useUrlState.js'
import { createPresetProject } from '../lib/languagePackProject.js'

function legacyHash(value) {
  return `#playground=${Buffer.from(JSON.stringify(value), 'utf8').toString('base64')}`
}

function bundleJson(id = 'shared-bundle') {
  return JSON.stringify({
    schemaVersion: 1,
    pack: { id, version: '0.1.0' },
    grammarJson: '{}',
    parseTable: { json: '{}', binaryBase64: 'AA==' },
    queries: {},
    capabilities: {},
  })
}

test('normalizes legacy v1 playground state', async () => {
  const state = await decodePlaygroundState(legacyHash({
    g: 'start document',
    s: 'hello',
    q: '(document) @root',
    h: '(document) @keyword',
  }))
  assert.equal(state.kind, 'grammar')
  assert.equal(state.grammar, 'start document')
  assert.equal(state.source, 'hello')
  assert.equal(state.query, '(document) @root')
  assert.equal(state.highlight, '(document) @keyword')
  assert.equal(state.queryMode, 'query')
})

test('round-trips v2 grammar state', async () => {
  const original = normalizeLoadedState({
    v: 2,
    kind: 'grammar',
    grammar: 'start n\nrule n: /[0-9]+/',
    source: '42',
    query: '(n) @number',
    highlight: '(n) @number',
    queryMode: 'query',
    queryModePatterns: { locals: '(n) @local.reference' },
    incrementalTraceEnabled: true,
    previewTab: 'output',
    packBottomTab: 'diagnostics',
    outputTab: 'incremental',
  })
  const encoded = await encodePlaygroundState(original)
  const decoded = await decodePlaygroundState(`#playground=${encoded}`)
  assert.deepEqual(decoded, {
    ...original,
    queryModePatterns: {
      locals: '(n) @local.reference',
      bindings: '',
      folding: '',
    },
  })
})

test('round-trips v2 source Pack state', async () => {
  const project = createPresetProject('json')
  const original = normalizeLoadedState({
    v: 2,
    kind: 'source-pack',
    grammar: project.files['grammar/main.grammar'],
    source: '{"x": 1}',
    query: '(pair) @pair',
    highlight: project.files['queries/highlights.scm'],
    queryMode: 'query',
    queryModePatterns: {},
    incrementalTraceEnabled: false,
    previewTab: 'query',
    packBottomTab: 'corpus',
    outputTab: 'sexp',
    project: {
      files: project.files,
      selectedPath: 'grammar/main.grammar',
      mode: 'source',
      bundleJson: null,
    },
  })
  const decoded = await decodePlaygroundState(await encodePlaygroundState(original))
  assert.equal(decoded.kind, 'source-pack')
  assert.equal(decoded.project.mode, 'source')
  assert.equal(decoded.project.selectedPath, 'grammar/main.grammar')
  assert.equal(decoded.project.files['language-pack.json'], project.files['language-pack.json'])
  assert.equal(decoded.previewTab, 'query')
  assert.equal(decoded.packBottomTab, 'corpus')
})

test('round-trips v2 Bundle state', async () => {
  const json = bundleJson()
  const decoded = await decodePlaygroundState(await encodePlaygroundState({
    v: 2,
    kind: 'bundle',
    source: '{"demo": true}',
    query: '',
    queryMode: 'query',
    project: {
      files: {},
      selectedPath: null,
      mode: 'bundle',
      bundleJson: json,
    },
  }))
  assert.equal(decoded.kind, 'bundle')
  assert.equal(decoded.project.mode, 'bundle')
  assert.equal(decoded.project.bundleJson, json)
  assert.deepEqual(decoded.project.files, {})
})

test('compressed payloads decode and invalid payloads are safe', async () => {
  const state = {
    v: 2,
    kind: 'grammar',
    grammar: `start doc\nrule doc: /x+/\n// ${'x'.repeat(5000)}`,
    source: 'x'.repeat(5000),
    query: '(doc) @root',
  }
  const encoded = await encodePlaygroundState(state, { forceCompress: true })
  if (typeof CompressionStream !== 'undefined') assert.match(encoded, /^z\./)
  const decoded = await decodePlaygroundState(`#playground=${encoded}`)
  assert.equal(decoded.grammar, state.grammar)
  assert.equal(await decodePlaygroundState('#playground=not-base64'), null)
  assert.equal(await decodePlaygroundState(''), null)
  assert.equal(normalizeLoadedState({ v: 2, kind: 'source-pack', project: { files: { a: 1 } } }), null)
})

test('restores the Tree-sitter compare output tab', async () => {
  const decoded = await decodePlaygroundState(await encodePlaygroundState({
    v: 2,
    kind: 'grammar',
    grammar: 'start json\nrule json: "{}"',
    source: '{}',
    outputTab: 'compare',
  }))
  assert.equal(decoded.outputTab, 'compare')
})

test('restores the Pack lint bottom tab', async () => {
  const project = createPresetProject('json')
  const decoded = await decodePlaygroundState(await encodePlaygroundState({
    v: 2,
    kind: 'source-pack',
    source: '{"value": -0}',
    packBottomTab: 'lint',
    project: {
      files: project.files,
      selectedPath: 'language-pack.json',
      mode: 'source',
      bundleJson: null,
    },
  }))
  assert.equal(decoded.packBottomTab, 'lint')
})
