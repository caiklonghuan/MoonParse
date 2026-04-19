<script setup>
import { ref, watch, onMounted, onUnmounted } from 'vue'
import {
  EditorState,
  StateEffect,
  StateField,
} from '@codemirror/state'
import {
  EditorView,
  keymap,
  lineNumbers,
  highlightActiveLine,
  Decoration,
} from '@codemirror/view'
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands'
import { moonGrammarSyntax } from '@/lib/dslSyntax.js'

const props = defineProps({
  modelValue:          { type: String,  default: '' },
  grammar:             { type: String,  default: '' },
  syntaxRanges:        { type: Array,   default: () => [] },
  parserError:         { type: String,  default: null },
  dslValidationErrors: { type: Array,   default: () => [] },
})

const emit = defineEmits(['update:modelValue', 'update:grammar', 'edit'])

const activeTab = ref('source')

const sourceEditorRef  = ref(null)
const grammarEditorRef = ref(null)
let sourceView  = null
let grammarView = null

const setRangeEffect = StateEffect.define()
const clearRangeEffect = StateEffect.define()

const setSyntaxEffect = StateEffect.define()

const rangeField = StateField.define({
  create: () => Decoration.none,
  update(decos, tr) {
    decos = decos.map(tr.changes)
    for (const e of tr.effects) {
      if (e.is(setRangeEffect)) {
        const { from, to } = e.value
        decos = Decoration.set([
          Decoration.mark({ class: 'cm-highlight-range' }).range(from, to),
        ])
      } else if (e.is(clearRangeEffect)) {
        decos = Decoration.none
      }
    }
    return decos
  },
  provide: (f) => EditorView.decorations.from(f),
})

const syntaxField = StateField.define({
  create: () => Decoration.none,
  update(decos, tr) {
    decos = decos.map(tr.changes)
    for (const e of tr.effects) {
      if (e.is(setSyntaxEffect)) {
        decos = e.value
      }
    }
    return decos
  },
  provide: (f) => EditorView.decorations.from(f),
})

const HL_CLASS = {
  string:    'hl-string',
  number:    'hl-number',
  boolean:   'hl-boolean',
  keyword:   'hl-keyword',
  operator:  'hl-operator',
  comment:   'hl-comment',
  type:      'hl-type',
  function:  'hl-function',
  variable:  'hl-variable',
  attribute: 'hl-attribute',
  property:  'hl-property',
  constant:  'hl-constant',
}

function buildSyntaxDecos(ranges, docLen) {
  if (!ranges || !ranges.length) return Decoration.none
  const marks = []
  for (const r of ranges) {
    const from = Math.min(r.start_byte, docLen)
    const to   = Math.min(r.end_byte,   docLen)
    if (from >= to) continue
    const cls = HL_CLASS[r.highlight] ?? `hl-${r.highlight}`
    marks.push(Decoration.mark({ class: cls }).range(from, to))
  }
  marks.sort((a, b) => a.from - b.from || a.to - b.to)
  try {
    return Decoration.set(marks, true)
  } catch {
    return Decoration.none
  }
}

function applySyntaxRanges(ranges) {
  if (!sourceView) return
  const docLen = sourceView.state.doc.length
  const decos = buildSyntaxDecos(ranges, docLen)
  sourceView.dispatch({ effects: setSyntaxEffect.of(decos) })
}

function byteToRowCol(doc, offset) {
  const line = doc.lineAt(offset)
  return { row: line.number - 1, col: offset - line.from }
}

function computeInputEdit(tr) {
  let edit = null
  const oldDoc = tr.startState.doc
  const newDoc = tr.state.doc
  tr.changes.iterChanges((fromA, toA, fromB, toB, inserted) => {
    if (edit) return
    const newEndByte = fromB + inserted.length
    edit = {
      start_byte:   fromA,
      old_end_byte: toA,
      new_end_byte: newEndByte,
      start_row:    byteToRowCol(oldDoc, fromA).row,
      start_col:    byteToRowCol(oldDoc, fromA).col,
      old_end_row:  byteToRowCol(oldDoc, toA).row,
      old_end_col:  byteToRowCol(oldDoc, toA).col,
      new_end_row:  byteToRowCol(newDoc, newEndByte).row,
      new_end_col:  byteToRowCol(newDoc, newEndByte).col,
    }
  })
  return edit
}

function buildState(content, onChange, onEditEmit, options = {}) {
  const {
    withSelectionField = false,
    withSemanticField = false,
    extraExtensions = [],
  } = options

  const extensions = [
    history(),
    lineNumbers(),
    highlightActiveLine(),
    keymap.of([...defaultKeymap, ...historyKeymap]),
    EditorView.updateListener.of((update) => {
      if (!update.docChanged) return
      const newContent = update.state.doc.toString()
      onChange(newContent)
      if (onEditEmit) {
        const edit = computeInputEdit(update.transactions[0])
        if (edit) onEditEmit(edit)
      }
    }),
    EditorView.theme({
      '&': { height: '100%', fontSize: '13px' },
      '.cm-scroller': { overflow: 'auto', fontFamily: 'ui-monospace, Consolas, monospace' },
    }),
    ...extraExtensions,
  ]

  if (withSelectionField) {
    extensions.push(rangeField)
  }

  if (withSemanticField) {
    extensions.push(syntaxField)
  }

  return EditorState.create({ doc: content, extensions })
}

onMounted(() => {
  sourceView = new EditorView({
    state: buildState(
      props.modelValue,
      (val) => emit('update:modelValue', val),
      (edit) => emit('edit', edit),
      { withSelectionField: true, withSemanticField: true },
    ),
    parent: sourceEditorRef.value,
  })

  applySyntaxRanges(props.syntaxRanges)

  grammarView = new EditorView({
    state: buildState(
      props.grammar,
      (val) => emit('update:grammar', val),
      null,
      { extraExtensions: [moonGrammarSyntax] },
    ),
    parent: grammarEditorRef.value,
  })
})

onUnmounted(() => {
  sourceView?.destroy()
  grammarView?.destroy()
})

watch(() => props.modelValue, (val) => {
  if (!sourceView) return
  const cur = sourceView.state.doc.toString()
  if (cur !== val) {
    sourceView.dispatch({ changes: { from: 0, to: cur.length, insert: val } })
  }
})

watch(() => props.grammar, (val) => {
  if (!grammarView) return
  const cur = grammarView.state.doc.toString()
  if (cur !== val) {
    grammarView.dispatch({ changes: { from: 0, to: cur.length, insert: val } })
  }
})

watch(() => props.syntaxRanges, (ranges) => {
  applySyntaxRanges(ranges)
}, { deep: false })

function highlightRange(startByte, endByte) {
  if (!sourceView) return
  const docLen = sourceView.state.doc.length
  const from = Math.min(startByte, docLen)
  const to   = Math.min(endByte,   docLen)
  if (from > to) return
  sourceView.dispatch({
    effects:       setRangeEffect.of({ from, to }),
    selection:     { anchor: from, head: to },
    scrollIntoView: true,
  })
  sourceView.focus()
}

function clearHighlight() {
  if (!sourceView) return
  sourceView.dispatch({ effects: clearRangeEffect.of(null) })
}

function focus() {
  if (activeTab.value !== 'source') activeTab.value = 'source'
  sourceView?.focus()
}

defineExpose({ highlightRange, clearHighlight, focus })
</script>

<template>
  <div class="editor-panel panel">
    <div class="panel-header">
      <div class="panel-tabs">
        <button
          class="tab-btn"
          :class="{ 'tab-btn--active': activeTab === 'source' }"
          @click="activeTab = 'source'"
        >✎ 源码</button>
        <button
          class="tab-btn"
          :class="{ 'tab-btn--active': activeTab === 'grammar' }"
          @click="activeTab = 'grammar'"
        >⚙ 语法</button>
      </div>
    </div>

    <div class="editor-body">
      <div
        ref="sourceEditorRef"
        class="cm-host"
        :class="{ 'cm-host--hidden': activeTab !== 'source' }"
      />
      <div
        ref="grammarEditorRef"
        class="cm-host"
        :class="{ 'cm-host--hidden': activeTab !== 'grammar' }"
      />
    </div>

    <Transition name="err">
      <div v-if="parserError" class="grammar-error-bar" role="alert" :title="parserError">
        <span class="err-icon">⚠</span>
        <span class="err-text">{{ parserError }}</span>
      </div>
    </Transition>

    <Transition name="err">
      <div
        v-if="activeTab === 'grammar' && dslValidationErrors.length > 0"
        class="grammar-validation-bar"
        role="status"
      >
        <div
          v-for="(err, i) in dslValidationErrors"
          :key="i"
          class="validation-item"
          :title="err.message"
        >
          <span class="warn-icon">⚠</span>
          <span v-if="err.rule" class="warn-rule">[{{ err.rule }}]</span>
          <span class="warn-text">{{ err.message }}</span>
        </div>
      </div>
    </Transition>
  </div>
</template>

<style scoped>
.editor-panel {
  display: flex;
  flex-direction: column;
  height: 100%;
  overflow: hidden;
}
.editor-body {
  flex: 1;
  overflow: hidden;
  position: relative;
}
.cm-host {
  position: absolute;
  inset: 0;
  overflow: hidden;
}
.cm-host--hidden { display: none; }

.grammar-error-bar {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 5px 12px;
  font-size: 12px;
  color: #ef4444;
  background: rgba(239, 68, 68, 0.1);
  border-top: 1px solid rgba(239, 68, 68, 0.25);
  font-family: var(--mono);
  overflow: hidden;
  flex-shrink: 0;
  cursor: default;
}
.err-icon { flex-shrink: 0; }
.err-text {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.err-enter-active, .err-leave-active { transition: max-height 0.2s, opacity 0.2s; max-height: 40px; }
.err-enter-from, .err-leave-to { max-height: 0; opacity: 0; }

.grammar-validation-bar {
  max-height: 100px;
  overflow-y: auto;
  flex-shrink: 0;
  border-top: 1px solid rgba(234, 179, 8, 0.3);
  background: rgba(234, 179, 8, 0.08);
}
.validation-item {
  display: flex;
  align-items: baseline;
  gap: 5px;
  padding: 3px 12px;
  font-size: 11px;
  font-family: var(--mono);
  color: #b45309;
  overflow: hidden;
}
.warn-icon { flex-shrink: 0; }
.warn-rule {
  flex-shrink: 0;
  font-weight: 600;
  color: #92400e;
}
.warn-text {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>

<style>
.cm-highlight-range {
  background: rgba(255, 213, 0, 0.28);
  border-radius: 2px;
  outline: 1px solid rgba(255, 213, 0, 0.6);
}

.hl-string    { color: #1f8f52; }
.hl-number    { color: #b27000; }
.hl-boolean   { color: #0b7285; font-weight: 600; }
.hl-keyword   { color: #8f1fc7; font-weight: 700; }
.hl-operator  { color: #445266; }
.hl-comment   { color: #9ca3af; font-style: italic; }
.hl-type      { color: #b65f00; font-weight: 600; }
.hl-function  { color: #155eef; font-weight: 600; }
.hl-variable  { color: #c2410c; }
.hl-attribute { color: #a83f7a; font-weight: 600; }
.hl-property  { color: #1857b6; }
.hl-constant  { color: #0f766e; font-weight: 600; }
</style>

