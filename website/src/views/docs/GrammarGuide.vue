<script setup>
import { computed, defineAsyncComponent } from 'vue'
import { DEFAULT_GRAMMAR_PAGE, normalizeGrammarPage } from './grammar/navigation.js'

const props = defineProps({
  page: {
    type: String,
    default: DEFAULT_GRAMMAR_PAGE,
  },
})

const PAGE_COMPONENTS = {
  overview: defineAsyncComponent(() => import('./grammar/OverviewPage.vue')),
  'syntax-rules': defineAsyncComponent(() => import('./grammar/SyntaxRulesPage.vue')),
  'supported-features': defineAsyncComponent(() => import('./grammar/SupportedFeaturesPage.vue')),
  'usage-guide': defineAsyncComponent(() => import('./grammar/UsageGuidePage.vue')),
  examples: defineAsyncComponent(() => import('./grammar/ExamplesPage.vue')),
  interfaces: defineAsyncComponent(() => import('./grammar/InterfacesPage.vue')),
  'best-practices': defineAsyncComponent(() => import('./grammar/BestPracticesPage.vue')),
}

const currentPage = computed(() => normalizeGrammarPage(props.page))
const activePage = computed(() => PAGE_COMPONENTS[currentPage.value] ?? PAGE_COMPONENTS[DEFAULT_GRAMMAR_PAGE])
</script>

<template>
  <Suspense>
    <component :is="activePage" />
    <template #fallback>
      <article>
        <h1>Grammar</h1>
        <p>子页面加载中…</p>
      </article>
    </template>
  </Suspense>
</template>
