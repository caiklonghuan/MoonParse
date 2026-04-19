import { onUnmounted } from 'vue'

const HASH_KEY    = 'playground'
const COMPRESS_THRESHOLD = 2048


function toB64(str) {
  const bytes = new TextEncoder().encode(str)
  return btoa(String.fromCharCode(...bytes))
}

function fromB64(b64) {
  const binary = atob(b64)
  const bytes  = Uint8Array.from(binary, c => c.charCodeAt(0))
  return new TextDecoder().decode(bytes)
}

async function compressToB64(str) {
  const bytes  = new TextEncoder().encode(str)
  const stream = new CompressionStream('deflate')
  const writer = stream.writable.getWriter()
  writer.write(bytes)
  writer.close()
  const compressed = await new Response(stream.readable).arrayBuffer()
  return btoa(String.fromCharCode(...new Uint8Array(compressed)))
}

async function decompressFromB64(b64) {
  const bytes  = Uint8Array.from(atob(b64), c => c.charCodeAt(0))
  const stream = new DecompressionStream('deflate')
  const writer = stream.writable.getWriter()
  writer.write(bytes)
  writer.close()
  const plain = await new Response(stream.readable).arrayBuffer()
  return new TextDecoder().decode(plain)
}


export function loadState() {
  const raw = location.hash.slice(1)
  if (!raw) return null

  const b64 = raw.startsWith(HASH_KEY + '=')
    ? raw.slice(HASH_KEY.length + 1)
    : raw

  if (b64.startsWith('z.')) return null

  try {
    return JSON.parse(fromB64(b64))
  } catch {
    return null
  }
}

export async function loadStateAsync() {
  const raw = location.hash.slice(1)
  if (!raw) return null

  const b64 = raw.startsWith(HASH_KEY + '=')
    ? raw.slice(HASH_KEY.length + 1)
    : raw

  try {
    if (b64.startsWith('z.')) {
      const json = await decompressFromB64(b64.slice(2))
      return JSON.parse(json)
    }
    return JSON.parse(fromB64(b64))
  } catch {
    return null
  }
}


export function useUrlState() {
  let timer = null

  function saveState(g, s, q, h) {
    clearTimeout(timer)
    timer = setTimeout(async () => {
      try {
        const json = JSON.stringify({ g, s, q, h })
        let encoded

        if (json.length >= COMPRESS_THRESHOLD && typeof CompressionStream !== 'undefined') {
          const b64 = await compressToB64(json)
          encoded = `z.${b64}`
        } else {
          encoded = toB64(json)
        }

        history.replaceState(null, '', `#${HASH_KEY}=${encoded}`)
      } catch (e) {
        console.warn('[useUrlState] save failed:', e)
      }
    }, 500)
  }

  onUnmounted(() => clearTimeout(timer))

  return { loadState, loadStateAsync, saveState }
}

