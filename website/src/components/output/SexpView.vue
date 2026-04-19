<script setup>
import { computed, defineComponent, h, ref, watch } from 'vue'

const props = defineProps({
  value: { type: String, default: '' },
})

const viewMode = ref('pretty')
const collapsedIds = ref(new Set())

watch(() => props.value, () => {
  collapsedIds.value = new Set()
})

function tokenizeSexp(raw) {
  const tokens = []
  let index = 0

  while (index < raw.length) {
    const ch = raw[index]

    if (/\s/.test(ch)) {
      index += 1
      continue
    }

    if (ch === '(' || ch === ')') {
      tokens.push({ kind: ch, value: ch })
      index += 1
      continue
    }

    if (ch === '"') {
      const start = index
      index += 1
      let escaped = false

      while (index < raw.length) {
        const cur = raw[index]
        index += 1
        if (escaped) {
          escaped = false
          continue
        }
        if (cur === '\\') {
          escaped = true
          continue
        }
        if (cur === '"') break
      }

      tokens.push({ kind: 'string', value: raw.slice(start, index) })
      continue
    }

    if (ch === '[') {
      const start = index
      index += 1
      while (index < raw.length && raw[index] !== ']') index += 1
      if (index < raw.length) index += 1
      tokens.push({ kind: 'marker', value: raw.slice(start, index) })
      continue
    }

    const start = index
    while (index < raw.length && !/\s/.test(raw[index]) && raw[index] !== '(' && raw[index] !== ')') {
      index += 1
    }
    tokens.push({ kind: 'atom', value: raw.slice(start, index) })
  }

  return tokens
}

function parseSexp(raw) {
  const tokens = tokenizeSexp(raw)
  let index = 0

  function parseExpr() {
    const token = tokens[index]
    if (!token) return null

    if (token.kind === '(') {
      index += 1
      const items = []
      while (index < tokens.length && tokens[index].kind !== ')') {
        const expr = parseExpr()
        if (expr) items.push(expr)
      }
      if (index < tokens.length && tokens[index].kind === ')') index += 1
      return { kind: 'list', items }
    }

    if (token.kind === ')') {
      index += 1
      return { kind: 'atom', value: ')' }
    }

    index += 1
    return token
  }

  const exprs = []
  while (index < tokens.length) {
    const expr = parseExpr()
    if (expr) exprs.push(expr)
  }
  return exprs
}

function withIds(expr, id) {
  if (expr.kind !== 'list') return { ...expr, id }
  return {
    ...expr,
    id,
    items: expr.items.map((item, index) => withIds(item, `${id}.${index}`)),
  }
}

function isAtomic(expr) {
  return expr.kind !== 'list'
}

function exprText(expr) {
  if (expr.kind === 'list') {
    return `(${expr.items.map(exprText).join(' ')})`
  }
  return expr.value
}

function tokenClass(token, isHead) {
  if (token.kind === 'string') return 'sx-str'
  if (token.kind === 'marker') {
    if (token.value.startsWith('[MISSING')) return 'sx-miss'
    if (token.value.includes('ERROR')) return 'sx-err'
    return 'sx-mark'
  }
  if (isHead) return 'sx-node'
  if (token.kind === 'atom' && token.value.endsWith(':')) return 'sx-field'
  return 'sx-atom'
}

function shouldInlineList(expr) {
  if (expr.items.length <= 1) return true

  const tail = expr.items.slice(1)
  if (!tail.every(isAtomic)) return false

  return exprText(expr).length <= 56
}

function renderToken(token, isHead = false) {
  return h('span', { class: tokenClass(token, isHead) }, token.value)
}

function renderInlineExpr(expr, isHead = false) {
  if (expr.kind !== 'list') {
    return renderToken(expr, isHead)
  }

  const children = [h('span', { class: 'sx-paren' }, '(')]
  expr.items.forEach((item, index) => {
    if (index > 0) children.push(' ')
    children.push(renderInlineExpr(item, index === 0))
  })
  children.push(h('span', { class: 'sx-paren' }, ')'))
  return h('span', { class: 'sx-inline' }, children)
}

function renderCollapsedSummary(expr) {
  if (expr.items.length === 0) {
    return h('span', { class: 'sx-inline' }, [
      h('span', { class: 'sx-paren' }, '('),
      h('span', { class: 'sx-paren' }, ')'),
    ])
  }

  const children = [
    h('span', { class: 'sx-paren' }, '('),
    renderInlineExpr(expr.items[0], true),
  ]

  if (expr.items.length > 1) {
    children.push(' ')
    children.push(h('span', { class: 'sx-ellipsis' }, `… ${expr.items.length - 1}`))
  }

  children.push(h('span', { class: 'sx-paren' }, ')'))
  return h('span', { class: 'sx-inline' }, children)
}

const parsedExprs = computed(() => {
  try {
    return parseSexp(props.value ?? '').map((expr, index) => withIds(expr, String(index)))
  } catch {
    return []
  }
})

const rootCount = computed(() => parsedExprs.value.length)

const collapsibleIds = computed(() => {
  const ids = []

  function visit(expr) {
    if (expr.kind !== 'list') return
    if (expr.items.length > 0) ids.push(expr.id)
    expr.items.forEach(visit)
  }

  parsedExprs.value.forEach(visit)
  return ids
})

const collapsedCount = computed(() => collapsedIds.value.size)

function toggleNode(id) {
  const next = new Set(collapsedIds.value)
  if (next.has(id)) next.delete(id)
  else next.add(id)
  collapsedIds.value = next
}

function expandAll() {
  collapsedIds.value = new Set()
}

function collapseAll() {
  collapsedIds.value = new Set(collapsibleIds.value)
}

function onFoldKeydown(event, emitToggle, id) {
  if (event.key === 'Enter' || event.key === ' ') {
    event.preventDefault()
    emitToggle(id)
  }
}

let SexpNode

function renderNodeBlock(node, depth, isHead, emitToggle) {
  const padding = `${depth * 18}px`
  const guideLeft = `${Math.max(depth * 18 - 9, 0)}px`
  const rowClass = ['sx-row']
  if (depth > 0) rowClass.push('sx-row--nested')

  if (node.kind !== 'list') {
    return h('div', {
      class: rowClass,
      style: { paddingLeft: padding, '--sx-guide-left': guideLeft },
    }, [
      h('span', { class: 'sx-fold sx-fold--stub' }),
      renderToken(node, isHead),
    ])
  }

  const isCollapsed = collapsedIds.value.has(node.id)
  const canInline = shouldInlineList(node)
  const foldButton = h('span', {
    class: ['sx-fold', isCollapsed ? 'is-collapsed' : ''],
    role: 'button',
    tabindex: 0,
    title: isCollapsed ? '展开子树' : '折叠子树',
    'aria-label': isCollapsed ? '展开子树' : '折叠子树',
    'aria-expanded': isCollapsed ? 'false' : 'true',
    onClick: () => emitToggle(node.id),
    onKeydown: (event) => onFoldKeydown(event, emitToggle, node.id),
  }, isCollapsed ? '▸' : '▾')

  if (isCollapsed) {
    return h('div', { class: 'sx-block' }, [
      h('div', {
        class: [...rowClass, 'sx-row--collapsed'],
        style: { paddingLeft: padding, '--sx-guide-left': guideLeft },
      }, [foldButton, renderCollapsedSummary(node)]),
    ])
  }

  if (canInline) {
    return h('div', { class: 'sx-block' }, [
      h('div', {
        class: rowClass,
        style: { paddingLeft: padding, '--sx-guide-left': guideLeft },
      }, [foldButton, renderInlineExpr(node, isHead)]),
    ])
  }

  const rows = []
  const head = node.items[0]

  rows.push(h('div', {
    class: rowClass,
    style: { paddingLeft: padding, '--sx-guide-left': guideLeft },
  }, [
    foldButton,
    h('span', { class: 'sx-paren' }, '('),
    head ? renderInlineExpr(head, true) : null,
  ]))

  for (const item of node.items.slice(1)) {
    rows.push(h(SexpNode, {
      key: item.id,
      node: item,
      depth: depth + 1,
      isHead: false,
      onToggle: emitToggle,
    }))
  }

  rows.push(h('div', {
    class: [...rowClass, 'sx-row--close'],
    style: { paddingLeft: padding, '--sx-guide-left': guideLeft },
  }, [
    h('span', { class: 'sx-fold sx-fold--stub' }),
    h('span', { class: 'sx-paren' }, ')'),
  ]))

  return h('div', { class: 'sx-block' }, rows)
}

SexpNode = defineComponent({
  name: 'SexpNode',
  props: {
    node: { type: Object, required: true },
    depth: { type: Number, default: 0 },
    isHead: { type: Boolean, default: false },
  },
  emits: ['toggle'],
  setup(componentProps, { emit }) {
    return () => renderNodeBlock(
      componentProps.node,
      componentProps.depth,
      componentProps.isHead,
      (id) => emit('toggle', id),
    )
  },
})
</script>

<template>
  <div class="sexp-viewer">
    <div class="sexp-toolbar">
      <div class="sexp-toolbar-copy">
        <div class="sexp-kicker">S-Expression</div>
        <div class="sexp-meta">
          <span>{{ rootCount }} 个根节点</span>
          <span>{{ collapsibleIds.length }} 个可折叠块</span>
          <span v-if="viewMode === 'pretty' && collapsedCount">{{ collapsedCount }} 个已折叠</span>
        </div>
      </div>

      <div class="sexp-toolbar-actions">
        <div class="sexp-mode-switch" role="tablist" aria-label="S-expression 视图模式">
          <button
            type="button"
            class="sexp-mode-btn"
            :class="{ 'is-active': viewMode === 'pretty' }"
            @click="viewMode = 'pretty'"
          >
            格式化
          </button>
          <button
            type="button"
            class="sexp-mode-btn"
            :class="{ 'is-active': viewMode === 'raw' }"
            @click="viewMode = 'raw'"
          >
            原始
          </button>
        </div>

        <div v-if="viewMode === 'pretty'" class="sexp-toolbar-group sexp-toolbar-group--links">
          <button
            type="button"
            class="sexp-link-btn"
            :disabled="!collapsibleIds.length || !collapsedCount"
            @click="expandAll"
          >
            展开全部
          </button>
          <button
            type="button"
            class="sexp-link-btn"
            :disabled="!collapsibleIds.length"
            @click="collapseAll"
          >
            折叠全部
          </button>
        </div>
      </div>
    </div>

    <pre v-if="viewMode === 'raw'" class="sexp-raw">{{ value }}</pre>

    <div v-else class="sexp-tree">
      <SexpNode
        v-for="expr in parsedExprs"
        :key="expr.id"
        :node="expr"
        :depth="0"
        @toggle="toggleNode"
      />
    </div>
  </div>
</template>

<style scoped>
.sexp-viewer {
  position: relative;
  display: flex;
  flex-direction: column;
  min-height: 0;
  height: 100%;
  border: 1px solid var(--line);
  border-radius: 10px;
  background: linear-gradient(180deg, var(--surface-2) 0%, var(--surface-4) 100%);
  box-shadow: var(--shadow-sm);
  overflow: hidden;
  font-size: 12px;
  line-height: 1.72;
  color: var(--text-h);
  font-family: var(--mono, ui-monospace, Consolas, monospace);
}

.sexp-viewer::after {
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

.sexp-toolbar {
  position: sticky;
  top: 0;
  z-index: 1;
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 14px;
  flex-wrap: wrap;
  padding: 10px 12px;
  border-bottom: 1px solid var(--line);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.66), rgba(255, 255, 255, 0)),
    var(--surface);
  backdrop-filter: blur(10px);
}

.sexp-toolbar-group {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}

.sexp-toolbar-copy {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.sexp-kicker {
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  color: var(--text-soft);
}

.sexp-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 0;
  font-size: 11px;
  color: var(--text-muted);
}

.sexp-meta span:not(:last-child)::after {
  content: '·';
  margin: 0 8px;
  color: var(--text-soft);
}

.sexp-toolbar-actions {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-left: auto;
  flex-wrap: wrap;
}

.sexp-mode-switch {
  display: inline-flex;
  align-items: center;
  gap: 2px;
  padding: 2px;
  border: 1px solid var(--line);
  border-radius: 8px;
  background: var(--surface-2);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.32);
}

.sexp-mode-btn {
  min-height: 28px;
  padding: 0 10px;
  border: 0;
  border-radius: 6px;
  background: transparent;
  color: var(--text-muted);
  font-family: var(--sans);
  font-size: 12px;
  font-weight: 500;
  cursor: pointer;
}

.sexp-mode-btn.is-active {
  background: var(--surface);
  color: var(--text-h);
  box-shadow:
    inset 0 0 0 1px var(--line),
    0 1px 1px rgba(15, 23, 42, 0.06);
}

.sexp-toolbar-group--links {
  gap: 2px;
}

.sexp-link-btn {
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

.sexp-link-btn:hover:not(:disabled) {
  background: var(--surface-3);
  color: var(--text-h);
}

.sexp-link-btn:disabled,
.sexp-mode-btn:disabled {
  opacity: 0.42;
  cursor: default;
}

.sexp-tree,
.sexp-raw {
  margin: 0;
  padding: 10px 12px 12px;
}

.sexp-raw {
  white-space: pre-wrap;
  overflow-wrap: anywhere;
  word-break: normal;
}

.sexp-tree {
  display: flex;
  flex-direction: column;
  gap: 1px;
}

.sx-block + .sx-block {
  margin-top: 4px;
}

.sx-row {
  position: relative;
  display: flex;
  align-items: flex-start;
  gap: 6px;
  padding-right: 8px;
  min-height: 1.5em;
  flex-wrap: wrap;
  border-radius: 6px;
}

.sx-row:hover {
  background: linear-gradient(90deg, var(--accent-bg) 0%, transparent 82%);
}

.sx-row--collapsed {
  opacity: 0.94;
}

.sx-row--nested::before {
  content: '';
  position: absolute;
  left: var(--sx-guide-left);
  top: -3px;
  bottom: -3px;
  width: 1px;
  background: linear-gradient(180deg, transparent, var(--line) 12%, var(--line) 88%, transparent);
}

.sx-row--nested::after {
  content: '';
  position: absolute;
  left: var(--sx-guide-left);
  top: calc(0.92em + 1px);
  width: 10px;
  height: 1px;
  background: var(--line);
}

.sx-row--close:hover {
  background: transparent;
}

.sx-fold {
  display: inline-block;
  width: 14px;
  min-width: 14px;
  height: 14px;
  padding: 0;
  margin: 0;
  border: 0;
  border-radius: 0;
  background: transparent;
  box-shadow: none;
  color: var(--text);
  cursor: pointer;
  font: inherit;
  font-size: 10px;
  line-height: 1;
  text-align: center;
  user-select: none;
  transform: translateY(1px);
  transition: color 180ms ease;
}

.sx-fold:hover {
  color: var(--text-h);
}

.sx-fold:focus,
.sx-fold:focus-visible,
.sx-fold:active {
  outline: none;
  border: 0;
  background: transparent;
  box-shadow: none;
}

.sx-fold.is-collapsed {
  color: var(--text-soft);
}

.sx-fold--stub {
  visibility: hidden;
  pointer-events: none;
}

.sx-inline {
  display: inline;
}

.sx-ellipsis {
  color: var(--text-soft);
  font-style: italic;
  background: var(--surface-3);
  border: 1px solid var(--line);
  border-radius: 4px;
  padding: 0 5px;
}

.sx-paren {
  color: var(--text);
  opacity: 0.32;
}

.sx-node {
  color: var(--accent);
  font-weight: 650;
}

.sx-field {
  color: #d7ba7d;
}

.sx-atom {
  color: var(--text-h);
}

.sx-str {
  color: #ce9178;
}

.sx-mark {
  color: var(--accent);
}

.sx-err {
  color: #f44747;
  font-weight: 700;
}

.sx-miss {
  color: #f44747;
  opacity: 0.78;
}

@media (max-width: 680px) {
  .sexp-toolbar {
    align-items: stretch;
  }

  .sexp-toolbar-actions {
    margin-left: 0;
    width: 100%;
    justify-content: space-between;
  }
}
</style>
