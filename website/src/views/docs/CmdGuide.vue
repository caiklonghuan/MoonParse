<script setup>
import { computed, defineAsyncComponent } from 'vue'
import { DEFAULT_CMD_PAGE, normalizeCmdPage } from './cmd/navigation.js'

const props = defineProps({
  page: {
    type: String,
    default: DEFAULT_CMD_PAGE,
  },
})

const PAGE_COMPONENTS = {
  overview: defineAsyncComponent(() => import('./cmd/OverviewPage.vue')),
  examples: defineAsyncComponent(() => import('./cmd/ExamplesPage.vue')),
  interfaces: defineAsyncComponent(() => import('./cmd/InterfacesPage.vue')),
  commands: defineAsyncComponent(() => import('./cmd/CommandsPage.vue')),
  generate: defineAsyncComponent(() => import('./cmd/GeneratePage.vue')),
  'parse-query': defineAsyncComponent(() => import('./cmd/ParseQueryPage.vue')),
  'check-fmt-test': defineAsyncComponent(() => import('./cmd/CheckFmtTestPage.vue')),
  'io-reporter': defineAsyncComponent(() => import('./cmd/IoReporterPage.vue')),
}

const currentPage = computed(() => normalizeCmdPage(props.page))
const activePage = computed(() => PAGE_COMPONENTS[currentPage.value] ?? PAGE_COMPONENTS[DEFAULT_CMD_PAGE])
</script>

<template>
  <Suspense>
    <component :is="activePage" />
    <template #fallback>
      <article>
        <h1>Cmd</h1>
        <p>子页面加载中...</p>
      </article>
    </template>
  </Suspense>
</template>