import assert from 'node:assert/strict'
import test from 'node:test'
import { strToU8, zipSync } from 'fflate'
import { ref } from 'vue'

import {
  PROJECT_LIMITS,
  LanguagePackProjectError,
  createBundleProject,
  createMinimalProject,
  createProjectFile,
  createPresetProject,
  deleteProjectFile,
  exportProjectZip,
  importDirectoryFiles,
  importZip,
  isLanguageBundleObject,
  markProjectClean,
  normalizeProjectPath,
  replaceProject,
  renameProjectFile,
  selectProjectFile,
  updateProjectFile,
} from '../lib/languagePackProject.js'
import {
  createManifestJsonDiagnostic,
  sortPackDiagnostics,
} from '../lib/packDiagnostics.js'
import {
  bundleDownloadFileName,
  collectSnapshotUpdates,
  corpusSourceForCase,
  createLineDiff,
  parseCorpusCases,
} from '../lib/corpusWorkbench.js'
import { useLanguagePackProject } from '../composables/useLanguagePackProject.js'

function fileLike(path, value) {
  const bytes = typeof value === 'string' ? strToU8(value) : value
  return {
    name: path.split('/').at(-1),
    webkitRelativePath: path,
    size: bytes.byteLength,
    async arrayBuffer() {
      return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength)
    },
    async text() {
      return new TextDecoder().decode(bytes)
    },
  }
}

function minimalFiles(prefix = '') {
  const root = prefix ? `${prefix}/` : ''
  return [
    fileLike(`${root}language-pack.json`, '{"schemaVersion":1,"id":"roundtrip"}\n'),
    fileLike(`${root}grammar/main.grammar`, 'start document\nrule document: "ok"\n'),
    fileLike(`${root}corpus/basic.txt`, '====\nok\n====\nok\n----\nerror: ok\n'),
    fileLike(`${root}notes/说明.txt`, '你好，MoonParse。\n'),
  ]
}

test('path validation rejects unsafe and non-canonical paths', () => {
  assert.equal(normalizeProjectPath('grammar/main.grammar'), 'grammar/main.grammar')
  for (const path of ['', '/absolute', 'C:/absolute', 'a\\b', 'a//b', './a', 'a/../b', `a\0b`]) {
    assert.throws(() => normalizeProjectPath(path), LanguagePackProjectError)
  }
})

test('directory import strips the manifest root and round-trips ZIP text', async () => {
  const project = await importDirectoryFiles(minimalFiles('roundtrip-pack'))
  assert.equal(project.mode, 'source')
  assert.equal(project.dirty, false)
  assert.deepEqual(Object.keys(project.files).sort(), [
    'corpus/basic.txt',
    'grammar/main.grammar',
    'language-pack.json',
    'notes/说明.txt',
  ])
  const artifact = exportProjectZip(project)
  assert.equal(artifact.fileName, 'roundtrip-source.zip')
  const restored = await importZip(artifact.bytes)
  assert.deepEqual(restored.files, project.files)
})

test('directory import rejects duplicate, missing, multiple, and outside-root manifests', async () => {
  await assert.rejects(
    importDirectoryFiles([...minimalFiles('root'), fileLike('root/grammar/main.grammar', 'duplicate')]),
    { code: 'DUPLICATE_PATH' },
  )
  await assert.rejects(
    importDirectoryFiles([fileLike('root/grammar/main.grammar', 'start x')]),
    { code: 'MISSING_MANIFEST' },
  )
  await assert.rejects(
    importDirectoryFiles([
      ...minimalFiles('one'),
      fileLike('two/language-pack.json', '{}'),
    ]),
    { code: 'MULTIPLE_MANIFESTS' },
  )
  await assert.rejects(
    importDirectoryFiles([...minimalFiles('root'), fileLike('outside.txt', 'x')]),
    { code: 'FILES_OUTSIDE_ROOT' },
  )
})

test('directory import rejects invalid UTF-8 and configured limits', async () => {
  await assert.rejects(
    importDirectoryFiles([
      fileLike('root/language-pack.json', '{}'),
      fileLike('root/bad.txt', new Uint8Array([0xc3, 0x28])),
    ]),
    { code: 'INVALID_UTF8' },
  )
  await assert.rejects(
    importDirectoryFiles(minimalFiles('root'), { maxFiles: 2, maxFileBytes: 100, maxTotalBytes: 200 }),
    { code: 'TOO_MANY_FILES' },
  )
  await assert.rejects(
    importDirectoryFiles(minimalFiles('root'), { maxFiles: 10, maxFileBytes: 8, maxTotalBytes: 200 }),
    { code: 'FILE_TOO_LARGE' },
  )
  await assert.rejects(
    importDirectoryFiles(minimalFiles('root'), { maxFiles: 10, maxFileBytes: 200, maxTotalBytes: 20 }),
    { code: 'PROJECT_TOO_LARGE' },
  )
  assert.deepEqual(PROJECT_LIMITS, {
    maxFiles: 512,
    maxFileBytes: 2 * 1024 * 1024,
    maxTotalBytes: 10 * 1024 * 1024,
  })
})

test('production import limits reject 513 files, 2 MiB files, and 10 MiB projects', async () => {
  const tooMany = [fileLike('root/language-pack.json', '{}')]
  for (let index = 0; index < 512; index += 1) {
    tooMany.push(fileLike(`root/files/${index}.txt`, 'x'))
  }
  await assert.rejects(importDirectoryFiles(tooMany), { code: 'TOO_MANY_FILES' })

  const overFileLimit = new Uint8Array(PROJECT_LIMITS.maxFileBytes + 1)
  await assert.rejects(
    importDirectoryFiles([
      fileLike('root/language-pack.json', '{}'),
      fileLike('root/large.bin', overFileLimit),
    ]),
    { code: 'FILE_TOO_LARGE' },
  )

  const twoMiB = new Uint8Array(PROJECT_LIMITS.maxFileBytes)
  await assert.rejects(
    importDirectoryFiles([
      fileLike('root/language-pack.json', '{}'),
      fileLike('root/1.txt', twoMiB),
      fileLike('root/2.txt', twoMiB),
      fileLike('root/3.txt', twoMiB),
      fileLike('root/4.txt', twoMiB),
      fileLike('root/5.txt', twoMiB),
    ]),
    { code: 'PROJECT_TOO_LARGE' },
  )
})

test('ZIP filter rejects unsafe paths and declared uncompressed sizes', async () => {
  const unsafe = zipSync({
    '../language-pack.json': strToU8('{}'),
  })
  await assert.rejects(importZip(unsafe), { code: 'INVALID_PATH' })

  const oversized = zipSync({
    'root/language-pack.json': strToU8('{}'),
    'root/large.txt': new Uint8Array(32),
  })
  await assert.rejects(
    importZip(oversized, { maxFiles: 10, maxFileBytes: 16, maxTotalBytes: 100 }),
    { code: 'FILE_TOO_LARGE' },
  )

  const productionOversized = zipSync({
    'root/language-pack.json': strToU8('{}'),
    'root/large.txt': new Uint8Array(PROJECT_LIMITS.maxFileBytes + 1),
  })
  await assert.rejects(importZip(productionOversized), { code: 'FILE_TOO_LARGE' })
})

test('minimal and built-in projects have complete source state', () => {
  const minimal = createMinimalProject()
  assert.equal(minimal.dirty, true)
  assert.ok(minimal.files['grammar/main.grammar'])
  assert.ok(minimal.files['corpus/basic.txt'])
  for (const id of ['json', 'python', 'moonbit']) {
    const preset = createPresetProject(id)
    assert.equal(preset.dirty, false)
    assert.ok(preset.files['language-pack.json'])
    assert.ok(Object.keys(preset.files).some((path) => path.startsWith('corpus/')))
  }
})

test('source updates are immutable and Bundle projects are read-only', () => {
  const project = createMinimalProject()
  const changed = updateProjectFile(project, 'grammar/main.grammar', 'start changed')
  assert.notEqual(changed, project)
  assert.notEqual(changed.files, project.files)
  assert.equal(changed.dirty, true)
  assert.equal(markProjectClean(changed).dirty, false)

  const bundleObject = {
    schemaVersion: 1,
    pack: { id: 'test', version: '0.1.0' },
    grammarJson: '{}',
    parseTable: { json: '{}', binaryBase64: 'AA==' },
    queries: {},
    capabilities: {},
  }
  assert.equal(isLanguageBundleObject(bundleObject), true)
  const bundle = createBundleProject(JSON.stringify(bundleObject))
  assert.equal(bundle.mode, 'bundle')
  assert.equal(bundle.selectedPath, null)
  assert.throws(() => updateProjectFile(bundle, 'x', 'y'), { code: 'READ_ONLY_PROJECT' })
  assert.throws(() => createProjectFile(bundle, 'x', 'y'), { code: 'READ_ONLY_PROJECT' })
  assert.throws(() => renameProjectFile(bundle, 'x', 'y'), { code: 'READ_ONLY_PROJECT' })
  assert.throws(() => deleteProjectFile(bundle, 'x'), { code: 'READ_ONLY_PROJECT' })
  assert.throws(() => exportProjectZip(bundle), { code: 'READ_ONLY_PROJECT' })
})

test('source file create, select, rename, and delete are immutable and protect manifest', () => {
  const project = createMinimalProject()
  const created = createProjectFile(project, 'queries/highlights.scm', '(document) @keyword\n')
  assert.notEqual(created.files, project.files)
  assert.equal(created.selectedPath, 'queries/highlights.scm')
  assert.equal(created.files['queries/highlights.scm'], '(document) @keyword\n')

  const selected = selectProjectFile(created, 'grammar/main.grammar')
  assert.equal(selected.selectedPath, 'grammar/main.grammar')
  assert.equal(selected.files, created.files)

  const renamed = renameProjectFile(selected, 'queries/highlights.scm', 'queries/tags.scm')
  assert.equal(renamed.files['queries/highlights.scm'], undefined)
  assert.equal(renamed.files['queries/tags.scm'], '(document) @keyword\n')
  assert.equal(renamed.dirty, true)

  const deleted = deleteProjectFile(renamed, 'queries/tags.scm')
  assert.equal(deleted.files['queries/tags.scm'], undefined)
  assert.equal(deleted.selectedPath, 'grammar/main.grammar')
  assert.throws(() => renameProjectFile(project, 'language-pack.json', 'manifest.json'), { code: 'PROTECTED_FILE' })
  assert.throws(() => deleteProjectFile(project, 'language-pack.json'), { code: 'PROTECTED_FILE' })
})

test('pack diagnostics sort with errors first and local manifest parse errors are structured', () => {
  const sorted = sortPackDiagnostics([
    { severity: 'info', code: 'I', path: 'b', line: 0, column: 0, message: 'info' },
    { severity: 'error', code: 'E2', path: 'b', line: 1, column: 0, message: 'error 2' },
    { severity: 'warning', code: 'W', path: 'a', line: 0, column: 0, message: 'warn' },
    { severity: 'error', code: 'E1', path: 'a', line: 0, column: 1, message: 'error 1' },
  ])
  assert.deepEqual(sorted.map((item) => item.code), ['E1', 'E2', 'W', 'I'])

  const diagnostic = createManifestJsonDiagnostic('{\n  "id":\n}')
  assert.equal(diagnostic.severity, 'error')
  assert.equal(diagnostic.code, 'JSON_PARSE')
  assert.equal(diagnostic.path, 'language-pack.json')
  assert.equal(createManifestJsonDiagnostic('{"id":"ok"}'), null)
})

test('Corpus utilities diff, parse source, and aggregate snapshot updates deterministically', () => {
  assert.deepEqual(
    createLineDiff('a\nb', 'a\nb').map((line) => line.type),
    ['equal', 'equal'],
  )
  const inserted = createLineDiff('a\nb', 'a\nx\nb')
  assert.ok(inserted.some((line) => line.type === 'add' && line.text === 'x'))
  const replaced = createLineDiff('a\nb', 'a\ny')
  assert.ok(replaced.some((line) => line.type === 'remove' && line.text === 'b'))
  assert.ok(replaced.some((line) => line.type === 'add' && line.text === 'y'))

  const largeExpected = Array.from({ length: 2501 }, (_, index) => `left-${index}`).join('\n')
  const largeActual = Array.from({ length: 2501 }, (_, index) => `right-${index}`).join('\n')
  assert.ok(createLineDiff(largeExpected, largeActual).some((line) => line.type === 'omitted'))

  const corpusText = [
    '====',
    'utf8 case',
    '====',
    'print("你好")',
    '----',
    'error: ok',
    'sexp:',
    '  (document)',
    '====',
    'second',
    '====',
    '42',
    '----',
    'error: ok',
    '',
  ].join('\n')
  const parsed = parseCorpusCases('corpus/basic.txt', corpusText)
  assert.equal(parsed.length, 2)
  assert.equal(parsed[0].source, 'print("你好")')
  assert.equal(parsed[0].expectedSexp, '(document)')
  assert.equal(
    corpusSourceForCase({ 'corpus/basic.txt': corpusText }, {
      path: 'corpus/basic.txt',
      name: 'second',
      sourceLine: parsed[1].sourceLine,
    }),
    '42',
  )

  const files = {
    'corpus/one.txt': corpusText,
    'corpus/two.txt': corpusText.replace('utf8 case', 'other file'),
  }
  const cases = [
    {
      path: 'corpus/one.txt',
      caseIndex: 0,
      name: 'utf8 case',
      sourceLine: parsed[0].sourceLine,
      actualSexp: '(new-one)',
      failures: [{ kind: 'Sexp', expected: '(old)', actual: '(new-one)' }],
      passed: false,
    },
    {
      path: 'corpus/two.txt',
      caseIndex: 1,
      name: 'other file',
      sourceLine: parsed[0].sourceLine,
      actualSexp: '(new-two)',
      failures: [{ kind: 'sexp', expected: '(old)', actual: '(new-two)' }],
      passed: false,
    },
    {
      path: 'corpus/two.txt',
      caseIndex: 2,
      name: 'second',
      sourceLine: parsed[1].sourceLine,
      actualSexp: '(second)',
      failures: [{ kind: 'contains', expected: '(missing)' }],
      passed: false,
    },
  ]
  const groups = collectSnapshotUpdates(cases, files, { all: true })
  assert.deepEqual(groups.map((group) => group.path), ['corpus/one.txt', 'corpus/two.txt'])
  assert.equal(groups[0].updates[0].caseIndex, 0)
  assert.equal(groups[1].updates[0].caseIndex, 0)
  assert.equal(groups[1].updates[0].caseName, 'other file')
  assert.equal(bundleDownloadFileName('{"pack":{"id":"my pack/!"}}'), 'my-pack.language-bundle.json')
})

test('dirty project replacement is transactional', () => {
  const current = createMinimalProject()
  const next = createPresetProject('json')
  const cancelled = replaceProject(current, next, () => false)
  assert.equal(cancelled.accepted, false)
  assert.equal(cancelled.project, current)
  const accepted = replaceProject(current, next, () => true)
  assert.equal(accepted.accepted, true)
  assert.equal(accepted.project, next)
})

test('project composable preserves or frees parser resources transactionally', async () => {
  let allowDiscard = true
  const freed = []
  const built = []
  let cleanup = null
  const mp = ref({
    checkPack() {
      return { ok: true, diagnostics: [] }
    },
    buildPack(files) {
      const id = JSON.parse(files['language-pack.json']).id
      built.push(id)
      return {
        ok: true,
        diagnostics: [],
        language: { id, free() { freed.push(id) } },
      }
    },
  })
  const state = useLanguagePackProject(mp, {
    confirmDiscard: () => allowDiscard,
    registerCleanup: (callback) => { cleanup = callback },
  })
  assert.equal(await state.selectPresetProject('json'), true)
  state.updateFile('grammar/main.grammar', 'changed')
  allowDiscard = false
  assert.equal(await state.selectPresetProject('python'), false)
  assert.deepEqual(built, ['json'])
  assert.deepEqual(freed, [])

  allowDiscard = true
  const invalid = fileLike('invalid.zip', new Uint8Array([1, 2, 3]))
  assert.equal(await state.importProjectFile(invalid), false)
  assert.equal(state.language.value.id, 'json')
  assert.deepEqual(freed, [])

  assert.equal(await state.selectPresetProject('python'), true)
  assert.deepEqual(freed, ['json'])
  cleanup()
  assert.deepEqual(freed, ['json', 'python'])
})

test('Bundle activation is authoritative and source build failures enter repair mode', async () => {
  const freed = []
  const mp = ref({
    checkPack() {
      return { ok: true, diagnostics: [] }
    },
    buildPack(files) {
      const id = JSON.parse(files['language-pack.json']).id
      if (id === 'python') {
        return { ok: false, diagnostics: [{ severity: 'error', message: 'broken' }], language: null }
      }
      return { ok: true, diagnostics: [], language: { id, free() { freed.push(id) } } }
    },
    loadBundle(bundleJson) {
      const bundle = JSON.parse(bundleJson)
      if (bundle.pack.id === 'rejected') throw new Error('authoritative rejection')
      const id = bundle.pack.id
      return { id, free() { freed.push(id) } }
    },
  })
  const state = useLanguagePackProject(mp, {
    confirmDiscard: () => true,
    registerCleanup: () => {},
  })
  await state.selectPresetProject('json')

  const bundle = {
    schemaVersion: 1,
    pack: { id: 'bundle-ok', version: '0.1.0' },
    grammarJson: '{}',
    parseTable: { json: '{}', binaryBase64: 'AA==' },
    queries: {},
    capabilities: {},
  }
  assert.equal(
    await state.importProjectFile(fileLike('bundle.json', JSON.stringify(bundle))),
    true,
  )
  assert.equal(state.project.value.mode, 'bundle')
  assert.deepEqual(freed, ['json'])

  bundle.pack.id = 'rejected'
  assert.equal(
    await state.importProjectFile(fileLike('rejected.json', JSON.stringify(bundle))),
    false,
  )
  assert.equal(state.language.value.id, 'bundle-ok')
  assert.deepEqual(freed, ['json'])

  assert.equal(await state.selectPresetProject('python'), true)
  assert.equal(state.project.value.mode, 'source')
  assert.equal(state.language.value, null)
  assert.equal(state.diagnostics.value[0].message, 'broken')
  assert.deepEqual(freed, ['json', 'bundle-ok'])
})

test('manifest JSON syntax errors skip checkPack and block build', async () => {
  let checkCalls = 0
  let buildCalls = 0
  const mp = ref({
    checkPack() {
      checkCalls += 1
      return { ok: true, diagnostics: [] }
    },
    buildPack(files) {
      buildCalls += 1
      const id = JSON.parse(files['language-pack.json']).id
      return { ok: true, diagnostics: [], language: { id, free() {} } }
    },
  })
  const state = useLanguagePackProject(mp, {
    confirmDiscard: () => true,
    registerCleanup: () => {},
  })
  await state.createNewProject()
  const checksAfterCreate = checkCalls
  const buildsAfterCreate = buildCalls

  state.updateFile('language-pack.json', '{')
  await state.checkProject()
  assert.equal(state.checkDiagnostics.value[0].code, 'JSON_PARSE')
  assert.equal(checkCalls, checksAfterCreate)
  assert.equal(await state.buildProject(), false)
  assert.equal(buildCalls, buildsAfterCreate)
})

test('warnings allow build and failed rebuild keeps stale preview language', async () => {
  const freed = []
  let failBuild = false
  let buildIndex = 0
  const mp = ref({
    checkPack() {
      return {
        ok: true,
        diagnostics: [{ severity: 'warning', code: 'PACK-W', path: 'language-pack.json', line: 0, column: 0, message: 'warn' }],
      }
    },
    buildPack(files) {
      const id = JSON.parse(files['language-pack.json']).id
      buildIndex += 1
      if (failBuild) {
        return {
          ok: false,
          diagnostics: [{ severity: 'error', code: 'PACK-E', path: 'grammar/main.grammar', line: 0, column: 0, message: 'broken' }],
          language: null,
        }
      }
      const languageId = `${id}-${buildIndex}`
      return {
        ok: true,
        diagnostics: [{ severity: 'warning', code: 'PACK-W', path: 'language-pack.json', line: 0, column: 0, message: 'warn' }],
        bundleJson: `{"pack":{"id":"${languageId}"}}`,
        language: { id: languageId, free() { freed.push(languageId) } },
      }
    },
  })
  const state = useLanguagePackProject(mp, {
    confirmDiscard: () => true,
    registerCleanup: () => {},
  })

  assert.equal(await state.selectPresetProject('json'), true)
  const firstLanguage = state.language.value
  assert.ok(firstLanguage.id.startsWith('json-'))
  assert.equal(state.previewStale.value, false)

  state.updateFile('grammar/main.grammar', 'start broken\n')
  assert.equal(state.buildStale.value, true)
  assert.equal(state.previewStale.value, true)

  failBuild = true
  assert.equal(await state.buildProject(), false)
  assert.equal(state.language.value, firstLanguage)
  assert.equal(state.previewStale.value, true)

  failBuild = false
  assert.equal(await state.buildProject(), true)
  assert.notEqual(state.language.value, firstLanguage)
  assert.equal(state.previewStale.value, false)
  assert.deepEqual(freed, [firstLanguage.id])
})

test('Corpus run state records cases, elapsed time, selected focus, and stale edits', async () => {
  let cleanup = null
  let runCalls = 0
  const corpusCase = {
    path: 'corpus/basic.txt',
    caseIndex: 0,
    name: 'basic document',
    sourceLine: 4,
    actualError: 'ok',
    actualSexp: '(document)',
    failures: [],
    passed: true,
  }
  const mp = ref({
    checkPack() {
      return { ok: true, diagnostics: [] }
    },
    buildPack(files) {
      const id = JSON.parse(files['language-pack.json']).id
      return {
        ok: true,
        diagnostics: [],
        bundleJson: `{"pack":{"id":"${id}"}}`,
        language: { id, free() {} },
      }
    },
    runCorpus() {
      runCalls += 1
      return {
        ok: true,
        diagnostics: [{ severity: 'warning', code: 'CORPUS-W', path: 'corpus/basic.txt', line: 0, column: 0, message: 'warn' }],
        cases: [corpusCase],
      }
    },
  })
  const state = useLanguagePackProject(mp, {
    confirmDiscard: () => true,
    registerCleanup: (callback) => { cleanup = callback },
  })
  await state.createNewProject()
  assert.equal(state.projectRevision.value, 0)
  assert.equal(state.lastBuildRevision.value, 0)

  assert.equal(await state.runCorpusProject(), true)
  assert.equal(runCalls, 1)
  assert.equal(state.corpusCases.value.length, 1)
  assert.equal(state.corpusDiagnostics.value[0].code, 'CORPUS-W')
  assert.equal(state.corpusRunRevision.value, state.projectRevision.value)
  assert.equal(state.corpusStale.value, false)
  assert.equal(state.selectedCorpusKey.value, 'corpus/basic.txt\u00000\u0000basic document')

  assert.equal(await state.runCorpusProject({ focusCaseKey: state.selectedCorpusKey.value }), true)
  assert.equal(runCalls, 2)
  state.updateFile('grammar/main.grammar', 'start changed\n')
  assert.equal(state.projectRevision.value, 1)
  assert.equal(state.corpusStale.value, true)
  cleanup()
})

function v2CorpusFiles() {
  const manifest = {
    schemaVersion: 1,
    id: 'v2-pack',
    name: 'V2 Pack',
    version: '0.1.0',
    entryRule: 'document',
    grammar: { path: 'grammar/main.grammar', format: 'dsl' },
    corpus: { directory: 'corpus', format: 'moonparse-corpus-v2' },
  }
  const caseText = (name) => [
    '====',
    name,
    '====',
    'x',
    '----',
    'error: ok',
    'sexp:',
    '  (old)',
    '',
  ].join('\n')
  return [
    fileLike('root/language-pack.json', `${JSON.stringify(manifest, null, 2)}\n`),
    fileLike('root/grammar/main.grammar', 'start document\nrule document: "x"\n'),
    fileLike('root/corpus/one.txt', caseText('one')),
    fileLike('root/corpus/two.txt', caseText('two')),
  ]
}

test('snapshot rewrite updates v2 files all-or-nothing and marks build/test stale', async () => {
  const requests = []
  const cases = [
    {
      path: 'corpus/one.txt',
      caseIndex: 0,
      name: 'one',
      sourceLine: 4,
      actualError: 'ok',
      actualSexp: '(new-one)',
      failures: [{ kind: 'sexp', expected: '(old)', actual: '(new-one)', message: 'snapshot mismatch' }],
      passed: false,
    },
    {
      path: 'corpus/two.txt',
      caseIndex: 1,
      name: 'two',
      sourceLine: 4,
      actualError: 'ok',
      actualSexp: '(new-two)',
      failures: [{ kind: 'sexp', expected: '(old)', actual: '(new-two)', message: 'snapshot mismatch' }],
      passed: false,
    },
  ]
  const mp = ref({
    checkPack() {
      return { ok: true, diagnostics: [] }
    },
    buildPack(files) {
      const id = JSON.parse(files['language-pack.json']).id
      return { ok: true, diagnostics: [], bundleJson: `{"pack":{"id":"${id}"}}`, language: { id, free() {} } }
    },
    runCorpus() {
      return { ok: true, diagnostics: [], cases }
    },
    rewriteCorpusSnapshots(request) {
      requests.push(request)
      return {
        ok: true,
        diagnostics: [],
        updatedText: request.text.replace('(old)', request.updates[0].sexp),
      }
    },
  })
  const state = useLanguagePackProject(mp, {
    confirmDiscard: () => true,
    registerCleanup: () => {},
  })
  assert.equal(await state.importDirectory(v2CorpusFiles()), true)
  assert.equal(await state.runCorpusProject(), true)

  assert.equal(await state.rewriteSelectedCorpusSnapshot(), true)
  assert.equal(requests.length, 1)
  assert.equal(requests[0].path, 'corpus/one.txt')
  assert.equal(requests[0].updates[0].caseIndex, 0)
  assert.match(state.project.value.files['corpus/one.txt'], /\(new-one\)/)
  assert.match(state.project.value.files['corpus/two.txt'], /\(old\)/)
  assert.equal(state.buildStale.value, true)
  assert.equal(state.corpusStale.value, true)

  requests.length = 0
  state.corpusStale.value = false
  assert.equal(await state.rewriteAllCorpusSnapshots(), true)
  assert.equal(requests.length, 2)
  assert.deepEqual(requests.map((request) => request.updates[0].caseIndex), [0, 0])
})

test('snapshot rewrite failure does not partially write project files', async () => {
  const originalTwo = v2CorpusFiles().find((file) => file.webkitRelativePath.endsWith('corpus/two.txt'))
  const cases = [
    {
      path: 'corpus/one.txt',
      caseIndex: 0,
      name: 'one',
      sourceLine: 4,
      actualSexp: '(new-one)',
      failures: [{ kind: 'sexp', expected: '(old)', actual: '(new-one)' }],
      passed: false,
    },
    {
      path: 'corpus/two.txt',
      caseIndex: 1,
      name: 'two',
      sourceLine: 4,
      actualSexp: '(new-two)',
      failures: [{ kind: 'sexp', expected: '(old)', actual: '(new-two)' }],
      passed: false,
    },
  ]
  const mp = ref({
    checkPack() {
      return { ok: true, diagnostics: [] }
    },
    buildPack(files) {
      const id = JSON.parse(files['language-pack.json']).id
      return { ok: true, diagnostics: [], language: { id, free() {} } }
    },
    runCorpus() {
      return { ok: true, diagnostics: [], cases }
    },
    rewriteCorpusSnapshots(request) {
      if (request.path === 'corpus/two.txt') {
        return {
          ok: false,
          diagnostics: [{ severity: 'error', code: 'SNAPSHOT', path: request.path, line: 0, column: 0, message: 'no match' }],
        }
      }
      return { ok: true, diagnostics: [], updatedText: request.text.replace('(old)', request.updates[0].sexp) }
    },
  })
  const state = useLanguagePackProject(mp, {
    confirmDiscard: () => true,
    registerCleanup: () => {},
  })
  assert.equal(await state.importDirectory(v2CorpusFiles()), true)
  assert.equal(await state.runCorpusProject(), true)
  const before = { ...state.project.value.files }
  assert.equal(await state.rewriteAllCorpusSnapshots(), false)
  assert.deepEqual(state.project.value.files, before)
  assert.equal(state.corpusDiagnostics.value[0].code, 'SNAPSHOT')
  assert.ok(await originalTwo.text())
})

test('Bundle artifact download requires current successful build and validates load/free round-trip', async () => {
  const loaded = []
  const freed = []
  const downloads = []
  const binaryDownloads = []
  const mp = ref({
    checkPack() {
      return { ok: true, diagnostics: [] }
    },
    buildPack(files) {
      const id = JSON.parse(files['language-pack.json']).id
      return {
        ok: true,
        diagnostics: [],
        bundleJson: JSON.stringify({
          schemaVersion: 1,
          pack: { id: `${id}-bundle`, version: '0.1.0' },
          grammarJson: '{}',
          parseTable: { json: '{}', binaryBase64: 'AA==' },
          queries: {},
          capabilities: {},
        }),
        language: { id, free() {} },
      }
    },
    loadBundle(bundleJson) {
      const id = JSON.parse(bundleJson).pack.id
      loaded.push(id)
      return { free() { freed.push(id) } }
    },
  })
  const state = useLanguagePackProject(mp, {
    confirmDiscard: () => true,
    registerCleanup: () => {},
    downloadText: (text, fileName, type) => downloads.push({ text, fileName, type }),
    downloadBinary: (bytes, fileName, type) => binaryDownloads.push({ bytes, fileName, type }),
  })
  assert.equal(await state.selectPresetProject('json'), true)
  assert.equal(state.canDownloadBundle.value, true)
  assert.equal(state.canDownloadVsix.value, true)
  assert.equal(state.downloadBundleArtifact(), true)
  assert.deepEqual(loaded, ['json-bundle'])
  assert.deepEqual(freed, ['json-bundle'])
  assert.equal(downloads[0].fileName, 'json-bundle.language-bundle.json')
  assert.equal(downloads[0].type, 'application/json')
  assert.equal(state.downloadVsixArtifact(), true)
  assert.deepEqual(loaded, ['json-bundle', 'json-bundle'])
  assert.deepEqual(freed, ['json-bundle', 'json-bundle'])
  assert.equal(binaryDownloads[0].fileName, 'json-bundle-vscode.vsix')
  assert.equal(binaryDownloads[0].type, 'application/vsix')
  assert.ok(binaryDownloads[0].bytes instanceof Uint8Array)

  state.updateFile('grammar/main.grammar', 'start stale\n')
  assert.equal(state.canDownloadBundle.value, false)
  assert.equal(state.canDownloadVsix.value, false)
  assert.equal(state.downloadBundleArtifact(), false)
  assert.equal(state.downloadVsixArtifact(), false)
})

test('VSIX artifact download does not fire when bundle round-trip validation fails', async () => {
  const binaryDownloads = []
  const state = useLanguagePackProject(ref({
    checkPack() {
      return { ok: true, diagnostics: [] }
    },
    buildPack() {
      return {
        ok: true,
        diagnostics: [],
        bundleJson: JSON.stringify({
          schemaVersion: 1,
          pack: { id: 'broken', version: '0.1.0' },
          grammarJson: '{}',
          parseTable: { json: '{}', binaryBase64: 'AA==' },
          queries: {},
          capabilities: {},
        }),
        language: { free() {} },
      }
    },
    loadBundle() {
      throw new Error('round-trip failed')
    },
  }), {
    confirmDiscard: () => true,
    registerCleanup: () => {},
    downloadBinary: (bytes, fileName, type) => binaryDownloads.push({ bytes, fileName, type }),
  })

  assert.equal(await state.selectPresetProject('json'), true)
  assert.equal(state.canDownloadVsix.value, true)
  assert.equal(state.downloadVsixArtifact(), false)
  assert.equal(binaryDownloads.length, 0)
  assert.equal(state.importError.value, 'round-trip failed')
})

test('out-of-order checkPack results do not overwrite newer diagnostics', async () => {
  let asyncChecks = false
  const pending = []
  const mp = ref({
    checkPack() {
      if (!asyncChecks) return { ok: true, diagnostics: [] }
      let resolve
      const promise = new Promise((done) => { resolve = done })
      pending.push(resolve)
      return promise
    },
    buildPack(files) {
      const id = JSON.parse(files['language-pack.json']).id
      return { ok: true, diagnostics: [], language: { id, free() {} } }
    },
  })
  const state = useLanguagePackProject(mp, {
    confirmDiscard: () => true,
    registerCleanup: () => {},
  })
  await state.createNewProject()

  asyncChecks = true
  state.updateFile('grammar/main.grammar', 'start one\n')
  const oldCheck = state.checkProject()
  state.updateFile('grammar/main.grammar', 'start two\n')
  const newCheck = state.checkProject()
  assert.equal(pending.length, 2)

  pending[1]({
    ok: true,
    diagnostics: [{ severity: 'warning', code: 'NEW', path: 'grammar/main.grammar', line: 0, column: 0, message: 'new' }],
  })
  await newCheck
  assert.equal(state.checkDiagnostics.value[0].code, 'NEW')

  pending[0]({
    ok: false,
    diagnostics: [{ severity: 'error', code: 'OLD', path: 'grammar/main.grammar', line: 0, column: 0, message: 'old' }],
  })
  await oldCheck
  assert.equal(state.checkDiagnostics.value[0].code, 'NEW')
})
