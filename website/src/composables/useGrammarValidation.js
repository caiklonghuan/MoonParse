import { ref, watch, onUnmounted } from 'vue'
import { useMoonParse } from './useMoonParse.js'

/**
 * Real-time grammar DSL validation using grammar_validate_dsl (no tablegen).
 * Returns an array of { rule, message } error objects, or [] if valid.
 * Debounced at 300 ms to avoid spamming WASM on every keystroke.
 */
export function useGrammarValidation(grammarDsl) {
  const { mp } = useMoonParse()
  const dslErrors = ref([])
  let timer = null

  function validate(dsl) {
    if (!mp.value || !dsl?.trim()) {
      dslErrors.value = []
      return
    }
    try {
      dslErrors.value = mp.value.validateGrammarDsl(dsl)
    } catch (_) {
      dslErrors.value = []
    }
  }

  watch(
    [mp, grammarDsl],
    ([mpVal, dsl]) => {
      clearTimeout(timer)
      if (!mpVal) return
      timer = setTimeout(() => validate(dsl), 300)
    },
    { immediate: true },
  )

  onUnmounted(() => clearTimeout(timer))

  return { dslErrors }
}
