<template>
  <div class="perf-bar" aria-label="性能指标">
    <span v-if="building" class="perf-item perf-building">
      ⏳ 构建语法表…
    </span>
    <template v-else>
      <span class="perf-item">
        解析:&nbsp;<strong>{{ parseTime }}ms</strong>
        <span v-if="isIncremental" class="perf-tag" title="增量重新解析">增量</span>
      </span>
      <span class="perf-sep" aria-hidden="true">|</span>
      <span class="perf-item">
        节点:&nbsp;<strong>{{ nodeCount }}</strong>
      </span>
      <span v-if="parserError" class="perf-sep" aria-hidden="true">|</span>
      <span v-if="parserError" class="perf-item perf-err" :title="parserError">
        ⚠ 语法错误
      </span>
    </template>
    <span class="perf-spacer" />
    <span class="perf-version">{{ version }}</span>
  </div>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  parseTime:    { type: Number,  default: 0 },
  isIncremental:{ type: Boolean, default: false },
  sexp:         { type: String,  default: '' },
  version:      { type: String,  default: '—' },
  parserError:  { type: String,  default: null },
  building:     { type: Boolean, default: false },
})

const nodeCount = computed(() => {
  if (!props.sexp) return 0
  let count = 0
  for (let i = 0; i < props.sexp.length; i++) {
    if (props.sexp.charCodeAt(i) === 40) count++
  }
  return count
})
</script>

<style scoped>
.perf-bar {
  display: flex;
  align-items: center;
  gap: 10px;
  margin: 12px 20px 20px;
  padding: 0 12px;
  min-height: 32px;
  font-size: 11px;
  font-family: var(--mono);
  color: var(--text-muted);
  background: var(--surface);
  border: 1px solid var(--line);
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-sm);
  flex-shrink: 0;
  user-select: none;
}

.perf-item  { white-space: nowrap; }
.perf-item strong { color: var(--text-h); }
.perf-sep   { opacity: 0.35; }
.perf-spacer{ flex: 1; }
.perf-version { opacity: 0.55; }

.perf-tag {
  display: inline-block;
  margin-left: 5px;
  padding: 1px 6px;
  border-radius: 999px;
  background: var(--surface-3);
  color: var(--accent);
  border: 1px solid var(--line);
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0;
  vertical-align: middle;
}

.perf-err {
  color: var(--danger);
  cursor: default;
}

.perf-building {
  color: var(--accent);
  animation: perf-pulse 1s ease-in-out infinite;
}
@keyframes perf-pulse {
  0%, 100% { opacity: 1; }
  50%      { opacity: 0.4; }
}

@media (max-width: 768px) {
  .perf-bar {
    margin: 12px;
    flex-wrap: wrap;
    padding-block: 8px;
  }
}
</style>
