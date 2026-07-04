const DEFAULT_NODE_LIMIT = 300
const DEFAULT_EDGE_LIMIT = 600
const NODE_WIDTH = 156
const NODE_HEIGHT = 24
const SCOPE_MIN_WIDTH = 380
const SCOPE_HEADER = 30
const SCOPE_PADDING = 16
const ROW_GAP = 6
const CHILD_GAP = 14

function numberOr(value, fallback = 0) {
  const number = Number(value)
  return Number.isFinite(number) ? number : fallback
}

function stringOr(value, fallback = '') {
  return value == null ? fallback : String(value)
}

function normalizedRange(item) {
  const startByte = Math.max(0, numberOr(item?.start_byte ?? item?.startByte))
  const endByte = Math.max(startByte, numberOr(item?.end_byte ?? item?.endByte, startByte))
  return { startByte, endByte }
}

function normalizeScope(scope, index) {
  return {
    ...scope,
    id: numberOr(scope?.id, index),
    parent: numberOr(scope?.parent, -1),
    kind: stringOr(scope?.kind, 'scope'),
    ...normalizedRange(scope),
    sourceIndex: index,
  }
}

function normalizeSymbol(symbol, index, type) {
  return {
    ...symbol,
    id: numberOr(symbol?.id, index),
    name: stringOr(symbol?.name, `${type} ${index}`),
    kind: stringOr(symbol?.kind, 'unknown'),
    ns: stringOr(symbol?.ns, 'unknown'),
    scopeId: numberOr(symbol?.scope_id ?? symbol?.scopeId, -1),
    ...normalizedRange(symbol),
    sourceIndex: index,
    type,
  }
}

function normalizeDiagnostic(diagnostic, index) {
  return {
    ...diagnostic,
    key: `diagnostic:${index}`,
    kind: stringOr(diagnostic?.kind, 'unknown'),
    message: stringOr(diagnostic?.message),
    referenceId: numberOr(diagnostic?.reference_id ?? diagnostic?.referenceId, -1),
    definitionId: numberOr(diagnostic?.definition_id ?? diagnostic?.definitionId, -1),
    ...normalizedRange(diagnostic),
    sourceIndex: index,
    type: 'diagnostic',
  }
}

export function normalizeBindingGraph(graph = {}) {
  const scopes = (Array.isArray(graph.scopes) ? graph.scopes : []).map(normalizeScope)
  const definitions = (Array.isArray(graph.definitions) ? graph.definitions : [])
    .map((item, index) => normalizeSymbol(item, index, 'definition'))
  const references = (Array.isArray(graph.references) ? graph.references : [])
    .map((item, index) => normalizeSymbol(item, index, 'reference'))
  const edges = (Array.isArray(graph.edges) ? graph.edges : []).map((edge, index) => ({
    ...edge,
    key: `edge:${index}`,
    referenceId: numberOr(edge?.reference_id ?? edge?.referenceId, -1),
    definitionId: numberOr(edge?.definition_id ?? edge?.definitionId, -1),
    sourceIndex: index,
    type: 'edge',
  }))
  const diagnostics = (Array.isArray(graph.diagnostics) ? graph.diagnostics : [])
    .map(normalizeDiagnostic)
  return {
    uri: stringOr(graph.uri),
    scopes,
    definitions,
    references,
    edges,
    diagnostics,
  }
}

export function collectBindingGraphFacets(graph) {
  const normalized = normalizeBindingGraph(graph)
  return {
    kinds: [...new Set([...normalized.definitions, ...normalized.references].map((item) => item.kind))].sort(),
    namespaces: [...new Set([...normalized.definitions, ...normalized.references].map((item) => item.ns))].sort(),
    diagnosticKinds: [...new Set(normalized.diagnostics.map((item) => item.kind))].sort(),
  }
}

function findScopeCycles(scopes, scopeById) {
  const cycleIds = new Set()
  for (const scope of scopes) {
    const path = []
    const position = new Map()
    let current = scope
    while (current && current.parent >= 0 && scopeById.has(current.parent)) {
      if (position.has(current.id)) {
        const cycleStart = position.get(current.id)
        for (let index = cycleStart; index < path.length; index += 1) cycleIds.add(path[index])
        break
      }
      position.set(current.id, path.length)
      path.push(current.id)
      current = scopeById.get(current.parent)
    }
  }
  return cycleIds
}

function rangesOverlap(left, right) {
  return left.startByte <= right.endByte && right.startByte <= left.endByte
}

function filterGraph(normalized, filters) {
  const kind = filters.kind ?? 'all'
  const namespace = filters.namespace ?? 'all'
  const diagnosticKind = filters.diagnosticKind ?? 'all'
  const diagnosticsOnly = Boolean(filters.diagnosticsOnly)
  const diagnostics = normalized.diagnostics.filter((diagnostic) =>
    diagnosticKind === 'all' || diagnostic.kind === diagnosticKind)

  let definitions = normalized.definitions.filter((item) =>
    (kind === 'all' || item.kind === kind) && (namespace === 'all' || item.ns === namespace))
  let references = normalized.references.filter((item) =>
    (kind === 'all' || item.kind === kind) && (namespace === 'all' || item.ns === namespace))

  if (diagnosticsOnly) {
    const definitionIds = new Set()
    const referenceIds = new Set()
    for (const diagnostic of diagnostics) {
      if (diagnostic.definitionId >= 0) definitionIds.add(diagnostic.definitionId)
      if (diagnostic.referenceId >= 0) referenceIds.add(diagnostic.referenceId)
      for (const definition of definitions) {
        if (diagnostic.definitionId < 0 && rangesOverlap(diagnostic, definition)) definitionIds.add(definition.id)
      }
      for (const reference of references) {
        if (diagnostic.referenceId < 0 && rangesOverlap(diagnostic, reference)) referenceIds.add(reference.id)
      }
    }
    let changed = true
    while (changed) {
      changed = false
      for (const edge of normalized.edges) {
        if (referenceIds.has(edge.referenceId) && !definitionIds.has(edge.definitionId)) {
          definitionIds.add(edge.definitionId)
          changed = true
        }
        if (definitionIds.has(edge.definitionId) && !referenceIds.has(edge.referenceId)) {
          referenceIds.add(edge.referenceId)
          changed = true
        }
      }
    }
    definitions = definitions.filter((item) => definitionIds.has(item.id))
    references = references.filter((item) => referenceIds.has(item.id))
  }

  return { definitions, references, diagnostics, kind, namespace, diagnosticsOnly }
}

function createHierarchy(normalized, filtered) {
  const scopeById = new Map()
  for (const scope of normalized.scopes) {
    if (!scopeById.has(scope.id)) scopeById.set(scope.id, scope)
  }
  const cycleIds = findScopeCycles(normalized.scopes, scopeById)
  const root = {
    id: -1,
    kind: 'workspace',
    parent: -1,
    startByte: 0,
    endByte: Math.max(0, ...normalized.scopes.map((scope) => scope.endByte)),
    sourceIndex: -1,
    virtual: true,
    children: [],
    definitions: [],
    references: [],
  }
  const hierarchyById = new Map([[-1, root]])
  for (const scope of normalized.scopes) {
    if (!hierarchyById.has(scope.id)) {
      hierarchyById.set(scope.id, { ...scope, virtual: false, children: [], definitions: [], references: [] })
    }
  }
  for (const scope of normalized.scopes) {
    const node = hierarchyById.get(scope.id)
    if (!node) continue
    const parentId = scope.parent >= 0 && scopeById.has(scope.parent) && !cycleIds.has(scope.id)
      ? scope.parent
      : -1
    const parent = hierarchyById.get(parentId) ?? root
    if (!parent.children.includes(node)) parent.children.push(node)
  }

  for (const definition of filtered.definitions) {
    ;(hierarchyById.get(definition.scopeId) ?? root).definitions.push(definition)
  }
  for (const reference of filtered.references) {
    ;(hierarchyById.get(reference.scopeId) ?? root).references.push(reference)
  }

  const restrictive = filtered.kind !== 'all' || filtered.namespace !== 'all' || filtered.diagnosticsOnly
  if (restrictive) {
    const keep = new Set([-1])
    function keepScopeAndAncestors(initialScopeId) {
      let scopeId = hierarchyById.has(initialScopeId) ? initialScopeId : -1
      const seen = new Set()
      while (!seen.has(scopeId)) {
        seen.add(scopeId)
        keep.add(scopeId)
        const scope = scopeById.get(scopeId)
        if (!scope || scope.parent < 0 || !scopeById.has(scope.parent) || cycleIds.has(scopeId)) break
        scopeId = scope.parent
      }
    }
    for (const symbol of [...filtered.definitions, ...filtered.references]) {
      keepScopeAndAncestors(symbol.scopeId)
    }
    for (const diagnostic of filtered.diagnostics) {
      let best = null
      for (const scope of normalized.scopes) {
        if (scope.startByte <= diagnostic.startByte && diagnostic.endByte <= scope.endByte) {
          if (!best || scope.endByte - scope.startByte < best.endByte - best.startByte) best = scope
        }
      }
      if (best) keepScopeAndAncestors(best.id)
    }
    for (const node of hierarchyById.values()) {
      node.children = node.children.filter((child) => keep.has(child.id))
    }
  }
  return { root, hierarchyById }
}

function truncateHierarchy(root, nodeLimit) {
  let used = 0
  const renderedKeys = new Set()

  function visit(scope) {
    const copy = { ...scope, children: [], definitions: [], references: [] }
    if (!scope.virtual) {
      if (used >= nodeLimit) return null
      used += 1
      renderedKeys.add(`scope:${scope.id}`)
    }
    for (const definition of scope.definitions) {
      if (used >= nodeLimit) break
      copy.definitions.push(definition)
      used += 1
      renderedKeys.add(`definition:${definition.id}`)
    }
    for (const reference of scope.references) {
      if (used >= nodeLimit) break
      copy.references.push(reference)
      used += 1
      renderedKeys.add(`reference:${reference.id}`)
    }
    for (const child of scope.children) {
      if (used >= nodeLimit) break
      const childCopy = visit(child)
      if (childCopy) copy.children.push(childCopy)
    }
    return copy
  }

  return { root: visit(root), renderedKeys, used }
}

function measureScope(scope) {
  const rows = Math.max(scope.definitions.length, scope.references.length)
  const directHeight = rows * (NODE_HEIGHT + ROW_GAP)
  let childrenHeight = 0
  let widestChild = 0
  for (const child of scope.children) {
    measureScope(child)
    childrenHeight += child.height
    widestChild = Math.max(widestChild, child.width)
  }
  if (scope.children.length > 1) childrenHeight += (scope.children.length - 1) * CHILD_GAP
  const sections = (directHeight > 0 && childrenHeight > 0) ? CHILD_GAP : 0
  scope.width = Math.max(SCOPE_MIN_WIDTH, widestChild + SCOPE_PADDING * 2)
  scope.height = SCOPE_HEADER + SCOPE_PADDING * 2 + directHeight + sections + childrenHeight
}

function positionScope(scope, x, y, output) {
  scope.x = x
  scope.y = y
  const scopeNode = {
    key: scope.virtual ? 'scope:virtual' : `scope:${scope.id}`,
    type: 'scope',
    item: scope,
    x,
    y,
    width: scope.width,
    height: scope.height,
    label: scope.virtual ? 'Workspace' : `${scope.kind} #${scope.id}`,
    virtual: scope.virtual,
    startByte: scope.startByte,
    endByte: scope.endByte,
  }
  output.scopes.push(scopeNode)
  output.nodes.push(scopeNode)

  let contentY = y + SCOPE_HEADER + SCOPE_PADDING
  const definitionX = x + SCOPE_PADDING
  const referenceX = x + scope.width - SCOPE_PADDING - NODE_WIDTH
  scope.definitions.forEach((definition, index) => {
    const node = {
      key: `definition:${definition.id}`,
      type: 'definition',
      item: definition,
      x: definitionX,
      y: contentY + index * (NODE_HEIGHT + ROW_GAP),
      width: NODE_WIDTH,
      height: NODE_HEIGHT,
      label: definition.name,
      startByte: definition.startByte,
      endByte: definition.endByte,
    }
    output.symbols.push(node)
    output.nodes.push(node)
  })
  scope.references.forEach((reference, index) => {
    const node = {
      key: `reference:${reference.id}`,
      type: 'reference',
      item: reference,
      x: referenceX,
      y: contentY + index * (NODE_HEIGHT + ROW_GAP),
      width: NODE_WIDTH,
      height: NODE_HEIGHT,
      label: reference.name,
      startByte: reference.startByte,
      endByte: reference.endByte,
    }
    output.symbols.push(node)
    output.nodes.push(node)
  })
  const rows = Math.max(scope.definitions.length, scope.references.length)
  contentY += rows * (NODE_HEIGHT + ROW_GAP)
  if (rows && scope.children.length) contentY += CHILD_GAP
  for (const child of scope.children) {
    positionScope(child, x + SCOPE_PADDING, contentY, output)
    contentY += child.height + CHILD_GAP
  }
}

function attachDiagnostics(scene, diagnostics) {
  const byKey = new Map()
  const nodeByKey = new Map(scene.nodes.map((node) => [node.key, node]))
  for (const diagnostic of diagnostics) {
    let key = diagnostic.referenceId >= 0 ? `reference:${diagnostic.referenceId}` : null
    if (!nodeByKey.has(key) && diagnostic.definitionId >= 0) key = `definition:${diagnostic.definitionId}`
    if (!nodeByKey.has(key)) {
      let best = null
      for (const node of scene.nodes) {
        if (node.virtual) continue
        if (node.startByte <= diagnostic.startByte && diagnostic.endByte <= node.endByte) {
          const span = node.endByte - node.startByte
          if (!best || span < best.endByte - best.startByte) best = node
        }
      }
      key = best?.key ?? null
    }
    diagnostic.nodeKey = key
    if (key) {
      if (!byKey.has(key)) byKey.set(key, [])
      byKey.get(key).push(diagnostic)
    }
  }
  scene.diagnosticsByNodeKey = byKey
}

export function buildBindingGraphScene(graph, filters = {}, limits = {}) {
  const normalized = normalizeBindingGraph(graph)
  const filtered = filterGraph(normalized, filters)
  const { root } = createHierarchy(normalized, filtered)
  const nodeLimit = Math.max(1, numberOr(limits.nodeLimit, DEFAULT_NODE_LIMIT))
  const edgeLimit = Math.max(0, numberOr(limits.edgeLimit, DEFAULT_EDGE_LIMIT))
  const truncated = truncateHierarchy(root, nodeLimit)
  measureScope(truncated.root)
  const scene = { nodes: [], scopes: [], symbols: [], edges: [], diagnostics: filtered.diagnostics }
  positionScope(truncated.root, 20, 20, scene)

  const nodeByKey = new Map(scene.nodes.map((node) => [node.key, node]))
  const filteredDefinitionIds = new Set(filtered.definitions.map((item) => item.id))
  const filteredReferenceIds = new Set(filtered.references.map((item) => item.id))
  const filteredEdges = normalized.edges.filter((edge) =>
    filteredReferenceIds.has(edge.referenceId) && filteredDefinitionIds.has(edge.definitionId))
  const eligibleEdges = filteredEdges.filter((edge) =>
    nodeByKey.has(`reference:${edge.referenceId}`) && nodeByKey.has(`definition:${edge.definitionId}`))
  scene.edges = eligibleEdges.slice(0, edgeLimit).map((edge) => {
    const reference = nodeByKey.get(`reference:${edge.referenceId}`)
    const definition = nodeByKey.get(`definition:${edge.definitionId}`)
    const startX = reference.x
    const startY = reference.y + reference.height / 2
    const endX = definition.x + definition.width
    const endY = definition.y + definition.height / 2
    const bend = Math.max(36, Math.abs(startX - endX) * 0.45)
    return {
      ...edge,
      reference,
      definition,
      path: `M ${startX} ${startY} C ${startX - bend} ${startY}, ${endX + bend} ${endY}, ${endX} ${endY}`,
    }
  })
  attachDiagnostics(scene, filtered.diagnostics)

  const totalNodes = root.virtual
    ? countHierarchyNodes(root)
    : filtered.definitions.length + filtered.references.length + normalized.scopes.length
  scene.uri = normalized.uri
  scene.bounds = { x: 0, y: 0, width: truncated.root.width + 40, height: truncated.root.height + 40 }
  scene.stats = {
    totalNodes,
    renderedNodes: truncated.used,
    totalEdges: filteredEdges.length,
    renderedEdges: scene.edges.length,
    truncatedNodes: Math.max(0, totalNodes - truncated.used),
    truncatedEdges: Math.max(0, filteredEdges.length - scene.edges.length),
  }
  return scene
}

function countHierarchyNodes(scope) {
  let count = scope.virtual ? 0 : 1
  count += scope.definitions.length + scope.references.length
  for (const child of scope.children) count += countHierarchyNodes(child)
  return count
}

export function findBindingGraphNode(scene, range) {
  if (!scene || !range) return null
  const startByte = Math.max(0, numberOr(range.startByte))
  const endByte = Math.max(startByte, numberOr(range.endByte, startByte))
  let best = null
  for (const node of scene.nodes ?? []) {
    if (node.virtual) continue
    const contains = startByte === endByte
      ? node.startByte <= startByte && startByte <= node.endByte
      : node.startByte <= startByte && endByte <= node.endByte
    if (!contains) continue
    const exact = node.startByte === startByte && node.endByte === endByte
    const span = node.endByte - node.startByte
    if (!best || (exact && !best.exact) || (exact === best.exact && span < best.span)) {
      best = { ...node, exact, span }
    }
  }
  return best
}

export function clampGraphScale(scale) {
  return Math.max(0.25, Math.min(4, Number(scale) || 1))
}

export function zoomGraphViewport(viewport, pointer, nextScale) {
  const previousScale = clampGraphScale(viewport?.scale)
  const scale = clampGraphScale(nextScale)
  const x = numberOr(viewport?.x)
  const y = numberOr(viewport?.y)
  const pointerX = numberOr(pointer?.x)
  const pointerY = numberOr(pointer?.y)
  const sceneX = (pointerX - x) / previousScale
  const sceneY = (pointerY - y) / previousScale
  return { x: pointerX - sceneX * scale, y: pointerY - sceneY * scale, scale }
}

export function panGraphViewport(viewport, dx, dy) {
  return {
    x: numberOr(viewport?.x) + numberOr(dx),
    y: numberOr(viewport?.y) + numberOr(dy),
    scale: clampGraphScale(viewport?.scale),
  }
}

export function fitGraphViewport(bounds, viewportSize, padding = 24) {
  const width = Math.max(1, numberOr(viewportSize?.width))
  const height = Math.max(1, numberOr(viewportSize?.height))
  const boundsWidth = Math.max(1, numberOr(bounds?.width, 1))
  const boundsHeight = Math.max(1, numberOr(bounds?.height, 1))
  const inset = Math.max(0, numberOr(padding))
  const scale = clampGraphScale(Math.min(
    (width - inset * 2) / boundsWidth,
    (height - inset * 2) / boundsHeight,
  ))
  return {
    x: (width - boundsWidth * scale) / 2 - numberOr(bounds?.x) * scale,
    y: (height - boundsHeight * scale) / 2 - numberOr(bounds?.y) * scale,
    scale,
  }
}
