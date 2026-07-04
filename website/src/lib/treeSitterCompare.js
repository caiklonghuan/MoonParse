const SUPPORTED_LANGUAGES = Object.freeze({
  json: 'tree-sitter-json.wasm',
})

const IDLE_RESULT = Object.freeze({
  status: 'idle',
  languageId: '',
  sexp: '',
  parseTimeMs: 0,
  nodeCount: 0,
  errorCount: 0,
  hasError: false,
  error: null,
})

function now() {
  return globalThis.performance?.now?.() ?? Date.now()
}

function errorMessage(error) {
  return error instanceof Error ? error.message : String(error)
}

export function normalizeTreeSitterLanguageId(value) {
  const id = String(value ?? '').trim().toLowerCase()
  if (id === 'application/json' || id === 'json-pack') return 'json'
  return id || 'unknown'
}

export function isTreeSitterLanguageSupported(languageId) {
  return Object.hasOwn(SUPPORTED_LANGUAGES, normalizeTreeSitterLanguageId(languageId))
}

export function idleTreeSitterResult(languageId = '') {
  return { ...IDLE_RESULT, languageId: normalizeTreeSitterLanguageId(languageId) }
}

export function unavailableTreeSitterResult(languageId) {
  const normalized = normalizeTreeSitterLanguageId(languageId)
  return {
    ...IDLE_RESULT,
    status: 'unavailable',
    languageId: normalized,
    error: `Tree-sitter comparison unavailable for ${normalized}. Supported: JSON.`,
  }
}

export function loadingTreeSitterResult(languageId) {
  return {
    ...IDLE_RESULT,
    status: 'loading',
    languageId: normalizeTreeSitterLanguageId(languageId),
  }
}

export function collectTreeSitterMetrics(rootNode) {
  let errorCount = 0
  const stack = [rootNode]
  while (stack.length > 0) {
    const node = stack.pop()
    if (node.isError || node.isMissing) errorCount += 1
    for (let index = node.childCount - 1; index >= 0; index -= 1) {
      const child = node.child(index)
      if (child) stack.push(child)
    }
  }
  return {
    sexp: rootNode.toString(),
    nodeCount: rootNode.descendantCount,
    errorCount,
    hasError: Boolean(rootNode.hasError),
  }
}

export function collectMoonParseMetrics(tree) {
  if (!tree) return { nodeCount: 0, errorCount: 0, hasError: false }
  try {
    let nodeCount = 0
    let errorCount = 0
    const stack = tree.root ? [tree.root] : []
    while (stack.length > 0) {
      const node = stack.pop()
      nodeCount += 1
      if (node.is_error || node.is_missing) errorCount += 1
      for (const child of node.children ?? []) stack.push(child)
    }
    const summary = tree.errorSummary?.() ?? 'ok'
    return { nodeCount, errorCount, hasError: summary !== 'ok' }
  } catch {
    return { nodeCount: 0, errorCount: 0, hasError: false }
  }
}

function normalizeAssetBase(assetBase) {
  const base = String(assetBase ?? '')
  return base.endsWith('/') ? base : `${base}/`
}

export function createTreeSitterRuntime({
  assetBase = `${import.meta.env?.BASE_URL ?? '/'}tree-sitter/`,
  loadModule = () => import('web-tree-sitter'),
  clock = now,
} = {}) {
  const base = normalizeAssetBase(assetBase)
  let modulePromise = null
  const parserPromises = new Map()

  async function loadRuntimeModule() {
    if (!modulePromise) {
      modulePromise = loadModule().then(async (module) => {
        await module.Parser.init({ locateFile: () => `${base}tree-sitter.wasm` })
        return module
      })
    }
    return modulePromise
  }

  async function parserFor(languageId) {
    if (!parserPromises.has(languageId)) {
      parserPromises.set(languageId, loadRuntimeModule().then(async ({ Parser, Language }) => {
        const language = await Language.load(`${base}${SUPPORTED_LANGUAGES[languageId]}`)
        const parser = new Parser()
        parser.setLanguage(language)
        return { parser, language }
      }))
    }
    return parserPromises.get(languageId)
  }

  async function compare(source, languageId) {
    const normalized = normalizeTreeSitterLanguageId(languageId)
    if (!isTreeSitterLanguageSupported(normalized)) {
      return unavailableTreeSitterResult(normalized)
    }

    let tree = null
    try {
      const { parser } = await parserFor(normalized)
      const started = clock()
      tree = parser.parse(String(source ?? ''))
      const parseTimeMs = Math.max(0, clock() - started)
      if (!tree) throw new Error('Tree-sitter returned no parse tree.')
      return {
        status: 'ready',
        languageId: normalized,
        ...collectTreeSitterMetrics(tree.rootNode),
        parseTimeMs,
        error: null,
      }
    } catch (error) {
      return {
        ...IDLE_RESULT,
        status: 'error',
        languageId: normalized,
        error: errorMessage(error),
      }
    } finally {
      tree?.delete()
    }
  }

  return { compare }
}

let sharedRuntime = null

export function compareWithTreeSitter(source, languageId) {
  sharedRuntime ??= createTreeSitterRuntime()
  return sharedRuntime.compare(source, languageId)
}

export function createTreeSitterComparisonController({
  run = compareWithTreeSitter,
  delay = 150,
  onResult = () => {},
  setTimer = (callback, timeout) => setTimeout(callback, timeout),
  clearTimer = (timer) => clearTimeout(timer),
} = {}) {
  let timer = null
  let requestId = 0
  let disposed = false

  function update({ source = '', languageId = 'unknown', active = false } = {}) {
    requestId += 1
    const currentRequest = requestId
    if (timer != null) clearTimer(timer)
    timer = null

    if (!active) {
      onResult(idleTreeSitterResult(languageId))
      return
    }
    if (!isTreeSitterLanguageSupported(languageId)) {
      onResult(unavailableTreeSitterResult(languageId))
      return
    }

    onResult(loadingTreeSitterResult(languageId))
    timer = setTimer(async () => {
      timer = null
      const result = await run(source, languageId)
      if (!disposed && currentRequest === requestId) onResult(result)
    }, delay)
  }

  function dispose() {
    disposed = true
    requestId += 1
    if (timer != null) clearTimer(timer)
    timer = null
  }

  return { update, dispose }
}
