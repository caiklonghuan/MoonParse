<script setup>
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue'
import {
  buildBindingGraphScene,
  collectBindingGraphFacets,
  findBindingGraphNode,
  fitGraphViewport,
  panGraphViewport,
  zoomGraphViewport,
} from '@/lib/bindingGraph.js'

const props = defineProps({
  graph: { type: Object, default: () => ({}) },
  selectedRange: { type: Object, default: null },
})

const emit = defineEmits(['select'])

const canvasRef = ref(null)
const svgRef = ref(null)
const kindFilter = ref('all')
const namespaceFilter = ref('all')
const diagnosticFilter = ref('all')
const diagnosticsOnly = ref(false)
const viewport = ref({ x: 20, y: 20, scale: 1 })
const selectedEntity = ref(null)
const dragging = ref(null)
const markerId = `binding-arrow-${Math.random().toString(36).slice(2)}`
let resizeObserver = null

const facets = computed(() => collectBindingGraphFacets(props.graph))
const scene = computed(() => buildBindingGraphScene(props.graph, {
  kind: kindFilter.value,
  namespace: namespaceFilter.value,
  diagnosticKind: diagnosticFilter.value,
  diagnosticsOnly: diagnosticsOnly.value,
}))
const transform = computed(() =>
  `translate(${viewport.value.x} ${viewport.value.y}) scale(${viewport.value.scale})`)
const selectedKey = computed(() => {
  if (selectedEntity.value?.type === 'node') return selectedEntity.value.value.key
  if (selectedEntity.value?.type === 'edge') return selectedEntity.value.value.key
  if (selectedEntity.value?.type === 'diagnostic') return selectedEntity.value.value.key
  return null
})
const hasTruncation = computed(() =>
  scene.value.stats.truncatedNodes > 0 || scene.value.stats.truncatedEdges > 0)

function fitGraph() {
  const canvas = canvasRef.value
  if (!canvas) return
  viewport.value = fitGraphViewport(scene.value.bounds, {
    width: canvas.clientWidth,
    height: canvas.clientHeight,
  })
}

function resetZoom() {
  const canvas = canvasRef.value
  const bounds = scene.value.bounds
  if (!canvas) return
  viewport.value = {
    x: (canvas.clientWidth - bounds.width) / 2 - bounds.x,
    y: (canvas.clientHeight - bounds.height) / 2 - bounds.y,
    scale: 1,
  }
}

function zoomBy(factor) {
  const canvas = canvasRef.value
  if (!canvas) return
  viewport.value = zoomGraphViewport(viewport.value, {
    x: canvas.clientWidth / 2,
    y: canvas.clientHeight / 2,
  }, viewport.value.scale * factor)
}

function onWheel(event) {
  event.preventDefault()
  const rect = svgRef.value?.getBoundingClientRect()
  if (!rect) return
  const factor = event.deltaY < 0 ? 1.12 : 1 / 1.12
  viewport.value = zoomGraphViewport(viewport.value, {
    x: event.clientX - rect.left,
    y: event.clientY - rect.top,
  }, viewport.value.scale * factor)
}

function onPointerDown(event) {
  if (event.button !== 0 || event.target?.dataset?.panSurface !== 'true') return
  svgRef.value?.setPointerCapture?.(event.pointerId)
  dragging.value = { pointerId: event.pointerId, x: event.clientX, y: event.clientY }
}

function onPointerMove(event) {
  if (!dragging.value || dragging.value.pointerId !== event.pointerId) return
  viewport.value = panGraphViewport(
    viewport.value,
    event.clientX - dragging.value.x,
    event.clientY - dragging.value.y,
  )
  dragging.value = { pointerId: event.pointerId, x: event.clientX, y: event.clientY }
}

function stopDragging(event) {
  if (!dragging.value || dragging.value.pointerId !== event.pointerId) return
  svgRef.value?.releasePointerCapture?.(event.pointerId)
  dragging.value = null
}

function shortLabel(value, limit = 20) {
  const text = String(value ?? '')
  return text.length > limit ? `${text.slice(0, limit - 1)}…` : text
}

function diagnosticCount(key) {
  return scene.value.diagnosticsByNodeKey.get(key)?.length ?? 0
}

function rangeOf(item) {
  return {
    startByte: Number(item?.startByte ?? item?.start_byte ?? 0),
    endByte: Number(item?.endByte ?? item?.end_byte ?? item?.startByte ?? 0),
  }
}

function declarationRange(item) {
  return {
    startByte: Number(item?.declaration_start_byte ?? item?.startByte ?? 0),
    endByte: Number(item?.declaration_end_byte ?? item?.endByte ?? 0),
  }
}

function emitRange(range) {
  emit('select', {
    startByte: Math.max(0, Number(range?.startByte) || 0),
    endByte: Math.max(0, Number(range?.endByte) || 0),
  })
}

function selectNode(node, locate = true) {
  selectedEntity.value = { type: 'node', value: node }
  if (locate && !node.virtual) emitRange(rangeOf(node))
}

function selectEdge(edge) {
  selectedEntity.value = { type: 'edge', value: edge }
}

function selectDiagnostic(diagnostic) {
  selectedEntity.value = { type: 'diagnostic', value: diagnostic }
  emitRange(rangeOf(diagnostic))
}

function activateNode(event, node) {
  if (event.key !== 'Enter' && event.key !== ' ') return
  event.preventDefault()
  selectNode(node)
}

function isNodeSelected(node) {
  return selectedEntity.value?.type === 'node' && selectedKey.value === node.key
}

function isEdgeSelected(edge) {
  return selectedEntity.value?.type === 'edge' && selectedKey.value === edge.key
}

function sameRange(left, right) {
  if (!left || !right) return false
  const normalizedLeft = rangeOf(left)
  const normalizedRight = rangeOf(right)
  return normalizedLeft.startByte === normalizedRight.startByte &&
    normalizedLeft.endByte === normalizedRight.endByte
}

function selectedEntityOwnsRange(range) {
  if (selectedEntity.value?.type === 'node' || selectedEntity.value?.type === 'diagnostic') {
    return sameRange(selectedEntity.value.value, range)
  }
  if (selectedEntity.value?.type === 'edge') {
    return sameRange(selectedEntity.value.value.reference, range) ||
      sameRange(selectedEntity.value.value.definition, range)
  }
  return false
}

function syncExternalSelection(range) {
  if (!range || selectedEntityOwnsRange(range)) return
  const match = findBindingGraphNode(scene.value, range)
  if (match) selectedEntity.value = { type: 'node', value: match }
}

watch(scene, () => {
  selectedEntity.value = null
  syncExternalSelection(props.selectedRange)
  nextTick(fitGraph)
})

watch(() => props.selectedRange, (range) => {
  syncExternalSelection(range)
}, { deep: false })

onMounted(() => {
  resizeObserver = new ResizeObserver(() => fitGraph())
  if (canvasRef.value) resizeObserver.observe(canvasRef.value)
  syncExternalSelection(props.selectedRange)
  nextTick(fitGraph)
})

onUnmounted(() => resizeObserver?.disconnect())
</script>

<template>
  <div class="binding-graph-panel">
    <div class="graph-toolbar">
      <label>
        Kind
        <select v-model="kindFilter">
          <option value="all">All</option>
          <option v-for="kind in facets.kinds" :key="kind" :value="kind">{{ kind }}</option>
        </select>
      </label>
      <label>
        Namespace
        <select v-model="namespaceFilter">
          <option value="all">All</option>
          <option v-for="namespace in facets.namespaces" :key="namespace" :value="namespace">
            {{ namespace }}
          </option>
        </select>
      </label>
      <label>
        Diagnostic
        <select v-model="diagnosticFilter">
          <option value="all">All</option>
          <option v-for="kind in facets.diagnosticKinds" :key="kind" :value="kind">{{ kind }}</option>
        </select>
      </label>
      <label class="diagnostic-toggle">
        <input v-model="diagnosticsOnly" type="checkbox">
        Only diagnostics
      </label>
      <div class="zoom-actions">
        <button type="button" title="Zoom out" @click="zoomBy(1 / 1.2)">−</button>
        <span>{{ Math.round(viewport.scale * 100) }}%</span>
        <button type="button" title="Zoom in" @click="zoomBy(1.2)">+</button>
        <button type="button" @click="fitGraph">Fit</button>
        <button type="button" @click="resetZoom">100%</button>
      </div>
    </div>

    <div v-if="hasTruncation" class="graph-limit-warning">
      Showing {{ scene.stats.renderedNodes }}/{{ scene.stats.totalNodes }} nodes and
      {{ scene.stats.renderedEdges }}/{{ scene.stats.totalEdges }} edges. Apply filters to inspect omitted data.
    </div>

    <div class="graph-content">
      <div ref="canvasRef" class="graph-canvas">
        <svg
          ref="svgRef"
          class="graph-svg"
          role="img"
          aria-label="Binding scope and resolution graph"
          @wheel="onWheel"
          @pointerdown="onPointerDown"
          @pointermove="onPointerMove"
          @pointerup="stopDragging"
          @pointercancel="stopDragging"
        >
          <defs>
            <marker :id="markerId" markerWidth="7" markerHeight="7" refX="6" refY="3.5" orient="auto">
              <path d="M0,0 L7,3.5 L0,7 Z" class="edge-arrow" />
            </marker>
          </defs>
          <rect data-pan-surface="true" class="graph-background" width="100%" height="100%" />
          <g :transform="transform">
            <g
              v-for="scope in scene.scopes"
              :key="scope.key"
              class="scope-node"
              :class="{ 'scope-node--virtual': scope.virtual, 'graph-item--selected': isNodeSelected(scope) }"
              role="button"
              tabindex="0"
              @click.stop="selectNode(scope)"
              @keydown="activateNode($event, scope)"
            >
              <rect :x="scope.x" :y="scope.y" :width="scope.width" :height="scope.height" rx="10" />
              <text :x="scope.x + 12" :y="scope.y + 20" class="scope-label">{{ scope.label }}</text>
              <text :x="scope.x + scope.width - 12" :y="scope.y + 20" text-anchor="end" class="scope-range">
                {{ scope.startByte }}..{{ scope.endByte }}
              </text>
            </g>

            <g v-for="edge in scene.edges" :key="edge.key" class="edge-group" @click.stop="selectEdge(edge)">
              <path class="edge-hit" :d="edge.path" />
              <path
                class="resolution-edge"
                :class="{ 'graph-item--selected': isEdgeSelected(edge) }"
                :d="edge.path"
                :marker-end="`url(#${markerId})`"
              />
            </g>

            <g
              v-for="node in scene.symbols"
              :key="node.key"
              class="symbol-node"
              :class="[
                `symbol-node--${node.type}`,
                { 'graph-item--selected': isNodeSelected(node), 'symbol-node--diagnostic': diagnosticCount(node.key) > 0 },
              ]"
              role="button"
              tabindex="0"
              @click.stop="selectNode(node)"
              @keydown="activateNode($event, node)"
            >
              <rect :x="node.x" :y="node.y" :width="node.width" :height="node.height" rx="6" />
              <text :x="node.x + 8" :y="node.y + 15" class="symbol-label">{{ shortLabel(node.label) }}</text>
              <text :x="node.x + node.width - 7" :y="node.y + 15" text-anchor="end" class="symbol-meta">
                {{ node.item.ns }}
              </text>
              <g
                v-if="diagnosticCount(node.key)"
                class="diagnostic-badge"
                @click.stop="selectDiagnostic(scene.diagnosticsByNodeKey.get(node.key)[0])"
              >
                <circle :cx="node.x + node.width - 4" :cy="node.y + 4" r="7" />
                <text :x="node.x + node.width - 4" :y="node.y + 7" text-anchor="middle">
                  {{ diagnosticCount(node.key) }}
                </text>
              </g>
            </g>
          </g>
        </svg>

        <div v-if="scene.stats.totalNodes === 0 && scene.diagnostics.length === 0" class="graph-empty">
          No binding nodes for the current query and filters.
        </div>
      </div>

      <aside class="graph-inspector">
        <template v-if="selectedEntity?.type === 'node'">
          <h4>{{ selectedEntity.value.type }}</h4>
          <dl>
            <template v-if="selectedEntity.value.type === 'scope'">
              <dt>Kind</dt><dd>{{ selectedEntity.value.item.kind }}</dd>
              <dt>Parent</dt><dd>{{ selectedEntity.value.item.parent }}</dd>
            </template>
            <template v-else>
              <dt>Name</dt><dd>{{ selectedEntity.value.item.name }}</dd>
              <dt>Kind</dt><dd>{{ selectedEntity.value.item.kind }}</dd>
              <dt>Namespace</dt><dd>{{ selectedEntity.value.item.ns }}</dd>
              <dt>Scope</dt><dd>{{ selectedEntity.value.item.scopeId }}</dd>
              <template v-if="selectedEntity.value.type === 'reference'">
                <dt>Diagnose unresolved</dt><dd>{{ Boolean(selectedEntity.value.item.diagnose_unresolved) }}</dd>
              </template>
            </template>
            <dt>Range</dt><dd>{{ selectedEntity.value.startByte }}..{{ selectedEntity.value.endByte }}</dd>
          </dl>
          <div class="inspector-actions" v-if="!selectedEntity.value.virtual">
            <button type="button" @click="emitRange(rangeOf(selectedEntity.value))">Locate range</button>
            <button
              v-if="selectedEntity.value.type === 'definition'"
              type="button"
              @click="emitRange(declarationRange(selectedEntity.value.item))"
            >
              Locate declaration
            </button>
          </div>
        </template>

        <template v-else-if="selectedEntity?.type === 'edge'">
          <h4>Resolution edge</h4>
          <dl>
            <dt>Reference</dt><dd>{{ selectedEntity.value.reference.item.name }}</dd>
            <dt>Definition</dt><dd>{{ selectedEntity.value.definition.item.name }}</dd>
            <dt>Namespace</dt><dd>{{ selectedEntity.value.reference.item.ns }}</dd>
          </dl>
          <div class="inspector-actions">
            <button type="button" @click="emitRange(rangeOf(selectedEntity.value.reference))">Locate reference</button>
            <button type="button" @click="emitRange(rangeOf(selectedEntity.value.definition))">Locate definition</button>
          </div>
        </template>

        <template v-else-if="selectedEntity?.type === 'diagnostic'">
          <h4>{{ selectedEntity.value.kind }}</h4>
          <p>{{ selectedEntity.value.message }}</p>
          <code>{{ selectedEntity.value.startByte }}..{{ selectedEntity.value.endByte }}</code>
          <div class="inspector-actions">
            <button type="button" @click="emitRange(rangeOf(selectedEntity.value))">Locate diagnostic</button>
          </div>
        </template>

        <template v-else>
          <h4>Binding Graph</h4>
          <p>Select a scope, symbol, edge, or diagnostic to inspect it.</p>
          <code v-if="scene.uri">{{ scene.uri }}</code>
        </template>

        <section class="diagnostic-list">
          <h4>Diagnostics ({{ scene.diagnostics.length }})</h4>
          <button
            v-for="diagnostic in scene.diagnostics"
            :key="diagnostic.key"
            type="button"
            :class="{ active: selectedKey === diagnostic.key }"
            @click="selectDiagnostic(diagnostic)"
          >
            <strong>{{ diagnostic.kind }}</strong>
            <span>{{ diagnostic.message }}</span>
            <code>{{ diagnostic.startByte }}..{{ diagnostic.endByte }}</code>
          </button>
          <p v-if="scene.diagnostics.length === 0" class="no-diagnostics">No diagnostics.</p>
        </section>
      </aside>
    </div>
  </div>
</template>

<style scoped>
.binding-graph-panel { display: flex; flex-direction: column; min-height: 0; height: 100%; }
.graph-toolbar {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 6px 8px;
  border-bottom: 1px solid var(--border);
  background: var(--surface);
  font-size: 10px;
}
.graph-toolbar label { display: flex; align-items: center; gap: 4px; color: var(--text-muted); }
.graph-toolbar select {
  max-width: 110px;
  min-height: 24px;
  border: 1px solid var(--border);
  border-radius: 5px;
  color: var(--text);
  background: var(--surface);
  font-size: 10px;
}
.diagnostic-toggle { white-space: nowrap; }
.zoom-actions { display: flex; align-items: center; gap: 3px; margin-left: auto; }
.zoom-actions button, .inspector-actions button {
  min-height: 24px;
  border: 1px solid var(--border);
  border-radius: 5px;
  color: var(--text);
  background: var(--surface-2);
  cursor: pointer;
  font-size: 10px;
}
.zoom-actions span { min-width: 34px; text-align: center; color: var(--text-muted); }
.graph-limit-warning { padding: 5px 9px; color: #b45309; background: rgba(245, 158, 11, 0.12); font-size: 10px; }
.graph-content { display: grid; grid-template-columns: minmax(0, 1fr) 220px; min-height: 0; flex: 1; }
.graph-canvas { position: relative; min-width: 0; min-height: 260px; overflow: hidden; }
.graph-svg { width: 100%; height: 100%; min-height: 260px; cursor: grab; user-select: none; }
.graph-svg:active { cursor: grabbing; }
.graph-background { fill: var(--surface); }
.scope-node rect { fill: color-mix(in srgb, var(--surface-2) 78%, transparent); stroke: var(--border); stroke-width: 1; }
.scope-node--virtual > rect { fill: transparent; stroke-dasharray: 6 5; }
.scope-label { fill: var(--text); font-size: 11px; font-weight: 700; }
.scope-range { fill: var(--text-muted); font-size: 9px; }
.symbol-node rect { stroke-width: 1; }
.symbol-node--definition rect { fill: rgba(34, 197, 94, 0.13); stroke: rgba(34, 197, 94, 0.65); }
.symbol-node--reference rect { fill: rgba(59, 130, 246, 0.13); stroke: rgba(59, 130, 246, 0.65); }
.symbol-node--diagnostic rect { stroke: #ef4444; }
.symbol-label { fill: var(--text); font-size: 10px; font-weight: 600; }
.symbol-meta { fill: var(--text-muted); font-size: 8px; }
.resolution-edge { fill: none; stroke: color-mix(in srgb, var(--accent) 70%, var(--text-muted)); stroke-width: 1.4; opacity: 0.75; pointer-events: none; }
.edge-hit { fill: none; stroke: transparent; stroke-width: 10; cursor: pointer; }
.edge-arrow { fill: var(--accent); }
.graph-item--selected > rect, rect.graph-item--selected { stroke: var(--accent); stroke-width: 3; }
.resolution-edge.graph-item--selected { stroke: #f59e0b; stroke-width: 3; opacity: 1; }
.diagnostic-badge circle { fill: #ef4444; }
.diagnostic-badge text { fill: white; font-size: 8px; font-weight: 700; }
.graph-empty { position: absolute; inset: 0; display: grid; place-items: center; color: var(--text-muted); font-size: 12px; pointer-events: none; }
.graph-inspector { overflow: auto; padding: 10px; border-left: 1px solid var(--border); background: var(--surface-2); font-size: 10px; }
.graph-inspector h4 { margin: 0 0 8px; color: var(--text); font-size: 11px; }
.graph-inspector p { color: var(--text-muted); line-height: 1.4; }
.graph-inspector code { color: var(--text-muted); word-break: break-all; }
.graph-inspector dl { display: grid; grid-template-columns: auto minmax(0, 1fr); gap: 4px 8px; margin: 0 0 9px; }
.graph-inspector dt { color: var(--text-muted); }
.graph-inspector dd { min-width: 0; margin: 0; color: var(--text); overflow-wrap: anywhere; }
.inspector-actions { display: flex; flex-wrap: wrap; gap: 5px; margin-bottom: 12px; }
.diagnostic-list { margin-top: 14px; padding-top: 10px; border-top: 1px solid var(--border); }
.diagnostic-list button { display: grid; width: 100%; gap: 2px; margin-bottom: 5px; padding: 6px; border: 1px solid var(--border); border-radius: 5px; color: var(--text); background: var(--surface); text-align: left; cursor: pointer; }
.diagnostic-list button.active { border-color: var(--accent); }
.diagnostic-list strong { color: #ef4444; font-size: 9px; text-transform: uppercase; }
.diagnostic-list span { overflow: hidden; text-overflow: ellipsis; }
.no-diagnostics { opacity: 0.65; }
@media (max-width: 800px) {
  .graph-toolbar { flex-wrap: wrap; }
  .zoom-actions { margin-left: 0; }
  .graph-content { grid-template-columns: 1fr; grid-template-rows: minmax(260px, 1fr) auto; }
  .graph-inspector { max-height: 190px; border-top: 1px solid var(--border); border-left: 0; }
}
</style>
