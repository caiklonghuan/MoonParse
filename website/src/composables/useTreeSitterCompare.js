import { onUnmounted, ref, watch } from 'vue'
import {
  createTreeSitterComparisonController,
  idleTreeSitterResult,
} from '@/lib/treeSitterCompare.js'

export function useTreeSitterCompare(source, languageId, active) {
  const result = ref(idleTreeSitterResult(languageId.value))
  const controller = createTreeSitterComparisonController({
    onResult(value) {
      result.value = value
    },
  })

  watch([source, languageId, active], ([nextSource, nextLanguageId, nextActive]) => {
    controller.update({
      source: nextSource,
      languageId: nextLanguageId,
      active: nextActive,
    })
  }, { immediate: true })

  onUnmounted(() => controller.dispose())
  return { treeSitterResult: result }
}
