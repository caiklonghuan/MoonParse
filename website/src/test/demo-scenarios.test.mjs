import assert from 'node:assert/strict'
import test from 'node:test'

import { DEMO_SCENARIOS, findDemoScenario } from '../data/demoScenarios.js'
import {
  decodePlaygroundState,
  encodePlaygroundState,
  normalizeLoadedState,
} from '../composables/useUrlState.js'

test('demo scenario ids are unique and discoverable', () => {
  const ids = DEMO_SCENARIOS.map((scenario) => scenario.id)
  assert.deepEqual([...new Set(ids)], ids)
  for (const id of ids) {
    assert.equal(findDemoScenario(id)?.id, id)
  }
  assert.equal(findDemoScenario('missing-demo'), null)
})

test('demo scenario states are URL-shareable', async () => {
  for (const scenario of DEMO_SCENARIOS) {
    const normalized = normalizeLoadedState(scenario.state)
    assert.ok(normalized, `${scenario.id} should normalize`)
    const decoded = await decodePlaygroundState(await encodePlaygroundState(scenario.state))
    assert.equal(decoded.kind, normalized.kind, scenario.id)
    assert.equal(decoded.queryMode, normalized.queryMode, scenario.id)
    assert.equal(decoded.previewTab, normalized.previewTab, scenario.id)
    assert.equal(decoded.outputTab, normalized.outputTab, scenario.id)
  }
})

test('Pack demo contains a source project with a manifest', () => {
  const demo = findDemoScenario('pack-main-flow')
  assert.equal(demo.state.kind, 'source-pack')
  assert.equal(demo.state.project.mode, 'source')
  assert.equal(typeof demo.state.project.files['language-pack.json'], 'string')
  const manifest = JSON.parse(demo.state.project.files['language-pack.json'])
  assert.equal(manifest.id, 'json')
  assert.equal(demo.state.packBottomTab, 'corpus')
})

test('debug demos open the expected modes and panels', () => {
  assert.equal(findDemoScenario('query-debug').state.queryMode, 'query')
  assert.equal(findDemoScenario('query-debug').state.previewTab, 'query')

  const binding = findDemoScenario('binding-graph').state
  assert.equal(binding.queryMode, 'bindings')
  assert.ok(binding.queryModePatterns.bindings.includes('@definition'))
  assert.equal(binding.previewTab, 'query')

  const conflict = findDemoScenario('lr-conflict').state
  assert.equal(conflict.previewTab, 'output')
  assert.equal(conflict.outputTab, 'diagnostics')
  assert.match(conflict.grammar, /expr "\+" expr/)

  const incremental = findDemoScenario('incremental-trace').state
  assert.equal(incremental.incrementalTraceEnabled, true)
  assert.equal(incremental.previewTab, 'output')
  assert.equal(incremental.outputTab, 'incremental')

  const lint = findDemoScenario('lint-quick-fix').state
  assert.equal(lint.kind, 'source-pack')
  assert.equal(lint.packBottomTab, 'lint')
  assert.match(lint.source, /-0/)
})
