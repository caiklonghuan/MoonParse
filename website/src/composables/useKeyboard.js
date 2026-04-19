import { onMounted, onUnmounted } from 'vue'

export function useKeyboard({ onRunQuery, onForceParse, onFocusPanel } = {}) {
  function handler(e) {
    if (e.ctrlKey && !e.shiftKey && !e.altKey && e.key === 'Enter') {
      onRunQuery?.()
      return
    }

    if (e.ctrlKey && !e.shiftKey && !e.altKey && e.key === 's') {
      e.preventDefault()
      onForceParse?.()
      return
    }

    if (e.altKey && ['1', '2', '3', '4'].includes(e.key)) {
      e.preventDefault()
      onFocusPanel?.(Number(e.key) - 1)
    }
  }

  onMounted(()   => document.addEventListener('keydown', handler))
  onUnmounted(() => document.removeEventListener('keydown', handler))
}
