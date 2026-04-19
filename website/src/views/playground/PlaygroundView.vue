<script setup>
import { ref, computed, provide, watch, onMounted, onUnmounted } from 'vue'
import SplitPane        from '@/components/layout/SplitPane.vue'
import EditorPanel      from '@/components/editor/EditorPanel.vue'
import TreePanel        from '@/components/tree/TreePanel.vue'
import QueryPanel       from '@/components/query/QueryPanel.vue'
import OutputPanel      from '@/components/output/OutputPanel.vue'
import PerfBar          from '@/components/common/PerfBar.vue'
import { useMoonParse }          from '@/composables/useMoonParse.js'
import { useParser }             from '@/composables/useParser.js'
import { useParseTree }          from '@/composables/useParseTree.js'
import { useHighlight }          from '@/composables/useHighlight.js'
import { useUrlState }           from '@/composables/useUrlState.js'
import { useKeyboard }           from '@/composables/useKeyboard.js'
import { useGrammarValidation }  from '@/composables/useGrammarValidation.js'
import { BUILTIN_LANGUAGE_PRESETS, findBuiltinPresetByGrammar } from '@/data/languagePresets.js'

const DEFAULT_PRESET = BUILTIN_LANGUAGE_PRESETS[0]

const { loadState, loadStateAsync, saveState } = useUrlState()
const savedState = loadState()
const initialPreset = findBuiltinPresetByGrammar(savedState?.g)

const grammarDsl   = ref(savedState?.g ?? DEFAULT_PRESET.grammar)
const sourceCode   = ref(savedState?.s ?? DEFAULT_PRESET.source)
const queryPattern = ref(savedState?.q ?? '')
const hlQueryStr   = ref(savedState?.h ?? (savedState?.g ? (initialPreset?.highlightQuery ?? '') : (DEFAULT_PRESET.highlightQuery ?? '')))
const querySuggestion = ref(savedState?.q ? '' : DEFAULT_PRESET.query ?? '')

if (!savedState) {
  loadStateAsync().then(state => {
    if (!state) return
    if (state.g) grammarDsl.value   = state.g
    if (state.s) sourceCode.value   = state.s
    if (state.q) queryPattern.value = state.q
  })
}

const { mp, loading, error: mpError } = useMoonParse()
const { parser, parserError, building }  = useParser(grammarDsl)
const { tree, parseTime, isIncremental, triggerEdit } = useParseTree(parser, sourceCode)

watch([grammarDsl, sourceCode, queryPattern, hlQueryStr], ([g, s, q, h]) =>
  saveState(g, s, q, h)
)

const editorPanelRef = ref(null)
const queryPanelRef  = ref(null)
const currentPresetId = computed(() => findBuiltinPresetByGrammar(grammarDsl.value)?.id ?? 'custom')

const { highlightRanges } = useHighlight(mp, tree, hlQueryStr, currentPresetId, sourceCode)
const { dslErrors } = useGrammarValidation(grammarDsl)

provide('mp', mp)

const sexp = computed(() => { try { return tree.value?.sexp() ?? '' } catch { return '' } })

const version = computed(() => { try { return mp.value?.version() ?? '—' } catch { return '—' } })

const isMobile = ref(window.innerWidth <= 768)
const mobileTab = ref(0)
const MOBILE_TABS = [
  { label: '✎ 编辑' },
  { label: '⊶ 树' },
  { label: '🔍 查询' },
  { label: '{ } 输出' },
]

function onResize() { isMobile.value = window.innerWidth <= 768 }
onMounted(()   => window.addEventListener('resize', onResize))
onUnmounted(() => window.removeEventListener('resize', onResize))

function onSourceChange(val) { sourceCode.value = val }
function onEdit(inputEdit)   { triggerEdit(inputEdit) }

function clearSourceHighlight() {
  editorPanelRef.value?.clearHighlight?.()
}

function shouldKeepSourceHighlight(target) {
  if (!(target instanceof Element)) {
    return false
  }
  return Boolean(target.closest('.tree-node') || target.closest('.query-result'))
}

function onPlaygroundPointerDown(event) {
  if (shouldKeepSourceHighlight(event.target)) {
    return
  }
  clearSourceHighlight()
}

function applyCustomPreset() {
  grammarDsl.value = ''
  sourceCode.value = ''
  queryPattern.value = ''
  querySuggestion.value = ''
  hlQueryStr.value = ''
  mobileTab.value = 0
  clearSourceHighlight()
}

function applyPreset(id) {
  if (id === 'custom') {
    applyCustomPreset()
    return
  }

  const preset = BUILTIN_LANGUAGE_PRESETS.find((item) => item.id === id)
  if (!preset) return
  grammarDsl.value = preset.grammar
  sourceCode.value = preset.source
  queryPattern.value = ''
  querySuggestion.value = preset.query ?? ''
  hlQueryStr.value = preset.highlightQuery ?? ''
  mobileTab.value = 0
  clearSourceHighlight()
}

function onPresetChange(event) {
  applyPreset(event.target.value)
}

function onSelect({ startByte, endByte }) {
  editorPanelRef.value?.highlightRange(startByte, endByte)
}

watch(grammarDsl, (value) => {
  const preset = findBuiltinPresetByGrammar(value)
  if (preset) hlQueryStr.value = preset.highlightQuery ?? ''
  // else: keep user's custom hl query
})

useKeyboard({
  onRunQuery:    () => queryPanelRef.value?.runQuery(),
  onForceParse:  () => {
    const p = parser.value
    const src = sourceCode.value
    if (p && src != null) triggerEdit(null)
  },
  onFocusPanel: (idx) => {
    if (isMobile.value) {
      mobileTab.value = idx
    } else if (idx === 0) {
      editorPanelRef.value?.focus()
    }
  },
})
</script>

<template>
  <div class="playground" @pointerdown.capture="onPlaygroundPointerDown">
    <div v-if="loading" class="playground-loading">
      <span class="spinner" />
      <span>正在加载 MoonParse WASM…</span>
    </div>

    <div v-else-if="mpError" class="playground-fatal">
      <strong>MoonParse 加载失败：</strong>{{ mpError }}
    </div>

    <template v-else>
      <div class="playground-toolbar">
        <div class="playground-toolbar-copy">
          <span class="playground-toolbar-kicker">Built-in Grammars</span>
          <strong>直接切换到仓库内置语言</strong>
        </div>

        <label class="playground-toolbar-field">
          <span>语言</span>
          <select :value="currentPresetId" @change="onPresetChange">
            <option value="custom">自定义文法</option>
            <option v-for="preset in BUILTIN_LANGUAGE_PRESETS" :key="preset.id" :value="preset.id">
              {{ preset.name }}
            </option>
          </select>
        </label>

        <div class="playground-toolbar-chips">
          <button
            v-for="preset in BUILTIN_LANGUAGE_PRESETS"
            :key="preset.id"
            type="button"
            class="preset-chip"
            :class="{ active: currentPresetId === preset.id }"
            @click="applyPreset(preset.id)"
          >
            {{ preset.name }}
          </button>
        </div>

      </div>

      <template v-if="isMobile">
        <div class="playground-mobile-tabs" role="tablist">
          <button
            v-for="(t, i) in MOBILE_TABS"
            :key="i"
            class="playground-mobile-tab"
            :class="{ active: mobileTab === i }"
            role="tab"
            :aria-selected="mobileTab === i"
            @click="mobileTab = i"
          >{{ t.label }}</button>
        </div>
        <div class="playground-mobile-content">
          <div class="playground-mobile-panel" :class="{ active: mobileTab === 0 }">
            <EditorPanel
              ref="editorPanelRef"
              :model-value="sourceCode"
              :grammar="grammarDsl"
              :syntax-ranges="highlightRanges"
              :parser-error="parserError"
              :dsl-validation-errors="dslErrors"
              @update:model-value="onSourceChange"
              @update:grammar="grammarDsl = $event"
              @edit="onEdit"
            />
          </div>
          <div class="playground-mobile-panel" :class="{ active: mobileTab === 1 }">
            <TreePanel :tree="tree" @select="onSelect" />
          </div>
          <div class="playground-mobile-panel" :class="{ active: mobileTab === 2 }">
            <QueryPanel
              ref="queryPanelRef"
              :model-value="queryPattern"
              :tree="tree"
              :suggestion="querySuggestion"
              @update:model-value="queryPattern = $event"
              @select="onSelect"
            />
          </div>
          <div class="playground-mobile-panel" :class="{ active: mobileTab === 3 }">
            <OutputPanel
              :tree="tree"
              :parser="parser"
              :parse-time="parseTime"
              :is-incremental="isIncremental"
              :parser-error="parserError"
            />
          </div>
        </div>
      </template>

      <template v-else>
        <div class="playground-frame">
          <SplitPane direction="vertical" :initial-split="0.55" class="playground-split">
            <template #first>
              <SplitPane direction="horizontal" :initial-split="0.5" style="height:100%">
                <template #first>
                  <EditorPanel
                    ref="editorPanelRef"
                    :model-value="sourceCode"
                    :grammar="grammarDsl"
                    :syntax-ranges="highlightRanges"
                    :parser-error="parserError"
                    :dsl-validation-errors="dslErrors"
                    @update:model-value="onSourceChange"
                    @update:grammar="grammarDsl = $event"
                    @edit="onEdit"
                  />
                </template>
                <template #second>
                  <TreePanel :tree="tree" @select="onSelect" />
                </template>
              </SplitPane>
            </template>

            <template #second>
              <SplitPane direction="horizontal" :initial-split="0.45" style="height:100%">
                <template #first>
                  <QueryPanel
                    ref="queryPanelRef"
                    :model-value="queryPattern"
                    :tree="tree"
                    :suggestion="querySuggestion"
                    @update:model-value="queryPattern = $event"
                    @select="onSelect"
                  />
                </template>
                <template #second>
                  <OutputPanel
                    :tree="tree"
                    :parser="parser"
                    :parse-time="parseTime"
                    :is-incremental="isIncremental"
                    :parser-error="parserError"
                  />
                </template>
              </SplitPane>
            </template>
          </SplitPane>
        </div>
      </template>

    </template>

    <PerfBar
      v-if="!loading && !mpError"
      :parse-time="parseTime"
      :is-incremental="isIncremental"
      :sexp="sexp"
      :version="version"
      :parser-error="parserError"
      :building="building"
    />
  </div>
</template>

<style scoped>
.playground {
  height: calc(100vh - 64px);
  display: flex;
  flex-direction: column;
  overflow: hidden;
  background: transparent;
}

.playground-toolbar {
  display: grid;
  grid-template-columns: auto auto minmax(0, 1fr);
  align-items: center;
  gap: 14px;
  margin: 18px 20px 0;
  padding: 12px 14px;
  border: 1px solid var(--line);
  border-radius: var(--radius-lg);
  background: var(--surface);
  box-shadow: var(--shadow-sm);
}

.playground-toolbar-copy {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}

.playground-toolbar-kicker {
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--text-soft);
}

.playground-toolbar-copy strong {
  font-size: 14px;
  color: var(--text-h);
}

.playground-toolbar-field {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  min-width: 0;
}

.playground-toolbar-field span {
  font-size: 12px;
  color: var(--text-soft);
  white-space: nowrap;
}

.playground-toolbar-field select {
  min-width: 180px;
  height: 36px;
  padding: 0 12px;
  border: 1px solid var(--line);
  border-radius: var(--radius-md);
  background: var(--surface-2);
  color: var(--text-h);
}

.playground-toolbar-chips {
  display: flex;
  gap: 8px;
  min-width: 0;
  overflow-x: auto;
  padding-bottom: 2px;
}

.preset-chip {
  flex: 0 0 auto;
  min-height: 32px;
  padding: 0 10px;
  border: 1px solid var(--line);
  border-radius: var(--radius-md);
  background: var(--surface-2);
  color: var(--text-muted);
  font-size: 12px;
  font-weight: 500;
  cursor: pointer;
}

.preset-chip:hover {
  color: var(--text-h);
  border-color: var(--line-strong);
  background: var(--surface-3);
}

.preset-chip.active {
  color: var(--accent);
  border-color: var(--accent-border);
  background: var(--accent-bg);
}

.playground-frame {
  flex: 1;
  min-height: 0;
  margin: 14px 20px 0;
  border-radius: var(--radius-lg);
  padding: 1px;
  background: linear-gradient(180deg, var(--line-strong) 0%, var(--line) 100%);
  box-shadow: var(--shadow-sm);
  overflow: hidden;
}

.playground-split {
  flex: 1;
  min-height: 0;
  height: 100%;
  border-radius: calc(var(--radius-lg) - 1px);
  background: var(--surface);
  overflow: hidden;
}

.playground-loading,
.playground-fatal {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 12px;
  font-size: 15px;
  color: var(--text);
}
.playground-fatal {
  color: #f44747;
  padding: 32px;
  text-align: center;
}

.spinner {
  display: inline-block;
  width: 20px;
  height: 20px;
  border: 2px solid var(--border);
  border-top-color: var(--accent);
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }

.playground-mobile-tabs {
  display: flex;
  margin: 16px 12px 0;
  border: 1px solid var(--line);
  border-bottom: none;
  border-radius: var(--radius-lg) var(--radius-lg) 0 0;
  background: var(--surface-3);
  flex-shrink: 0;
  overflow-x: auto;
  -webkit-overflow-scrolling: touch;
}

.playground-mobile-tab {
  flex: 1;
  min-width: max-content;
  padding: 9px 14px;
  border: none;
  background: none;
  color: var(--text-muted);
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
  border-bottom: 2px solid transparent;
  white-space: nowrap;
  transition: color 0.15s, border-color 0.15s;
}
.playground-mobile-tab.active {
  color: var(--accent);
  border-bottom-color: var(--accent);
  background: var(--surface);
}

.playground-mobile-content {
  flex: 1;
  min-height: 0;
  overflow: hidden;
  position: relative;
  margin: 0 12px;
  border: 1px solid var(--line);
  border-radius: 0 0 var(--radius-lg) var(--radius-lg);
  background: var(--surface);
}

.playground-mobile-content::after {
  content: '';
  position: absolute;
  top: 0;
  right: 0;
  bottom: 0;
  width: 1px;
  background: var(--line-strong);
  pointer-events: none;
  z-index: 3;
}

.playground-mobile-panel {
  position: absolute;
  inset: 0;
  display: none;
  flex-direction: column;
}
.playground-mobile-panel.active {
  display: flex;
}

@media (max-width: 980px) {
  .playground-toolbar {
    grid-template-columns: 1fr;
    align-items: stretch;
  }

  .playground-toolbar-field {
    justify-content: space-between;
  }

  .playground-toolbar-field select {
    width: 100%;
    min-width: 0;
  }
}


</style>

