import { shallowRef, ref, watch, onUnmounted } from 'vue'

export function useParseTree(parser, sourceCode) {
  const tree = shallowRef(null)
  const parseTime = ref(0)
  const isIncremental = ref(false)

  let pendingEdit = null
  let debounceTimer = null

  function freeTree(t) {
    if (t) { try { t.free() } catch (_) {} }
  }

  function clearTree() {
    const old = tree.value
    if (old) { freeTree(old); tree.value = null }
    parseTime.value = 0
    isIncremental.value = false
  }

  function doParse(p, source, edit) {
    if (!source || !source.trim()) { clearTree(); return }
    const t0 = performance.now()
    let newTree = null
    let incremental = false

    try {
      if (edit && tree.value) {
        newTree = p.parseIncremental(source, tree.value, edit)
        incremental = true
      } else {
        newTree = p.parse(source)
      }
    } catch (_) {
      try {
        freeTree(newTree)
        newTree = p.parse(source)
        incremental = false
      } catch (e2) {
        console.error('[useParseTree] parse failed:', e2)
        return
      }
    }

    const old = tree.value
    tree.value = newTree
    parseTime.value = Math.round((performance.now() - t0) * 100) / 100
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

  onUnmounted(() => {
    clearTimeout(debounceTimer)
    freeTree(tree.value)
    tree.value = null
  })

  return { tree, parseTime, isIncremental, triggerEdit }
}
