import { shallowRef, ref } from 'vue'

const mp = shallowRef(null)
const loading = ref(true)
const error = ref(null)

let _promise = null

function loadOnce() {
  if (_promise) return _promise
  _promise = (async () => {
    try {
      const { loadMoonParse } = await import('@/lib/moonparse.js')
      mp.value = await loadMoonParse('/moonparse.wasm')
    } catch (e) {
      error.value = e?.message ?? String(e)
      _promise = null
    } finally {
      loading.value = false
    }
  })()
  return _promise
}

export function useMoonParse() {
  loadOnce()
  return { mp, loading, error }
}
