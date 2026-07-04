import { onUnmounted } from 'vue'

const HASH_KEY    = 'playground'
const COMPRESS_THRESHOLD = 2048
const VALID_KINDS = new Set(['grammar', 'source-pack', 'bundle'])
const VALID_QUERY_MODES = new Set(['query', 'locals', 'bindings', 'folding'])
const VALID_PREVIEW_TABS = new Set(['source', 'tree', 'query', 'output'])
const VALID_BOTTOM_TABS = new Set(['diagnostics', 'corpus', 'lint', 'artifact'])
const VALID_OUTPUT_TABS = new Set(['sexp', 'diagnostics', 'perf', 'incremental', 'compare'])


function toB64(str) {
  const bytes = new TextEncoder().encode(str)
  return bytesToB64(bytes)
}

function bytesToB64(bytes) {
  let binary = ''
  for (let index = 0; index < bytes.length; index += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(index, index + 0x8000))
  }
  if (typeof btoa === 'function') return btoa(binary)
  return Buffer.from(binary, 'binary').toString('base64')
}

function fromB64(b64) {
  const binary = typeof atob === 'function'
    ? atob(b64)
    : Buffer.from(b64, 'base64').toString('binary')
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
  return bytesToB64(new Uint8Array(compressed))
}

async function decompressFromB64(b64) {
  const binary = typeof atob === 'function'
    ? atob(b64)
    : Buffer.from(b64, 'base64').toString('binary')
  const bytes  = Uint8Array.from(binary, c => c.charCodeAt(0))
  const stream = new DecompressionStream('deflate')
  const writer = stream.writable.getWriter()
  writer.write(bytes)
  writer.close()
  const plain = await new Response(stream.readable).arrayBuffer()
  return new TextDecoder().decode(plain)
}

function hashPayload(raw) {
  const text = String(raw ?? '').startsWith('#') ? String(raw).slice(1) : String(raw ?? '')
  const value = text.startsWith(HASH_KEY + '=')
    ? text.slice(HASH_KEY.length + 1)
    : text
  try {
    return decodeURIComponent(value)
  } catch {
    return value
  }
}

function stringValue(value, fallback = '') {
  return typeof value === 'string' ? value : fallback
}

function boolValue(value) {
  return value === true
}

function normalizeQueryMode(value) {
  return VALID_QUERY_MODES.has(value) ? value : 'query'
}

function normalizeQueryModePatterns(value) {
  const source = value && typeof value === 'object' && !Array.isArray(value) ? value : {}
  return {
    locals: stringValue(source.locals),
    bindings: stringValue(source.bindings),
    folding: stringValue(source.folding),
  }
}

function normalizeFiles(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const files = {}
  for (const [path, text] of Object.entries(value)) {
    if (typeof path !== 'string' || typeof text !== 'string') return null
    files[path] = text
  }
  return files
}

function normalizeProject(value, kind) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  if (kind === 'source-pack') {
    const files = normalizeFiles(value.files)
    if (!files) return null
    return {
      files,
      selectedPath: value.selectedPath == null ? null : stringValue(value.selectedPath, null),
      mode: 'source',
      bundleJson: null,
    }
  }
  if (kind === 'bundle') {
    const bundleJson = stringValue(value.bundleJson)
    if (!bundleJson) return null
    return {
      files: {},
      selectedPath: null,
      mode: 'bundle',
      bundleJson,
    }
  }
  return null
}

export function normalizeLoadedState(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null

  if (value.v === 2) {
    const kind = VALID_KINDS.has(value.kind) ? value.kind : null
    if (!kind) return null
    const normalized = {
      v: 2,
      kind,
      grammar: stringValue(value.grammar),
      source: stringValue(value.source),
      query: stringValue(value.query),
      highlight: stringValue(value.highlight),
      queryMode: normalizeQueryMode(value.queryMode),
      queryModePatterns: normalizeQueryModePatterns(value.queryModePatterns),
      incrementalTraceEnabled: boolValue(value.incrementalTraceEnabled),
      previewTab: VALID_PREVIEW_TABS.has(value.previewTab) ? value.previewTab : 'source',
      packBottomTab: VALID_BOTTOM_TABS.has(value.packBottomTab) ? value.packBottomTab : 'diagnostics',
      outputTab: VALID_OUTPUT_TABS.has(value.outputTab) ? value.outputTab : 'sexp',
      project: null,
    }
    if (kind !== 'grammar') {
      const project = normalizeProject(value.project, kind)
      if (!project) return null
      normalized.project = project
    }
    return normalized
  }

  if ('g' in value || 's' in value || 'q' in value || 'h' in value) {
    return {
      v: 2,
      kind: 'grammar',
      grammar: stringValue(value.g),
      source: stringValue(value.s),
      query: stringValue(value.q),
      highlight: stringValue(value.h),
      queryMode: 'query',
      queryModePatterns: { locals: '', bindings: '', folding: '' },
      incrementalTraceEnabled: false,
      previewTab: 'source',
      packBottomTab: 'diagnostics',
      outputTab: 'sexp',
      project: null,
    }
  }

  return null
}

export async function encodePlaygroundState(state, { forceCompress = false } = {}) {
  const normalized = normalizeLoadedState(state)
  if (!normalized) return ''
  const json = JSON.stringify(normalized)
  if ((forceCompress || json.length >= COMPRESS_THRESHOLD) && typeof CompressionStream !== 'undefined') {
    try {
      return `z.${await compressToB64(json)}`
    } catch {
      // Fall back to plain base64 below.
    }
  }
  return toB64(json)
}

export async function decodePlaygroundState(raw) {
  const encoded = hashPayload(raw)
  if (!encoded) return null
  try {
    const json = encoded.startsWith('z.')
      ? await decompressFromB64(encoded.slice(2))
      : fromB64(encoded)
    return normalizeLoadedState(JSON.parse(json))
  } catch {
    return null
  }
}

function decodePlaygroundStateSync(raw) {
  const encoded = hashPayload(raw)
  if (!encoded || encoded.startsWith('z.')) return null
  try {
    return normalizeLoadedState(JSON.parse(fromB64(encoded)))
  } catch {
    return null
  }
}

function legacySnapshot(g, s, q, h) {
  return normalizeLoadedState({
    v: 2,
    kind: 'grammar',
    grammar: g,
    source: s,
    query: q,
    highlight: h,
  })
}


export function loadState() {
  return decodePlaygroundStateSync(location.hash)
}

export async function loadStateAsync() {
  return decodePlaygroundState(location.hash)
}


export function useUrlState() {
  let timer = null
  let pendingState = null

  function snapshotFromArgs(args) {
    return args.length > 1 ? legacySnapshot(args[0], args[1], args[2], args[3]) : normalizeLoadedState(args[0])
  }

  async function writeState(state) {
    const encoded = await encodePlaygroundState(state)
    if (!encoded) return location.href
    history.replaceState(null, '', `#${HASH_KEY}=${encoded}`)
    return location.href
  }

  function saveState(...args) {
    pendingState = snapshotFromArgs(args)
    clearTimeout(timer)
    timer = setTimeout(async () => {
      try {
        await writeState(pendingState)
      } catch (e) {
        console.warn('[useUrlState] save failed:', e)
      }
    }, 500)
  }

  async function flushState(state = pendingState) {
    clearTimeout(timer)
    timer = null
    pendingState = normalizeLoadedState(state)
    return writeState(pendingState)
  }

  onUnmounted(() => clearTimeout(timer))

  return { loadState, loadStateAsync, saveState, flushState }
}
