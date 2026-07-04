import test from 'node:test'
import assert from 'node:assert/strict'
import {
  classifyTraceNode,
  formatTraceRange,
  rangeContainsNode,
  rangeOverlapsNode,
  traceDecorationRanges,
  traceReuseRate,
} from '../lib/incrementalTrace.js'

test('trace range overlap and containment handle normal and zero-width ranges', () => {
  assert.equal(rangeOverlapsNode({ startByte: 2, endByte: 5 }, 4, 8), true)
  assert.equal(rangeOverlapsNode({ startByte: 2, endByte: 5 }, 5, 8), false)
  assert.equal(rangeOverlapsNode({ startByte: 5, endByte: 5 }, 0, 5), true)
  assert.equal(rangeContainsNode({ startByte: 2, endByte: 8 }, 3, 7), true)
  assert.equal(rangeContainsNode({ startByte: 2, endByte: 8 }, 1, 7), false)
})

test('trace node classification combines edit, reparse, and reused ranges', () => {
  const trace = {
    edit: { newRange: { startByte: 4, endByte: 6 } },
    reparseRange: { startByte: 3, endByte: 9 },
    reusedRanges: [
      { kind: 'leaf', startByte: 0, endByte: 3 },
      { kind: 'subtree', startByte: 9, endByte: 12 },
    ],
  }
  assert.deepEqual(classifyTraceNode(trace, 1, 2), {
    edit: false,
    reparse: false,
    reused: true,
  })
  assert.deepEqual(classifyTraceNode(trace, 5, 7), {
    edit: true,
    reparse: true,
    reused: false,
  })
})

test('reuse rate and decoration ranges are deterministic', () => {
  const trace = {
    edit: { newRange: { startByte: 4, endByte: 5 } },
    reparseRange: { startByte: 3, endByte: 6 },
    reusedRanges: [{ kind: 'leaf', startByte: 0, endByte: 3 }],
    reusedByteCount: 3,
    sourceByteLength: 12,
  }
  assert.equal(traceReuseRate(trace), 0.25)
  assert.deepEqual(traceDecorationRanges(trace).map((range) => range.role), [
    'reused',
    'reparse',
    'edit',
  ])
})

test('trace range formatting is stable', () => {
  assert.equal(
    formatTraceRange({
      startByte: 1,
      endByte: 4,
      startRow: 0,
      startCol: 1,
      endRow: 0,
      endCol: 4,
    }),
    '1–4 bytes · 0:1–0:4',
  )
})
