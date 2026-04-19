import { shallowRef, watch, onUnmounted } from 'vue'
import { computeLexicalHighlightRanges, mergeHighlightRanges } from '@/lib/lexicalHighlights.js'

export function useHighlight(mp, tree, hlQueryStr, presetId, sourceCode) {
  const highlightRanges = shallowRef([])

  let currentQuery = null
  let currentQueryStr = null

  function freeQuery() {
    if (currentQuery) {
      try { currentQuery.free() } catch (_) {}
      currentQuery = null
      currentQueryStr = null
    }
  }

  function computeHighlights(mpVal, treeVal, queryStr, currentPresetId, source) {
    const lexicalRanges = computeLexicalHighlightRanges(currentPresetId, source)
    highlightRanges.value = lexicalRanges

    if (!mpVal || !treeVal || !queryStr?.trim()) return

    if (queryStr !== currentQueryStr) {
      freeQuery()
      try {
        currentQuery = mpVal.compileQuery(queryStr)
        currentQueryStr = queryStr
      } catch (e) {
        console.warn('[useHighlight] query compile error:', e.message)
        return
      }
    }

    try {
      const treeRanges = treeVal.highlight(currentQuery) ?? []
      highlightRanges.value = mergeHighlightRanges(treeRanges, lexicalRanges)
    } catch (e) {
      console.warn('[useHighlight] highlight exec error:', e.message)
      highlightRanges.value = lexicalRanges
    }
  }

  watch(
    [mp, tree, hlQueryStr, presetId, sourceCode],
    ([mpVal, treeVal, queryStr, currentPresetId, source]) => computeHighlights(mpVal, treeVal, queryStr, currentPresetId, source),
    { immediate: true },
  )

  onUnmounted(() => freeQuery())

  return { highlightRanges }
}
