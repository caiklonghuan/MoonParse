<script setup>
import { computed, defineAsyncComponent } from 'vue'
import { DEFAULT_RUNTIME_PAGE, normalizeRuntimePage } from './runtime/navigation.js'

const props = defineProps({
  page: {
    type: String,
    default: DEFAULT_RUNTIME_PAGE,
  },
})

const PAGE_COMPONENTS = {
  overview: defineAsyncComponent(() => import('./runtime/OverviewPage.vue')),
  examples: defineAsyncComponent(() => import('./runtime/ExamplesPage.vue')),
  interfaces: defineAsyncComponent(() => import('./runtime/InterfacesPage.vue')),
  lexer: defineAsyncComponent(() => import('./runtime/LexerPage.vue')),
  parser: defineAsyncComponent(() => import('./runtime/ParserPage.vue')),
  glr: defineAsyncComponent(() => import('./runtime/GlrPage.vue')),
  recovery: defineAsyncComponent(() => import('./runtime/RecoveryPage.vue')),
  incremental: defineAsyncComponent(() => import('./runtime/IncrementalPage.vue')),
  concepts: defineAsyncComponent(() => import('./runtime/ConceptsPage.vue')),
}

const currentPage = computed(() => normalizeRuntimePage(props.page))
const activePage = computed(() => PAGE_COMPONENTS[currentPage.value] ?? PAGE_COMPONENTS[DEFAULT_RUNTIME_PAGE])
</script>

<template>
  <Suspense>
    <component :is="activePage" />
    <template #fallback>
      <article>
        <h1>Runtime</h1>
        <p>子页面加载中…</p>
      </article>
    </template>
  </Suspense>
</template>