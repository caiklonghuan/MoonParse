<script setup>
import { computed, ref } from 'vue'

import {
  corpusCaseKey,
  corpusSourceForCase,
  createLineDiff,
  hasSexpFailure,
} from '@/lib/corpusWorkbench.js'

const props = defineProps({
  files: { type: Object, default: () => ({}) },
  cases: { type: Array, default: () => [] },
  diagnostics: { type: Array, default: () => [] },
  elapsedMs: { type: Number, default: 0 },
  stale: { type: Boolean, default: false },
  running: { type: Boolean, default: false },
  selectedKey: { type: String, default: null },
  runRevision: { type: Number, default: -1 },
  projectRevision: { type: Number, default: 0 },
  format: { type: String, default: 'moonparse-corpus-v1' },
})

const emit = defineEmits(['run', 'run-case', 'select', 'update-selected', 'update-all'])

const statusFilter = ref('all')
const fileFilter = ref('all')
const nameFilter = ref('')

const caseRows = computed(() => props.cases.map((testCase) => ({
  testCase,
  key: corpusCaseKey(testCase),
})))

const fileOptions = computed(() =>
  [...new Set(props.cases.map((testCase) => testCase.path).filter(Boolean))].sort())

const filteredRows = computed(() => {
  const query = nameFilter.value.trim().toLowerCase()
  return caseRows.value.filter(({ testCase }) => {
    if (statusFilter.value === 'passed' && !testCase.passed) return false
    if (statusFilter.value === 'failed' && testCase.passed) return false
    if (fileFilter.value !== 'all' && testCase.path !== fileFilter.value) return false
    if (query && !String(testCase.name ?? '').toLowerCase().includes(query)) return false
    return true
  })
})

const selectedCase = computed(() =>
  caseRows.value.find((row) => row.key === props.selectedKey)?.testCase ?? null)

const selectedSource = computed(() =>
  selectedCase.value ? corpusSourceForCase(props.files, selectedCase.value) : '')

const totalCount = computed(() => props.cases.length)
const failedCount = computed(() => props.cases.filter((testCase) => !testCase.passed).length)
const passedCount = computed(() => totalCount.value - failedCount.value)
const selectedCanUpdate = computed(() =>
  props.format === 'moonparse-corpus-v2' &&
  Boolean(selectedCase.value && !selectedCase.value.passed && hasSexpFailure(selectedCase.value)))
const allSnapshotUpdateCount = computed(() =>
  props.format === 'moonparse-corpus-v2'
    ? props.cases.filter((testCase) =>
      !testCase.passed && hasSexpFailure(testCase) && Boolean(testCase.actualSexp)).length
    : 0)

function kindOf(failure) {
  return String(failure?.kind ?? '').toLowerCase()
}

function lineDiffFor(failure) {
  const expected = failure?.expected ?? ''
  const actual = failure?.actual ?? selectedCase.value?.actualSexp ?? ''
  return createLineDiff(expected, actual)
}

function diffPrefix(type) {
  if (type === 'add') return '+'
  if (type === 'remove') return '-'
  if (type === 'omitted') return '…'
  return ' '
}

function formatMs(value) {
  if (!Number.isFinite(value)) return '-'
  if (value < 1000) return `${value.toFixed(1)} ms`
  return `${(value / 1000).toFixed(2)} s`
}
</script>

<template>
  <section class="corpus-panel">
    <div class="corpus-toolbar">
      <button type="button" class="corpus-btn corpus-btn-primary" :disabled="running" @click="emit('run')">
        {{ running ? 'Running...' : 'Run all Corpus' }}
      </button>
      <button
        type="button"
        class="corpus-btn"
        :disabled="running || !selectedCase"
        @click="emit('run-case', selectedKey)"
      >
        Rerun selected
      </button>
      <button
        v-if="format === 'moonparse-corpus-v2'"
        type="button"
        class="corpus-btn"
        :disabled="running || !selectedCanUpdate"
        @click="emit('update-selected')"
      >
        Update selected snapshot
      </button>
      <button
        v-if="format === 'moonparse-corpus-v2'"
        type="button"
        class="corpus-btn"
        :disabled="running || allSnapshotUpdateCount === 0"
        @click="emit('update-all')"
      >
        Update all snapshots ({{ allSnapshotUpdateCount }})
      </button>
      <span v-if="stale" class="corpus-badge corpus-badge-warn">stale</span>
      <span class="corpus-meta">
        {{ totalCount }} total / {{ passedCount }} passed / {{ failedCount }} failed ·
        {{ formatMs(elapsedMs) }} · rev {{ runRevision < 0 ? '-' : runRevision }}/{{ projectRevision }}
      </span>
    </div>

    <div class="corpus-filters">
      <label>
        Status
        <select v-model="statusFilter">
          <option value="all">All</option>
          <option value="failed">Failed</option>
          <option value="passed">Passed</option>
        </select>
      </label>
      <label>
        File
        <select v-model="fileFilter">
          <option value="all">All files</option>
          <option v-for="path in fileOptions" :key="path" :value="path">{{ path }}</option>
        </select>
      </label>
      <label class="corpus-name-filter">
        Name
        <input v-model="nameFilter" type="search" placeholder="Filter case name">
      </label>
    </div>

    <div v-if="diagnostics.length" class="corpus-diagnostics">
      <div v-for="(diagnostic, index) in diagnostics" :key="`${diagnostic.code}:${index}`" class="corpus-diagnostic">
        <span>{{ diagnostic.severity ?? 'info' }}</span>
        <code>{{ diagnostic.code ?? '-' }}</code>
        <span>{{ diagnostic.message }}</span>
      </div>
    </div>

    <div v-if="cases.length === 0" class="corpus-empty">
      Run Corpus to see case results.
    </div>

    <div v-else class="corpus-content">
      <div class="corpus-case-list">
        <button
          v-for="{ testCase, key } in filteredRows"
          :key="key"
          type="button"
          class="corpus-case"
          :class="{ selected: key === selectedKey, passed: testCase.passed, failed: !testCase.passed }"
          @click="emit('select', key)"
        >
          <span class="corpus-case-status">{{ testCase.passed ? 'PASS' : 'FAIL' }}</span>
          <span class="corpus-case-name">{{ testCase.name || '<unnamed>' }}</span>
          <span class="corpus-case-path">{{ testCase.path }}:{{ testCase.sourceLine }}</span>
        </button>
      </div>

      <div class="corpus-detail">
        <div v-if="!selectedCase" class="corpus-empty">
          Select a Corpus case to inspect details.
        </div>
        <template v-else>
          <div class="corpus-detail-header">
            <strong>{{ selectedCase.name || '<unnamed>' }}</strong>
            <span>{{ selectedCase.path }} · case #{{ selectedCase.caseIndex }} · source line {{ selectedCase.sourceLine }}</span>
            <span :class="selectedCase.passed ? 'corpus-pass' : 'corpus-fail'">
              {{ selectedCase.passed ? 'passed' : 'failed' }}
            </span>
          </div>

          <div class="corpus-section">
            <h4>Source</h4>
            <pre>{{ selectedSource || '(source unavailable)' }}</pre>
          </div>

          <div v-if="selectedCase.failures?.length" class="corpus-section">
            <h4>Failures</h4>
            <div
              v-for="(failure, index) in selectedCase.failures"
              :key="`${kindOf(failure)}:${index}`"
              class="corpus-failure"
            >
              <div class="corpus-failure-title">
                <span>{{ kindOf(failure) }}</span>
                <small>{{ failure.message }}</small>
              </div>

              <dl v-if="kindOf(failure) === 'error'" class="corpus-kv">
                <dt>Expected</dt>
                <dd>{{ failure.expected || '-' }}</dd>
                <dt>Actual</dt>
                <dd>{{ failure.actual || '-' }}</dd>
              </dl>

              <div v-else-if="kindOf(failure) === 'sexp'" class="corpus-diff">
                <div
                  v-for="(line, lineIndex) in lineDiffFor(failure)"
                  :key="lineIndex"
                  class="corpus-diff-line"
                  :class="`corpus-diff-${line.type}`"
                >
                  <span class="corpus-diff-sign">{{ diffPrefix(line.type) }}</span>
                  <span class="corpus-diff-no">{{ line.leftLine ?? '' }}</span>
                  <span class="corpus-diff-no">{{ line.rightLine ?? '' }}</span>
                  <span class="corpus-diff-text">{{ line.text }}</span>
                </div>
              </div>

              <div v-else-if="kindOf(failure) === 'contains' || kindOf(failure) === 'notcontains'" class="corpus-fragment">
                <p>{{ kindOf(failure) === 'contains' ? 'Missing expected fragment:' : 'Unexpected forbidden fragment:' }}</p>
                <pre>{{ failure.expected || failure.actual || '' }}</pre>
              </div>

              <dl v-else class="corpus-kv">
                <dt>Expected</dt>
                <dd>{{ failure.expected || '-' }}</dd>
                <dt>Actual</dt>
                <dd>{{ failure.actual || '-' }}</dd>
              </dl>
            </div>
          </div>

          <div class="corpus-section">
            <h4>Actual S-expression</h4>
            <pre>{{ selectedCase.actualSexp || '(none)' }}</pre>
          </div>
        </template>
      </div>
    </div>
  </section>
</template>

<style scoped>
.corpus-panel {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 8px;
  overflow: hidden;
}

.corpus-toolbar,
.corpus-filters {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}

.corpus-btn {
  min-height: 30px;
  padding: 0 9px;
  border: 1px solid var(--line);
  border-radius: var(--radius-sm);
  background: var(--surface-2);
  color: var(--text-muted);
  font: inherit;
  font-size: 12px;
  cursor: pointer;
}

.corpus-btn-primary {
  color: var(--accent);
  border-color: var(--accent-border);
  background: var(--accent-bg);
}

.corpus-btn:disabled {
  cursor: not-allowed;
  opacity: 0.55;
}

.corpus-meta,
.corpus-badge {
  color: var(--text-soft);
  font-size: 11px;
}

.corpus-badge {
  border: 1px solid var(--line);
  border-radius: 999px;
  padding: 2px 7px;
}

.corpus-badge-warn {
  color: #f4b747;
  border-color: color-mix(in srgb, #f4b747 45%, transparent);
}

.corpus-filters label {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  color: var(--text-soft);
  font-size: 11px;
}

.corpus-filters select,
.corpus-filters input {
  min-height: 28px;
  border: 1px solid var(--line);
  border-radius: var(--radius-sm);
  background: var(--surface-2);
  color: var(--text-muted);
  font: inherit;
  font-size: 12px;
}

.corpus-name-filter {
  flex: 1;
  min-width: 180px;
}

.corpus-name-filter input {
  flex: 1;
  min-width: 0;
  padding: 0 8px;
}

.corpus-diagnostics {
  display: flex;
  flex-direction: column;
  gap: 4px;
  max-height: 84px;
  overflow: auto;
}

.corpus-diagnostic {
  display: grid;
  grid-template-columns: 70px 100px minmax(0, 1fr);
  gap: 8px;
  padding: 5px 7px;
  border: 1px solid var(--line);
  border-radius: var(--radius-sm);
  color: var(--text-muted);
  font-size: 12px;
}

.corpus-content {
  flex: 1;
  min-height: 0;
  display: grid;
  grid-template-columns: minmax(230px, 0.45fr) minmax(0, 1fr);
  gap: 8px;
  overflow: hidden;
}

.corpus-case-list,
.corpus-detail {
  min-height: 0;
  overflow: auto;
  border: 1px solid var(--line);
  border-radius: var(--radius-md);
  background: var(--surface-2);
}

.corpus-case-list {
  padding: 5px;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.corpus-case {
  display: grid;
  grid-template-columns: 44px minmax(0, 1fr);
  gap: 4px 8px;
  padding: 7px;
  border: 1px solid transparent;
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--text-muted);
  text-align: left;
  font: inherit;
  cursor: pointer;
}

.corpus-case:hover,
.corpus-case.selected {
  border-color: var(--line-strong);
  background: var(--surface-3);
}

.corpus-case-status {
  font-family: var(--mono);
  font-size: 10px;
}

.corpus-case.failed .corpus-case-status,
.corpus-fail {
  color: #f44747;
}

.corpus-case.passed .corpus-case-status,
.corpus-pass {
  color: #4ec98f;
}

.corpus-case-name,
.corpus-case-path {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.corpus-case-path {
  grid-column: 2;
  color: var(--text-soft);
  font-family: var(--mono);
  font-size: 11px;
}

.corpus-detail {
  padding: 10px;
}

.corpus-detail-header {
  display: flex;
  gap: 8px;
  align-items: baseline;
  flex-wrap: wrap;
  color: var(--text-soft);
  font-size: 12px;
}

.corpus-detail-header strong {
  color: var(--text-h);
  font-size: 13px;
}

.corpus-section {
  margin-top: 10px;
}

.corpus-section h4 {
  margin: 0 0 5px;
  color: var(--text-soft);
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.06em;
}

.corpus-section pre,
.corpus-fragment pre {
  margin: 0;
  padding: 8px;
  border: 1px solid var(--line);
  border-radius: var(--radius-sm);
  background: var(--surface);
  color: var(--text-muted);
  font-family: var(--mono);
  font-size: 12px;
  white-space: pre-wrap;
  overflow: auto;
}

.corpus-failure {
  margin-bottom: 8px;
  border: 1px solid var(--line);
  border-radius: var(--radius-sm);
  background: var(--surface);
  overflow: hidden;
}

.corpus-failure-title {
  display: flex;
  gap: 8px;
  align-items: center;
  padding: 6px 8px;
  border-bottom: 1px solid var(--line);
  color: var(--text-muted);
}

.corpus-failure-title span {
  font-family: var(--mono);
  color: #f44747;
}

.corpus-failure-title small {
  color: var(--text-soft);
}

.corpus-kv {
  display: grid;
  grid-template-columns: 80px minmax(0, 1fr);
  gap: 4px 8px;
  margin: 0;
  padding: 8px;
  color: var(--text-muted);
  font-size: 12px;
}

.corpus-kv dt {
  color: var(--text-soft);
}

.corpus-kv dd {
  margin: 0;
  font-family: var(--mono);
}

.corpus-diff {
  overflow: auto;
  font-family: var(--mono);
  font-size: 12px;
}

.corpus-diff-line {
  display: grid;
  grid-template-columns: 18px 42px 42px minmax(0, 1fr);
  gap: 4px;
  padding: 1px 8px;
  white-space: pre;
}

.corpus-diff-add {
  background: color-mix(in srgb, #4ec98f 14%, transparent);
}

.corpus-diff-remove {
  background: color-mix(in srgb, #f44747 14%, transparent);
}

.corpus-diff-omitted {
  color: var(--text-soft);
}

.corpus-diff-sign,
.corpus-diff-no {
  color: var(--text-soft);
}

.corpus-fragment {
  padding: 8px;
}

.corpus-fragment p {
  margin: 0 0 6px;
  color: var(--text-soft);
  font-size: 12px;
}

.corpus-empty {
  padding: 18px;
  color: var(--text-soft);
  font-size: 12px;
}
</style>
