import { strToU8, zipSync } from 'fflate'

import { sanitizeDownloadId } from './corpusWorkbench.js'

const ZIP_MTIME = new Date('1980-01-01T00:00:00.000Z')
const PUBLISHER = 'moonparse'

function parseBundle(bundleJson) {
  const bundle = JSON.parse(bundleJson)
  if (!bundle || typeof bundle !== 'object' || !bundle.pack || typeof bundle.pack !== 'object') {
    throw new Error('Invalid Language Bundle JSON.')
  }
  return bundle
}

function packageName(value) {
  return sanitizeDownloadId(value)
    .replace(/[^A-Za-z0-9-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .toLowerCase() || 'language-pack'
}

function semver(value) {
  const text = String(value ?? '')
  return /^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$/.test(text)
    ? text
    : '0.1.0'
}

function scopeSegment(value) {
  return packageName(value).replace(/-+/g, '-')
}

function escapeXml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;')
}

function normalizeExtensions(extensions) {
  if (!Array.isArray(extensions)) return []
  const result = []
  const seen = new Set()
  for (const item of extensions) {
    if (typeof item !== 'string' || !item.trim()) continue
    const extension = item.startsWith('.') ? item : `.${item}`
    if (seen.has(extension)) continue
    seen.add(extension)
    result.push(extension)
  }
  return result
}

function prettyJson(value) {
  return `${JSON.stringify(value, null, 2)}\n`
}

function extensionPackageJson(bundle, paths) {
  const pack = bundle.pack
  const languageId = typeof pack.id === 'string' && pack.id ? pack.id : 'language-pack'
  const displayName = typeof pack.name === 'string' && pack.name ? pack.name : languageId
  const extensions = normalizeExtensions(pack.extensions)
  const language = {
    id: languageId,
    aliases: Array.from(new Set([displayName, languageId].filter(Boolean))),
    configuration: paths.configuration,
  }
  if (extensions.length > 0) language.extensions = extensions

  return {
    name: paths.packageName,
    displayName: `${displayName} Language Pack`,
    description: `Generated MoonParse language extension for ${displayName}.`,
    version: semver(pack.version),
    publisher: PUBLISHER,
    engines: { vscode: '^1.90.0' },
    categories: ['Programming Languages'],
    activationEvents: [`onLanguage:${languageId}`],
    main: './dist/extension.js',
    contributes: {
      languages: [language],
      grammars: [{
        language: languageId,
        scopeName: paths.scopeName,
        path: paths.syntax,
      }],
    },
  }
}

function vsixManifest(bundle, paths) {
  const pack = bundle.pack
  const languageId = typeof pack.id === 'string' && pack.id ? pack.id : 'language-pack'
  const displayName = typeof pack.name === 'string' && pack.name ? pack.name : languageId
  const version = semver(pack.version)
  return `<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Id="${escapeXml(paths.packageName)}" Version="${escapeXml(version)}" Language="en-US" Publisher="${PUBLISHER}" />
    <DisplayName>${escapeXml(`${displayName} Language Pack`)}</DisplayName>
    <Description xml:space="preserve">${escapeXml(`Generated MoonParse language extension for ${displayName}.`)}</Description>
    <Tags>MoonParse,language-pack</Tags>
    <Categories>Programming Languages</Categories>
  </Metadata>
  <Installation>
    <InstallationTarget Id="Microsoft.VisualStudio.Code" />
  </Installation>
  <Dependencies />
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true" />
  </Assets>
</PackageManifest>
`
}

function contentTypesXml() {
  return `<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="json" ContentType="application/json" />
  <Default Extension="js" ContentType="application/javascript" />
  <Default Extension="md" ContentType="text/markdown" />
  <Default Extension="txt" ContentType="text/plain" />
  <Default Extension="xml" ContentType="text/xml" />
  <Override PartName="/extension.vsixmanifest" ContentType="text/xml" />
</Types>
`
}

function languageConfigurationJson() {
  return {
    brackets: [['{', '}'], ['[', ']'], ['(', ')']],
    autoClosingPairs: [
      { open: '{', close: '}' },
      { open: '[', close: ']' },
      { open: '(', close: ')' },
      { open: '"', close: '"' },
      { open: "'", close: "'" },
    ],
    surroundingPairs: [
      { open: '{', close: '}' },
      { open: '[', close: ']' },
      { open: '(', close: ')' },
      { open: '"', close: '"' },
      { open: "'", close: "'" },
    ],
  }
}

function syntaxJson(paths) {
  return {
    name: paths.displayName,
    scopeName: paths.scopeName,
    patterns: [{
      name: paths.scopeName,
      match: '.+',
    }],
  }
}

function extensionJs(paths) {
  return `'use strict';

function activate() {
  console.log(${JSON.stringify(`${paths.displayName} MoonParse language extension active.`)});
}

function deactivate() {}

module.exports = { activate, deactivate };
`
}

function readme(bundle, paths) {
  const pack = bundle.pack
  const displayName = typeof pack.name === 'string' && pack.name ? pack.name : paths.languageId
  return `# ${displayName} Language Pack

Generated by MoonParse Playground.

This VSIX contains:

- VS Code language and grammar contribution.
- Embedded MoonParse Bundle: \`${paths.bundleFileName}\`.
- Minimal activation script for local installation and demo use.

For full LSP packaging, use the MoonParse CLI workflow.
`
}

function changelog() {
  return `# Changelog

## 0.1.0

- Generated from a MoonParse Language Pack Bundle.
`
}

function artifactPaths(bundle) {
  const pack = bundle.pack
  const languageId = typeof pack.id === 'string' && pack.id ? pack.id : 'language-pack'
  const safeId = sanitizeDownloadId(languageId)
  const displayName = typeof pack.name === 'string' && pack.name ? pack.name : languageId
  return {
    languageId,
    safeId,
    packageName: packageName(languageId),
    displayName,
    scopeName: `source.${scopeSegment(languageId)}`,
    bundleFileName: `${safeId}.language-bundle.json`,
    bundle: `./${safeId}.language-bundle.json`,
    configuration: './language-configuration.json',
    syntax: `./syntaxes/${safeId}.tmLanguage.json`,
    syntaxEntry: `extension/syntaxes/${safeId}.tmLanguage.json`,
  }
}

export function vsixDownloadFileName(bundleJson) {
  try {
    const bundle = parseBundle(bundleJson)
    return `${sanitizeDownloadId(bundle.pack?.id)}-vscode.vsix`
  } catch {
    return 'language-pack-vscode.vsix'
  }
}

export function createVsixArtifact(bundleJson) {
  const bundle = parseBundle(bundleJson)
  const paths = artifactPaths(bundle)
  const entries = {
    '[Content_Types].xml': strToU8(contentTypesXml()),
    'extension.vsixmanifest': strToU8(vsixManifest(bundle, paths)),
    'extension/package.json': strToU8(prettyJson(extensionPackageJson(bundle, paths))),
    'extension/README.md': strToU8(readme(bundle, paths)),
    'extension/CHANGELOG.md': strToU8(changelog()),
    'extension/language-configuration.json': strToU8(prettyJson(languageConfigurationJson())),
    [`extension/${paths.bundleFileName}`]: strToU8(bundleJson),
    [paths.syntaxEntry]: strToU8(prettyJson(syntaxJson(paths))),
    'extension/dist/extension.js': strToU8(extensionJs(paths)),
  }
  return {
    bytes: zipSync(entries, { level: 6, mtime: ZIP_MTIME }),
    fileName: vsixDownloadFileName(bundleJson),
    entries: Object.keys(entries),
  }
}

export function downloadBinaryFile(bytes, fileName, type = 'application/vsix') {
  if (typeof document === 'undefined' || typeof URL === 'undefined') {
    throw new Error('Browser download APIs are unavailable.')
  }
  const url = URL.createObjectURL(new Blob([bytes], { type }))
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = fileName
  anchor.click()
  setTimeout(() => URL.revokeObjectURL(url), 0)
}
