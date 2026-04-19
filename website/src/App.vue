<script setup>
import NavBar from '@/components/common/NavBar.vue'
import Footer from '@/components/common/Footer.vue'
import { useMoonParse } from '@/composables/useMoonParse.js'

const { loading: wasmLoading, error: wasmError } = useMoonParse()
</script>

<template>
  <div class="app-shell">
    <div v-if="wasmLoading" class="wasm-loading-bar" aria-label="正在加载 MoonParse" />
    <div v-else-if="wasmError" class="wasm-error-banner">
      ⚠ MoonParse WASM 加载失败：{{ wasmError }}
    </div>

    <NavBar />

    <main class="app-main">
      <RouterView />
    </main>

    <Footer />
  </div>
</template>

<style scoped>
.app-shell {
  display: flex;
  flex-direction: column;
  min-height: 100vh;
  position: relative;
}

.app-main {
  flex: 1;
  display: flex;
  flex-direction: column;
  position: relative;
  z-index: 1;
}

.wasm-loading-bar {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  height: 3px;
  background: linear-gradient(90deg, var(--accent) 0%, transparent 100%);
  background-size: 200% 100%;
  animation: wasm-slide 1.2s linear infinite;
  z-index: 9999;
}

@keyframes wasm-slide {
  0% { background-position: 200% 0; }
  100% { background-position: -200% 0; }
}

.wasm-error-banner {
  position: relative;
  z-index: 2;
  background: rgba(241, 125, 150, 0.12);
  color: var(--danger);
  font-size: 13px;
  padding: 10px 20px;
  text-align: center;
  border-bottom: 1px solid rgba(241, 125, 150, 0.22);
}
</style>