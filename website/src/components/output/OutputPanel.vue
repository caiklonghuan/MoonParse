<script setup>
import { ref, computed, inject } from 'vue'
import SexpView from './SexpView.vue'

const props = defineProps({
  tree:        { type: Object,  default: null },
  parser:      { type: Object,  default: null },
  parseTime:   { type: Number,  default: 0    },
  isIncremental:{ type: Boolean, default: false },
  parserError: { type: String,  default: null },
})

const mp = inject('mp')

function diagMessage(d) {
  return typeof d === 'string' ? d : (d.severity ?? JSON.stringify(d))
}

const activeTab = ref('sexp')
const TABS = ['sexp', 'diagnostics', 'perf']
const TAB_LABELS = {
  sexp:        '{ } S 表达式',
  diagnostics: '⚠ 诊断',
  perf:        '⚡ 性能',
}

const sexp = computed(() => {
  try { return props.tree?.sexp() ?? '' }
  catch { return '' }
})

const errorSummary = computed(() => {
  try { return props.tree?.errorSummary() ?? '暂无语法树' }
  catch { return '错误' }
})

const errorSummaryLabel = computed(() => {
  return errorSummary.value || '—'
})

const diagnostics = computed(() => {
  try {
    const raw = props.parser?.diagnosticsJson() ?? '[]'
    return JSON.parse(raw)
  } catch { return [] }
})

const version = computed(() => {
  try { return mp?.value?.version() ?? '—' }
  catch { return '—' }
})
</script>

<template>
  <div class="output-panel panel">
    <div class="panel-header">
      <div class="panel-tabs">
        <button
          v-for="tab in TABS"
          :key="tab"
          class="tab-btn"
          :class="{ 'tab-btn--active': activeTab === tab }"
          @click="activeTab = tab"
        >
          {{ TAB_LABELS[tab] }}
        </button>
      </div>
    </div>

    <div class="output-body">
      <div v-if="activeTab === 'sexp'" class="output-sexp">
        <div v-if="parserError" class="diag-error">
          <strong>语法错误：</strong>{{ parserError }}
        </div>
        <SexpView v-if="sexp" :value="sexp" />
        <div v-else class="output-empty">还没有解析结果。</div>
      </div>

      <div v-else-if="activeTab === 'diagnostics'" class="output-diag">
        <div class="diag-section">
          <div class="diag-label">错误概览</div>
          <div class="diag-value" :class="errorSummary === 'ok' ? 'diag-ok' : 'diag-warn'">
            {{ errorSummaryLabel }}
          </div>
        </div>
        <div v-if="parserError" class="diag-section">
          <div class="diag-label">语法 DSL 错误</div>
          <div class="diag-value diag-error">{{ parserError }}</div>
        </div>
        <div v-if="diagnostics.length" class="diag-section">
          <div class="diag-label">解析器诊断（{{ diagnostics.length }}）</div>
          <div v-for="(d, i) in diagnostics" :key="i" class="diag-item">
            {{ diagMessage(d) }}
          </div>
        </div>
        <div v-if="!diagnostics.length && !parserError && errorSummary === 'ok'" class="output-empty">
          ✓ 未发现问题。
        </div>
      </div>

      <div v-else-if="activeTab === 'perf'" class="output-perf">
        <div class="perf-row">
          <span class="perf-label">解析模式</span>
          <span class="perf-value" :class="isIncremental ? 'perf-good' : ''">
            {{ isIncremental ? '⚡ 增量' : '↺ 全量' }}
          </span>
        </div>
        <div class="perf-row">
          <span class="perf-label">解析耗时</span>
          <span class="perf-value">{{ parseTime }} ms</span>
        </div>
        <div class="perf-row">
          <span class="perf-label">语法树状态</span>
          <span class="perf-value">{{ tree ? '✓ 已生成' : '✗ 未生成' }}</span>
        </div>
        <div class="perf-row">
          <span class="perf-label">MoonParse 版本</span>
          <span class="perf-value">{{ version }}</span>
        </div>
      </div>

    </div>
  </div>
</template>

<style scoped>
.output-panel {
  display: flex;
  flex-direction: column;
  height: 100%;
  overflow: hidden;
}

.output-body {
  flex: 1;
  overflow: auto;
  font-family: var(--mono);
  font-size: 12.5px;
}

.output-sexp { padding: 4px 0; }

.output-diag { padding: 12px; display: flex; flex-direction: column; gap: 16px; }
.diag-section {}
.diag-label   { font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px; color: var(--text); opacity: 0.5; margin-bottom: 4px; }
.diag-value   { font-size: 13px; padding: 4px 0; }
.diag-ok      { color: #4ec9b0; }
.diag-warn    { color: #f4b747; }
.diag-error   { color: #f44747; }
.diag-item    { padding: 2px 0; color: var(--text); font-size: 12px; }

.output-perf { padding: 16px; display: flex; flex-direction: column; gap: 12px; }
.perf-row    { display: flex; gap: 16px; align-items: baseline; }
.perf-label  { min-width: 140px; color: var(--text); opacity: 0.6; font-size: 12px; }
.perf-value  { font-size: 14px; color: var(--text-h); }
.perf-good   { color: #4ec9b0; }

.output-empty {
  padding: 24px 16px;
  color: var(--text);
  opacity: 0.4;
  font-style: italic;
  font-family: var(--sans);
}
</style>
