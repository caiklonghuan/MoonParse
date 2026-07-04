<script setup>
import { computed, nextTick, onMounted, onUnmounted, provide, ref, watch } from 'vue'
import SplitPane from '@/components/layout/SplitPane.vue'
import EditorPanel from '@/components/editor/EditorPanel.vue'
import TreePanel from '@/components/tree/TreePanel.vue'
import QueryPanel from '@/components/query/QueryPanel.vue'
import OutputPanel from '@/components/output/OutputPanel.vue'
import PerfBar from '@/components/common/PerfBar.vue'
import CorpusPanel from '@/components/pack/CorpusPanel.vue'
import LintPanel from '@/components/pack/LintPanel.vue'
import PackFileTree from '@/components/pack/PackFileTree.vue'
import PackFileEditor from '@/components/pack/PackFileEditor.vue'
import { useMoonParse } from '@/composables/useMoonParse.js'
import { useParser } from '@/composables/useParser.js'
import { useParseTree } from '@/composables/useParseTree.js'
import { useHighlight } from '@/composables/useHighlight.js'
import { useUrlState } from '@/composables/useUrlState.js'
import { useKeyboard } from '@/composables/useKeyboard.js'
import { useGrammarValidation } from '@/composables/useGrammarValidation.js'
import { useLanguagePackProject } from '@/composables/useLanguagePackProject.js'
import { useLintWorkbench } from '@/composables/useLintWorkbench.js'
import { DEMO_SCENARIOS, findDemoScenario } from '@/data/demoScenarios.js'
import { BUILTIN_LANGUAGE_PRESETS, findBuiltinPresetByGrammar } from '@/data/languagePresets.js'
import {
  diagnosticColumn,
  diagnosticDisplayLocation,
  diagnosticLine,
  diagnosticPath,
  hasErrorDiagnostics,
  isFileDiagnostic,
} from '@/lib/packDiagnostics.js'

const DEFAULT_PRESET = BUILTIN_LANGUAGE_PRESETS[0]
const PACK_PRESET_IDS = new Set(['json', 'python', 'moonbit'])

const { loadState, loadStateAsync, saveState, flushState } = useUrlState()
const savedState = loadState()
const initialGrammarState = savedState?.kind === 'grammar' ? savedState : null
const initialPreset = findBuiltinPresetByGrammar(initialGrammarState?.grammar)

const grammarDsl = ref(initialGrammarState?.grammar ?? DEFAULT_PRESET.grammar)
const sourceCode = ref(initialGrammarState?.source ?? DEFAULT_PRESET.source)
const queryPattern = ref(initialGrammarState?.query ?? '')
const queryMode = ref(initialGrammarState?.queryMode ?? 'query')
const queryModePatterns = ref(initialGrammarState?.queryModePatterns ?? { locals: '', bindings: '', folding: '' })
const selectedRange = ref(null)
const incrementalTraceEnabled = ref(Boolean(initialGrammarState?.incrementalTraceEnabled))
const bindingGraph = ref({
  uri: '', scopes: [], definitions: [], references: [], edges: [], diagnostics: [],
})
const hlQueryStr = ref(initialGrammarState?.highlight ?? (initialGrammarState?.grammar
  ? (initialPreset?.highlightQuery ?? '')
  : (DEFAULT_PRESET.highlightQuery ?? '')))
const querySuggestion = ref(initialGrammarState?.query ? '' : (DEFAULT_PRESET.query ?? ''))
const pendingSharedState = ref(savedState?.kind !== 'grammar' ? savedState : null)

if (!savedState) {
  loadStateAsync().then((state) => {
    if (!state) return
    pendingSharedState.value = state
  })
}

const { mp, loading, error: mpError } = useMoonParse()
const { parser: grammarParser, parserError: grammarParserError, building } = useParser(grammarDsl)
const {
  project,
  language: importedLanguage,
  diagnostics: projectDiagnostics,
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
  corpusFormat,
  canDownloadBundle,
  bundleFileName,
  canDownloadVsix,
  vsixFileName,
  importError: projectImportError,
  busy: projectBusy,
  checking: projectChecking,
  building: projectBuilding,
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
  leaveProject,
} = useLanguagePackProject(mp)

const parser = computed(() => project.value
  ? (importedLanguage.value?.parser ?? null)
  : grammarParser.value)
const parserError = computed(() =>
  projectImportError.value ?? (project.value ? null : grammarParserError.value))
const workspaceBuilding = computed(() =>
  building.value || projectBusy.value || projectChecking.value || projectBuilding.value)
const {
  tree,
  parseTime,
  isIncremental,
  incrementalTrace,
  triggerEdit,
} = useParseTree(parser, sourceCode, incrementalTraceEnabled)

const editorPanelRef = ref(null)
const queryPanelRef = ref(null)
const packFileEditorRef = ref(null)
const previewTab = ref('source')
const packBottomTab = ref('diagnostics')
const outputTab = ref(initialGrammarState?.outputTab ?? 'sexp')
const shareStatus = ref('')
const lintActive = computed(() => Boolean(project.value) && packBottomTab.value === 'lint')
const {
  lintDiagnostics,
  lintOptions,
  lintRunning,
  lintStale,
  lintError,
  lintSourceSnapshot,
  lintRuleSets,
  runLint,
  setLintOptions,
  rejectLintFix,
} = useLintWorkbench(importedLanguage, tree, sourceCode, lintActive)

const isPackProject = computed(() => Boolean(project.value))
const isSourcePack = computed(() => project.value?.mode === 'source')
const isBundlePack = computed(() => project.value?.mode === 'bundle')
const selectedPackPath = computed(() => project.value?.selectedPath ?? null)
const selectedPackText = computed(() => {
  const path = selectedPackPath.value
  return path ? (project.value?.files?.[path] ?? '') : ''
})
const projectFileCount = computed(() => Object.keys(project.value?.files ?? {}).length)
const diagnosticErrorCount = computed(() =>
  projectDiagnostics.value.filter((item) => item.severity === 'error').length)
const projectHasErrors = computed(() =>
  hasErrorDiagnostics([...checkDiagnostics.value, ...buildDiagnostics.value]))

const currentPresetId = computed(() => {
  if (project.value) {
    const id = importedLanguage.value?.id
    if (id && BUILTIN_LANGUAGE_PRESETS.some((item) => item.id === id)) return id
    return id ?? 'custom'
  }
  return findBuiltinPresetByGrammar(grammarDsl.value)?.id ?? 'custom'
})

const comparisonLanguageId = computed(() => {
  if (project.value?.mode === 'source') {
    try {
      const manifest = JSON.parse(project.value.files['language-pack.json'] ?? '{}')
      return typeof manifest.id === 'string' && manifest.id ? manifest.id : 'unknown'
    } catch {
      return 'unknown'
    }
  }
  if (project.value?.mode === 'bundle') {
    try {
      const bundle = JSON.parse(project.value.bundleJson ?? '{}')
      return typeof bundle.pack?.id === 'string' && bundle.pack.id ? bundle.pack.id : 'unknown'
    } catch {
      return 'unknown'
    }
  }
  return findBuiltinPresetByGrammar(grammarDsl.value)?.id ?? 'custom'
})

const queryModeSuggestions = computed(() => {
  if (project.value?.mode === 'source') {
    try {
      const manifest = JSON.parse(project.value.files['language-pack.json'])
      const queries = manifest.queries ?? {}
      return {
        locals: queries.locals ? (project.value.files[queries.locals] ?? '') : '',
        bindings: queries.bindings ? (project.value.files[queries.bindings] ?? '') : '',
        folding: queries.folding ? (project.value.files[queries.folding] ?? '') : '',
      }
    } catch {
      return {}
    }
  }
  if (project.value?.mode === 'bundle') {
    const queries = importedLanguage.value?.bundle?.queries ?? {}
    return {
      locals: queries.locals ?? '',
      bindings: queries.bindings ?? '',
      folding: queries.folding ?? '',
    }
  }
  const preset = findBuiltinPresetByGrammar(grammarDsl.value)
  return {
    locals: preset?.localsQuery ?? '',
    bindings: preset?.bindingsQuery ?? '',
    folding: preset?.foldingQuery ?? '',
  }
})

const projectName = computed(() => {
  if (!project.value) return ''
  if (project.value.mode === 'bundle') return importedLanguage.value?.name ?? 'Language Bundle'
  try {
    return JSON.parse(project.value.files['language-pack.json']).name ?? 'Language Pack'
  } catch {
    return 'Language Pack'
  }
})

const projectStatus = computed(() => {
  if (!project.value) return ''
  if (project.value.mode === 'bundle') return 'Bundle · read-only'
  const parts = [`${projectFileCount.value} files`]
  if (project.value.dirty) parts.push('dirty')
  if (buildStale.value) parts.push('build stale')
  if (previewStale.value) parts.push('preview stale')
  if (corpusStale.value) parts.push('corpus stale')
  return parts.join(' · ')
})

const lastBundlePretty = computed(() => {
  const json = lastBundleJson.value
  if (!json) return ''
  try {
    return JSON.stringify(JSON.parse(json), null, 2)
  } catch {
    return json
  }
})

const bundlePretty = computed(() => {
  const json = project.value?.bundleJson ?? lastBundleJson.value
  if (!json) return ''
  try {
    return JSON.stringify(JSON.parse(json), null, 2)
  } catch {
    return json
  }
})

const mobileTabs = computed(() => isPackProject.value
  ? [
      { key: 'pack', label: 'Pack' },
      { key: 'source', label: 'Source' },
      { key: 'tree', label: 'CST' },
      { key: 'query', label: 'Query' },
      { key: 'output', label: 'Output' },
      { key: 'lint', label: 'Lint' },
    ]
  : [
      { key: 'editor', label: 'Editor' },
      { key: 'tree', label: 'CST' },
      { key: 'query', label: 'Query' },
      { key: 'output', label: 'Output' },
    ])

const { highlightRanges } = useHighlight(mp, tree, hlQueryStr, currentPresetId, sourceCode)
const { dslErrors } = useGrammarValidation(grammarDsl)

provide('mp', mp)

const sexp = computed(() => {
  try { return tree.value?.sexp() ?? '' } catch { return '' }
})

const version = computed(() => {
  try { return mp.value?.version() ?? '-' } catch { return '-' }
})

const isMobile = ref(window.innerWidth <= 768)
const mobileTab = ref(0)

function onResize() {
  isMobile.value = window.innerWidth <= 768
}

onMounted(() => window.addEventListener('resize', onResize))
onUnmounted(() => {
  window.removeEventListener('resize', onResize)
  if (shareStatusTimer) clearTimeout(shareStatusTimer)
})

watch(mobileTabs, () => {
  if (mobileTab.value >= mobileTabs.value.length) mobileTab.value = 0
})

function onSourceChange(value) {
  sourceCode.value = value
}

function onEdit(inputEdit) {
  triggerEdit(inputEdit)
}

function clearSourceHighlight() {
  selectedRange.value = null
  editorPanelRef.value?.clearHighlight?.()
}

function resetQueryDebugger() {
  queryMode.value = 'query'
  queryModePatterns.value = { locals: '', bindings: '', folding: '' }
  bindingGraph.value = {
    uri: '', scopes: [], definitions: [], references: [], edges: [], diagnostics: [],
  }
}

function shouldKeepSourceHighlight(target) {
  return target instanceof Element &&
    Boolean(target.closest('.tree-node') || target.closest('.query-result'))
}

function onPlaygroundPointerDown(event) {
  if (!shouldKeepSourceHighlight(event.target)) clearSourceHighlight()
}

function applyCustomPreset() {
  grammarDsl.value = ''
  sourceCode.value = ''
  queryPattern.value = ''
  querySuggestion.value = ''
  resetQueryDebugger()
  hlQueryStr.value = ''
  previewTab.value = 'source'
  packBottomTab.value = 'diagnostics'
  outputTab.value = 'sexp'
  mobileTab.value = 0
  clearSourceHighlight()
}

function syncProjectPreview(preferredPresetId = null, { resetQueries = true } = {}) {
  if (!project.value) return
  if (resetQueries) {
    queryPattern.value = ''
    resetQueryDebugger()
    outputTab.value = 'sexp'
  }
  previewTab.value = 'source'
  mobileTab.value = 0
  clearSourceHighlight()

  if (project.value.mode === 'bundle') {
    grammarDsl.value = ''
    hlQueryStr.value = ''
    querySuggestion.value = ''
    return
  }

  try {
    const manifest = JSON.parse(project.value.files['language-pack.json'])
    grammarDsl.value = project.value.files[manifest.grammar?.path] ?? ''
    hlQueryStr.value = manifest.queries?.highlights
      ? (project.value.files[manifest.queries.highlights] ?? '')
      : ''
    const preset = BUILTIN_LANGUAGE_PRESETS.find((item) => item.id === (preferredPresetId ?? manifest.id))
    if (preset) {
      sourceCode.value = preset.source
      querySuggestion.value = preset.query ?? ''
    } else {
      querySuggestion.value = ''
    }
  } catch {
    grammarDsl.value = ''
    hlQueryStr.value = ''
    querySuggestion.value = ''
  }
}

function cloneState(state) {
  return typeof structuredClone === 'function'
    ? structuredClone(state)
    : JSON.parse(JSON.stringify(state))
}

function resetSharedUiState(state) {
  queryPattern.value = state.query ?? ''
  queryMode.value = state.queryMode ?? 'query'
  queryModePatterns.value = state.queryModePatterns ?? { locals: '', bindings: '', folding: '' }
  incrementalTraceEnabled.value = Boolean(state.incrementalTraceEnabled)
  previewTab.value = state.previewTab ?? 'source'
  packBottomTab.value = state.packBottomTab ?? 'diagnostics'
  outputTab.value = state.outputTab ?? 'sexp'
  if (state.kind === 'source-pack' || state.kind === 'bundle') {
    mobileTab.value = packBottomTab.value === 'lint'
      ? 5
      : ({ source: 1, tree: 2, query: 3, output: 4 }[previewTab.value] ?? 0)
  } else {
    mobileTab.value = { tree: 1, query: 2, output: 3 }[previewTab.value] ?? 0
  }
  clearSourceHighlight()
  bindingGraph.value = {
    uri: '', scopes: [], definitions: [], references: [], edges: [], diagnostics: [],
  }
}

function createShareState() {
  const base = {
    v: 2,
    kind: project.value?.mode === 'source'
      ? 'source-pack'
      : (project.value?.mode === 'bundle' ? 'bundle' : 'grammar'),
    grammar: grammarDsl.value,
    source: sourceCode.value,
    query: queryPattern.value,
    highlight: hlQueryStr.value,
    queryMode: queryMode.value,
    queryModePatterns: queryModePatterns.value,
    incrementalTraceEnabled: incrementalTraceEnabled.value,
    previewTab: previewTab.value,
    packBottomTab: packBottomTab.value,
    outputTab: outputTab.value,
    project: null,
  }
  if (project.value?.mode === 'source') {
    base.project = {
      files: project.value.files,
      selectedPath: project.value.selectedPath,
      mode: 'source',
      bundleJson: null,
    }
  } else if (project.value?.mode === 'bundle') {
    base.project = {
      files: {},
      selectedPath: null,
      mode: 'bundle',
      bundleJson: project.value.bundleJson,
    }
  }
  return base
}

async function applySharedState(state, { confirm = true } = {}) {
  if (!state) return false
  if (state.kind === 'grammar') {
    if (project.value && !leaveProject()) return false
    grammarDsl.value = state.grammar || DEFAULT_PRESET.grammar
    sourceCode.value = state.source || ''
    hlQueryStr.value = state.highlight ?? ''
    const preset = findBuiltinPresetByGrammar(grammarDsl.value)
    querySuggestion.value = state.query ? '' : (preset?.query ?? '')
    resetSharedUiState(state)
    return true
  }

  if (!mp.value || !state.project) return false
  const restored = await restoreProjectSnapshot(state.project, { confirm, build: true })
  if (!restored) return false
  syncProjectPreview(null, { resetQueries: false })
  if (typeof state.source === 'string') sourceCode.value = state.source
  resetSharedUiState(state)
  return true
}

let shareStatusTimer = null

function setShareStatus(message) {
  shareStatus.value = message
  if (shareStatusTimer) clearTimeout(shareStatusTimer)
  shareStatusTimer = window.setTimeout(() => {
    if (shareStatus.value === message) shareStatus.value = ''
  }, 2400)
}

async function onCopyShareUrl() {
  try {
    const url = await flushState(createShareState())
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(url)
      setShareStatus('Share URL copied.')
    } else {
      setShareStatus('Share URL updated in address bar.')
    }
  } catch (error) {
    setShareStatus(`Share failed: ${error?.message ?? String(error)}`)
  }
}

async function onDemoChange(event) {
  const id = event.target.value
  event.target.value = ''
  const scenario = findDemoScenario(id)
  if (!scenario) return
  if (await applySharedState(cloneState(scenario.state))) {
    setShareStatus(`Demo loaded: ${scenario.name}`)
  }
}

async function applyPreset(id) {
  if (PACK_PRESET_IDS.has(id)) {
    if (await selectPresetProject(id)) syncProjectPreview(id)
    return
  }
  if (!leaveProject()) return
  if (id === 'custom') {
    applyCustomPreset()
    return
  }
  const preset = BUILTIN_LANGUAGE_PRESETS.find((item) => item.id === id)
  if (!preset) return
  grammarDsl.value = preset.grammar
  sourceCode.value = preset.source
  queryPattern.value = ''
  resetQueryDebugger()
  querySuggestion.value = preset.query ?? ''
  hlQueryStr.value = preset.highlightQuery ?? ''
  previewTab.value = 'source'
  packBottomTab.value = 'diagnostics'
  outputTab.value = 'sexp'
  mobileTab.value = 0
  clearSourceHighlight()
}

async function onImportProjectFile(event) {
  const file = event.target.files?.[0]
  event.target.value = ''
  if (!file || !mp.value) return
  if (await importProjectFile(file)) syncProjectPreview()
}

async function onImportDirectory(event) {
  const files = event.target.files
  event.target.value = ''
  if (!files?.length || !mp.value) return
  if (await importDirectory(files)) syncProjectPreview()
}

async function onNewProject() {
  if (await createNewProject()) {
    sourceCode.value = 'hello world'
    syncProjectPreview()
  }
}

async function onPackPresetChange(event) {
  const id = event.target.value
  event.target.value = ''
  if (id && await selectPresetProject(id)) syncProjectPreview(id)
}

function setProjectUiError(error) {
  projectImportError.value = error?.message ?? String(error)
}

function onExportProject() {
  try {
    exportSourceProject()
  } catch (error) {
    setProjectUiError(error)
  }
}

async function onCheckProject() {
  await checkProject()
}

async function onBuildProject() {
  if (await buildProject()) syncProjectPreview(null, { resetQueries: false })
}

async function onRunCorpus(focusCaseKey = null) {
  await runCorpusProject({ focusCaseKey })
}

function onSelectCorpusCase(key) {
  selectedCorpusKey.value = key
}

async function onRerunCorpusCase(key) {
  await runCorpusProject({ focusCaseKey: key })
}

async function onUpdateSelectedSnapshot() {
  await rewriteSelectedCorpusSnapshot()
}

async function onUpdateAllSnapshots() {
  await rewriteAllCorpusSnapshots()
}

function onDownloadBundleArtifact() {
  downloadBundleArtifact()
}

function onDownloadVsixArtifact() {
  downloadVsixArtifact()
}

function onMobileTab(index, tab) {
  mobileTab.value = index
  if (tab?.key === 'lint') packBottomTab.value = 'lint'
  else if (packBottomTab.value === 'lint') packBottomTab.value = 'diagnostics'
}

async function onApplyLintFix(diagnostic) {
  if (!diagnostic?.fix) return
  if (lintSourceSnapshot.value !== sourceCode.value) {
    rejectLintFix('Quick Fix rejected because the source changed after lint ran.')
    return
  }
  previewTab.value = 'source'
  if (isMobile.value) mobileTab.value = 1
  await nextTick()
  const applied = editorPanelRef.value?.applyTextEdit?.(
    diagnostic.fix.edit,
    lintSourceSnapshot.value,
  )
  if (!applied) rejectLintFix('Quick Fix rejected because its UTF-8 range is stale or invalid.')
}

function onPresetChange(event) {
  void applyPreset(event.target.value)
}

function onSelect(range) {
  selectedRange.value = {
    startByte: Math.max(0, Number(range?.startByte) || 0),
    endByte: Math.max(0, Number(range?.endByte) || 0),
  }
  if (selectedRange.value.startByte > selectedRange.value.endByte) {
    const start = selectedRange.value.startByte
    selectedRange.value.startByte = selectedRange.value.endByte
    selectedRange.value.endByte = start
  }
  previewTab.value = 'source'
  nextTick(() => editorPanelRef.value?.highlightRange(
    selectedRange.value.startByte,
    selectedRange.value.endByte,
  ))
}

function onSourceSelect(range) {
  selectedRange.value = range
}

function onBindingsResult(graph) {
  bindingGraph.value = graph
}

function onSelectPackFile(path) {
  try {
    selectFile(path)
    nextTick(() => packFileEditorRef.value?.focus())
  } catch (error) {
    setProjectUiError(error)
  }
}

function onCreatePackFile(path) {
  try {
    createFile(path, '')
  } catch (error) {
    setProjectUiError(error)
  }
}

function onRenamePackFile({ oldPath, newPath }) {
  try {
    renameFile(oldPath, newPath)
  } catch (error) {
    setProjectUiError(error)
  }
}

function onDeletePackFile(path) {
  try {
    deleteFile(path)
  } catch (error) {
    setProjectUiError(error)
  }
}

function onUpdateSelectedPackFile(text) {
  const path = selectedPackPath.value
  if (!path) return
  try {
    updateFile(path, text)
  } catch (error) {
    setProjectUiError(error)
  }
}

function onDiagnosticClick(diagnostic) {
  if (!project.value || !isFileDiagnostic(diagnostic, project.value.files)) return
  const path = diagnosticPath(diagnostic)
  try {
    selectFile(path)
    packBottomTab.value = 'diagnostics'
    nextTick(() => {
      packFileEditorRef.value?.focusPosition(diagnosticLine(diagnostic), diagnosticColumn(diagnostic))
    })
  } catch (error) {
    setProjectUiError(error)
  }
}

function diagnosticLabel(diagnostic) {
  return diagnosticDisplayLocation(diagnostic) || diagnosticPath(diagnostic) || '<project>'
}

watch(grammarDsl, (value) => {
  if (project.value) return
  const preset = findBuiltinPresetByGrammar(value)
  if (preset) hlQueryStr.value = preset.highlightQuery ?? ''
})

watch(
  [
    project,
    grammarDsl,
    sourceCode,
    queryPattern,
    hlQueryStr,
    queryMode,
    queryModePatterns,
    incrementalTraceEnabled,
    previewTab,
    packBottomTab,
    outputTab,
  ],
  () => saveState(createShareState()),
)

watch([mp, pendingSharedState], ([api, state]) => {
  if (!state) return
  if (state.kind !== 'grammar' && !api) return
  pendingSharedState.value = null
  void applySharedState(state, { confirm: false })
}, { immediate: true })

useKeyboard({
  onRunQuery: () => queryPanelRef.value?.runQuery(),
  onForceParse: () => {
    if (parser.value && sourceCode.value != null) triggerEdit(null)
  },
  onFocusPanel: (index) => {
    if (isMobile.value) {
      mobileTab.value = index
    } else if (index === 0) {
      editorPanelRef.value?.focus()
    }
  },
})
</script>

<template>
  <div class="playground" @pointerdown.capture="onPlaygroundPointerDown">
    <div v-if="loading" class="playground-loading">
      <span class="spinner" />
      <span>Loading MoonParse WASM...</span>
    </div>

    <div v-else-if="mpError" class="playground-fatal">
      <strong>MoonParse failed to load:</strong>{{ mpError }}
    </div>

    <template v-else>
      <div class="playground-toolbar">
        <div class="playground-toolbar-copy">
          <span class="playground-toolbar-kicker">Language Workbench</span>
          <strong>{{ project ? projectName : 'Grammar Playground' }}</strong>
          <small v-if="project" class="project-status">{{ projectStatus }}</small>
        </div>

        <div class="project-actions">
          <button type="button" class="project-action" :disabled="projectBusy" @click="onNewProject">
            New Pack
          </button>
          <label class="project-action project-action-select">
            <span>Pack preset</span>
            <select value="" :disabled="projectBusy" @change="onPackPresetChange">
              <option value="" disabled>Select...</option>
              <option value="json">JSON</option>
              <option value="python">Python</option>
              <option value="moonbit">MoonBit</option>
            </select>
          </label>
          <label class="project-action project-file-action">
            Import directory
            <input
              class="project-file-input"
              type="file"
              webkitdirectory
              multiple
              :disabled="projectBusy"
              @change="onImportDirectory"
            >
          </label>
          <label class="project-action project-file-action">
            Import ZIP / Bundle
            <input
              class="project-file-input"
              type="file"
              accept=".zip,.json,application/zip,application/json"
              :disabled="projectBusy"
              @change="onImportProjectFile"
            >
          </label>
          <button
            v-if="isSourcePack"
            type="button"
            class="project-action"
            :disabled="projectBusy"
            @click="onCheckProject"
          >
            Check Pack
          </button>
          <button
            v-if="isSourcePack"
            type="button"
            class="project-action project-action-primary"
            :disabled="projectBusy || projectHasErrors"
            @click="onBuildProject"
          >
            Build Pack
          </button>
          <button
            v-if="isSourcePack"
            type="button"
            class="project-action"
            :disabled="projectBusy"
            @click="onExportProject"
          >
            Export source ZIP
          </button>
          <label class="project-action project-action-select">
            <span>Demo</span>
            <select value="" :disabled="projectBusy" @change="onDemoChange">
              <option value="" disabled>Select...</option>
              <option v-for="demo in DEMO_SCENARIOS" :key="demo.id" :value="demo.id">
                {{ demo.name }}
              </option>
            </select>
          </label>
          <button
            type="button"
            class="project-action"
            :disabled="projectBusy"
            @click="onCopyShareUrl"
          >
            Copy Share URL
          </button>
        </div>

        <label class="playground-toolbar-field">
          <span>Grammar</span>
          <select :value="currentPresetId" @change="onPresetChange">
            <option value="custom">Custom grammar</option>
            <option v-for="preset in BUILTIN_LANGUAGE_PRESETS" :key="preset.id" :value="preset.id">
              {{ preset.name }}
            </option>
          </select>
        </label>

        <div class="playground-toolbar-chips">
          <button
            v-for="preset in BUILTIN_LANGUAGE_PRESETS"
            :key="preset.id"
            type="button"
            class="preset-chip"
            :class="{ active: currentPresetId === preset.id }"
            @click="applyPreset(preset.id)"
          >
            {{ preset.name }}
          </button>
        </div>

        <div v-if="projectImportError" class="project-message project-message-error">
          {{ projectImportError }}
        </div>
        <div v-if="shareStatus" class="project-message">
          {{ shareStatus }}
        </div>
        <div v-if="!projectImportError && projectDiagnostics.length" class="project-message">
          {{ projectDiagnostics.length }} Pack diagnostics · {{ diagnosticErrorCount }} errors
        </div>
      </div>

      <template v-if="isMobile">
        <div class="playground-mobile-tabs" role="tablist">
          <button
            v-for="(tab, index) in mobileTabs"
            :key="tab.key"
            class="playground-mobile-tab"
            :class="{ active: mobileTab === index }"
            role="tab"
            :aria-selected="mobileTab === index"
            @click="onMobileTab(index, tab)"
          >{{ tab.label }}</button>
        </div>

        <div class="playground-mobile-content">
          <template v-if="isPackProject">
            <div class="playground-mobile-panel" :class="{ active: mobileTab === 0 }">
              <div v-if="isSourcePack" class="mobile-pack-editor">
                <PackFileTree
                  :files="project.files"
                  :selected-path="selectedPackPath"
                  @select="onSelectPackFile"
                  @create="onCreatePackFile"
                  @rename="onRenamePackFile"
                  @delete="onDeletePackFile"
                />
                <PackFileEditor
                  ref="packFileEditorRef"
                  :path="selectedPackPath"
                  :text="selectedPackText"
                  @update:text="onUpdateSelectedPackFile"
                />
              </div>
              <pre v-else class="bundle-viewer">{{ bundlePretty }}</pre>
            </div>
            <div class="playground-mobile-panel" :class="{ active: mobileTab === 1 }">
              <EditorPanel
                ref="editorPanelRef"
                :model-value="sourceCode"
                :grammar="grammarDsl"
                :syntax-ranges="highlightRanges"
                :selected-range="selectedRange"
                :incremental-trace="incrementalTrace"
                :parser-error="parserError"
                :show-grammar="false"
                @update:model-value="onSourceChange"
                @edit="onEdit"
                @select="onSourceSelect"
              />
            </div>
            <div class="playground-mobile-panel" :class="{ active: mobileTab === 2 }">
              <TreePanel :tree="tree" :selected-range="selectedRange" :incremental-trace="incrementalTrace" @select="onSelect" />
            </div>
            <div class="playground-mobile-panel" :class="{ active: mobileTab === 3 }">
              <QueryPanel
                ref="queryPanelRef"
                :model-value="queryPattern"
                :mode="queryMode"
                :mode-patterns="queryModePatterns"
                :tree="tree"
                :suggestion="querySuggestion"
                :mode-suggestions="queryModeSuggestions"
                :selected-range="selectedRange"
                @update:model-value="queryPattern = $event"
                @update:mode="queryMode = $event"
                @update:mode-patterns="queryModePatterns = $event"
                @bindings-result="onBindingsResult"
                @select="onSelect"
              />
            </div>
            <div class="playground-mobile-panel" :class="{ active: mobileTab === 4 }">
              <OutputPanel
                :tree="tree"
                :source="sourceCode"
                :language-id="comparisonLanguageId"
                :parser="parser"
                :parse-time="parseTime"
                :is-incremental="isIncremental"
                :parser-error="parserError"
                :trace-enabled="incrementalTraceEnabled"
                :incremental-trace="incrementalTrace"
                :active-tab="outputTab"
                @update:trace-enabled="incrementalTraceEnabled = $event"
                @update:active-tab="outputTab = $event"
              />
            </div>
            <div class="playground-mobile-panel" :class="{ active: mobileTab === 5 }">
              <LintPanel
                :diagnostics="lintDiagnostics"
                :rule-sets="lintRuleSets"
                :options="lintOptions"
                :running="lintRunning"
                :stale="lintStale"
                :error="lintError"
                @run="runLint"
                @select="onSelect"
                @apply-fix="onApplyLintFix"
                @update:options="setLintOptions"
              />
            </div>
          </template>

          <template v-else>
            <div class="playground-mobile-panel" :class="{ active: mobileTab === 0 }">
              <EditorPanel
                ref="editorPanelRef"
                :model-value="sourceCode"
                :grammar="grammarDsl"
                :syntax-ranges="highlightRanges"
                :selected-range="selectedRange"
                :incremental-trace="incrementalTrace"
                :parser-error="parserError"
                :dsl-validation-errors="dslErrors"
                @update:model-value="onSourceChange"
                @update:grammar="grammarDsl = $event"
                @edit="onEdit"
                @select="onSourceSelect"
              />
            </div>
            <div class="playground-mobile-panel" :class="{ active: mobileTab === 1 }">
              <TreePanel :tree="tree" :selected-range="selectedRange" :incremental-trace="incrementalTrace" @select="onSelect" />
            </div>
            <div class="playground-mobile-panel" :class="{ active: mobileTab === 2 }">
              <QueryPanel
                ref="queryPanelRef"
                :model-value="queryPattern"
                :mode="queryMode"
                :mode-patterns="queryModePatterns"
                :tree="tree"
                :suggestion="querySuggestion"
                :mode-suggestions="queryModeSuggestions"
                :selected-range="selectedRange"
                @update:model-value="queryPattern = $event"
                @update:mode="queryMode = $event"
                @update:mode-patterns="queryModePatterns = $event"
                @bindings-result="onBindingsResult"
                @select="onSelect"
              />
            </div>
            <div class="playground-mobile-panel" :class="{ active: mobileTab === 3 }">
              <OutputPanel
                :tree="tree"
                :source="sourceCode"
                :language-id="comparisonLanguageId"
                :parser="parser"
                :parse-time="parseTime"
                :is-incremental="isIncremental"
                :parser-error="parserError"
                :trace-enabled="incrementalTraceEnabled"
                :incremental-trace="incrementalTrace"
                :active-tab="outputTab"
                @update:trace-enabled="incrementalTraceEnabled = $event"
                @update:active-tab="outputTab = $event"
              />
            </div>
          </template>
        </div>
      </template>

      <template v-else>
        <div v-if="isPackProject" class="pack-workbench">
          <div class="pack-main-grid">
            <PackFileTree
              v-if="isSourcePack"
              :files="project.files"
              :selected-path="selectedPackPath"
              @select="onSelectPackFile"
              @create="onCreatePackFile"
              @rename="onRenamePackFile"
              @delete="onDeletePackFile"
            />
            <PackFileEditor
              v-if="isSourcePack"
              ref="packFileEditorRef"
              :path="selectedPackPath"
              :text="selectedPackText"
              @update:text="onUpdateSelectedPackFile"
            />
            <section v-if="isBundlePack" class="bundle-panel panel">
              <div class="panel-header">
                <span class="panel-title">Bundle JSON</span>
                <span class="pack-readonly">Read-only</span>
              </div>
              <pre class="bundle-viewer">{{ bundlePretty }}</pre>
            </section>

            <section class="pack-preview panel">
              <div class="panel-header pack-preview-header">
                <span class="panel-title">Preview</span>
                <span v-if="previewStale" class="preview-stale">Preview is stale; rebuild Pack.</span>
                <div class="panel-tabs panel-tabs-right">
                  <button class="tab-btn" :class="{ 'tab-btn--active': previewTab === 'source' }" @click="previewTab = 'source'">Source</button>
                  <button class="tab-btn" :class="{ 'tab-btn--active': previewTab === 'tree' }" @click="previewTab = 'tree'">CST</button>
                  <button class="tab-btn" :class="{ 'tab-btn--active': previewTab === 'query' }" @click="previewTab = 'query'">Query</button>
                  <button class="tab-btn" :class="{ 'tab-btn--active': previewTab === 'output' }" @click="previewTab = 'output'">Output</button>
                </div>
              </div>
              <div class="pack-preview-body">
                <EditorPanel
                  v-if="previewTab === 'source'"
                  ref="editorPanelRef"
                  :model-value="sourceCode"
                  :grammar="grammarDsl"
                  :syntax-ranges="highlightRanges"
                  :selected-range="selectedRange"
                  :incremental-trace="incrementalTrace"
                  :parser-error="parserError"
                  :show-grammar="false"
                  @update:model-value="onSourceChange"
                  @edit="onEdit"
                  @select="onSourceSelect"
                />
                <TreePanel
                  v-else-if="previewTab === 'tree'"
                  :tree="tree"
                  :selected-range="selectedRange"
                  :incremental-trace="incrementalTrace"
                  @select="onSelect"
                />
                <QueryPanel
                  v-else-if="previewTab === 'query'"
                  ref="queryPanelRef"
                  :model-value="queryPattern"
                  :mode="queryMode"
                  :mode-patterns="queryModePatterns"
                  :tree="tree"
                  :suggestion="querySuggestion"
                  :mode-suggestions="queryModeSuggestions"
                  :selected-range="selectedRange"
                  @update:model-value="queryPattern = $event"
                  @update:mode="queryMode = $event"
                  @update:mode-patterns="queryModePatterns = $event"
                  @bindings-result="onBindingsResult"
                  @select="onSelect"
                />
                <OutputPanel
                  v-else
                  :tree="tree"
                  :source="sourceCode"
                  :language-id="comparisonLanguageId"
                  :parser="parser"
                  :parse-time="parseTime"
                  :is-incremental="isIncremental"
                  :parser-error="parserError"
                  :trace-enabled="incrementalTraceEnabled"
                  :incremental-trace="incrementalTrace"
                  :active-tab="outputTab"
                  @update:trace-enabled="incrementalTraceEnabled = $event"
                  @update:active-tab="outputTab = $event"
                />
              </div>
            </section>
          </div>

          <section class="pack-bottom panel">
            <div class="panel-header">
              <div class="panel-tabs">
                <button class="tab-btn" :class="{ 'tab-btn--active': packBottomTab === 'diagnostics' }" @click="packBottomTab = 'diagnostics'">Diagnostics</button>
                <button class="tab-btn" :class="{ 'tab-btn--active': packBottomTab === 'corpus' }" @click="packBottomTab = 'corpus'">Corpus</button>
                <button class="tab-btn" :class="{ 'tab-btn--active': packBottomTab === 'lint' }" @click="packBottomTab = 'lint'">Lint</button>
                <button class="tab-btn" :class="{ 'tab-btn--active': packBottomTab === 'artifact' }" @click="packBottomTab = 'artifact'">Build Artifact</button>
              </div>
              <span class="pack-bottom-status">
                check {{ projectChecking ? 'running' : 'idle' }} · build {{ buildStatus }} · corpus {{ corpusRunning ? 'running' : (corpusStale ? 'stale' : 'idle') }}
              </span>
            </div>

            <div v-if="packBottomTab === 'diagnostics'" class="pack-diagnostics">
              <div v-if="projectDiagnostics.length === 0" class="pack-empty">
                No Pack diagnostics.
              </div>
              <button
                v-for="(diagnostic, index) in projectDiagnostics"
                :key="`${diagnostic.code}:${diagnostic.path}:${diagnostic.line}:${diagnostic.column}:${index}`"
                type="button"
                class="pack-diagnostic"
                :class="`pack-diagnostic-${diagnostic.severity}`"
                :disabled="!isFileDiagnostic(diagnostic, project.files)"
                @click="onDiagnosticClick(diagnostic)"
              >
                <span class="diag-severity">{{ diagnostic.severity }}</span>
                <span class="diag-code">{{ diagnostic.code }}</span>
                <span class="diag-location">{{ diagnosticLabel(diagnostic) }}</span>
                <span class="diag-message">{{ diagnostic.message }}</span>
              </button>
            </div>

            <CorpusPanel
              v-else-if="packBottomTab === 'corpus'"
              :files="project.files"
              :cases="corpusCases"
              :diagnostics="corpusDiagnostics"
              :elapsed-ms="corpusElapsedMs"
              :stale="corpusStale"
              :running="corpusRunning"
              :selected-key="selectedCorpusKey"
              :run-revision="corpusRunRevision"
              :project-revision="projectRevision"
              :format="corpusFormat"
              @run="onRunCorpus"
              @run-case="onRerunCorpusCase"
              @select="onSelectCorpusCase"
              @update-selected="onUpdateSelectedSnapshot"
              @update-all="onUpdateAllSnapshots"
            />

            <LintPanel
              v-else-if="packBottomTab === 'lint'"
              :diagnostics="lintDiagnostics"
              :rule-sets="lintRuleSets"
              :options="lintOptions"
              :running="lintRunning"
              :stale="lintStale"
              :error="lintError"
              @run="runLint"
              @select="onSelect"
              @apply-fix="onApplyLintFix"
              @update:options="setLintOptions"
            />

            <div v-else class="pack-artifact">
              <div class="artifact-actions">
                <button
                  type="button"
                  class="project-action project-action-primary"
                  :disabled="!canDownloadBundle"
                  @click="onDownloadBundleArtifact"
                >
                  Download {{ bundleFileName || 'Bundle JSON' }}
                </button>
                <button
                  type="button"
                  class="project-action"
                  :disabled="!canDownloadVsix"
                  @click="onDownloadVsixArtifact"
                >
                  Download {{ vsixFileName || 'VSIX' }}
                </button>
                <span v-if="!canDownloadBundle" class="artifact-hint">
                  Build must be successful, current, and verified before artifact download.
                </span>
                <span v-else class="artifact-hint">
                  Downloads validate Bundle round-trip registration first.
                </span>
              </div>
              <div v-if="!lastBundlePretty" class="pack-empty">
                Build the Pack to view the generated Bundle JSON.
              </div>
              <pre v-else>{{ lastBundlePretty }}</pre>
            </div>
          </section>
        </div>

        <div v-else class="playground-frame">
          <SplitPane direction="vertical" :initial-split="0.55" class="playground-split">
            <template #first>
              <SplitPane direction="horizontal" :initial-split="0.5" style="height:100%">
                <template #first>
                  <EditorPanel
                    ref="editorPanelRef"
                    :model-value="sourceCode"
                    :grammar="grammarDsl"
                    :syntax-ranges="highlightRanges"
                    :selected-range="selectedRange"
                    :incremental-trace="incrementalTrace"
                    :parser-error="parserError"
                    :dsl-validation-errors="dslErrors"
                    @update:model-value="onSourceChange"
                    @update:grammar="grammarDsl = $event"
                    @edit="onEdit"
                    @select="onSourceSelect"
                  />
                </template>
                <template #second>
                  <TreePanel :tree="tree" :selected-range="selectedRange" :incremental-trace="incrementalTrace" @select="onSelect" />
                </template>
              </SplitPane>
            </template>

            <template #second>
              <SplitPane direction="horizontal" :initial-split="0.45" style="height:100%">
                <template #first>
                  <QueryPanel
                    ref="queryPanelRef"
                    :model-value="queryPattern"
                    :mode="queryMode"
                    :mode-patterns="queryModePatterns"
                    :tree="tree"
                    :suggestion="querySuggestion"
                    :mode-suggestions="queryModeSuggestions"
                    :selected-range="selectedRange"
                    @update:model-value="queryPattern = $event"
                    @update:mode="queryMode = $event"
                    @update:mode-patterns="queryModePatterns = $event"
                    @bindings-result="onBindingsResult"
                    @select="onSelect"
                  />
                </template>
                <template #second>
                  <OutputPanel
                    :tree="tree"
                    :source="sourceCode"
                    :language-id="comparisonLanguageId"
                    :parser="parser"
                    :parse-time="parseTime"
                    :is-incremental="isIncremental"
                    :parser-error="parserError"
                    :trace-enabled="incrementalTraceEnabled"
                    :incremental-trace="incrementalTrace"
                    :active-tab="outputTab"
                    @update:trace-enabled="incrementalTraceEnabled = $event"
                    @update:active-tab="outputTab = $event"
                  />
                </template>
              </SplitPane>
            </template>
          </SplitPane>
        </div>
      </template>
    </template>

    <PerfBar
      v-if="!loading && !mpError"
      :parse-time="parseTime"
      :is-incremental="isIncremental"
      :sexp="sexp"
      :version="version"
      :parser-error="parserError"
      :building="workspaceBuilding"
    />
  </div>
</template>

<style scoped>
.playground {
  height: calc(100vh - 64px);
  display: flex;
  flex-direction: column;
  overflow: hidden;
  background: transparent;
}

.playground-toolbar {
  display: grid;
  grid-template-columns: minmax(180px, auto) minmax(0, 1fr) auto;
  align-items: center;
  gap: 14px;
  margin: 18px 20px 0;
  padding: 12px 14px;
  border: 1px solid var(--line);
  border-radius: var(--radius-lg);
  background: var(--surface);
  box-shadow: var(--shadow-sm);
}

.playground-toolbar-copy {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}

.playground-toolbar-kicker {
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--text-soft);
}

.playground-toolbar-copy strong {
  font-size: 14px;
  color: var(--text-h);
}

.project-status {
  color: var(--text-soft);
  font-size: 11px;
}

.project-actions {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
  flex-wrap: wrap;
}

.project-action {
  position: relative;
  min-height: 34px;
  padding: 0 10px;
  border: 1px solid var(--line);
  border-radius: var(--radius-md);
  background: var(--surface-2);
  color: var(--text-muted);
  font: inherit;
  font-size: 12px;
  cursor: pointer;
}

.project-action-primary {
  color: var(--accent);
  border-color: var(--accent-border);
  background: var(--accent-bg);
}

.project-action:hover:not(:disabled) {
  border-color: var(--line-strong);
  color: var(--text-h);
}

.project-action:disabled {
  cursor: not-allowed;
  opacity: 0.55;
}

.project-action-select {
  display: inline-flex;
  align-items: center;
  gap: 6px;
}

.project-action-select select {
  max-width: 110px;
  border: none;
  background: transparent;
  color: inherit;
  font: inherit;
}

.project-file-action {
  display: inline-flex;
  align-items: center;
}

.project-file-input {
  position: absolute;
  width: 1px;
  height: 1px;
  opacity: 0;
  pointer-events: none;
}

.project-message {
  grid-column: 1 / -1;
  padding: 8px 10px;
  border-radius: var(--radius-md);
  background: var(--surface-2);
  color: var(--text-muted);
  font-size: 12px;
}

.project-message-error {
  border: 1px solid color-mix(in srgb, #f44747 45%, transparent);
  color: #f44747;
}

.playground-toolbar-field {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  min-width: 0;
}

.playground-toolbar-field span {
  font-size: 12px;
  color: var(--text-soft);
  white-space: nowrap;
}

.playground-toolbar-field select {
  min-width: 180px;
  height: 36px;
  padding: 0 12px;
  border: 1px solid var(--line);
  border-radius: var(--radius-md);
  background: var(--surface-2);
  color: var(--text-h);
}

.playground-toolbar-chips {
  grid-column: 1 / -1;
  display: flex;
  gap: 8px;
  min-width: 0;
  overflow-x: auto;
  padding-bottom: 2px;
}

.preset-chip {
  flex: 0 0 auto;
  min-height: 32px;
  padding: 0 10px;
  border: 1px solid var(--line);
  border-radius: var(--radius-md);
  background: var(--surface-2);
  color: var(--text-muted);
  font-size: 12px;
  font-weight: 500;
  cursor: pointer;
}

.preset-chip:hover {
  color: var(--text-h);
  border-color: var(--line-strong);
  background: var(--surface-3);
}

.preset-chip.active {
  color: var(--accent);
  border-color: var(--accent-border);
  background: var(--accent-bg);
}

.playground-frame,
.pack-workbench {
  flex: 1;
  min-height: 0;
  margin: 14px 20px 0;
}

.playground-frame {
  border-radius: var(--radius-lg);
  padding: 1px;
  background: linear-gradient(180deg, var(--line-strong) 0%, var(--line) 100%);
  box-shadow: var(--shadow-sm);
  overflow: hidden;
}

.playground-split {
  flex: 1;
  min-height: 0;
  height: 100%;
  border-radius: calc(var(--radius-lg) - 1px);
  background: var(--surface);
  overflow: hidden;
}

.pack-workbench {
  display: grid;
  grid-template-rows: minmax(0, 1fr) minmax(160px, 220px);
  gap: 10px;
}

.pack-main-grid {
  min-height: 0;
  display: grid;
  grid-template-columns: minmax(180px, 240px) minmax(280px, 1fr) minmax(320px, 0.9fr);
  gap: 10px;
}

.bundle-panel {
  grid-column: 1 / span 2;
  min-width: 0;
  overflow: hidden;
  display: flex;
  flex-direction: column;
}

.bundle-viewer,
.pack-artifact pre {
  flex: 1;
  min-height: 0;
  margin: 0;
  padding: 12px;
  overflow: auto;
  color: var(--text-muted);
  font-family: var(--mono);
  font-size: 12px;
  white-space: pre;
}

.pack-readonly {
  margin-left: auto;
  border: 1px solid var(--line);
  border-radius: 999px;
  padding: 2px 7px;
  color: var(--text-soft);
  font-size: 10px;
}

.pack-preview {
  min-width: 0;
  overflow: hidden;
  display: flex;
  flex-direction: column;
}

.pack-preview-header {
  gap: 8px;
}

.preview-stale {
  color: #f4b747;
  font-size: 11px;
}

.panel-tabs-right {
  margin-left: auto;
}

.pack-preview-body {
  flex: 1;
  min-height: 0;
  overflow: hidden;
}

.pack-bottom {
  min-height: 0;
  overflow: hidden;
  display: flex;
  flex-direction: column;
}

.pack-bottom-status {
  margin-left: auto;
  color: var(--text-soft);
  font-size: 11px;
}

.pack-diagnostics {
  flex: 1;
  overflow: auto;
  padding: 6px;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.pack-diagnostic {
  display: grid;
  grid-template-columns: 70px 90px minmax(180px, 260px) minmax(0, 1fr);
  gap: 8px;
  align-items: baseline;
  border: 1px solid var(--line);
  border-radius: var(--radius-sm);
  background: var(--surface-2);
  color: var(--text-muted);
  padding: 6px 8px;
  text-align: left;
  font: inherit;
  font-size: 12px;
  cursor: pointer;
}

.pack-diagnostic:disabled {
  cursor: default;
  opacity: 0.8;
}

.pack-diagnostic-error .diag-severity {
  color: #f44747;
}

.pack-diagnostic-warning .diag-severity,
.pack-diagnostic-warn .diag-severity {
  color: #f4b747;
}

.diag-code,
.diag-location {
  color: var(--text-soft);
  font-family: var(--mono);
}

.diag-message {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pack-empty {
  padding: 18px;
  color: var(--text-soft);
  font-size: 12px;
}

.pack-artifact {
  flex: 1;
  min-height: 0;
  overflow: hidden;
  display: flex;
  flex-direction: column;
}

.artifact-actions {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 10px;
  padding: 8px;
  border-bottom: 1px solid var(--line);
}

.artifact-hint {
  color: var(--text-soft);
  font-size: 11px;
}

.playground-loading,
.playground-fatal {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 12px;
  font-size: 15px;
  color: var(--text);
}

.playground-fatal {
  color: #f44747;
  padding: 32px;
  text-align: center;
}

.spinner {
  display: inline-block;
  width: 20px;
  height: 20px;
  border: 2px solid var(--border);
  border-top-color: var(--accent);
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

.playground-mobile-tabs {
  display: flex;
  margin: 16px 12px 0;
  border: 1px solid var(--line);
  border-bottom: none;
  border-radius: var(--radius-lg) var(--radius-lg) 0 0;
  background: var(--surface-3);
  flex-shrink: 0;
  overflow-x: auto;
  -webkit-overflow-scrolling: touch;
}

.playground-mobile-tab {
  flex: 1;
  min-width: max-content;
  padding: 9px 14px;
  border: none;
  background: none;
  color: var(--text-muted);
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
  border-bottom: 2px solid transparent;
  white-space: nowrap;
}

.playground-mobile-tab.active {
  color: var(--accent);
  border-bottom-color: var(--accent);
  background: var(--surface);
}

.playground-mobile-content {
  flex: 1;
  min-height: 0;
  overflow: hidden;
  position: relative;
  margin: 0 12px;
  border: 1px solid var(--line);
  border-radius: 0 0 var(--radius-lg) var(--radius-lg);
  background: var(--surface);
}

.playground-mobile-panel {
  position: absolute;
  inset: 0;
  display: none;
  flex-direction: column;
}

.playground-mobile-panel.active {
  display: flex;
}

.mobile-pack-editor {
  flex: 1;
  min-height: 0;
  display: grid;
  grid-template-rows: minmax(120px, 35%) minmax(0, 1fr);
}

@media (max-width: 1100px) {
  .pack-main-grid {
    grid-template-columns: minmax(170px, 220px) minmax(260px, 1fr) minmax(280px, 0.9fr);
  }
}

@media (max-width: 980px) {
  .playground-toolbar {
    grid-template-columns: 1fr;
    align-items: stretch;
  }

  .playground-toolbar-field {
    justify-content: space-between;
  }

  .playground-toolbar-field select {
    width: 100%;
    min-width: 0;
  }
}
</style>
