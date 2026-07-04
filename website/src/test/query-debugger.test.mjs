import test from 'node:test'
import assert from 'node:assert/strict'
import {
  ancestorNodeIds,
  executeQueryMode,
  findBestCstNode,
  groupQueryCaptures,
  markLocalCaptures,
  normalizeFoldingRanges,
  updateQueryModePattern,
} from '../lib/queryDebugger.js'
import {
  byteRangeToUtf16Range,
  utf16OffsetToPoint,
  utf16OffsetToUtf8Byte,
  utf16RangeToByteRange,
  utf8ByteToUtf16Offset,
  utf8Length,
} from '../lib/textOffsets.js'
import {
  buildBindingGraphScene,
  collectBindingGraphFacets,
  findBindingGraphNode,
  fitGraphViewport,
  panGraphViewport,
  zoomGraphViewport,
} from '../lib/bindingGraph.js'

test('groups captures by match_id while preserving encounter order', () => {
  const groups = groupQueryCaptures([
    { match_id: 2, capture: 'a', start: 0, end: 1 },
    { match_id: 1, capture: 'b', start: 2, end: 3 },
    { match_id: 2, capture: 'c', start: 4, end: 5 },
    { capture: 'orphan', start: 6, end: 7 },
    { capture: 'orphan-2', start: 8, end: 9 },
  ])
  assert.deepEqual(groups.map((group) => group.matchId), [2, 1, null, null])
  assert.deepEqual(groups[0].captures.map((capture) => capture.capture), ['a', 'c'])
})

test('marks local captures and creates folding ranges', () => {
  const groups = groupQueryCaptures([
    { match_id: 0, capture: 'local.reference', start: 4, end: 7, start_row: 1, end_row: 1 },
    { match_id: 0, capture: 'other', start: 8, end: 10, start_row: 2, end_row: 3 },
  ])
  const locals = markLocalCaptures(groups, { 4: true, 8: false })
  assert.equal(locals[0].captures[0].isLocalReference, true)
  assert.equal(locals[0].captures[1].isLocalReference, false)
  assert.deepEqual(normalizeFoldingRanges(groups)[0].captures[1].foldingRange, {
    startByte: 8,
    endByte: 10,
    startRow: 2,
    endRow: 3,
  })
})

test('keeps mode drafts immutable and always frees compiled queries', () => {
  const drafts = { locals: 'old' }
  const next = updateQueryModePattern(drafts, 'bindings', '(name) @reference')
  assert.deepEqual(drafts, { locals: 'old' })
  assert.deepEqual(next, { locals: 'old', bindings: '(name) @reference' })

  let frees = 0
  const runtime = {
    compileQuery() {
      return {
        exec: () => [{ match_id: 0, capture: 'name', start: 0, end: 4 }],
        resolveLocals: () => ({ 0: true }),
        free: () => { frees += 1 },
      }
    },
  }
  const result = executeQueryMode(runtime, {}, '(name) @local.reference', 'locals')
  assert.equal(result.groups[0].captures[0].isLocalReference, true)
  assert.equal(frees, 1)

  const failingRuntime = {
    compileQuery() {
      return {
        exec: () => { throw new Error('query failed') },
        free: () => { frees += 1 },
      }
    },
  }
  assert.throws(() => executeQueryMode(failingRuntime, {}, '(bad)', 'query'), /query failed/)
  assert.equal(frees, 2)
})

test('converts UTF-8 bytes and CodeMirror UTF-16 offsets safely', () => {
  const source = 'a中😀z'
  assert.equal(utf8Length(source), 9)
  assert.equal(utf16OffsetToUtf8Byte(source, 1), 1)
  assert.equal(utf16OffsetToUtf8Byte(source, 2), 4)
  assert.equal(utf16OffsetToUtf8Byte(source, 4), 8)
  assert.equal(utf8ByteToUtf16Offset(source, 3), 1)
  assert.equal(utf8ByteToUtf16Offset(source, 4), 2)
  assert.deepEqual(byteRangeToUtf16Range(source, 1, 8), { from: 1, to: 4 })
  assert.deepEqual(utf16RangeToByteRange(source, 1, 4), { startByte: 1, endByte: 8 })
  assert.deepEqual(utf16OffsetToPoint('甲\n😀x', 4), { row: 1, column: 1 })
})

test('finds the smallest exact or containing CST node', () => {
  const tree = {
    start_byte: 0,
    end_byte: 20,
    children: [
      { start_byte: 0, end_byte: 10, children: [{ start_byte: 2, end_byte: 5, children: [] }] },
      { start_byte: 10, end_byte: 20, children: [] },
    ],
  }
  assert.equal(findBestCstNode(tree, { startByte: 2, endByte: 5 }).path, '0.0.0')
  assert.equal(findBestCstNode(tree, { startByte: 3, endByte: 4 }).path, '0.0.0')
  assert.equal(findBestCstNode(tree, { startByte: 12, endByte: 12 }).path, '0.1')
  assert.equal(findBestCstNode(tree, { startByte: 21, endByte: 22 }), null)
  assert.deepEqual(ancestorNodeIds('0.2.3'), ['0', '0.2', '0.2.3'])
})

const bindingFixture = {
  uri: 'file:///fixture',
  scopes: [
    { id: 0, parent: -1, kind: 'module', start_byte: 0, end_byte: 100 },
    { id: 1, parent: 0, kind: 'function', start_byte: 10, end_byte: 90 },
    { id: 2, parent: 99, kind: 'block', start_byte: 50, end_byte: 80 },
    { id: 3, parent: 4, kind: 'block', start_byte: 60, end_byte: 70 },
    { id: 4, parent: 3, kind: 'block', start_byte: 61, end_byte: 69 },
  ],
  definitions: [
    { id: 10, name: 'x', kind: 'variable', ns: 'value', scope_id: 1, start_byte: 20, end_byte: 21, declaration_start_byte: 16, declaration_end_byte: 25 },
    { id: 11, name: 'T', kind: 'type', ns: 'type', scope_id: 0, start_byte: 2, end_byte: 3, declaration_start_byte: 0, declaration_end_byte: 5 },
  ],
  references: [
    { id: 20, name: 'x', kind: 'variable', ns: 'value', scope_id: 1, start_byte: 30, end_byte: 31, diagnose_unresolved: true },
    { id: 21, name: 'missing', kind: 'variable', ns: 'value', scope_id: 2, start_byte: 55, end_byte: 62, diagnose_unresolved: true },
  ],
  edges: [{ reference_id: 20, definition_id: 10 }],
  diagnostics: [
    { kind: 'unresolved', message: 'missing', reference_id: 21, definition_id: -1, start_byte: 55, end_byte: 62 },
    { kind: 'duplicate', message: 'duplicate x', reference_id: -1, definition_id: 10, start_byte: 20, end_byte: 21 },
    { kind: 'ambiguous', message: 'ambiguous x', reference_id: 20, definition_id: 10, start_byte: 30, end_byte: 31 },
  ],
}

test('lays out scope hierarchy and safely roots missing parents and cycles', () => {
  const scene = buildBindingGraphScene(bindingFixture)
  assert.equal(scene.uri, 'file:///fixture')
  assert.equal(scene.nodes.some((node) => node.key === 'scope:2'), true)
  assert.equal(scene.nodes.some((node) => node.key === 'scope:3'), true)
  assert.equal(scene.edges.length, 1)
  assert.match(scene.edges[0].path, /^M /)
  assert.equal(scene.stats.totalNodes, 9)
})

test('filters binding graph facets and diagnostics-only nodes', () => {
  assert.deepEqual(collectBindingGraphFacets(bindingFixture), {
    kinds: ['type', 'variable'],
    namespaces: ['type', 'value'],
    diagnosticKinds: ['ambiguous', 'duplicate', 'unresolved'],
  })
  const typeScene = buildBindingGraphScene(bindingFixture, { kind: 'type' })
  assert.deepEqual(typeScene.symbols.map((node) => node.key), ['definition:11'])
  const typeNamespace = buildBindingGraphScene(bindingFixture, { namespace: 'type' })
  assert.deepEqual(typeNamespace.symbols.map((node) => node.key), ['definition:11'])
  const unresolved = buildBindingGraphScene(bindingFixture, {
    diagnosticKind: 'unresolved',
    diagnosticsOnly: true,
  })
  assert.deepEqual(unresolved.symbols.map((node) => node.key), ['reference:21'])
  assert.equal(unresolved.diagnostics.length, 1)
  const duplicate = buildBindingGraphScene(bindingFixture, {
    diagnosticKind: 'duplicate',
    diagnosticsOnly: true,
  })
  assert.deepEqual(duplicate.symbols.map((node) => node.key), ['definition:10', 'reference:20'])
  const ambiguous = buildBindingGraphScene(bindingFixture, {
    diagnosticKind: 'ambiguous',
    diagnosticsOnly: true,
  })
  assert.deepEqual(ambiguous.symbols.map((node) => node.key), ['definition:10', 'reference:20'])
})

test('limits graph nodes and edges deterministically', () => {
  const definitions = Array.from({ length: 12 }, (_, id) => ({
    id, name: `d${id}`, kind: 'variable', ns: 'value', scope_id: 0, start_byte: id, end_byte: id + 1,
  }))
  const references = Array.from({ length: 12 }, (_, id) => ({
    id, name: `r${id}`, kind: 'variable', ns: 'value', scope_id: 0, start_byte: id + 20, end_byte: id + 21,
  }))
  const edges = Array.from({ length: 700 }, (_, index) => ({
    reference_id: index % 12,
    definition_id: (index * 7) % 12,
  }))
  const scene = buildBindingGraphScene({
    scopes: [{ id: 0, parent: -1, kind: 'module', start_byte: 0, end_byte: 100 }],
    definitions,
    references,
    edges,
  }, {}, { nodeLimit: 20, edgeLimit: 15 })
  assert.equal(scene.stats.renderedNodes, 20)
  assert.equal(scene.stats.truncatedNodes, 5)
  assert.equal(scene.stats.renderedEdges, 15)
  assert.ok(scene.stats.truncatedEdges > 0)

  const edgeLimited = buildBindingGraphScene({
    scopes: [{ id: 0, parent: -1, kind: 'module', start_byte: 0, end_byte: 100 }],
    definitions: definitions.slice(0, 1),
    references: references.slice(0, 1),
    edges: Array.from({ length: 601 }, () => ({ reference_id: 0, definition_id: 0 })),
  })
  assert.equal(edgeLimited.edges.length, 600)
  assert.equal(edgeLimited.stats.truncatedEdges, 1)
})

test('matches external ranges and calculates pan, zoom, and fit viewports', () => {
  const scene = buildBindingGraphScene(bindingFixture)
  assert.equal(findBindingGraphNode(scene, { startByte: 20, endByte: 21 }).key, 'definition:10')
  assert.deepEqual(panGraphViewport({ x: 1, y: 2, scale: 1 }, 4, -2), { x: 5, y: 0, scale: 1 })
  assert.deepEqual(zoomGraphViewport({ x: 0, y: 0, scale: 1 }, { x: 50, y: 50 }, 2), {
    x: -50, y: -50, scale: 2,
  })
  const fit = fitGraphViewport({ x: 0, y: 0, width: 200, height: 100 }, { width: 400, height: 300 }, 20)
  assert.equal(fit.scale, 1.8)
})
