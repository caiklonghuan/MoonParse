<script setup>
import { computed, ref } from 'vue'
import { MANIFEST_PATH } from '@/lib/languagePackProject.js'

const props = defineProps({
  files: { type: Object, default: () => ({}) },
  selectedPath: { type: String, default: null },
  readonly: { type: Boolean, default: false },
})

const emit = defineEmits(['select', 'create', 'rename', 'delete'])

const collapsed = ref(new Set())

const rows = computed(() => {
  const result = []
  const seenDirs = new Set()
  const paths = Object.keys(props.files).sort()
  for (const path of paths) {
    const parts = path.split('/')
    let prefix = ''
    let hidden = false
    for (let index = 0; index < parts.length - 1; index += 1) {
      prefix = prefix ? `${prefix}/${parts[index]}` : parts[index]
      if (!seenDirs.has(prefix)) {
        seenDirs.add(prefix)
        result.push({
          type: 'dir',
          path: prefix,
          name: parts[index],
          level: index,
          collapsed: collapsed.value.has(prefix),
        })
      }
      if (collapsed.value.has(prefix)) {
        hidden = true
      }
    }
    if (!hidden) {
      result.push({
        type: 'file',
        path,
        name: parts.at(-1),
        level: parts.length - 1,
        protected: path === MANIFEST_PATH,
      })
    }
  }
  return result
})

function toggleDir(path) {
  const next = new Set(collapsed.value)
  if (next.has(path)) next.delete(path)
  else next.add(path)
  collapsed.value = next
}

function promptPath(message, initial = '') {
  const value = window.prompt(message, initial)
  return value == null ? null : value.trim()
}

function createFile() {
  const path = promptPath('New Pack file path', 'queries/highlights.scm')
  if (path) emit('create', path)
}

function renameFile(path) {
  const next = promptPath('Rename Pack file', path)
  if (next && next !== path) emit('rename', { oldPath: path, newPath: next })
}

function deleteFile(path) {
  if (window.confirm(`Delete ${path}?`)) emit('delete', path)
}
</script>

<template>
  <aside class="pack-file-tree panel">
    <div class="panel-header pack-file-tree-header">
      <span class="panel-title">Pack Files</span>
      <button
        v-if="!readonly"
        type="button"
        class="tree-action"
        @click="createFile"
      >
        New
      </button>
    </div>

    <div class="pack-file-tree-body">
      <div
        v-for="row in rows"
        :key="`${row.type}:${row.path}`"
        role="button"
        tabindex="0"
        class="tree-row"
        :class="{
          'tree-row-dir': row.type === 'dir',
          'tree-row-file': row.type === 'file',
          'tree-row-active': row.path === selectedPath,
        }"
        :style="{ paddingLeft: `${8 + row.level * 14}px` }"
        @click="row.type === 'dir' ? toggleDir(row.path) : emit('select', row.path)"
        @keydown.enter.prevent="row.type === 'dir' ? toggleDir(row.path) : emit('select', row.path)"
        @keydown.space.prevent="row.type === 'dir' ? toggleDir(row.path) : emit('select', row.path)"
      >
        <span v-if="row.type === 'dir'" class="tree-icon">{{ row.collapsed ? '▸' : '▾' }}</span>
        <span v-else class="tree-icon">·</span>
        <span class="tree-name">{{ row.name }}</span>
        <span v-if="row.type === 'file' && !readonly" class="tree-row-actions" @click.stop>
          <button
            type="button"
            class="tree-inline-action"
            :disabled="row.protected"
            title="Rename"
            @click="renameFile(row.path)"
          >Rename</button>
          <button
            type="button"
            class="tree-inline-action"
            :disabled="row.protected"
            title="Delete"
            @click="deleteFile(row.path)"
          >Delete</button>
        </span>
      </div>

      <div v-if="rows.length === 0" class="tree-empty">
        No source files.
      </div>
    </div>
  </aside>
</template>

<style scoped>
.pack-file-tree {
  display: flex;
  flex-direction: column;
  min-width: 0;
  height: 100%;
  overflow: hidden;
}

.pack-file-tree-header {
  gap: 8px;
}

.tree-action {
  margin-left: auto;
  border: 1px solid var(--line);
  border-radius: var(--radius-sm);
  background: var(--surface-2);
  color: var(--text-muted);
  font: inherit;
  font-size: 11px;
  padding: 3px 8px;
  cursor: pointer;
}

.tree-action:hover {
  color: var(--text-h);
  border-color: var(--line-strong);
}

.pack-file-tree-body {
  flex: 1;
  overflow: auto;
  padding: 6px 0;
}

.tree-row {
  width: 100%;
  min-height: 28px;
  display: flex;
  align-items: center;
  gap: 6px;
  border: none;
  background: transparent;
  color: var(--text-muted);
  font: inherit;
  font-size: 12px;
  text-align: left;
  cursor: pointer;
}

.tree-row:hover {
  background: var(--surface-2);
  color: var(--text-h);
}

.tree-row-active {
  color: var(--accent);
  background: var(--accent-bg);
}

.tree-row-dir {
  font-weight: 600;
}

.tree-icon {
  flex: 0 0 12px;
  color: var(--text-soft);
}

.tree-name {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.tree-row-actions {
  margin-left: auto;
  display: none;
  align-items: center;
  gap: 4px;
  padding-right: 6px;
}

.tree-row-file:hover .tree-row-actions,
.tree-row-active .tree-row-actions {
  display: inline-flex;
}

.tree-inline-action {
  border: 1px solid var(--line);
  border-radius: 4px;
  background: var(--surface);
  color: var(--text-soft);
  font: inherit;
  font-size: 10px;
  padding: 1px 5px;
  cursor: pointer;
}

.tree-inline-action:disabled {
  cursor: not-allowed;
  opacity: 0.4;
}

.tree-empty {
  padding: 16px;
  color: var(--text-soft);
  font-size: 12px;
}
</style>
