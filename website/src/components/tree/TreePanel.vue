<script setup>
import { computed, ref, watch } from 'vue'

const props = defineProps({
  tree: { type: Object, default: null },
})

const emit = defineEmits(['select'])

const showHelpers = ref(false)
const expandedIds = ref(new Set())

function createUiNode(node, id) {
  const children = (node.children ?? []).map((child, index) => createUiNode(child, `${id}.${index}`))

  // Propagate end position upward from children (fixes parser not propagating
  // ranges through suite/indented_text/helper nodes).
  let endByte = node.end_byte
  let endRow = node.end_row
  let endCol = node.end_col
  for (const child of children) {
    if (child.endByte > endByte) {
      endByte = child.endByte
      endRow = child.endRow
      endCol = child.endCol
    }
  }

  // Propagate start position downward: if the node has no real start (byte=0,row=0,col=0
  // but children with real positions exist), take the minimum valid child start.
  let startByte = node.start_byte
  let startRow = node.start_row
  let startCol = node.start_col
  const isZeroStart = startByte === 0 && startRow === 0 && startCol === 0
  if (isZeroStart && children.length > 0) {
    let minByte = Infinity
    let minRow = 0
    let minCol = 0
    for (const child of children) {
      // Only consider children that themselves have real (non-zero-width) content
      if (child.startByte < minByte && child.endByte > child.startByte) {
        minByte = child.startByte
        minRow = child.startRow
        minCol = child.startCol
      }
    }
    if (minByte !== Infinity) {
      startByte = minByte
      startRow = minRow
      startCol = minCol
    }
  }

  return {
    id,
    type: node.type,
    isNamed: node.is_named,
    isError: node.is_error,
    isMissing: node.is_missing,
    isExtra: node.extra,
    field: node.field ?? null,
    startByte,
    endByte,
    startRow,
    startCol,
    endRow,
    endCol,
    text: node.text ?? '',
    children,
  }
}

function isHelperNode(node) {
  return /^_/.test(node.type)
}

function shouldFlattenWrapper(node, children) {
  if (children.length !== 1) return false

  const onlyChild = children[0]
  if (onlyChild.type !== node.type) return false
  if (node.field || onlyChild.field) return false

  const zeroWidth = node.startByte === node.endByte && node.startRow === node.endRow && node.startCol === node.endCol
  const sameRange = node.startByte === onlyChild.startByte && node.endByte === onlyChild.endByte
  return zeroWidth || sameRange
}

/**
 * Flatten left-recursive repetition chains (e.g. module → module item).
 * When a node has exactly one same-type child among its children,
 * replace that child with its own children (promoting siblings up).
 * Repeat until the chain is fully collapsed into a flat list.
 */
function flattenLeftRecursion(node, children) {
  if (!node.isNamed || node.field) return children
  let changed = true
  let result = children
  while (changed) {
    changed = false
    const next = []
    for (const child of result) {
      if (child.type === node.type && child.isNamed && !child.field) {
        // Inline this same-type child's children
        next.push(...child.children)
        changed = true
      } else {
        next.push(child)
      }
    }
    result = next
  }
  return result
}

function materializeVisibleTree(node, helpersVisible) {
  let children = node.children.flatMap((child) => materializeVisibleTree(child, helpersVisible))

  if (!helpersVisible && isHelperNode(node)) {
    return children
  }

  if (!helpersVisible && shouldFlattenWrapper(node, children)) {
    return children
  }

  // Collapse left-recursive repetition (e.g. module → module _choice)
  // Always active — deeply nested same-type chains are never useful
  children = flattenLeftRecursion(node, children)

  return [{
    ...node,
    children,
    hasChildren: children.length > 0,
  }]
}

function collectExpandableIds(nodes, target = []) {
  for (const node of nodes) {
    if (node.hasChildren) {
      target.push(node.id)
      collectExpandableIds(node.children, target)
    }
  }
  return target
}

function collectHelperNodes(nodes) {
  let found = false

  function visit(node) {
    if (isHelperNode(node)) {
      found = true
      return
    }
    for (const child of node.children) {
      visit(child)
      if (found) return
    }
  }

  for (const node of nodes) {
    visit(node)
    if (found) break
  }

  return found
}

const rawRoots = computed(() => {
  if (!props.tree) return []

  try {
    return [createUiNode(props.tree.root, '0')]
  } catch {
    return []
  }
})

const roots = computed(() => {
  return rawRoots.value.flatMap((node) => materializeVisibleTree(node, showHelpers.value))
})

const hasHelperNodes = computed(() => collectHelperNodes(rawRoots.value))
const hasExpandableNodes = computed(() => roots.value.some((node) => node.hasChildren))

watch(roots, (nodes) => {
  expandedIds.value = new Set(nodes.filter((node) => node.hasChildren).map((node) => node.id))
}, { immediate: true })

function isExpanded(node) {
  return expandedIds.value.has(node.id)
}

function toggleNode(node) {
  if (!node?.hasChildren) return

  const next = new Set(expandedIds.value)
  if (next.has(node.id)) next.delete(node.id)
  else next.add(node.id)
  expandedIds.value = next
}

function expandAll() {
  expandedIds.value = new Set(collectExpandableIds(roots.value))
}

function collapseAll() {
  expandedIds.value = new Set()
}

function toggleHelpers() {
  showHelpers.value = !showHelpers.value
}

function selectNode(node) {
  emit('select', { startByte: node.startByte, endByte: node.endByte })
}
</script>

<template>
  <div class="tree-panel panel">
    <div class="panel-header">
      <span class="panel-title">🌲 语法树</span>
      <span v-if="!tree" class="panel-hint">暂无语法树</span>
      <div v-else class="tree-header-actions">
        <button
          v-if="hasHelperNodes"
          type="button"
          class="tree-link-btn"
          :class="{ 'tree-link-btn--active': showHelpers }"
          @click="toggleHelpers"
        >
          {{ showHelpers ? '隐藏辅助节点' : '显示辅助节点' }}
        </button>
        <button
          v-if="hasExpandableNodes"
          type="button"
          class="tree-link-btn"
          @click="expandAll"
        >
          展开全部
        </button>
        <button
          v-if="hasExpandableNodes"
          type="button"
          class="tree-link-btn"
          @click="collapseAll"
        >
          折叠全部
        </button>
      </div>
    </div>

    <div class="tree-body">
      <template v-if="roots.length">
        <TreeNodeItem
          v-for="node in roots"
          :key="node.id"
          :node="node"
          :depth="0"
          :expanded-ids="expandedIds"
          @toggle="toggleNode"
          @select="selectNode"
        />
      </template>
      <div v-else-if="tree" class="tree-empty">空语法树</div>
    </div>
  </div>
</template>

<script>
import { defineComponent, h } from 'vue'

const TreeNodeItem = defineComponent({
  name: 'TreeNodeItem',
  props: {
    node:  { type: Object, required: true },
    depth: { type: Number, default: 0    },
    expandedIds: { type: Object, required: true },
  },
  emits: ['toggle', 'select'],
  setup(props, { emit }) {
    function toggle() {
      if (!props.node.hasChildren) return
      emit('toggle', props.node)
    }

    function select() {
      emit('select', props.node)
    }

    return () => {
      const n = props.node
      const indent = props.depth * 16
      const expanded = props.expandedIds.has(n.id)

      const arrow = n.hasChildren
        ? h('span', {
            class: 'tree-arrow',
            onClick: toggle,
          }, expanded ? '▾' : '▸')
        : h('span', { class: 'tree-arrow tree-arrow--leaf' }, '·')

      const typeEl = h('span', {
        class: [
          'tree-type',
          n.isError   ? 'tree-type--error'   : '',
          n.isMissing ? 'tree-type--missing'  : '',
          n.isExtra   ? 'tree-type--extra'    : '',
          !n.isNamed  ? 'tree-type--anon'     : '',
        ].filter(Boolean),
        onClick: select,
      }, [
        n.field ? h('span', { class: 'tree-field' }, n.field + ': ') : null,
        n.type,
      ])

      const range = h('span', { class: 'tree-range' },
        ` [${n.startRow}:${n.startCol}–${n.endRow}:${n.endCol}]`)

      const preview = (!n.hasChildren && n.text && n.text.length < 40)
        ? h('span', { class: 'tree-text' }, ` "${n.text}"`)
        : null

      const row = h('div', {
        class: 'tree-node',
        style: { paddingLeft: indent + 'px' },
      }, [arrow, typeEl, range, preview])

      const children = (expanded && n.children && n.children.length)
        ? n.children.map(child =>
            h(TreeNodeItem, {
              key:   child.id,
              node:  child,
              depth: props.depth + 1,
              expandedIds: props.expandedIds,
              onToggle: (c) => emit('toggle', c),
              onSelect: (c) => emit('select', c),
            })
          )
        : []

      return h('div', [row, ...children])
    }
  },
})
export default { components: { TreeNodeItem } }
</script>

<style scoped>
.tree-panel {
  position: relative;
  display: flex;
  flex-direction: column;
  height: 100%;
  overflow: hidden;
}

.tree-panel::after {
  content: '';
  position: absolute;
  top: 0;
  right: 0;
  bottom: 0;
  width: 1px;
  background: var(--line-strong);
  pointer-events: none;
  z-index: 1;
}

.tree-body {
  flex: 1;
  overflow: auto;
  padding: 4px 0;
  font-family: var(--mono);
  font-size: 12.5px;
}

.tree-header-actions {
  display: flex;
  align-items: center;
  gap: 2px;
  margin-left: auto;
  margin-right: 8px;
}

.tree-link-btn {
  min-height: 28px;
  padding: 0 8px;
  border: 0;
  border-radius: 6px;
  background: transparent;
  color: var(--text-soft);
  font-family: var(--sans);
  font-size: 12px;
  font-weight: 500;
  cursor: pointer;
}

.tree-link-btn:hover {
  background: var(--surface-3);
  color: var(--text-h);
}

.tree-link-btn--active {
  background: var(--surface-3);
  color: var(--text-h);
}

.tree-node {
  display: flex;
  align-items: baseline;
  gap: 4px;
  padding: 1px 8px;
  line-height: 1.8;
  cursor: default;
  white-space: nowrap;
}
.tree-node:hover {
  background: var(--accent-bg);
}

.tree-arrow {
  display: inline-block;
  width: 14px;
  font-size: 10px;
  color: var(--text);
  cursor: pointer;
  transition: color 0.15s;
  flex-shrink: 0;
}
.tree-arrow--leaf {
  color: var(--border);
  cursor: default;
}

.tree-type {
  color: var(--accent);
  font-weight: 600;
  cursor: pointer;
}
.tree-type:hover { text-decoration: underline; }

.tree-type--error   { color: #f44747; }
.tree-type--missing { color: #f44747; opacity: 0.7; }
.tree-type--extra   { color: var(--text); opacity: 0.5; font-style: italic; }
.tree-type--anon    { color: var(--text); font-weight: 400; }

.tree-field {
  color: #9cdcfe;
  font-weight: 500;
}

.tree-range {
  color: var(--text);
  opacity: 0.45;
  font-size: 11px;
}

.tree-text {
  color: #ce9178;
  opacity: 0.85;
}

.panel-hint {
  font-size: 12px;
  color: var(--text);
  opacity: 0.5;
}
.tree-empty {
  padding: 16px;
  color: var(--text);
  opacity: 0.4;
  font-style: italic;
}
</style>
