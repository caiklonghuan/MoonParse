import { computed, onUnmounted, ref, shallowRef } from 'vue'

import {
  createBundleProject,
  createMinimalProject,
  createPresetProject,
  createSourceProject,
  createProjectFile,
  deleteProjectFile,
  downloadProjectZip,
  importDirectoryFiles,
  importZip,
  markProjectClean,
  renameProjectFile,
  replaceProject,
  selectProjectFile,
  updateProjectFile,
  MANIFEST_PATH,
} from '../lib/languagePackProject.js'
import {
  createManifestJsonDiagnostic,
  hasErrorDiagnostics,
  sortPackDiagnostics,
} from '../lib/packDiagnostics.js'
import {
  bundleDownloadFileName,
  collectSnapshotUpdates,
  corpusCaseKey,
  corpusManifestInfo,
  downloadTextFile,
} from '../lib/corpusWorkbench.js'
import {
  createVsixArtifact,
  downloadBinaryFile,
  vsixDownloadFileName,
} from '../lib/vsixArtifact.js'

const CHECK_DEBOUNCE_MS = 300

function defaultConfirmDiscard() {
  return window.confirm('Current Language Pack has unexported changes. Discard them?')
}

function uniqueDiagnostics(diagnostics) {
  const seen = new Set()
  const result = []
  for (const diagnostic of diagnostics) {
    const key = [
      diagnostic?.severity ?? '',
      diagnostic?.code ?? '',
      diagnostic?.path ?? '',
      diagnostic?.line ?? '',
      diagnostic?.column ?? '',
      diagnostic?.message ?? '',
    ].join('\0')
    if (seen.has(key)) continue
    seen.add(key)
    result.push(diagnostic)
  }
  return sortPackDiagnostics(result)
}

export function useLanguagePackProject(
  mp,
  {
    confirmDiscard = defaultConfirmDiscard,
    registerCleanup = onUnmounted,
    downloadText = downloadTextFile,
    downloadBinary = downloadBinaryFile,
  } = {},
) {
  const project = shallowRef(null)
  const language = shallowRef(null)
  const checkDiagnostics = ref([])
  const buildDiagnostics = ref([])
  const importError = ref(null)
  const importing = ref(false)
  const checking = ref(false)
  const building = ref(false)
  const checkStatus = ref('idle')
  const buildStatus = ref('idle')
  const buildStale = ref(false)
  const previewStale = ref(false)
  const lastBundleJson = ref(null)
  const projectRevision = ref(0)
  const lastBuildRevision = ref(-1)
  const corpusCases = ref([])
  const corpusDiagnostics = ref([])
  const corpusElapsedMs = ref(0)
  const corpusStale = ref(false)
  const corpusRunning = ref(false)
  const selectedCorpusKey = ref(null)
  const corpusRunRevision = ref(-1)

  const busy = computed(() =>
    importing.value || checking.value || building.value || corpusRunning.value)
  const diagnostics = computed(() =>
    uniqueDiagnostics([
      ...checkDiagnostics.value,
      ...buildDiagnostics.value,
      ...corpusDiagnostics.value,
    ]))
  const corpusFormat = computed(() => corpusManifestInfo(project.value?.files ?? {}).format)
  const canDownloadBundle = computed(() =>
    project.value?.mode === 'source' &&
    Boolean(lastBundleJson.value) &&
    !buildStale.value &&
    !previewStale.value &&
    lastBuildRevision.value === projectRevision.value)
  const bundleFileName = computed(() =>
    lastBundleJson.value ? bundleDownloadFileName(lastBundleJson.value) : '')
  const canDownloadVsix = computed(() => canDownloadBundle.value)
  const vsixFileName = computed(() =>
    lastBundleJson.value ? vsixDownloadFileName(lastBundleJson.value) : '')

  let checkTimer = null
  let checkRequestId = 0
  let buildRequestId = 0
  let corpusRequestId = 0

  function runtime() {
    return mp?.value ?? mp
  }

  function nowMs() {
    return globalThis.performance?.now?.() ?? Date.now()
  }

  function canReplace(next) {
    return replaceProject(project.value, next, confirmDiscard).accepted
  }

  function clearCheckTimer() {
    if (checkTimer != null) {
      clearTimeout(checkTimer)
      checkTimer = null
    }
  }

  function replaceLanguage(next) {
    const previous = language.value
    language.value = next
    if (previous && previous !== next) {
      try { previous.free() } catch (_) {}
    }
  }

  function resetReports() {
    clearCheckTimer()
    checkRequestId += 1
    buildRequestId += 1
    corpusRequestId += 1
    checking.value = false
    building.value = false
    corpusRunning.value = false
    checkDiagnostics.value = []
    buildDiagnostics.value = []
    corpusDiagnostics.value = []
    corpusCases.value = []
    corpusElapsedMs.value = 0
    corpusStale.value = false
    selectedCorpusKey.value = null
    corpusRunRevision.value = -1
    checkStatus.value = 'idle'
    buildStatus.value = 'idle'
    buildStale.value = false
    previewStale.value = false
    lastBundleJson.value = null
    projectRevision.value = 0
    lastBuildRevision.value = -1
  }

  function commitSourceProject(nextProject) {
    project.value = nextProject
    importError.value = null
    resetReports()
    replaceLanguage(null)
    buildStale.value = true
  }

  function commitBundleProject(nextProject, nextLanguage) {
    project.value = nextProject
    importError.value = null
    resetReports()
    replaceLanguage(nextLanguage)
    lastBundleJson.value = nextProject.bundleJson
  }

  async function runCheck(requestId) {
    const current = project.value
    if (current?.mode !== 'source') {
      if (requestId === checkRequestId) {
        checkDiagnostics.value = []
        checkStatus.value = 'idle'
        checking.value = false
      }
      return []
    }

    checking.value = true
    checkStatus.value = 'checking'
    const manifestDiagnostic = createManifestJsonDiagnostic(current.files[MANIFEST_PATH] ?? '')
    if (manifestDiagnostic) {
      const diagnostics = sortPackDiagnostics([manifestDiagnostic])
      if (requestId === checkRequestId && project.value === current) {
        checkDiagnostics.value = diagnostics
        checkStatus.value = 'error'
        checking.value = false
      }
      return diagnostics
    }

    try {
      const api = runtime()
      const raw = typeof api?.checkPack === 'function'
        ? await Promise.resolve(api.checkPack(current.files))
        : { ok: true, diagnostics: [] }
      const nextDiagnostics = sortPackDiagnostics(raw?.diagnostics ?? [])
      if (requestId === checkRequestId && project.value === current) {
        checkDiagnostics.value = nextDiagnostics
        checkStatus.value = hasErrorDiagnostics(nextDiagnostics) ? 'error' : 'ok'
        checking.value = false
      }
      return nextDiagnostics
    } catch (error) {
      if (requestId === checkRequestId && project.value === current) {
        importError.value = error?.message ?? String(error)
        checkStatus.value = 'error'
        checking.value = false
      }
      return []
    }
  }

  function scheduleCheck() {
    clearCheckTimer()
    const requestId = ++checkRequestId
    checking.value = true
    checkStatus.value = 'checking'
    checkTimer = setTimeout(() => {
      checkTimer = null
      void runCheck(requestId)
    }, CHECK_DEBOUNCE_MS)
  }

  async function checkProject() {
    clearCheckTimer()
    const requestId = ++checkRequestId
    return runCheck(requestId)
  }

  function markEdited() {
    projectRevision.value += 1
    corpusRequestId += 1
    corpusRunning.value = false
    buildDiagnostics.value = []
    buildStatus.value = 'stale'
    buildStale.value = true
    previewStale.value = Boolean(language.value)
    if (corpusCases.value.length > 0 || corpusDiagnostics.value.length > 0) {
      corpusStale.value = true
    }
    scheduleCheck()
  }

  async function buildProject() {
    const current = project.value
    if (current?.mode !== 'source') return false
    const api = runtime()
    if (!api) {
      importError.value = 'MoonParse WASM is not ready.'
      return false
    }

    const latestCheckDiagnostics = await checkProject()
    if (project.value !== current) return false
    if (hasErrorDiagnostics(latestCheckDiagnostics)) {
      buildDiagnostics.value = []
      buildStatus.value = 'error'
      buildStale.value = true
      previewStale.value = Boolean(language.value)
      return false
    }

    const requestId = ++buildRequestId
    building.value = true
    buildStatus.value = 'building'
    importError.value = null
    try {
      const result = await Promise.resolve(api.buildPack(current.files))
      if (requestId !== buildRequestId || project.value !== current) {
        try { result?.language?.free?.() } catch (_) {}
        return false
      }
      buildDiagnostics.value = sortPackDiagnostics(result?.diagnostics ?? [])
      if (result?.ok && result.language) {
        replaceLanguage(result.language)
        lastBundleJson.value = result.bundleJson ?? null
        lastBuildRevision.value = projectRevision.value
        buildStatus.value = 'ok'
        buildStale.value = false
        previewStale.value = false
        return true
      }
      try { result?.language?.free?.() } catch (_) {}
      buildStatus.value = 'error'
      buildStale.value = true
      previewStale.value = Boolean(language.value)
      return false
    } catch (error) {
      if (requestId === buildRequestId && project.value === current) {
        importError.value = error?.message ?? String(error)
        buildStatus.value = 'error'
        buildStale.value = true
        previewStale.value = Boolean(language.value)
      }
      return false
    } finally {
      if (requestId === buildRequestId) {
        building.value = false
      }
    }
  }

  async function runCorpusProject({ focusCaseKey = null } = {}) {
    const current = project.value
    if (current?.mode !== 'source') return false
    const api = runtime()
    if (!api || typeof api.runCorpus !== 'function') {
      importError.value = 'MoonParse Corpus API is not ready.'
      return false
    }

    const requestId = ++corpusRequestId
    const start = nowMs()
    corpusRunning.value = true
    importError.value = null
    try {
      const result = await Promise.resolve(api.runCorpus(current.files))
      const elapsed = Math.max(0, nowMs() - start)
      if (requestId !== corpusRequestId || project.value !== current) return false

      const cases = Array.isArray(result?.cases) ? result.cases : []
      corpusDiagnostics.value = sortPackDiagnostics(result?.diagnostics ?? [])
      corpusCases.value = cases
      corpusElapsedMs.value = elapsed
      corpusRunRevision.value = projectRevision.value
      corpusStale.value = false

      const keys = new Set(cases.map((testCase) => corpusCaseKey(testCase)))
      if (focusCaseKey && keys.has(focusCaseKey)) {
        selectedCorpusKey.value = focusCaseKey
      } else if (selectedCorpusKey.value && keys.has(selectedCorpusKey.value)) {
        selectedCorpusKey.value = selectedCorpusKey.value
      } else {
        const firstFailed = cases.find((testCase) => !testCase.passed)
        selectedCorpusKey.value = firstFailed
          ? corpusCaseKey(firstFailed)
          : (cases[0] ? corpusCaseKey(cases[0]) : null)
      }
      return Boolean(result?.ok)
    } catch (error) {
      if (requestId === corpusRequestId && project.value === current) {
        importError.value = error?.message ?? String(error)
      }
      return false
    } finally {
      if (requestId === corpusRequestId) {
        corpusRunning.value = false
      }
    }
  }

  async function rewriteCorpusSnapshots({ selectedOnly = false } = {}) {
    const current = project.value
    if (current?.mode !== 'source') return false
    if (corpusFormat.value !== 'moonparse-corpus-v2') return false
    const api = runtime()
    if (!api || typeof api.rewriteCorpusSnapshots !== 'function') {
      importError.value = 'MoonParse snapshot rewrite API is not ready.'
      return false
    }

    const groups = collectSnapshotUpdates(corpusCases.value, current.files, {
      selectedKey: selectedCorpusKey.value,
      all: !selectedOnly,
    })
    if (groups.length === 0) return false

    importError.value = null
    const updatedFiles = {}
    const diagnostics = []
    try {
      for (const group of groups) {
        const result = await Promise.resolve(api.rewriteCorpusSnapshots({
          path: group.path,
          text: group.text,
          format: corpusFormat.value,
          updates: group.updates,
        }))
        diagnostics.push(...(result?.diagnostics ?? []))
        if (!result?.ok || typeof result.updatedText !== 'string') {
          corpusDiagnostics.value = sortPackDiagnostics(diagnostics)
          return false
        }
        updatedFiles[group.path] = result.updatedText
      }
    } catch (error) {
      importError.value = error?.message ?? String(error)
      return false
    }

    if (project.value !== current) return false
    project.value = {
      ...current,
      files: { ...current.files, ...updatedFiles },
      dirty: true,
    }
    corpusDiagnostics.value = sortPackDiagnostics(diagnostics)
    markEdited()
    return true
  }

  function rewriteSelectedCorpusSnapshot() {
    return rewriteCorpusSnapshots({ selectedOnly: true })
  }

  function rewriteAllCorpusSnapshots() {
    return rewriteCorpusSnapshots({ selectedOnly: false })
  }

  function downloadBundleArtifact() {
    if (!canDownloadBundle.value) return false
    const api = runtime()
    if (!api || typeof api.loadBundle !== 'function') {
      importError.value = 'MoonParse Bundle API is not ready.'
      return false
    }
    try {
      const loaded = api.loadBundle(lastBundleJson.value)
      try { loaded?.free?.() } catch (_) {}
      downloadText(lastBundleJson.value, bundleFileName.value, 'application/json')
      return true
    } catch (error) {
      importError.value = error?.message ?? String(error)
      return false
    }
  }

  function downloadVsixArtifact() {
    if (!canDownloadVsix.value) return false
    const api = runtime()
    if (!api || typeof api.loadBundle !== 'function') {
      importError.value = 'MoonParse Bundle API is not ready.'
      return false
    }
    try {
      const loaded = api.loadBundle(lastBundleJson.value)
      try { loaded?.free?.() } catch (_) {}
      const artifact = createVsixArtifact(lastBundleJson.value)
      downloadBinary(artifact.bytes, artifact.fileName, 'application/vsix')
      return true
    } catch (error) {
      importError.value = error?.message ?? String(error)
      return false
    }
  }

  async function activateSource(nextProject, { confirm = true, build = true } = {}) {
    if (confirm && !canReplace(nextProject)) return false
    commitSourceProject(nextProject)
    await checkProject()
    if (build) {
      await buildProject()
    }
    return true
  }

  function activateBundle(nextProject, { confirm = true } = {}) {
    if (confirm && !canReplace(nextProject)) return false
    const api = runtime()
    if (!api) {
      importError.value = 'MoonParse WASM is not ready.'
      return false
    }
    const nextLanguage = api.loadBundle(nextProject.bundleJson)
    commitBundleProject(nextProject, nextLanguage)
    return true
  }

  async function createNewProject() {
    return activateSource(createMinimalProject())
  }

  async function selectPresetProject(id) {
    return activateSource(createPresetProject(id))
  }

  async function restoreProjectSnapshot(snapshot, { confirm = true, build = true } = {}) {
    if (snapshot?.mode === 'source') {
      return activateSource(createSourceProject(snapshot.files, {
        selectedPath: snapshot.selectedPath ?? undefined,
        dirty: false,
      }), { confirm, build })
    }
    if (snapshot?.mode === 'bundle') {
      return activateBundle(createBundleProject(snapshot.bundleJson), { confirm })
    }
    importError.value = 'Shared project state is invalid.'
    return false
  }

  async function importDirectory(fileList) {
    if (!canReplace(null)) return false
    importing.value = true
    importError.value = null
    try {
      const next = await importDirectoryFiles(fileList)
      return await activateSource(next, { confirm: false })
    } catch (error) {
      importError.value = error?.message ?? String(error)
      return false
    } finally {
      importing.value = false
    }
  }

  async function importProjectFile(file) {
    if (!file || !canReplace(null)) return false
    importing.value = true
    importError.value = null
    try {
      if (file.name.toLowerCase().endsWith('.zip')) {
        const next = await importZip(file)
        return await activateSource(next, { confirm: false })
      }
      const next = createBundleProject(await file.text())
      return activateBundle(next, { confirm: false })
    } catch (error) {
      importError.value = error?.message ?? String(error)
      return false
    } finally {
      importing.value = false
    }
  }

  function exportSourceProject() {
    if (!project.value) return null
    const fileName = downloadProjectZip(project.value)
    project.value = markProjectClean(project.value)
    return fileName
  }

  function selectFile(path) {
    project.value = selectProjectFile(project.value, path)
  }

  function createFile(path, text = '') {
    const next = createProjectFile(project.value, path, text)
    project.value = next
    markEdited()
  }

  function updateFile(path, text) {
    const previous = project.value
    const next = updateProjectFile(previous, path, text)
    project.value = next
    if (next.files === previous?.files) return
    markEdited()
  }

  function renameFile(oldPath, newPath) {
    const previous = project.value
    const next = renameProjectFile(previous, oldPath, newPath)
    project.value = next
    if (next === previous) return
    markEdited()
  }

  function deleteFile(path) {
    const next = deleteProjectFile(project.value, path)
    project.value = next
    markEdited()
  }

  function markClean() {
    project.value = markProjectClean(project.value)
  }

  function leaveProject() {
    if (!canReplace(null)) return false
    clearCheckTimer()
    checkRequestId += 1
    buildRequestId += 1
    corpusRequestId += 1
    project.value = null
    checkDiagnostics.value = []
    buildDiagnostics.value = []
    corpusDiagnostics.value = []
    corpusCases.value = []
    corpusElapsedMs.value = 0
    importError.value = null
    checking.value = false
    building.value = false
    corpusRunning.value = false
    checkStatus.value = 'idle'
    buildStatus.value = 'idle'
    buildStale.value = false
    previewStale.value = false
    corpusStale.value = false
    selectedCorpusKey.value = null
    corpusRunRevision.value = -1
    lastBundleJson.value = null
    projectRevision.value = 0
    lastBuildRevision.value = -1
    replaceLanguage(null)
    return true
  }

  registerCleanup(() => {
    clearCheckTimer()
    replaceLanguage(null)
  })

  return {
    project,
    language,
    diagnostics,
    checkDiagnostics,
    buildDiagnostics,
    corpusDiagnostics,
    corpusCases,
    corpusElapsedMs,
    corpusStale,
    corpusRunning,
    selectedCorpusKey,
    corpusRunRevision,
    projectRevision,
    lastBuildRevision,
    corpusFormat,
    canDownloadBundle,
    bundleFileName,
    canDownloadVsix,
    vsixFileName,
    importError,
    busy,
    importing,
    checking,
    building,
    checkStatus,
    buildStatus,
    buildStale,
    previewStale,
    lastBundleJson,
    createNewProject,
    selectPresetProject,
    restoreProjectSnapshot,
    importDirectory,
    importProjectFile,
    exportSourceProject,
    checkProject,
    buildProject,
    runCorpusProject,
    rewriteSelectedCorpusSnapshot,
    rewriteAllCorpusSnapshots,
    downloadBundleArtifact,
    downloadVsixArtifact,
    selectFile,
    createFile,
    updateFile,
    renameFile,
    deleteFile,
    markClean,
    leaveProject,
  }
}
