<script setup>
import { ref, computed, inject, watch } from 'vue'
import SexpView from './SexpView.vue'
import ConflictPanel from './ConflictPanel.vue'
import TreeSitterComparePanel from './TreeSitterComparePanel.vue'
import { formatTraceMs, formatTraceRange, traceReuseRate } from '@/lib/incrementalTrace.js'

const props = defineProps({
  tree:        { type: Object,  default: null },
  parser:      { type: Object,  default: null },
  parseTime:   { type: Number,  default: 0    },
  isIncremental:{ type: Boolean, default: false },
  parserError: { type: String,  default: null },
  traceEnabled: { type: Boolean, default: false },
  incrementalTrace: { type: Object, default: null },
  activeTab: { type: String, default: '' },
  source: { type: String, default: '' },
  languageId: { type: String, default: 'unknown' },
})

const emit = defineEmits(['update:traceEnabled', 'update:activeTab'])

const mp = inject('mp')

const TABS = ['sexp', 'diagnostics', 'perf', 'incremental', 'compare']
const activeTab = ref(TABS.includes(props.activeTab) ? props.activeTab : 'sexp')
const TAB_LABELS = {
  sexp:        '{ } S 表达式',
  diagnostics: '⚠ 诊断',
  perf:        '⚡ 性能',
  incremental: '↯ 增量',
}
TAB_LABELS.compare = 'Tree-sitter Compare'

function setActiveTab(tab) {
  if (!TABS.includes(tab)) return
  activeTab.value = tab
  emit('update:activeTab', tab)
}

watch(() => props.activeTab, (tab) => {
  if (TABS.includes(tab) && tab !== activeTab.value) {
    activeTab.value = tab
  }
})

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

const reuseRateLabel = computed(() => `${Math.round(traceReuseRate(props.incrementalTrace) * 10000) / 100}%`)
const reusedRanges = computed(() => props.incrementalTrace?.reusedRanges ?? [])
const speedupLabel = computed(() => {
  const value = props.incrementalTrace?.speedup
  return value == null || !Number.isFinite(Number(value)) ? '—' : `${Number(value).toFixed(2)}×`
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
          @click="setActiveTab(tab)"
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
        <ConflictPanel :diagnostics="diagnostics" />
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

      <div v-else-if="activeTab === 'incremental'" class="output-incremental">
        <div class="incremental-toolbar">
          <label class="trace-toggle">
            <input
              type="checkbox"
              :checked="traceEnabled"
              @change="emit('update:traceEnabled', $event.target.checked)"
            />
            Enable incremental trace
          </label>
          <span class="incremental-hint">
            Baseline full parse runs only while enabled and an incremental edit occurs.
          </span>
        </div>

        <div v-if="!traceEnabled" class="output-empty">
          Trace is disabled. Enable it, then edit the source to collect reuse data.
        </div>
        <div v-else-if="!incrementalTrace" class="output-empty">
          No incremental trace yet. Make a source edit after enabling this panel.
        </div>
        <template v-else>
          <div class="incremental-metrics">
            <div class="perf-row">
              <span class="perf-label">复用率</span>
              <span class="perf-value perf-good">{{ reuseRateLabel }}</span>
            </div>
            <div class="perf-row">
              <span class="perf-label">复用节点/字节</span>
              <span class="perf-value">
                {{ incrementalTrace.reusedNodeCount }} nodes · {{ incrementalTrace.reusedByteCount }}/{{ incrementalTrace.sourceByteLength }} bytes
              </span>
            </div>
            <div class="perf-row">
              <span class="perf-label">增量耗时</span>
              <span class="perf-value">{{ formatTraceMs(incrementalTrace.incrementalElapsedMs) }}</span>
            </div>
            <div class="perf-row">
              <span class="perf-label">全量基准</span>
              <span class="perf-value">{{ formatTraceMs(incrementalTrace.fullBaselineElapsedMs) }}</span>
            </div>
            <div class="perf-row">
              <span class="perf-label">加速比</span>
              <span class="perf-value">{{ speedupLabel }}</span>
            </div>
          </div>

          <div class="trace-section">
            <div class="trace-section-title">Ranges</div>
            <div class="trace-range-row"><span>Edit old</span><code>{{ formatTraceRange(incrementalTrace.edit?.oldRange) }}</code></div>
            <div class="trace-range-row"><span>Edit new</span><code>{{ formatTraceRange(incrementalTrace.edit?.newRange) }}</code></div>
            <div class="trace-range-row"><span>Reparse</span><code>{{ formatTraceRange(incrementalTrace.reparseRange) }}</code></div>
          </div>

          <div class="trace-section">
            <div class="trace-section-title">Reused ranges</div>
            <div v-if="reusedRanges.length === 0" class="trace-empty">No reused nodes recorded.</div>
            <div
              v-for="(range, index) in reusedRanges.slice(0, 80)"
              :key="`${range.kind}:${range.startByte}:${range.endByte}:${index}`"
              class="trace-range-row"
            >
              <span>{{ range.kind }}</span>
              <code>{{ formatTraceRange(range) }}</code>
            </div>
            <div v-if="reusedRanges.length > 80" class="trace-empty">
              {{ reusedRanges.length - 80 }} more reused ranges hidden.
            </div>
          </div>
        </template>
      </div>

      <TreeSitterComparePanel
        v-else-if="activeTab === 'compare'"
        :source="source"
        :language-id="languageId"
        :tree="tree"
        :moon-sexp="sexp"
        :moon-parse-time="parseTime"
        :active="activeTab === 'compare'"
      />

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

.output-incremental {
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 14px;
}
.incremental-toolbar {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
  font-family: var(--sans);
}
.trace-toggle {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  color: var(--text-h);
}
.incremental-hint,
.trace-empty {
  color: var(--text);
  opacity: 0.55;
  font-size: 12px;
  font-family: var(--sans);
}
.incremental-metrics {
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.trace-section {
  border-top: 1px solid var(--line);
  padding-top: 10px;
}
.trace-section-title {
  margin-bottom: 8px;
  color: var(--text-h);
  font-family: var(--sans);
  font-size: 12px;
  font-weight: 700;
}
.trace-range-row {
  display: grid;
  grid-template-columns: 90px minmax(0, 1fr);
  gap: 10px;
  align-items: baseline;
  padding: 3px 0;
}
.trace-range-row span {
  color: var(--text);
  opacity: 0.65;
  font-family: var(--sans);
  font-size: 12px;
}
.trace-range-row code {
  color: var(--text-h);
  white-space: pre-wrap;
  word-break: break-word;
}

.output-empty {
  padding: 24px 16px;
  color: var(--text);
  opacity: 0.4;
  font-style: italic;
  font-family: var(--sans);
}
</style>
