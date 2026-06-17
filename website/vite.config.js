import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { fileURLToPath, URL } from 'node:url'
import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

const repoRoot = fileURLToPath(new URL('../', import.meta.url))
const moonParseVersion = readFileSync(new URL('../VERSION', import.meta.url), 'utf8').trim()
let moonParseCommit = process.env.GITHUB_SHA || 'unknown'
if (moonParseCommit === 'unknown') {
  try {
    moonParseCommit = execFileSync('git', ['rev-parse', '--short', 'HEAD'], {
      cwd: repoRoot,
      encoding: 'utf8',
    }).trim()
  } catch (_) {
    // Source archives do not necessarily include Git metadata.
  }
}

export default defineConfig({
  base: '/MoonParse/',
  plugins: [vue()],

  define: {
    __MOONPARSE_VERSION__: JSON.stringify(moonParseVersion),
    __MOONPARSE_COMMIT__: JSON.stringify(moonParseCommit),
  },

  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },

  server: {
    headers: {
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'require-corp',
    },
  },

  assetsInclude: ['**/*.wasm'],

  optimizeDeps: {
    exclude: ['moonparse'],
  },
})
