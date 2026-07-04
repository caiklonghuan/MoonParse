<script setup>
import { computed, toRef } from 'vue'
import SexpView from './SexpView.vue'
import { useTreeSitterCompare } from '@/composables/useTreeSitterCompare.js'
import { collectMoonParseMetrics } from '@/lib/treeSitterCompare.js'

const props = defineProps({
  source: { type: String, default: '' },
  languageId: { type: String, default: 'unknown' },
  tree: { type: Object, default: null },
  moonSexp: { type: String, default: '' },
  moonParseTime: { type: Number, default: 0 },
  active: { type: Boolean, default: false },
})

const { treeSitterResult } = useTreeSitterCompare(
  toRef(props, 'source'),
  toRef(props, 'languageId'),
  toRef(props, 'active'),
)

const moonMetrics = computed(() => collectMoonParseMetrics(props.tree))
const structureSummary = computed(() => {
  if (treeSitterResult.value.status !== 'ready' || !props.moonSexp) return ''
  return props.moonSexp === treeSitterResult.value.sexp ? 'same' : 'different'
})

function formatMs(value) {
  const number = Number(value)
  if (!Number.isFinite(number)) return '—'
  return `${number.toFixed(number < 10 ? 2 : 1)} ms`
}
</script>

<template>
  <div class="compare-panel">
    <div v-if="treeSitterResult.status === 'idle'" class="compare-state">
      Open Compare to run Tree-sitter.
    </div>
    <div v-else-if="treeSitterResult.status === 'loading'" class="compare-state">
      Loading Tree-sitter JSON and parsing the current source…
    </div>
    <div v-else-if="treeSitterResult.status === 'unavailable'" class="compare-state compare-unavailable">
      {{ treeSitterResult.error }}
    </div>
    <div v-else-if="treeSitterResult.status === 'error'" class="compare-state compare-error">
      <strong>Tree-sitter failed:</strong> {{ treeSitterResult.error }}
      <div class="compare-isolation">MoonParse results remain available and unchanged.</div>
    </div>

    <template v-else>
      <div class="compare-summary">
        <span class="compare-badge">JSON · real parse</span>
        <span class="compare-badge" :class="`compare-badge--${structureSummary}`">
          S-expressions: {{ structureSummary }}
        </span>
        <span class="compare-note">Different node names are expected because the grammars are independent.</span>
      </div>

      <div class="compare-grid">
        <section class="compare-column">
          <h3>MoonParse</h3>
          <dl class="compare-metrics">
            <div><dt>Time</dt><dd>{{ formatMs(moonParseTime) }}</dd></div>
            <div><dt>Nodes</dt><dd>{{ moonMetrics.nodeCount }}</dd></div>
            <div><dt>Errors</dt><dd>{{ moonMetrics.errorCount }}</dd></div>
            <div><dt>Status</dt><dd :class="moonMetrics.hasError ? 'metric-error' : 'metric-ok'">{{ moonMetrics.hasError ? 'error' : 'ok' }}</dd></div>
          </dl>
          <SexpView v-if="moonSexp" :value="moonSexp" />
          <div v-else class="compare-empty">No MoonParse tree.</div>
        </section>

        <section class="compare-column">
          <h3>Tree-sitter</h3>
          <dl class="compare-metrics">
            <div><dt>Time</dt><dd>{{ formatMs(treeSitterResult.parseTimeMs) }}</dd></div>
            <div><dt>Nodes</dt><dd>{{ treeSitterResult.nodeCount }}</dd></div>
            <div><dt>Errors</dt><dd>{{ treeSitterResult.errorCount }}</dd></div>
            <div><dt>Status</dt><dd :class="treeSitterResult.hasError ? 'metric-error' : 'metric-ok'">{{ treeSitterResult.hasError ? 'error' : 'ok' }}</dd></div>
          </dl>
          <SexpView :value="treeSitterResult.sexp" />
        </section>
      </div>
    </template>
  </div>
</template>

<style scoped>
.compare-panel { min-height: 100%; padding: 14px; font-family: var(--sans); }
.compare-state { padding: 20px; border: 1px solid var(--line); border-radius: 6px; color: var(--text); }
.compare-unavailable { color: #d7ba7d; }
.compare-error { color: #f48771; }
.compare-isolation { margin-top: 8px; color: var(--text); opacity: 0.65; }
.compare-summary { display: flex; align-items: center; gap: 8px; margin-bottom: 12px; flex-wrap: wrap; }
.compare-badge { padding: 3px 8px; border: 1px solid var(--line); border-radius: 999px; color: var(--text-h); font-size: 11px; }
.compare-badge--same { border-color: #4ec9b0; color: #4ec9b0; }
.compare-badge--different { border-color: #d7ba7d; color: #d7ba7d; }
.compare-note { color: var(--text); opacity: 0.55; font-size: 11px; }
.compare-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; }
.compare-column { min-width: 0; padding: 12px; border: 1px solid var(--line); border-radius: 6px; overflow: auto; }
.compare-column h3 { margin: 0 0 10px; color: var(--text-h); font-size: 13px; }
.compare-metrics { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 5px 12px; margin: 0 0 12px; font-family: var(--mono); font-size: 11px; }
.compare-metrics div { display: flex; justify-content: space-between; gap: 8px; }
.compare-metrics dt { color: var(--text); opacity: 0.55; }
.compare-metrics dd { margin: 0; color: var(--text-h); }
.metric-ok { color: #4ec9b0 !important; }
.metric-error { color: #f48771 !important; }
.compare-empty { color: var(--text); opacity: 0.5; font-style: italic; }
@media (max-width: 800px) { .compare-grid { grid-template-columns: 1fr; } }
</style>
