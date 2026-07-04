<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { Compartment, EditorState } from '@codemirror/state'
import { EditorView, keymap, lineNumbers, highlightActiveLine } from '@codemirror/view'
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands'
import { moonGrammarSyntax, moonJsonSyntax, moonQuerySyntax } from '@/lib/dslSyntax.js'

const props = defineProps({
  path: { type: String, default: null },
  text: { type: String, default: '' },
  readonly: { type: Boolean, default: false },
})

const emit = defineEmits(['update:text'])

const editorHost = ref(null)
let view = null
let activePath = null
const stateCache = new Map()
const languageCompartment = new Compartment()
const readonlyCompartment = new Compartment()

const modeLabel = computed(() => {
  const lower = (props.path ?? '').toLowerCase()
  if (!props.path) return 'No file'
  if (lower.endsWith('.json') || lower === 'language-pack.json') return 'JSON'
  if (lower.endsWith('.grammar')) return 'Grammar DSL'
  if (lower.endsWith('.scm') || lower.endsWith('.query')) return 'Query'
  return 'Text'
})

function languageExtension(path) {
  const lower = (path ?? '').toLowerCase()
  if (lower.endsWith('.json') || lower === 'language-pack.json') return moonJsonSyntax
  if (lower.endsWith('.grammar')) return moonGrammarSyntax
  if (lower.endsWith('.scm') || lower.endsWith('.query')) return moonQuerySyntax
  return []
}

function readonlyExtension() {
  return [
    EditorState.readOnly.of(props.readonly),
    EditorView.editable.of(!props.readonly),
  ]
}

const editorTheme = EditorView.theme({
  '&': {
    height: '100%',
    fontSize: '13px',
    color: 'var(--text)',
    backgroundColor: 'var(--surface)',
  },
  '.cm-scroller': {
    overflow: 'auto',
    fontFamily: 'var(--mono)',
  },
  '.cm-content': {
    padding: '12px',
    caretColor: 'var(--accent)',
  },
  '.cm-cursor, .cm-dropCursor': {
    borderLeftColor: 'var(--accent)',
  },
  '&.cm-focused': {
    outline: 'none',
  },
})

function buildState(path, text) {
  return EditorState.create({
    doc: text ?? '',
    extensions: [
      history(),
      lineNumbers(),
      highlightActiveLine(),
      keymap.of([...defaultKeymap, ...historyKeymap]),
      languageCompartment.of(languageExtension(path)),
      readonlyCompartment.of(readonlyExtension()),
      editorTheme,
      EditorView.updateListener.of((update) => {
        if (!update.docChanged) return
        emit('update:text', update.state.doc.toString())
      }),
    ],
  })
}

function reconfigureDynamic() {
  if (!view) return
  view.dispatch({
    effects: [
      languageCompartment.reconfigure(languageExtension(props.path)),
      readonlyCompartment.reconfigure(readonlyExtension()),
    ],
  })
}

function cacheCurrentState() {
  if (view && activePath) {
    stateCache.set(activePath, view.state)
  }
}

function loadFile(path, text) {
  if (!view) return
  cacheCurrentState()
  activePath = path
  const cached = path ? stateCache.get(path) : null
  const nextState = cached && cached.doc.toString() === (text ?? '')
    ? cached
    : buildState(path, text ?? '')
  view.setState(nextState)
  reconfigureDynamic()
}

onMounted(() => {
  activePath = props.path
  view = new EditorView({
    state: buildState(props.path, props.text),
    parent: editorHost.value,
  })
})

onUnmounted(() => {
  cacheCurrentState()
  view?.destroy()
  view = null
  stateCache.clear()
})

watch(() => props.path, (path) => {
  loadFile(path, props.text)
})

watch(() => props.text, (text) => {
  if (!view) return
  if (props.path !== activePath) return
  const current = view.state.doc.toString()
  if (current !== text) {
    view.dispatch({ changes: { from: 0, to: current.length, insert: text ?? '' } })
  }
})

watch(() => props.readonly, () => {
  reconfigureDynamic()
})

function focusPosition(line = 0, column = 0) {
  if (!view) return
  const lineNumber = Math.max(1, Math.min(view.state.doc.lines, Number(line) + 1 || 1))
  const lineInfo = view.state.doc.line(lineNumber)
  const offset = Math.max(0, Number(column) || 0)
  const position = Math.min(lineInfo.to, lineInfo.from + offset)
  view.dispatch({
    selection: { anchor: position },
    scrollIntoView: true,
  })
  view.focus()
}

function focus() {
  view?.focus()
}

defineExpose({ focus, focusPosition })
</script>

<template>
  <section class="pack-file-editor panel">
    <div class="panel-header pack-file-editor-header">
      <div class="pack-file-title">
        <span class="panel-title">{{ path ?? 'No file selected' }}</span>
        <span class="pack-file-mode">{{ modeLabel }}</span>
      </div>
      <span v-if="readonly" class="pack-readonly">Read-only</span>
    </div>
    <div
      ref="editorHost"
      class="pack-editor-host"
      :class="{ 'pack-editor-host-hidden': !path }"
    />
    <div v-if="!path" class="pack-editor-empty">
      Select a source file to edit.
    </div>
  </section>
</template>

<style scoped>
.pack-file-editor {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-width: 0;
  overflow: hidden;
}

.pack-file-editor-header {
  gap: 8px;
}

.pack-file-title {
  min-width: 0;
  display: flex;
  align-items: center;
  gap: 8px;
}

.pack-file-title .panel-title {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pack-file-mode,
.pack-readonly {
  flex: 0 0 auto;
  border: 1px solid var(--line);
  border-radius: 999px;
  padding: 2px 7px;
  color: var(--text-soft);
  font-size: 10px;
}

.pack-readonly {
  margin-left: auto;
}

.pack-editor-host {
  flex: 1;
  min-height: 0;
  overflow: hidden;
}

.pack-editor-host-hidden {
  display: none;
}

.pack-editor-empty {
  flex: 1;
  display: grid;
  place-items: center;
  padding: 24px;
  color: var(--text-soft);
  font-size: 13px;
}
</style>
