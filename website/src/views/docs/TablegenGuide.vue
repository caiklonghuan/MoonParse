<script setup>
import { computed, defineAsyncComponent } from 'vue'
import { DEFAULT_TABLEGEN_PAGE, normalizeTablegenPage } from './tablegen/navigation.js'

const props = defineProps({
  page: {
    type: String,
    default: DEFAULT_TABLEGEN_PAGE,
  },
})

const PAGE_COMPONENTS = {
  overview: defineAsyncComponent(() => import('./tablegen/OverviewPage.vue')),
  examples: defineAsyncComponent(() => import('./tablegen/ExamplesPage.vue')),
  conflicts: defineAsyncComponent(() => import('./tablegen/ConflictsPage.vue')),
  serialization: defineAsyncComponent(() => import('./tablegen/SerializationPage.vue')),
  interfaces: defineAsyncComponent(() => import('./tablegen/InterfacesPage.vue')),
  'best-practices': defineAsyncComponent(() => import('./tablegen/BestPracticesPage.vue')),
  concepts: defineAsyncComponent(() => import('./tablegen/ConceptsPage.vue')),
  'pipeline-stages': defineAsyncComponent(() => import('./tablegen/PipelineStagesPage.vue')),
}

const currentPage = computed(() => normalizeTablegenPage(props.page))
const activePage = computed(() => PAGE_COMPONENTS[currentPage.value] ?? PAGE_COMPONENTS[DEFAULT_TABLEGEN_PAGE])
</script>

<template>
  <Suspense>
    <component :is="activePage" />
    <template #fallback>
      <article>
        <h1>Tablegen</h1>
        <p>子页面加载中…</p>
      </article>
    </template>
  </Suspense>
</template>