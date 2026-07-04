import test from 'node:test'
import assert from 'node:assert/strict'
import {
  conflictActionTitle,
  conflictStatus,
  normalizeConflictDiagnostic,
  normalizeConflictDiagnostics,
} from '../lib/conflictDiagnostics.js'

test('normalizes and sorts enriched conflict diagnostics', () => {
  const diagnostics = normalizeConflictDiagnostics([
    { severity: 'warn: resolved', state: 4, terminal: 2, terminalName: '+', actions: [], resolution: { kind: 'resolved' } },
    { severity: 'dynamic_conflict(id=1)', state: 2, terminal: 3, terminalName: '*', actions: [], resolution: { kind: 'dynamic-precedence' } },
    { severity: 'ambiguous: conflict', state: 2, terminal: 3, terminalName: '*', actions: [], resolution: { kind: 'ambiguous-glr' } },
  ])
  assert.deepEqual(diagnostics.map((item) => item.status), ['ambiguous', 'dynamic', 'warn'])
  assert.equal(diagnostics[0].extended, true)
})

test('supports legacy diagnostics without extended fields', () => {
  const object = normalizeConflictDiagnostic({ severity: 'warn: old', state: 1, terminal: 2 }, 0)
  assert.equal(object.status, 'warn')
  assert.equal(object.extended, false)
  assert.deepEqual(object.actions, [])
  const text = normalizeConflictDiagnostic('old parser warning', 1)
  assert.equal(text.status, 'legacy')
  assert.equal(text.message, 'old parser warning')
})

test('recognizes all conflict states and formats actions', () => {
  assert.equal(conflictStatus({ severity: 'warn: x' }), 'warn')
  assert.equal(conflictStatus({ severity: 'declared: x' }), 'declared')
  assert.equal(conflictStatus({ severity: 'ambiguous: x' }), 'ambiguous')
  assert.equal(conflictStatus({ severity: 'dynamic_conflict(id=2)' }), 'dynamic')
  assert.equal(conflictActionTitle({ kind: 'shift', targetState: 8 }), 'Shift to state 8')
  assert.equal(conflictActionTitle({ kind: 'reduce', productionId: 3, ruleName: 'expr' }), 'Reduce #3 · expr')
  assert.equal(conflictActionTitle({ kind: 'accept' }), 'Accept')
})

test('indexes branches and preserves path, items, and resolution', () => {
  const diagnostic = normalizeConflictDiagnostic({
    severity: 'declared: expected', state: 5, terminal: 1, terminalName: '+',
    actions: [{ index: 0, kind: 'reduce', body: ['expr'], display: 'expr → expr •' }],
    items: [{ productionId: 1, dot: 1, display: 'expr → expr •' }],
    statePath: [{ fromState: 0, toState: 5, symbolName: 'expr' }],
    branches: [{ actionIndex: 0, outcome: 'glr', message: 'expected' }],
    resolution: { kind: 'declared-glr', keptActionIndexes: [0], discardedActionIndexes: [] },
  })
  assert.equal(diagnostic.branchByAction.get(0).outcome, 'glr')
  assert.equal(diagnostic.statePath[0].toState, 5)
  assert.equal(diagnostic.items[0].dot, 1)
  assert.equal(diagnostic.resolution.kind, 'declared-glr')
})
