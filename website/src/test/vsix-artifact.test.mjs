import assert from 'node:assert/strict'
import test from 'node:test'
import { unzipSync } from 'fflate'

import {
  createVsixArtifact,
  vsixDownloadFileName,
} from '../lib/vsixArtifact.js'

const decoder = new TextDecoder()

function text(entries, path) {
  assert.ok(entries[path], `${path} should exist`)
  return decoder.decode(entries[path])
}

function sampleBundle(overrides = {}) {
  return JSON.stringify({
    schemaVersion: 1,
    softwareVersion: '0.1.0',
    pack: {
      id: 'my pack/!',
      name: 'My <Pack> & "Demo"',
      version: '1.2.3',
      extensions: ['json', '.jsonc', '.json'],
      ...overrides.pack,
    },
    grammarJson: '{}',
    parseTable: { json: '{}', binaryBase64: 'AA==' },
    queries: {},
    capabilities: {},
    ...overrides,
  }, null, 2)
}

test('VSIX artifact has deterministic structure and embeds bundle JSON', () => {
  const bundleJson = sampleBundle()
  const first = createVsixArtifact(bundleJson)
  const second = createVsixArtifact(bundleJson)
  assert.equal(first.fileName, 'my-pack-vscode.vsix')
  assert.equal(vsixDownloadFileName(bundleJson), 'my-pack-vscode.vsix')
  assert.equal(Buffer.compare(Buffer.from(first.bytes), Buffer.from(second.bytes)), 0)
  assert.deepEqual(first.entries, [
    '[Content_Types].xml',
    'extension.vsixmanifest',
    'extension/package.json',
    'extension/README.md',
    'extension/CHANGELOG.md',
    'extension/language-configuration.json',
    'extension/my-pack.language-bundle.json',
    'extension/syntaxes/my-pack.tmLanguage.json',
    'extension/dist/extension.js',
  ])

  const entries = unzipSync(first.bytes)
  assert.deepEqual(Object.keys(entries), first.entries)
  assert.equal(text(entries, 'extension/my-pack.language-bundle.json'), bundleJson)

  const packageJson = JSON.parse(text(entries, 'extension/package.json'))
  assert.equal(packageJson.name, 'my-pack')
  assert.equal(packageJson.publisher, 'moonparse')
  assert.equal(packageJson.version, '1.2.3')
  assert.equal(packageJson.main, './dist/extension.js')
  assert.deepEqual(packageJson.activationEvents, ['onLanguage:my pack/!'])
  assert.equal(packageJson.contributes.languages[0].id, 'my pack/!')
  assert.deepEqual(packageJson.contributes.languages[0].extensions, ['.json', '.jsonc'])
  assert.equal(packageJson.contributes.grammars[0].path, './syntaxes/my-pack.tmLanguage.json')
  assert.equal(packageJson.contributes.grammars[0].scopeName, 'source.my-pack')

  const manifest = text(entries, 'extension.vsixmanifest')
  assert.match(manifest, /<PackageManifest Version="2\.0\.0"/)
  assert.match(manifest, /Publisher="moonparse"/)
  assert.match(manifest, /My &lt;Pack&gt; &amp; &quot;Demo&quot; Language Pack/)
  assert.match(text(entries, '[Content_Types].xml'), /extension\.vsixmanifest/)
  assert.match(text(entries, 'extension/dist/extension.js'), /module\.exports = \{ activate, deactivate \}/)
})

test('VSIX artifact falls back for missing optional pack metadata', () => {
  const bundleJson = sampleBundle({
    pack: {
      id: '',
      name: '',
      version: 'not-semver',
      extensions: ['mbt'],
    },
  })
  const artifact = createVsixArtifact(bundleJson)
  const entries = unzipSync(artifact.bytes)
  const packageJson = JSON.parse(text(entries, 'extension/package.json'))
  assert.equal(artifact.fileName, 'language-pack-vscode.vsix')
  assert.equal(packageJson.name, 'language-pack')
  assert.equal(packageJson.version, '0.1.0')
  assert.deepEqual(packageJson.contributes.languages[0].extensions, ['.mbt'])
})

test('VSIX artifact rejects invalid bundle JSON and filename has a safe fallback', () => {
  assert.equal(vsixDownloadFileName('{'), 'language-pack-vscode.vsix')
  assert.throws(() => createVsixArtifact('{"schemaVersion":1}'), /Invalid Language Bundle/)
})
