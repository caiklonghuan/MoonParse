import { computed, onUnmounted, ref, watch } from 'vue'

import {
  createLintController,
  lintRuleInventory,
  normalizeLintOptions,
} from '../lib/lintWorkbench.js'

export function useLintWorkbench(language, tree, source, active) {
  const diagnostics = ref([])
  const options = ref(normalizeLintOptions())
  const running = ref(false)
  const stale = ref(true)
  const error = ref(null)
  const sourceSnapshot = ref(null)
  let treeSource = null

  const ruleSets = computed(() => lintRuleInventory(language.value))
  const controller = createLintController({
    onState(next) {
      if ('diagnostics' in next) diagnostics.value = next.diagnostics
      if ('running' in next) running.value = next.running
      if ('stale' in next) stale.value = next.stale
      if ('error' in next) error.value = next.error
      if ('sourceSnapshot' in next) sourceSnapshot.value = next.sourceSnapshot
    },
  })

  function schedule(immediate = false) {
    if (treeSource !== source.value) {
      stale.value = true
      running.value = false
      return false
    }
    controller.update({
      active: active.value,
      language: language.value,
      tree: tree.value,
      source: source.value,
      options: options.value,
      immediate,
    })
    return true
  }

  function run() {
    error.value = null
    if (!schedule(true)) error.value = 'Source parsing is still pending; lint will run when the new tree is ready.'
  }

  function setOptions(next) {
    options.value = normalizeLintOptions(next)
  }

  function rejectFix(message) {
    error.value = message
    stale.value = true
  }

  watch(source, () => {
    controller.cancel()
    stale.value = true
    running.value = false
  })

  watch(tree, () => {
    treeSource = source.value
    stale.value = true
    schedule()
  }, { immediate: true })

  watch(language, () => {
    treeSource = null
    controller.cancel()
    diagnostics.value = []
    sourceSnapshot.value = null
    stale.value = true
  })

  watch(active, (enabled) => {
    if (enabled) schedule()
    else controller.cancel()
  })

  watch(options, () => {
    stale.value = true
    schedule()
  }, { deep: true })

  onUnmounted(() => controller.dispose())

  return {
    lintDiagnostics: diagnostics,
    lintOptions: options,
    lintRunning: running,
    lintStale: stale,
    lintError: error,
    lintSourceSnapshot: sourceSnapshot,
    lintRuleSets: ruleSets,
    runLint: run,
    setLintOptions: setOptions,
    rejectLintFix: rejectFix,
  }
}
