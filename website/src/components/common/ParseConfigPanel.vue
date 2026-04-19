<script setup>
import { reactive, inject } from 'vue'

const mp = inject('mp')

const DEFAULTS = {
  error_cost_per_skipped_tree:   100,
  error_cost_per_skipped_char:   1,
  error_cost_per_skipped_line:   30,
  error_cost_per_missing_tree:   110,
  error_cost_per_recovery:       500,
  max_version_count:             6,
  max_version_count_overflow:    4,
}

const LABELS = {
  error_cost_per_skipped_tree:   '跳过子树代价',
  error_cost_per_skipped_char:   '跳过字节代价',
  error_cost_per_skipped_line:   '跳过行代价',
  error_cost_per_missing_tree:   'MISSING节点代价',
  error_cost_per_recovery:       '错误恢复固定惩罚',
  max_version_count:             'GLR 最大并行版本数',
  max_version_count_overflow:    '版本数溢出容忍量',
}

const cfg = reactive({ ...DEFAULTS })

function apply() {
  mp.value?.setParseConfig({ ...cfg })
}

function reset() {
  Object.assign(cfg, DEFAULTS)
  mp.value?.resetParseConfig()
}
</script>

<template>
  <div class="parse-config-panel">
    <div class="config-header">⚙ GLR 解析配置</div>
    <div class="config-body">
      <div v-for="(label, key) in LABELS" :key="key" class="config-row">
        <label class="config-label" :title="key">{{ label }}</label>
        <input
          v-model.number="cfg[key]"
          type="number"
          min="0"
          class="config-input"
          :placeholder="DEFAULTS[key]"
        />
      </div>
    </div>
    <div class="config-footer">
      <button class="config-btn config-btn--apply" @click="apply">应用</button>
      <button class="config-btn config-btn--reset" @click="reset">重置默认</button>
    </div>
  </div>
</template>

<style scoped>
.parse-config-panel {
  background: var(--panel-bg, #1e1e1e);
  border: 1px solid var(--border, #333);
  border-radius: 6px;
  font-size: 12px;
  overflow: hidden;
}
.config-header {
  padding: 6px 12px;
  font-weight: 600;
  font-size: 11px;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: var(--text-muted, #888);
  border-bottom: 1px solid var(--border, #333);
}
.config-body {
  display: grid;
  grid-template-columns: 1fr auto;
  gap: 4px 8px;
  padding: 8px 12px;
  align-items: center;
}
.config-row {
  display: contents;
}
.config-label {
  color: var(--text, #ccc);
  font-family: var(--sans, sans-serif);
  white-space: nowrap;
  cursor: default;
}
.config-input {
  width: 72px;
  padding: 2px 6px;
  border: 1px solid var(--border, #444);
  border-radius: 3px;
  background: var(--input-bg, #2a2a2a);
  color: var(--text, #eee);
  font-size: 12px;
  font-family: var(--mono, monospace);
  text-align: right;
}
.config-input:focus {
  outline: 1px solid #7c3aed;
}
.config-footer {
  display: flex;
  gap: 6px;
  padding: 6px 12px 8px;
  border-top: 1px solid var(--border, #333);
}
.config-btn {
  padding: 3px 10px;
  border-radius: 4px;
  font-size: 12px;
  cursor: pointer;
  border: 1px solid transparent;
}
.config-btn--apply {
  background: #7c3aed;
  color: #fff;
  border-color: #7c3aed;
}
.config-btn--apply:hover { background: #6d28d9; }
.config-btn--reset {
  background: transparent;
  color: var(--text-muted, #888);
  border-color: var(--border, #444);
}
.config-btn--reset:hover { color: var(--text, #ccc); border-color: #777; }
</style>
