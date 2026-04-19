import { shallowRef, ref, watch } from 'vue'
import { useMoonParse } from './useMoonParse.js'
import { EXAMPLE_PRESETS } from '@/data/languagePresets.js'

// Build a grammar-string → preset-id lookup at module load time
const grammarToPresetId = new Map(
  EXAMPLE_PRESETS.map(p => [p.grammar, p.id])
)

// Start fetching precompiled tables immediately (lazy chunk, loads in parallel)
const tablesReady = import('@/data/precompiledTables.js')
  .then(m => m.PRECOMPILED_TABLES)
  .catch(() => ({}))

export function useParser(grammarDsl) {
  const { mp } = useMoonParse()

  const parser = shallowRef(null)
  const parserError = ref(null)
  const building = ref(false)

  let buildId = 0

  async function rebuild(dsl) {
    const id = ++buildId
    if (parser.value) {
      try { parser.value.free() } catch (_) {}
      parser.value = null
    }
    parserError.value = null

    if (!mp.value || !dsl || !dsl.trim()) { building.value = false; return }

    building.value = true

    try {
      // Try precompiled table first (instant, no tablegen)
      const presetId = grammarToPresetId.get(dsl)
      if (presetId) {
        const tables = await tablesReady
        if (id !== buildId) return
        const tableJson = tables[presetId]
        if (tableJson) {
          parser.value = mp.value.createParserFromJson(tableJson, presetId)
          return
        }
      }

      // Custom grammar: yield to event loop then compile from DSL
      await new Promise(r => setTimeout(r, 0))
      if (id !== buildId) return
      parser.value = mp.value.createParser(dsl)
    } catch (e) {
      parserError.value = e?.message ?? String(e)
    } finally {
      if (id === buildId) building.value = false
    }
  }

  watch([mp, grammarDsl], ([mpVal, dsl]) => {
    if (mpVal) rebuild(dsl)
  }, { immediate: true })

  return { parser, parserError, building }
}
