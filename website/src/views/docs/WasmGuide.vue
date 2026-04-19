<script setup>
import { computed, defineAsyncComponent } from 'vue'
import { DEFAULT_WASM_PAGE, normalizeWasmPage } from './wasm/navigation.js'

const props = defineProps({
  page: {
    type: String,
    default: DEFAULT_WASM_PAGE,
  },
})

const PAGE_COMPONENTS = {
  overview: defineAsyncComponent(() => import('./wasm/OverviewPage.vue')),
  concepts: defineAsyncComponent(() => import('./wasm/ConceptsPage.vue')),
  'parser-tree': defineAsyncComponent(() => import('./wasm/ParserTreePage.vue')),
  'incremental-config': defineAsyncComponent(() => import('./wasm/IncrementalConfigPage.vue')),
  'cursor-query': defineAsyncComponent(() => import('./wasm/CursorQueryPage.vue')),
  interfaces: defineAsyncComponent(() => import('./wasm/InterfacesPage.vue')),
  examples: defineAsyncComponent(() => import('./wasm/ExamplesPage.vue')),
}

const currentPage = computed(() => normalizeWasmPage(props.page))
const activePage = computed(() => PAGE_COMPONENTS[currentPage.value] ?? PAGE_COMPONENTS[DEFAULT_WASM_PAGE])
</script>

<template>
  <Suspense>
    <component :is="activePage" />
    <template #fallback>
      <article>
        <h1>Wasm</h1>
        <p>子页面加载中...</p>
      </article>
    </template>
  </Suspense>
</template>