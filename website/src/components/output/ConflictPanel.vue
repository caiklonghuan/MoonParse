<script setup>
import { computed, ref, watch } from 'vue'
import { conflictActionTitle, normalizeConflictDiagnostics } from '@/lib/conflictDiagnostics.js'

const props = defineProps({ diagnostics: { type: Array, default: () => [] } })
const conflicts = computed(() => normalizeConflictDiagnostics(props.diagnostics))
const selectedKey = ref(null)
const selected = computed(() =>
  conflicts.value.find((conflict) => conflict.key === selectedKey.value) ?? conflicts.value[0] ?? null)

watch(conflicts, (next) => {
  if (!next.some((conflict) => conflict.key === selectedKey.value)) {
    selectedKey.value = next[0]?.key ?? null
  }
}, { immediate: true })

function branchFor(action) {
  return selected.value?.branchByAction?.get(action.index) ?? null
}

function statusLabel(status) {
  return {
    warn: 'Resolved', declared: 'Declared GLR', ambiguous: 'Ambiguous',
    dynamic: 'Dynamic', legacy: 'Legacy',
  }[status] ?? status
}
</script>

<template>
  <div v-if="conflicts.length" class="conflict-panel">
    <nav class="conflict-list" aria-label="LR conflicts">
      <button
        v-for="conflict in conflicts"
        :key="conflict.key"
        type="button"
        :class="{ active: selected?.key === conflict.key }"
        @click="selectedKey = conflict.key"
      >
        <span class="status-badge" :class="`status-badge--${conflict.status}`">
          {{ statusLabel(conflict.status) }}
        </span>
        <strong>{{ conflict.state >= 0 ? `State ${conflict.state}` : 'Diagnostic' }}</strong>
        <code>{{ conflict.terminalName }}</code>
      </button>
    </nav>

    <section v-if="selected" class="conflict-detail">
      <header>
        <div>
          <span class="status-badge" :class="`status-badge--${selected.status}`">
            {{ statusLabel(selected.status) }}
          </span>
          <strong v-if="selected.state >= 0">State {{ selected.state }} on {{ selected.terminalName }}</strong>
          <strong v-else>Parser diagnostic</strong>
        </div>
        <p>{{ selected.message }}</p>
      </header>

      <div v-if="!selected.extended" class="legacy-conflict">
        Legacy diagnostic format. Rebuild the parser to inspect its LR path and branches.
      </div>

      <template v-else>
        <section class="flow-stage">
          <h4>1. State path</h4>
          <div v-if="selected.statePath.length" class="state-path">
            <span class="state-chip">State 0</span>
            <template v-for="(step, index) in selected.statePath" :key="`${step.fromState}:${step.toState}:${index}`">
              <span class="path-edge">
                <code>{{ step.symbolName }}</code><small>{{ step.symbolKind }}</small>→
              </span>
              <span class="state-chip" :class="{ conflict: step.toState === selected.state }">
                State {{ step.toState }}
              </span>
            </template>
          </div>
          <div v-else-if="selected.state === 0" class="state-path">
            <span class="state-chip conflict">State 0</span>
          </div>
          <p v-else class="flow-empty">No path from state 0 was retained.</p>
        </section>

        <div class="flow-arrow">↓</div>
        <section class="flow-stage lookahead-stage">
          <h4>2. Lookahead terminal</h4>
          <strong>{{ selected.terminalName }}</strong><code>terminal #{{ selected.terminal }}</code>
        </section>

        <div class="flow-arrow">↓</div>
        <section class="flow-stage">
          <h4>3. Candidate actions</h4>
          <div class="action-grid">
            <article
              v-for="action in selected.actions"
              :key="action.index"
              class="action-card"
              :class="`action-card--${branchFor(action)?.outcome ?? 'unknown'}`"
            >
              <div class="action-title">
                <strong>{{ conflictActionTitle(action) }}</strong>
                <span>{{ branchFor(action)?.outcome ?? 'unknown' }}</span>
              </div>
              <code>{{ action.display }}</code>
              <dl v-if="action.kind === 'reduce'">
                <dt>Head</dt><dd>{{ action.head }}</dd>
                <dt>Body</dt><dd>{{ action.body.join(' ') || 'ε' }}</dd>
                <dt>Precedence</dt><dd>{{ action.precedence ?? 'none' }}</dd>
                <dt>Associativity</dt><dd>{{ action.associativity ?? 'none' }}</dd>
              </dl>
            </article>
          </div>
        </section>

        <div class="flow-arrow">↓</div>
        <section class="flow-stage resolution-stage">
          <h4>4. Resolution</h4>
          <strong>{{ selected.resolution?.kind }}</strong>
          <p>{{ selected.resolution?.message }}</p>
          <div class="resolution-indexes">
            <span>Kept: {{ selected.resolution?.keptActionIndexes?.join(', ') || 'none' }}</span>
            <span>Discarded: {{ selected.resolution?.discardedActionIndexes?.join(', ') || 'none' }}</span>
          </div>
        </section>

        <details class="item-snapshot">
          <summary>Conflict state LR items ({{ selected.items.length }})</summary>
          <div v-if="selected.items.length" class="item-list">
            <article v-for="(item, index) in selected.items" :key="`${item.productionId}:${item.dot}:${index}`">
              <code>{{ item.display }}</code><span>#{{ item.productionId }} · {{ item.ruleName }}</span>
            </article>
          </div>
          <p v-else>No LR item snapshot is available.</p>
        </details>
      </template>
    </section>
  </div>

  <div v-else class="conflict-empty">
    <strong>No LR conflicts</strong><span>The generated parser has no conflict diagnostics.</span>
  </div>
</template>

<style scoped>
.conflict-panel { display: grid; grid-template-columns: 190px minmax(0, 1fr); min-height: 100%; }
.conflict-list { padding: 8px; border-right: 1px solid var(--border); background: var(--surface-2); }
.conflict-list button { display: grid; grid-template-columns: 1fr auto; gap: 5px; width: 100%; margin-bottom: 6px; padding: 8px; border: 1px solid var(--border); border-radius: 7px; color: var(--text); background: var(--surface); text-align: left; cursor: pointer; }
.conflict-list button.active { border-color: var(--accent); box-shadow: inset 3px 0 var(--accent); }
.conflict-list .status-badge { grid-column: 1 / -1; justify-self: start; }
.status-badge { display: inline-flex; padding: 2px 6px; border-radius: 999px; font-size: 9px; font-weight: 700; text-transform: uppercase; }
.status-badge--warn { color: #b45309; background: rgba(245, 158, 11, .15); }
.status-badge--declared { color: #2563eb; background: rgba(59, 130, 246, .14); }
.status-badge--ambiguous { color: #dc2626; background: rgba(239, 68, 68, .14); }
.status-badge--dynamic { color: #7c3aed; background: rgba(139, 92, 246, .14); }
.status-badge--legacy { color: var(--text-muted); background: var(--surface-3); }
.conflict-detail { min-width: 0; padding: 12px; overflow: auto; }
.conflict-detail header > div { display: flex; align-items: center; gap: 8px; }
.conflict-detail header p { color: var(--text-muted); line-height: 1.45; }
.legacy-conflict { padding: 12px; border: 1px dashed var(--border); border-radius: 8px; color: var(--text-muted); }
.flow-stage { padding: 10px; border: 1px solid var(--border); border-radius: 8px; background: var(--surface); }
.flow-stage h4 { margin: 0 0 8px; color: var(--text-muted); font-size: 10px; text-transform: uppercase; }
.flow-arrow { padding: 3px 16px; color: var(--accent); font-size: 16px; }
.state-path { display: flex; align-items: center; gap: 6px; overflow-x: auto; padding-bottom: 4px; }
.state-chip { flex: 0 0 auto; padding: 5px 8px; border: 1px solid var(--border); border-radius: 6px; font-weight: 700; }
.state-chip.conflict { border-color: #ef4444; color: #ef4444; }
.path-edge { display: grid; grid-template-columns: auto auto auto; align-items: center; gap: 3px; color: var(--accent); white-space: nowrap; }
.path-edge small { color: var(--text-muted); font-size: 8px; }
.flow-empty { margin: 0; color: var(--text-muted); }
.lookahead-stage { display: flex; align-items: center; gap: 8px; }
.lookahead-stage h4 { margin-right: auto; }
.action-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 8px; }
.action-card { padding: 9px; border: 1px solid var(--border); border-radius: 7px; background: var(--surface-2); }
.action-card--discarded { opacity: .65; border-style: dashed; }
.action-card--glr { border-color: #3b82f6; }
.action-card--dynamic { border-color: #8b5cf6; }
.action-card--kept { border-color: #22c55e; }
.action-title { display: flex; justify-content: space-between; gap: 8px; margin-bottom: 6px; }
.action-title span { color: var(--text-muted); font-size: 9px; text-transform: uppercase; }
.action-card dl { display: grid; grid-template-columns: auto minmax(0, 1fr); gap: 3px 7px; margin: 8px 0 0; }
.action-card dt { color: var(--text-muted); }
.action-card dd { margin: 0; overflow-wrap: anywhere; }
.resolution-stage { border-color: var(--accent-border); }
.resolution-stage p { margin: 5px 0; color: var(--text-muted); }
.resolution-indexes { display: flex; gap: 12px; color: var(--text-muted); font-size: 10px; }
.item-snapshot { margin-top: 12px; padding: 9px; border: 1px solid var(--border); border-radius: 8px; }
.item-snapshot summary { cursor: pointer; font-weight: 700; }
.item-list { display: grid; gap: 4px; margin-top: 8px; }
.item-list article { display: flex; justify-content: space-between; gap: 10px; padding: 5px 7px; background: var(--surface-2); }
.item-list span { color: var(--text-muted); white-space: nowrap; }
.conflict-empty { display: grid; place-content: center; gap: 6px; min-height: 180px; color: var(--text-muted); text-align: center; }
@media (max-width: 700px) {
  .conflict-panel { grid-template-columns: 1fr; }
  .conflict-list { display: flex; gap: 6px; overflow-x: auto; border-right: 0; border-bottom: 1px solid var(--border); }
  .conflict-list button { min-width: 160px; }
}
</style>
