import { shallowRef, ref, watch, onUnmounted } from 'vue'

export function useParseTree(parser, sourceCode, traceEnabled = null) {
  const tree = shallowRef(null)
  const parseTime = ref(0)
  const isIncremental = ref(false)
  const incrementalTrace = shallowRef(null)

  let pendingEdit = null
  let debounceTimer = null

  function shouldTrace() {
    return Boolean(traceEnabled?.value ?? traceEnabled)
  }

  function freeTree(t) {
    if (t) { try { t.free() } catch (_) {} }
  }

  function clearTree() {
    const old = tree.value
    if (old) { freeTree(old); tree.value = null }
    parseTime.value = 0
    isIncremental.value = false
    incrementalTrace.value = null
  }

  function doParse(p, source, edit) {
    if (!source || !source.trim()) { clearTree(); return }
    const t0 = performance.now()
    let newTree = null
    let incremental = false

    try {
      if (edit && tree.value) {
        if (shouldTrace() && typeof p.parseIncrementalTrace === 'function') {
          const result = p.parseIncrementalTrace(source, tree.value, edit)
          newTree = result.tree
          incrementalTrace.value = result.trace
          parseTime.value = result.trace?.incrementalElapsedMs ?? 0
        } else {
          newTree = p.parseIncremental(source, tree.value, edit)
          incrementalTrace.value = null
        }
        incremental = true
      } else {
        newTree = p.parse(source)
        incrementalTrace.value = null
      }
    } catch (_) {
      try {
        freeTree(newTree)
        newTree = p.parse(source)
        incremental = false
        incrementalTrace.value = null
      } catch (e2) {
        console.error('[useParseTree] parse failed:', e2)
        return
      }
    }

    const old = tree.value
    tree.value = newTree
    if (!incrementalTrace.value) {
      parseTime.value = Math.round((performance.now() - t0) * 100) / 100
    }
    isIncremental.value = incremental

    if (old && old !== newTree) freeTree(old)
  }

  function schedule() {
    clearTimeout(debounceTimer)
    debounceTimer = setTimeout(() => {
      const p = parser.value
      const source = sourceCode.value
      if (!p || source == null) return
      const edit = pendingEdit
      pendingEdit = null
      doParse(p, source, edit)
    }, 150)
  }

  function triggerEdit(inputEdit) {
    pendingEdit = inputEdit
    schedule()
  }

  watch(parser, (p) => {
    if (!p) { clearTree(); return }
    pendingEdit = null
    clearTimeout(debounceTimer)
    doParse(p, sourceCode.value, null)
  }, { immediate: true })

  watch(sourceCode, () => {
    if (!parser.value) return
    schedule()
  })

  watch(() => shouldTrace(), (enabled) => {
    if (!enabled) incrementalTrace.value = null
  })

  onUnmounted(() => {
    clearTimeout(debounceTimer)
    freeTree(tree.value)
    tree.value = null
  })

  return { tree, parseTime, isIncremental, incrementalTrace, triggerEdit }
}
