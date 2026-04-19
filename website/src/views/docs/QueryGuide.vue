<script setup>
import { computed, defineAsyncComponent } from 'vue'
import { DEFAULT_QUERY_PAGE, normalizeQueryPage } from './query/navigation.js'

const props = defineProps({
  page: {
    type: String,
    default: DEFAULT_QUERY_PAGE,
  },
})

const PAGE_COMPONENTS = {
  overview: defineAsyncComponent(() => import('./query/OverviewPage.vue')),
  concepts: defineAsyncComponent(() => import('./query/ConceptsPage.vue')),
  language: defineAsyncComponent(() => import('./query/LanguagePage.vue')),
  matching: defineAsyncComponent(() => import('./query/MatchingPage.vue')),
  'highlights-locals': defineAsyncComponent(() => import('./query/HighlightsLocalsPage.vue')),
  interfaces: defineAsyncComponent(() => import('./query/InterfacesPage.vue')),
  examples: defineAsyncComponent(() => import('./query/ExamplesPage.vue')),
}

const currentPage = computed(() => normalizeQueryPage(props.page))
const activePage = computed(() => PAGE_COMPONENTS[currentPage.value] ?? PAGE_COMPONENTS[DEFAULT_QUERY_PAGE])
</script>

<template>
  <Suspense>
    <component :is="activePage" />
    <template #fallback>
      <article>
        <h1>Query</h1>
        <p>子页面加载中...</p>
      </article>
    </template>
  </Suspense>
</template>