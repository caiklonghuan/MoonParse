<script setup>
import { computed, ref } from 'vue'

import {
  LINT_SEVERITIES,
  lintDiagnosticCounts,
  setLintRuleOption,
  setLintRuleSetOption,
} from '@/lib/lintWorkbench.js'

const props = defineProps({
  diagnostics: { type: Array, default: () => [] },
  ruleSets: { type: Array, default: () => [] },
  options: { type: Object, required: true },
  running: { type: Boolean, default: false },
  stale: { type: Boolean, default: true },
  error: { type: String, default: null },
})

const emit = defineEmits(['run', 'select', 'apply-fix', 'update:options'])
const ruleFilter = ref('')
const counts = computed(() => lintDiagnosticCounts(props.diagnostics))
const filteredDiagnostics = computed(() => ruleFilter.value
  ? props.diagnostics.filter((item) => item.ruleId === ruleFilter.value)
  : props.diagnostics)
const allRules = computed(() => props.ruleSets.flatMap((ruleSet) => ruleSet.rules))

function updateEnabled(event) {
  emit('update:options', { ...props.options, enabled: event.target.checked })
}

function updateRuleSet(id, event) {
  emit('update:options', setLintRuleSetOption(props.options, id, event.target.value))
}

function updateRule(id, event) {
  emit('update:options', setLintRuleOption(props.options, id, event.target.value))
}

function ruleSetValue(id) {
  if (!Object.hasOwn(props.options.ruleSets ?? {}, id)) return 'default'
  return props.options.ruleSets[id] ? 'on' : 'off'
}

function ruleValue(id) {
  return props.options.rules?.[id] ?? 'default'
}
</script>

<template>
  <div class="lint-panel">
    <div class="lint-toolbar">
      <button type="button" class="lint-run" :disabled="running" @click="emit('run')">
        {{ running ? 'Running lint…' : 'Run Lint' }}
      </button>
      <label class="lint-enable">
        <input type="checkbox" :checked="options.enabled !== false" @change="updateEnabled">
        Enabled
      </label>
      <span v-for="severity in LINT_SEVERITIES" :key="severity" class="lint-count" :class="`lint-${severity}`">
        {{ severity }} {{ counts[severity] }}
      </span>
      <span v-if="stale" class="lint-stale">stale</span>
      <select v-model="ruleFilter" class="lint-filter" aria-label="Filter lint diagnostics by rule">
        <option value="">All rules</option>
        <option v-for="rule in allRules" :key="rule.id" :value="rule.id">{{ rule.id }}</option>
      </select>
    </div>

    <div v-if="error" class="lint-error" role="alert">{{ error }}</div>

    <div class="lint-body">
      <aside class="lint-config">
        <div v-if="ruleSets.length === 0" class="lint-empty">This Bundle declares no lint rules.</div>
        <section v-for="ruleSet in ruleSets" :key="ruleSet.id" class="lint-rule-set">
          <div class="lint-rule-set-head">
            <code>{{ ruleSet.id }}</code>
            <select :value="ruleSetValue(ruleSet.id)" @change="updateRuleSet(ruleSet.id, $event)">
              <option value="default">default</option>
              <option value="on">on</option>
              <option value="off">off</option>
            </select>
          </div>
          <label v-for="rule in ruleSet.rules" :key="rule.id" class="lint-rule">
            <span>
              <code>{{ rule.localId }}</code>
              <small>{{ rule.hasFix ? 'quick fix' : rule.severity }}</small>
            </span>
            <select :value="ruleValue(rule.id)" @change="updateRule(rule.id, $event)">
              <option value="default">default</option>
              <option value="off">off</option>
              <option value="hint">hint</option>
              <option value="information">information</option>
              <option value="warning">warning</option>
              <option value="error">error</option>
            </select>
          </label>
        </section>
      </aside>

      <div class="lint-results">
        <div v-if="!running && filteredDiagnostics.length === 0" class="lint-empty">
          {{ stale ? 'Lint results are stale. Run lint or wait for parsing.' : 'No lint diagnostics.' }}
        </div>
        <article
          v-for="(diagnostic, index) in filteredDiagnostics"
          :key="`${diagnostic.ruleId}:${diagnostic.startByte}:${diagnostic.endByte}:${index}`"
          class="lint-diagnostic"
          :class="`lint-diagnostic-${diagnostic.severity}`"
        >
          <button
            type="button"
            class="lint-diagnostic-main"
            @click="emit('select', { startByte: diagnostic.startByte, endByte: diagnostic.endByte })"
          >
            <span class="lint-diagnostic-meta">
              <strong>{{ diagnostic.severity }}</strong>
              <code>{{ diagnostic.ruleId }}</code>
              <span>{{ diagnostic.startByte }}–{{ diagnostic.endByte }}</span>
            </span>
            <span>{{ diagnostic.message }}</span>
          </button>
          <button
            v-if="diagnostic.fix"
            type="button"
            class="lint-fix"
            :disabled="stale"
            @click="emit('apply-fix', diagnostic)"
          >
            {{ diagnostic.fix.title }}
          </button>
        </article>
      </div>
    </div>
  </div>
</template>

<style scoped>
.lint-panel { height: 100%; min-height: 190px; display: flex; flex-direction: column; overflow: hidden; }
.lint-toolbar { display: flex; align-items: center; gap: 8px; padding: 8px 10px; border-bottom: 1px solid var(--line); flex-wrap: wrap; }
.lint-run, .lint-fix, select { border: 1px solid var(--line); border-radius: 6px; background: var(--surface-2); color: var(--text); padding: 5px 8px; font: inherit; font-size: 11px; }
.lint-run, .lint-fix { cursor: pointer; }
.lint-run:disabled, .lint-fix:disabled { opacity: .5; cursor: not-allowed; }
.lint-enable, .lint-count, .lint-stale { font-size: 11px; color: var(--text-muted); }
.lint-enable { display: flex; align-items: center; gap: 4px; }
.lint-stale { color: #b27000; font-weight: 700; }
.lint-filter { margin-left: auto; min-width: 180px; }
.lint-error { padding: 6px 10px; color: #b91c1c; background: rgba(239,68,68,.08); border-bottom: 1px solid rgba(239,68,68,.2); font-size: 11px; }
.lint-body { flex: 1; min-height: 0; display: grid; grid-template-columns: minmax(220px, 30%) 1fr; }
.lint-config, .lint-results { min-height: 0; overflow: auto; padding: 8px; }
.lint-config { border-right: 1px solid var(--line); }
.lint-rule-set { margin-bottom: 8px; border: 1px solid var(--line); border-radius: 7px; overflow: hidden; }
.lint-rule-set-head, .lint-rule { display: flex; justify-content: space-between; align-items: center; gap: 8px; padding: 6px 8px; }
.lint-rule-set-head { background: var(--surface-2); }
.lint-rule { border-top: 1px solid var(--line); }
.lint-rule > span { display: flex; flex-direction: column; min-width: 0; }
.lint-rule small { color: var(--text-soft); }
.lint-diagnostic { display: flex; gap: 8px; border: 1px solid var(--line); border-left-width: 3px; border-radius: 7px; margin-bottom: 6px; padding: 5px; }
.lint-diagnostic-error { border-left-color: #dc2626; }
.lint-diagnostic-warning { border-left-color: #d97706; }
.lint-diagnostic-information { border-left-color: #2563eb; }
.lint-diagnostic-hint { border-left-color: #0d9488; }
.lint-diagnostic-main { flex: 1; min-width: 0; display: flex; flex-direction: column; align-items: flex-start; gap: 3px; border: 0; background: transparent; color: var(--text); text-align: left; cursor: pointer; font: inherit; }
.lint-diagnostic-meta { display: flex; gap: 8px; align-items: center; color: var(--text-soft); font-size: 10px; flex-wrap: wrap; }
.lint-empty { padding: 18px; color: var(--text-soft); text-align: center; font-size: 12px; }
@media (max-width: 768px) {
  .lint-body { grid-template-columns: 1fr; }
  .lint-config { border-right: 0; border-bottom: 1px solid var(--line); max-height: 180px; }
}
</style>
