import { strToU8, unzipSync, zipSync } from 'fflate'
import { LANGUAGE_PACK_RESOURCES } from '../data/languagePackResources.js'

export const PROJECT_LIMITS = Object.freeze({
  maxFiles: 512,
  maxFileBytes: 2 * 1024 * 1024,
  maxTotalBytes: 10 * 1024 * 1024,
})

export const MANIFEST_PATH = 'language-pack.json'
const ZIP_MTIME = new Date('1980-01-01T00:00:00.000Z')
const utf8Decoder = new TextDecoder('utf-8', { fatal: true })

export class LanguagePackProjectError extends Error {
  constructor(code, message) {
    super(message)
    this.name = 'LanguagePackProjectError'
    this.code = code
  }
}

function projectError(code, message) {
  return new LanguagePackProjectError(code, message)
}

export function normalizeProjectPath(path) {
  if (typeof path !== 'string' || path.length === 0) {
    throw projectError('INVALID_PATH', 'Project path must not be empty.')
  }
  if (path.includes('\0')) {
    throw projectError('INVALID_PATH', `Project path contains NUL: ${JSON.stringify(path)}`)
  }
  if (path.includes('\\')) {
    throw projectError('INVALID_PATH', `Project path must use '/': ${path}`)
  }
  if (path.startsWith('/') || /^[A-Za-z]:\//.test(path)) {
    throw projectError('INVALID_PATH', `Absolute project path is not allowed: ${path}`)
  }
  const parts = path.split('/')
  if (parts.some((part) => part === '' || part === '.' || part === '..')) {
    throw projectError('INVALID_PATH', `Invalid project path segment: ${path}`)
  }
  return parts.join('/')
}

function assertLimits(entries, limits = PROJECT_LIMITS) {
  if (entries.length > limits.maxFiles) {
    throw projectError('TOO_MANY_FILES', `Pack contains ${entries.length} files; maximum is ${limits.maxFiles}.`)
  }
  let total = 0
  for (const entry of entries) {
    const size = entry.bytes.byteLength
    if (size > limits.maxFileBytes) {
      throw projectError('FILE_TOO_LARGE', `${entry.path} is ${size} bytes; maximum is ${limits.maxFileBytes}.`)
    }
    total += size
    if (total > limits.maxTotalBytes) {
      throw projectError('PROJECT_TOO_LARGE', `Pack is larger than ${limits.maxTotalBytes} uncompressed bytes.`)
    }
  }
}

function stripProjectRoot(entries) {
  const manifestPaths = entries
    .map((entry) => entry.path)
    .filter((path) => path === MANIFEST_PATH || path.endsWith(`/${MANIFEST_PATH}`))
  if (manifestPaths.length === 0) {
    throw projectError('MISSING_MANIFEST', `Pack must contain ${MANIFEST_PATH}.`)
  }
  if (manifestPaths.length !== 1) {
    throw projectError('MULTIPLE_MANIFESTS', `Pack contains ${manifestPaths.length} ${MANIFEST_PATH} files.`)
  }
  const manifestPath = manifestPaths[0]
  const suffixLength = MANIFEST_PATH.length
  const root = manifestPath.length === suffixLength
    ? ''
    : manifestPath.slice(0, manifestPath.length - suffixLength - 1)
  if (root && entries.some((entry) => !entry.path.startsWith(`${root}/`))) {
    throw projectError('FILES_OUTSIDE_ROOT', `All Pack files must be under the manifest directory '${root}'.`)
  }
  return entries.map((entry) => ({
    ...entry,
    path: root ? entry.path.slice(root.length + 1) : entry.path,
  }))
}

function decodeImportedEntries(entries, limits = PROJECT_LIMITS) {
  assertLimits(entries, limits)
  const normalized = entries.map((entry) => ({
    path: normalizeProjectPath(entry.path),
    bytes: entry.bytes,
  }))
  const rooted = stripProjectRoot(normalized)
  const files = {}
  for (const entry of rooted) {
    const path = normalizeProjectPath(entry.path)
    if (Object.prototype.hasOwnProperty.call(files, path)) {
      throw projectError('DUPLICATE_PATH', `Duplicate project path after normalization: ${path}`)
    }
    try {
      files[path] = utf8Decoder.decode(entry.bytes)
    } catch {
      throw projectError('INVALID_UTF8', `Project file is not valid UTF-8: ${path}`)
    }
  }
  return files
}

function validateSourceFiles(files) {
  if (files == null || typeof files !== 'object' || Array.isArray(files)) {
    throw projectError('INVALID_FILES', 'Project files must be an object.')
  }
  const result = {}
  for (const [rawPath, text] of Object.entries(files)) {
    const path = normalizeProjectPath(rawPath)
    if (typeof text !== 'string') {
      throw projectError('INVALID_FILE', `Project file must contain text: ${path}`)
    }
    if (Object.prototype.hasOwnProperty.call(result, path)) {
      throw projectError('DUPLICATE_PATH', `Duplicate project path: ${path}`)
    }
    result[path] = text
  }
  if (!Object.prototype.hasOwnProperty.call(result, MANIFEST_PATH)) {
    throw projectError('MISSING_MANIFEST', `Pack must contain ${MANIFEST_PATH}.`)
  }
  return result
}

export function createSourceProject(files, { selectedPath = MANIFEST_PATH, dirty = false } = {}) {
  const validated = validateSourceFiles(files)
  const selected = selectedPath == null ? MANIFEST_PATH : normalizeProjectPath(selectedPath)
  if (!Object.prototype.hasOwnProperty.call(validated, selected)) {
    throw projectError('MISSING_SELECTED_FILE', `Selected project file does not exist: ${selected}`)
  }
  return {
    files: validated,
    selectedPath: selected,
    mode: 'source',
    bundleJson: null,
    dirty: Boolean(dirty),
  }
}

export function createMinimalProject() {
  const manifest = {
    schemaVersion: 1,
    id: 'my-language',
    name: 'My Language',
    version: '0.1.0',
    maturity: 'experimental',
    entryRule: 'document',
    extensions: ['.my'],
    compatibility: {
      minimumMoonParseVersion: '0.1.0',
      maximumMoonParseVersionExclusive: '0.2.0',
    },
    grammar: { path: 'grammar/main.grammar', format: 'dsl' },
    corpus: { directory: 'corpus', format: 'moonparse-corpus-v1' },
    build: { allowAmbiguousConflicts: false },
  }
  return createSourceProject({
    [MANIFEST_PATH]: `${JSON.stringify(manifest, null, 2)}\n`,
    'grammar/main.grammar': 'start document\nrule document: word*\nrule word: /[A-Za-z]+/\nextras [/\\s+/]\n',
    'corpus/basic.txt': '====\nbasic document\n====\nhello world\n----\nerror: ok\nsexp-contains:\n  document\n',
  }, { dirty: true })
}

export function createPresetProject(id) {
  const resource = LANGUAGE_PACK_RESOURCES[id]
  if (!resource?.files) {
    throw projectError('UNKNOWN_PRESET', `Unknown Language Pack preset: ${id}`)
  }
  return createSourceProject(resource.files, { dirty: false })
}

function assertSourceProject(project) {
  if (project?.mode !== 'source') {
    throw projectError('READ_ONLY_PROJECT', 'Language Bundle projects are read-only.')
  }
}

function assertExistingFile(project, path) {
  if (!Object.prototype.hasOwnProperty.call(project.files, path)) {
    throw projectError('MISSING_FILE', `Project file does not exist: ${path}`)
  }
}

function assertNewFile(project, path) {
  if (Object.prototype.hasOwnProperty.call(project.files, path)) {
    throw projectError('DUPLICATE_PATH', `Project file already exists: ${path}`)
  }
}

export function selectProjectFile(project, rawPath) {
  assertSourceProject(project)
  const path = normalizeProjectPath(rawPath)
  assertExistingFile(project, path)
  return {
    ...project,
    selectedPath: path,
  }
}

export function createProjectFile(project, rawPath, text = '') {
  assertSourceProject(project)
  const path = normalizeProjectPath(rawPath)
  if (typeof text !== 'string') {
    throw projectError('INVALID_FILE', `Project file must contain text: ${path}`)
  }
  assertNewFile(project, path)
  return {
    ...project,
    files: { ...project.files, [path]: text },
    selectedPath: path,
    dirty: true,
  }
}

export function updateProjectFile(project, rawPath, text) {
  assertSourceProject(project)
  const path = normalizeProjectPath(rawPath)
  if (typeof text !== 'string') {
    throw projectError('INVALID_FILE', `Project file must contain text: ${path}`)
  }
  assertExistingFile(project, path)
  return {
    ...project,
    files: { ...project.files, [path]: text },
    selectedPath: path,
    dirty: true,
  }
}

export function renameProjectFile(project, rawOldPath, rawNewPath) {
  assertSourceProject(project)
  const oldPath = normalizeProjectPath(rawOldPath)
  const newPath = normalizeProjectPath(rawNewPath)
  assertExistingFile(project, oldPath)
  if (oldPath === MANIFEST_PATH) {
    throw projectError('PROTECTED_FILE', `${MANIFEST_PATH} cannot be renamed.`)
  }
  if (oldPath === newPath) return project
  assertNewFile(project, newPath)
  const files = {}
  for (const path of Object.keys(project.files)) {
    files[path === oldPath ? newPath : path] = project.files[path]
  }
  return {
    ...project,
    files,
    selectedPath: project.selectedPath === oldPath ? newPath : project.selectedPath,
    dirty: true,
  }
}

export function deleteProjectFile(project, rawPath) {
  assertSourceProject(project)
  const path = normalizeProjectPath(rawPath)
  assertExistingFile(project, path)
  if (path === MANIFEST_PATH) {
    throw projectError('PROTECTED_FILE', `${MANIFEST_PATH} cannot be deleted.`)
  }
  const files = { ...project.files }
  delete files[path]
  const selectedPath = project.selectedPath === path
    ? (Object.prototype.hasOwnProperty.call(files, MANIFEST_PATH)
      ? MANIFEST_PATH
      : (Object.keys(files).sort()[0] ?? null))
    : project.selectedPath
  return {
    ...project,
    files,
    selectedPath,
    dirty: true,
  }
}

export function markProjectClean(project) {
  return project == null ? project : { ...project, dirty: false }
}

export function replaceProject(current, next, confirmDiscard = () => true) {
  if (current?.dirty && !confirmDiscard(current)) {
    return { accepted: false, project: current }
  }
  return { accepted: true, project: next }
}

async function readBlobBytes(file) {
  return new Uint8Array(await file.arrayBuffer())
}

export async function importDirectoryFiles(fileList, limits = PROJECT_LIMITS) {
  const input = Array.from(fileList ?? [])
  if (input.length === 0) {
    throw projectError('EMPTY_IMPORT', 'No files were selected.')
  }
  if (input.length > limits.maxFiles) {
    throw projectError('TOO_MANY_FILES', `Pack contains ${input.length} files; maximum is ${limits.maxFiles}.`)
  }
  let declaredTotal = 0
  for (const file of input) {
    if (file.size > limits.maxFileBytes) {
      throw projectError('FILE_TOO_LARGE', `${file.webkitRelativePath || file.name} is too large.`)
    }
    declaredTotal += file.size
    if (declaredTotal > limits.maxTotalBytes) {
      throw projectError('PROJECT_TOO_LARGE', `Pack is larger than ${limits.maxTotalBytes} bytes.`)
    }
  }
  const entries = []
  for (const file of input) {
    entries.push({
      path: file.webkitRelativePath || file.name,
      bytes: await readBlobBytes(file),
    })
  }
  return createSourceProject(decodeImportedEntries(entries, limits), { dirty: false })
}

function asUint8Array(value) {
  if (value instanceof Uint8Array) return value
  if (value instanceof ArrayBuffer) return new Uint8Array(value)
  return null
}

export async function importZip(value, limits = PROJECT_LIMITS) {
  const archive = asUint8Array(value) ?? await readBlobBytes(value)
  let declaredCount = 0
  let declaredTotal = 0
  let rejected = null
  const archivePaths = new Set()
  let decompressed
  try {
    decompressed = unzipSync(archive, {
      filter(file) {
        if (file.name.endsWith('/')) return false
        declaredCount += 1
        if (archivePaths.has(file.name)) {
          rejected ??= projectError('DUPLICATE_PATH', `Duplicate ZIP entry: ${file.name}`)
          return false
        }
        archivePaths.add(file.name)
        try {
          normalizeProjectPath(file.name)
        } catch (error) {
          rejected ??= error
          return false
        }
        if (!Number.isSafeInteger(file.originalSize) || file.originalSize < 0) {
          rejected ??= projectError('UNKNOWN_FILE_SIZE', `ZIP entry has no usable uncompressed size: ${file.name}`)
          return false
        }
        if (declaredCount > limits.maxFiles) {
          rejected ??= projectError('TOO_MANY_FILES', `Pack contains more than ${limits.maxFiles} files.`)
          return false
        }
        if (file.originalSize > limits.maxFileBytes) {
          rejected ??= projectError('FILE_TOO_LARGE', `${file.name} is too large.`)
          return false
        }
        declaredTotal += file.originalSize
        if (declaredTotal > limits.maxTotalBytes) {
          rejected ??= projectError('PROJECT_TOO_LARGE', `Pack is larger than ${limits.maxTotalBytes} bytes.`)
          return false
        }
        return true
      },
    })
  } catch (error) {
    if (error instanceof LanguagePackProjectError) throw error
    throw projectError('INVALID_ZIP', `Cannot read ZIP archive: ${error?.message ?? String(error)}`)
  }
  if (rejected) throw rejected
  const entries = Object.entries(decompressed).map(([path, bytes]) => ({ path, bytes }))
  return createSourceProject(decodeImportedEntries(entries, limits), { dirty: false })
}

export function isLanguageBundleObject(value) {
  return Boolean(
    value &&
    typeof value === 'object' &&
    value.schemaVersion === 1 &&
    typeof value.grammarJson === 'string' &&
    value.pack && typeof value.pack.id === 'string' && typeof value.pack.version === 'string' &&
    value.parseTable && typeof value.parseTable === 'object' &&
    typeof value.parseTable.json === 'string' && typeof value.parseTable.binaryBase64 === 'string' &&
    value.queries && typeof value.queries === 'object' &&
    value.capabilities && typeof value.capabilities === 'object'
  )
}

export function createBundleProject(bundleJson) {
  let bundle
  try {
    bundle = JSON.parse(bundleJson)
  } catch (error) {
    throw projectError('INVALID_BUNDLE_JSON', `Invalid Bundle JSON: ${error?.message ?? String(error)}`)
  }
  if (!isLanguageBundleObject(bundle)) {
    throw projectError('NOT_LANGUAGE_BUNDLE', 'JSON file is not a Language Bundle v1.')
  }
  return {
    files: {},
    selectedPath: null,
    mode: 'bundle',
    bundleJson,
    dirty: false,
  }
}

function sourcePackId(project) {
  try {
    const manifest = JSON.parse(project.files[MANIFEST_PATH])
    return typeof manifest.id === 'string' && manifest.id ? manifest.id : 'language-pack'
  } catch {
    return 'language-pack'
  }
}

function safeDownloadId(value) {
  const safe = value.replace(/[^A-Za-z0-9._-]+/g, '-').replace(/^-+|-+$/g, '')
  return safe || 'language-pack'
}

export function exportProjectZip(project) {
  if (project?.mode !== 'source') {
    throw projectError('READ_ONLY_PROJECT', 'Language Bundle projects cannot be exported as source Packs.')
  }
  const files = validateSourceFiles(project.files)
  const encoded = {}
  for (const path of Object.keys(files).sort()) {
    encoded[path] = strToU8(files[path])
  }
  return {
    bytes: zipSync(encoded, { level: 6, mtime: ZIP_MTIME }),
    fileName: `${safeDownloadId(sourcePackId(project))}-source.zip`,
  }
}

export function downloadProjectZip(project) {
  if (typeof document === 'undefined' || typeof URL === 'undefined') {
    throw projectError('DOWNLOAD_UNAVAILABLE', 'Browser download APIs are unavailable.')
  }
  const artifact = exportProjectZip(project)
  const url = URL.createObjectURL(new Blob([artifact.bytes], { type: 'application/zip' }))
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = artifact.fileName
  anchor.click()
  setTimeout(() => URL.revokeObjectURL(url), 0)
  return artifact.fileName
}
