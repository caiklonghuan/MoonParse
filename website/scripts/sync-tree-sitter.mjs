#!/usr/bin/env node

import { copyFileSync, existsSync, mkdirSync, statSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const websiteRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const outputDir = resolve(websiteRoot, 'public/tree-sitter')
const assets = [
  {
    source: resolve(websiteRoot, 'node_modules/web-tree-sitter/web-tree-sitter.wasm'),
    target: resolve(outputDir, 'tree-sitter.wasm'),
  },
  {
    source: resolve(websiteRoot, 'node_modules/tree-sitter-json/tree-sitter-json.wasm'),
    target: resolve(outputDir, 'tree-sitter-json.wasm'),
  },
]

mkdirSync(outputDir, { recursive: true })

for (const asset of assets) {
  if (!existsSync(asset.source) || statSync(asset.source).size === 0) {
    throw new Error(`Missing Tree-sitter WASM asset: ${asset.source}`)
  }
  copyFileSync(asset.source, asset.target)
  if (!existsSync(asset.target) || statSync(asset.target).size === 0) {
    throw new Error(`Failed to synchronize Tree-sitter WASM asset: ${asset.target}`)
  }
}

console.log(`Synchronized ${assets.length} Tree-sitter WASM assets.`)
