<script setup>
import { computed, inject, nextTick, onMounted, onUnmounted, ref, watch } from 'vue'
import { EditorState } from '@codemirror/state'
import { EditorView, keymap } from '@codemirror/view'
import { defaultKeymap } from '@codemirror/commands'
import { moonQuerySyntax } from '@/lib/dslSyntax.js'
import BindingGraphPanel from '@/components/query/BindingGraphPanel.vue'
import {
  executeQueryMode,
  updateQueryModePattern,
} from '@/lib/queryDebugger.js'

const MODES = [
  { id: 'query', label: 'Query' },
  { id: 'locals', label: 'Locals' },
  { id: 'bindings', label: 'Bindings' },
  { id: 'folding', label: 'Folding' },
]

const EMPTY_BINDING_GRAPH = {
  uri: '',
  scopes: [],
  definitions: [],
  references: [],
  edges: [],
  diagnostics: [],
}

const props = defineProps({
  modelValue: { type: String, default: '' },
  mode: { type: String, default: 'query' },
  modePatterns: { type: Object, default: () => ({}) },
  tree: { type: Object, default: null },
  suggestion: { type: String, default: '' },
  modeSuggestions: { type: Object, default: () => ({}) },
  selectedRange: { type: Object, default: null },
})

const emit = defineEmits([
  'update:modelValue',
  'update:mode',
  'update:mode-patterns',
  'bindings-result',
  'select',
])

const mp = inject('mp')
const queryEditorRef = ref(null)
let queryView = null
let syncingEditor = false

const groups = ref([])
const queryError = ref(null)
const running = ref(false)
const localsMap = ref({})
const bindingGraph = ref(EMPTY_BINDING_GRAPH)
const bindingsView = ref('graph')
const editorEmpty = ref(true)

const activeMode = computed(() => MODES.some((mode) => mode.id === props.mode) ? props.mode : 'query')
const currentPattern = computed(() => activeMode.value === 'query'
  ? props.modelValue
  : String(props.modePatterns?.[activeMode.value] ?? ''))
const currentSuggestion = computed(() => activeMode.value === 'query'
  ? props.suggestion
  : String(props.modeSuggestions?.[activeMode.value] ?? ''))
const showGhost = computed(() => editorEmpty.value && Boolean(currentSuggestion.value?.trim()))
const captureCount = computed(() => groups.value.reduce((total, group) => total + group.captures.length, 0))
const localCount = computed(() => groups.value.reduce(
  (total, group) => total + group.captures.filter((capture) => capture.isLocalReference).length,
  0,
))

const queryEditorTheme = EditorView.theme({
  '&': {
    height: '120px',
    fontSize: '13px',
    color: 'var(--text)',
    backgroundColor: 'var(--surface)',
  },
  '.cm-scroller': { overflow: 'auto', fontFamily: 'var(--mono)' },
  '.cm-content': { padding: '10px 12px', caretColor: 'var(--accent)' },
  '.cm-cursor, .cm-dropCursor': { borderLeftColor: 'var(--accent)' },
  '.cm-selectionBackground, &.cm-focused .cm-selectionBackground, ::selection': {
    backgroundColor: 'var(--accent-bg-strong)',
  },
  '&.cm-focused': { outline: 'none' },
})

function patternForMode(mode) {
  return mode === 'query' ? props.modelValue : String(props.modePatterns?.[mode] ?? '')
}

function replaceEditorText(text) {
  if (!queryView) return
  const current = queryView.state.doc.toString()
  if (current === text) {
    editorEmpty.value = !text.trim()
    return
  }
  syncingEditor = true
  queryView.dispatch({ changes: { from: 0, to: current.length, insert: text } })
  syncingEditor = false
  editorEmpty.value = !text.trim()
}

function updateCurrentPattern(text) {
  if (activeMode.value === 'query') {
    emit('update:modelValue', text)
    return
  }
  emit('update:mode-patterns', updateQueryModePattern(props.modePatterns, activeMode.value, text))
}

function acceptSuggestion() {
  if (!queryView || !showGhost.value) return false
  const text = currentSuggestion.value.trim()
  queryView.dispatch({ changes: { from: 0, to: queryView.state.doc.length, insert: text } })
  queryView.focus()
  return true
}

function focusEditor() {
  queryView?.focus()
}

function emptyBindingGraph() {
  return {
    uri: '',
    scopes: [],
    definitions: [],
    references: [],
    edges: [],
    diagnostics: [],
  }
}

function clearResults({ clearBindings = true } = {}) {
  groups.value = []
  localsMap.value = {}
  queryError.value = null
  if (clearBindings) {
    bindingGraph.value = emptyBindingGraph()
    emit('bindings-result', bindingGraph.value)
  }
}

function handleModeChange(event) {
  const mode = event.target.value
  if (mode === activeMode.value) return
  emit('update:mode', mode)
}

function runQuery() {
  if (!mp?.value || !props.tree) {
    queryError.value = 'WASM 尚未就绪，或当前还没有语法树。'
    groups.value = []
    return
  }

  const pattern = queryView?.state.doc.toString().trim() ?? ''
  if (!pattern) {
    clearResults()
    return
  }

  running.value = true
  queryError.value = null
  groups.value = []
  try {
    const result = executeQueryMode(mp.value, props.tree, pattern, activeMode.value)
    groups.value = result.groups
    localsMap.value = result.localsMap
    if (activeMode.value === 'bindings') {
      bindingGraph.value = result.bindingGraph ?? emptyBindingGraph()
      emit('bindings-result', bindingGraph.value)
    }
  } catch (error) {
    queryError.value = error?.message ?? String(error)
    groups.value = []
    if (activeMode.value === 'bindings') {
      bindingGraph.value = emptyBindingGraph()
      emit('bindings-result', bindingGraph.value)
    }
  } finally {
    running.value = false
  }
}

function selectCapture(capture) {
  emit('select', { startByte: capture.startByte, endByte: capture.endByte })
}

function isSelected(capture) {
  return props.selectedRange &&
    props.selectedRange.startByte === capture.startByte &&
    props.selectedRange.endByte === capture.endByte
}

onMounted(() => {
  queryView = new EditorView({
    state: EditorState.create({
      doc: currentPattern.value,
      extensions: [
        keymap.of([
          ...defaultKeymap,
          { key: 'Tab', run: () => acceptSuggestion() },
          { key: 'Ctrl-Enter', run: () => { runQuery(); return true } },
        ]),
        moonQuerySyntax,
        queryEditorTheme,
        EditorView.updateListener.of((update) => {
          if (!update.docChanged) return
          const text = update.state.doc.toString()
          editorEmpty.value = !text.trim()
          if (!syncingEditor) updateCurrentPattern(text)
        }),
      ],
    }),
    parent: queryEditorRef.value,
  })
  editorEmpty.value = !currentPattern.value.trim()
  nextTick(() => {
    if (props.tree && queryView?.state.doc.toString().trim()) runQuery()
  })
})

onUnmounted(() => queryView?.destroy())

watch(currentPattern, (pattern) => replaceEditorText(pattern))

watch(activeMode, () => {
  clearResults()
  if (activeMode.value === 'bindings') bindingsView.value = 'graph'
  replaceEditorText(patternForMode(activeMode.value))
  nextTick(() => {
    if (queryView?.state.doc.toString().trim() && props.tree) runQuery()
  })
})

watch(() => props.tree, () => {
  if (!props.tree) {
    clearResults()
    return
  }
  if (queryView?.state.doc.toString().trim()) runQuery()
})

defineExpose({ runQuery, acceptSuggestion })
</script>

<template>
  <div class="query-panel panel">
    <div class="panel-header query-header">
      <span class="panel-title">Query 调试器</span>
      <select class="mode-select" :value="activeMode" @change="handleModeChange">
        <option v-for="modeOption in MODES" :key="modeOption.id" :value="modeOption.id">
          {{ modeOption.label }}
        </option>
      </select>
      <span class="panel-hint">Ctrl+Enter</span>
      <button class="run-btn" :disabled="running" @click="runQuery">
        {{ running ? '执行中…' : '运行' }}
      </button>
    </div>

    <div class="query-editor-wrap">
      <div ref="queryEditorRef" class="query-editor" />
      <div v-if="showGhost" class="query-ghost" @click="focusEditor">
        <pre class="query-ghost-text">{{ currentSuggestion.trim() }}</pre>
        <span class="query-ghost-hint">按 Tab 插入建议查询</span>
      </div>
    </div>

    <div v-if="queryError" class="query-error">{{ queryError }}</div>

    <div v-if="activeMode === 'locals' && !queryError" class="result-summary">
      {{ localCount }} 个 local capture / {{ captureCount }} 个 capture
    </div>
    <div v-else-if="activeMode === 'bindings' && !queryError" class="result-summary">
      {{ bindingGraph.scopes?.length ?? 0 }} scopes ·
      {{ bindingGraph.definitions?.length ?? 0 }} definitions ·
      {{ bindingGraph.references?.length ?? 0 }} references ·
      {{ bindingGraph.edges?.length ?? 0 }} edges
    </div>
    <div v-else-if="activeMode === 'folding' && !queryError" class="result-summary">
      {{ captureCount }} 个 folding range
    </div>

    <div v-if="activeMode === 'bindings'" class="bindings-view-tabs">
      <button
        type="button"
        :class="{ active: bindingsView === 'graph' }"
        @click="bindingsView = 'graph'"
      >
        Graph
      </button>
      <button
        type="button"
        :class="{ active: bindingsView === 'captures' }"
        @click="bindingsView = 'captures'"
      >
        Captures
      </button>
    </div>

    <BindingGraphPanel
      v-if="activeMode === 'bindings' && bindingsView === 'graph'"
      class="binding-result-body"
      :graph="bindingGraph"
      :selected-range="selectedRange"
      @select="emit('select', $event)"
    />

    <div v-else class="query-results">
      <div v-if="groups.length === 0 && !queryError" class="query-empty">暂无结果</div>
      <section v-for="(group, groupIndex) in groups" :key="group.key" class="match-group">
        <div class="match-header">
          {{ group.matchId == null ? `Result ${groupIndex + 1}` : `Match #${group.matchId}` }}
          <span>{{ group.captures.length }} captures</span>
        </div>
        <button
          v-for="capture in group.captures"
          :key="`${capture.resultIndex}:${capture.capture}`"
          type="button"
          class="query-result"
          :class="{
            'query-result--selected': isSelected(capture),
            'query-result--local': capture.isLocalReference,
          }"
          @click="selectCapture(capture)"
        >
          <span class="result-capture">@{{ capture.capture }}</span>
          <span v-if="capture.isLocalReference" class="result-badge">local</span>
          <span class="result-text">{{ capture.text.length > 48 ? `${capture.text.slice(0, 48)}…` : capture.text }}</span>
          <span class="result-range">[{{ capture.startByte }}..{{ capture.endByte }}]</span>
          <span class="result-pos">
            {{ capture.startRow }}:{{ capture.startCol }}–{{ capture.endRow }}:{{ capture.endCol }}
          </span>
        </button>
      </section>
    </div>
  </div>
</template>

<style scoped>
.query-panel { display: flex; flex-direction: column; height: 100%; overflow: hidden; }
.query-header { gap: 8px; }
.mode-select {
  min-height: 28px;
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 0 7px;
  color: var(--text);
  background: var(--surface);
  font-size: 12px;
}
.query-editor-wrap { position: relative; flex-shrink: 0; }
.query-editor { border-bottom: 1px solid var(--border); background: var(--surface); }
.query-ghost {
  position: absolute;
  inset: 0;
  padding: 10px 12px;
  font-family: var(--mono);
  font-size: 13px;
  overflow: hidden;
  cursor: text;
  pointer-events: auto;
}
.query-ghost-text {
  margin: 0;
  color: var(--text);
  opacity: 0.22;
  white-space: pre-wrap;
  word-break: break-all;
  line-height: 1.4;
}
.query-ghost-hint {
  display: inline-block;
  margin-top: 6px;
  padding: 2px 8px;
  border-radius: 4px;
  font-size: 11px;
  color: var(--accent);
  background: var(--accent-bg);
  opacity: 0.75;
}
.run-btn {
  margin-left: auto;
  padding: 3px 12px;
  border-radius: 6px;
  border: 1px solid var(--accent-border);
  background: var(--accent-bg);
  color: var(--accent);
  cursor: pointer;
  font-size: 12px;
  font-weight: 600;
}
.run-btn:hover:not(:disabled) { background: var(--accent); color: #fff; }
.run-btn:disabled { opacity: 0.5; cursor: default; }
.query-error {
  padding: 8px 12px;
  font-size: 12px;
  color: #f44747;
  background: rgba(244, 71, 71, 0.08);
  border-bottom: 1px solid rgba(244, 71, 71, 0.2);
  font-family: var(--mono);
  white-space: pre-wrap;
}
.result-summary {
  padding: 5px 12px;
  color: var(--text-muted);
  border-bottom: 1px solid var(--border);
  font-family: var(--mono);
  font-size: 11px;
}
.bindings-view-tabs {
  display: flex;
  gap: 3px;
  padding: 4px 8px;
  border-bottom: 1px solid var(--border);
  background: var(--surface-2);
}
.bindings-view-tabs button {
  padding: 3px 9px;
  border: 1px solid transparent;
  border-radius: 5px;
  color: var(--text-muted);
  background: transparent;
  cursor: pointer;
  font-size: 10px;
}
.bindings-view-tabs button.active {
  border-color: var(--accent-border);
  color: var(--accent);
  background: var(--accent-bg);
}
.binding-result-body { flex: 1; min-height: 0; }
.query-results { flex: 1; overflow: auto; padding: 4px 0; font-family: var(--mono); font-size: 12px; }
.query-empty { padding: 16px; color: var(--text); opacity: 0.4; font-style: italic; }
.match-group { padding-bottom: 4px; border-bottom: 1px solid color-mix(in srgb, var(--border) 60%, transparent); }
.match-header {
  display: flex;
  justify-content: space-between;
  padding: 5px 12px 3px;
  color: var(--text-muted);
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
}
.query-result {
  display: grid;
  grid-template-columns: auto auto minmax(80px, 1fr) auto auto;
  width: 100%;
  align-items: baseline;
  gap: 8px;
  padding: 4px 12px;
  border: 0;
  color: inherit;
  background: transparent;
  cursor: pointer;
  text-align: left;
  white-space: nowrap;
}
.query-result:hover { background: var(--accent-bg); }
.query-result--selected { background: var(--accent-bg-strong); box-shadow: inset 3px 0 var(--accent); }
.query-result--local .result-capture { color: #4ec9b0; }
.result-capture { color: var(--accent); font-weight: 700; }
.result-badge { padding: 1px 4px; border-radius: 4px; color: #4ec9b0; background: rgba(78, 201, 176, 0.12); font-size: 9px; }
.result-text { min-width: 0; overflow: hidden; color: var(--text-muted); text-overflow: ellipsis; }
.result-range { color: var(--text); opacity: 0.5; font-size: 10px; }
.result-pos { color: var(--text); opacity: 0.4; font-size: 10px; }
@media (max-width: 700px) {
  .query-result { grid-template-columns: auto auto minmax(60px, 1fr); }
  .result-range, .result-pos { display: none; }
}
</style>
