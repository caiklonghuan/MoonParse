<script setup>
import { ref, computed, inject, watch, onMounted, onUnmounted } from 'vue'
import { EditorState } from '@codemirror/state'
import { EditorView, keymap } from '@codemirror/view'
import { defaultKeymap }  from '@codemirror/commands'
import { moonQuerySyntax } from '@/lib/dslSyntax.js'

const props = defineProps({
  modelValue: { type: String, default: '' },
  tree:       { type: Object, default: null },
  suggestion: { type: String, default: '' },
})

const emit = defineEmits(['update:modelValue', 'select'])

const mp = inject('mp')

const queryEditorRef = ref(null)
let   queryView = null

const results    = ref([])
const queryError = ref(null)
const running    = ref(false)

const editorEmpty = ref(true)
const showGhost   = computed(() => editorEmpty.value && !!props.suggestion?.trim())

const queryEditorTheme = EditorView.theme({
  '&': {
    height: '120px',
    fontSize: '13px',
    color: 'var(--text)',
    backgroundColor: 'var(--surface)',
  },
  '.cm-scroller': {
    overflow: 'auto',
    fontFamily: 'var(--mono)',
  },
  '.cm-content': {
    padding: '10px 12px',
    caretColor: 'var(--accent)',
  },
  '.cm-cursor, .cm-dropCursor': {
    borderLeftColor: 'var(--accent)',
  },
  '.cm-selectionBackground, &.cm-focused .cm-selectionBackground, ::selection': {
    backgroundColor: 'var(--accent-bg-strong)',
  },
  '&.cm-focused': {
    outline: 'none',
  },
})

function acceptSuggestion() {
  if (!queryView || !showGhost.value) return false
  const text = props.suggestion.trim()
  queryView.dispatch({ changes: { from: 0, to: queryView.state.doc.length, insert: text } })
  queryView.focus()
  return true
}

function focusEditor() {
  queryView?.focus()
}

onMounted(() => {
  queryView = new EditorView({
    state: EditorState.create({
      doc: props.modelValue,
      extensions: [
        keymap.of([
          ...defaultKeymap,
          { key: 'Tab', run: () => acceptSuggestion() },
          { key: 'Ctrl-Enter', run: () => { runQuery(); return true } },
        ]),
        moonQuerySyntax,
        queryEditorTheme,
        EditorView.updateListener.of((u) => {
          if (u.docChanged) {
            const doc = u.state.doc.toString()
            emit('update:modelValue', doc)
            editorEmpty.value = !doc.trim()
          }
        }),
      ],
    }),
    parent: queryEditorRef.value,
  })
  editorEmpty.value = !props.modelValue?.trim()
})

onUnmounted(() => queryView?.destroy())

function clearResults() {
  results.value = []
  queryError.value = null
}

watch(() => props.modelValue, (val) => {
  if (!queryView) return
  const cur = queryView.state.doc.toString()
  if (cur !== val) {
    queryView.dispatch({ changes: { from: 0, to: cur.length, insert: val } })
  }
  if (!val?.trim()) {
    clearResults()
  }
})

function runQuery() {
  if (!mp?.value || !props.tree) {
    queryError.value = 'WASM 尚未就绪，或当前还没有语法树。'
    return
  }

  const pattern = queryView?.state.doc.toString().trim()
  if (!pattern) { results.value = []; queryError.value = null; return }

  running.value    = true
  queryError.value = null
  results.value    = []

  try {
    const q = mp.value.compileQuery(pattern)
    results.value = q.exec(props.tree)
    q.free()
  } catch (e) {
    queryError.value = e?.message ?? String(e)
  } finally {
    running.value = false
  }
}

watch(() => props.tree, () => {
  if (!props.tree) {
    clearResults()
    return
  }
  if (queryView && queryView.state.doc.toString().trim()) runQuery()
})

function selectResult(r) {
  emit('select', { startByte: r.start, endByte: r.end })
}

defineExpose({ runQuery, acceptSuggestion })
</script>

<template>
  <div class="query-panel panel">
    <div class="panel-header">
      <span class="panel-title">🔍 查询</span>
      <span class="panel-hint">按 Ctrl+Enter 执行</span>
      <button class="run-btn" :disabled="running" @click="runQuery">
        {{ running ? '执行中…' : '▶ 运行' }}
      </button>
    </div>

    <div class="query-editor-wrap">
      <div ref="queryEditorRef" class="query-editor" />
      <div v-if="showGhost" class="query-ghost" @click="focusEditor">
        <pre class="query-ghost-text">{{ suggestion.trim() }}</pre>
        <span class="query-ghost-hint">按 Tab 插入建议查询</span>
      </div>
    </div>

    <div v-if="queryError" class="query-error">
      {{ queryError }}
    </div>

    <div class="query-results">
      <div v-if="results.length === 0 && !queryError" class="query-empty">
        暂无结果
      </div>
      <div
        v-for="(r, i) in results"
        :key="i"
        class="query-result"
        @click="selectResult(r)"
      >
        <span class="result-capture">@{{ r.capture }}</span>
        <span class="result-text">"{{ r.text.length > 40 ? r.text.slice(0, 40) + '…' : r.text }}"</span>
        <span class="result-range">[{{ r.start }}..{{ r.end }}]</span>
        <span class="result-pos">({{ r.start_row }}:{{ r.start_col }})</span>
      </div>
    </div>
  </div>
</template>

<style scoped>
.query-panel {
  display: flex;
  flex-direction: column;
  height: 100%;
  overflow: hidden;
}

.query-editor-wrap {
  position: relative;
  flex-shrink: 0;
}

.query-editor {
  border-bottom: 1px solid var(--border);
  background: var(--surface);
}

.query-ghost {
  position: absolute;
  inset: 0;
  padding: 10px 12px;
  font-family: var(--mono);
  font-size: 13px;
  overflow: hidden;
  cursor: text;
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
  opacity: 0.7;
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
  transition: background 0.15s;
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

.query-results {
  flex: 1;
  overflow: auto;
  padding: 4px 0;
  font-family: var(--mono);
  font-size: 12.5px;
}

.query-empty {
  padding: 16px;
  color: var(--text);
  opacity: 0.4;
  font-style: italic;
}

.query-result {
  display: flex;
  align-items: baseline;
  gap: 8px;
  padding: 3px 12px;
  cursor: pointer;
  white-space: nowrap;
}
.query-result:hover { background: var(--accent-bg); }

.result-capture { color: var(--accent); font-weight: 700; }
.result-text    { color: var(--text-muted); }
.result-range   { color: var(--text); opacity: 0.45; font-size: 11px; }
.result-pos     { color: var(--text); opacity: 0.35; font-size: 11px; }
</style>
