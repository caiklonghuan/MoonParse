<script setup>
import { ref, computed, defineAsyncComponent } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  DEFAULT_GRAMMAR_PAGE,
  GRAMMAR_NAV,
  normalizeGrammarPage,
} from './grammar/navigation.js'
import {
  DEFAULT_TABLEGEN_PAGE,
  TABLEGEN_NAV,
  normalizeTablegenPage,
} from './tablegen/navigation.js'
import {
  DEFAULT_RUNTIME_PAGE,
  RUNTIME_NAV,
  normalizeRuntimePage,
} from './runtime/navigation.js'
import {
  DEFAULT_CMD_PAGE,
  CMD_NAV,
  normalizeCmdPage,
} from './cmd/navigation.js'

const route  = useRoute()
const router = useRouter()

const NAV = [
  { id: 'getting-started', label: '快速开始' },
  { id: 'grammar-guide',   label: 'Grammar', children: GRAMMAR_NAV },
  { id: 'tablegen-guide',  label: 'Tablegen', children: TABLEGEN_NAV },
  { id: 'runtime-guide',   label: 'Runtime', children: RUNTIME_NAV },
  { id: 'cmd-guide',       label: 'Cmd', children: CMD_NAV },
  { id: 'api-reference',   label: 'API 参考' },
]

const rawSection = computed(() => {
  if (route.name === 'docs-grammar') {
    return 'grammar-guide'
  }
  if (route.name === 'docs-tablegen') {
    return 'tablegen-guide'
  }
  if (route.name === 'docs-runtime') {
    return 'runtime-guide'
  }
  if (route.name === 'docs-cmd') {
    return 'cmd-guide'
  }
  return String(route.params.section || 'getting-started')
})

const section = computed(() => {
  return rawSection.value
})

const grammarPage = computed(() => {
  if (route.name === 'docs-grammar') {
    return normalizeGrammarPage(String(route.params.page || DEFAULT_GRAMMAR_PAGE))
  }
  return normalizeGrammarPage(String(route.query.page || DEFAULT_GRAMMAR_PAGE))
})

const tablegenPage = computed(() => {
  if (route.name === 'docs-tablegen') {
    return normalizeTablegenPage(String(route.params.page || DEFAULT_TABLEGEN_PAGE))
  }
  return normalizeTablegenPage(String(route.query.page || DEFAULT_TABLEGEN_PAGE))
})

const runtimePage = computed(() => {
  if (route.name === 'docs-runtime') {
    return normalizeRuntimePage(String(route.params.page || DEFAULT_RUNTIME_PAGE))
  }
  return normalizeRuntimePage(String(route.query.page || DEFAULT_RUNTIME_PAGE))
})

const cmdPage = computed(() => {
  if (route.name === 'docs-cmd') {
    return normalizeCmdPage(String(route.params.page || DEFAULT_CMD_PAGE))
  }
  return normalizeCmdPage(String(route.query.page || DEFAULT_CMD_PAGE))
})

const currentChildPage = computed(() => {
  if (section.value === 'grammar-guide') {
    return grammarPage.value
  }
  if (section.value === 'tablegen-guide') {
    return tablegenPage.value
  }
  if (section.value === 'runtime-guide') {
    return runtimePage.value
  }
  if (section.value === 'cmd-guide') {
    return cmdPage.value
  }
  return ''
})

const sidebarOpen = ref(false)

function go(id) {
  if (id == 'grammar-guide') {
    router.push(`/docs/grammar/${grammarPage.value}`)
  } else if (id == 'tablegen-guide') {
    router.push(`/docs/tablegen/${tablegenPage.value}`)
  } else if (id == 'runtime-guide') {
    router.push(`/docs/runtime/${runtimePage.value}`)
  } else if (id == 'cmd-guide') {
    router.push(`/docs/cmd/${cmdPage.value}`)
  } else {
    router.push(`/docs/${id}`)
  }
  sidebarOpen.value = false
}

function goChildPage(sectionId, id) {
  if (sectionId == 'grammar-guide') {
    router.push(`/docs/grammar/${id}`)
  } else if (sectionId == 'tablegen-guide') {
    router.push(`/docs/tablegen/${id}`)
  } else if (sectionId == 'runtime-guide') {
    router.push(`/docs/runtime/${id}`)
  } else if (sectionId == 'cmd-guide') {
    router.push(`/docs/cmd/${id}`)
  }
  sidebarOpen.value = false
}

function isSectionActive(id) {
  return section.value == id
}

const SECTIONS = {
  'getting-started': defineAsyncComponent(() => import('./GettingStarted.vue')),
  'grammar-guide':   defineAsyncComponent(() => import('./GrammarGuide.vue')),
  'tablegen-guide':  defineAsyncComponent(() => import('./TablegenGuide.vue')),
  'runtime-guide':   defineAsyncComponent(() => import('./RuntimeGuide.vue')),
  'cmd-guide':       defineAsyncComponent(() => import('./CmdGuide.vue')),
  'api-reference':   defineAsyncComponent(() => import('./ApiReference.vue')),
}

const activeDoc = computed(() => SECTIONS[section.value] ?? null)
const activeDocProps = computed(() => {
  if (section.value == 'grammar-guide') {
    return { page: grammarPage.value }
  }
  if (section.value == 'tablegen-guide') {
    return { page: tablegenPage.value }
  }
  if (section.value == 'runtime-guide') {
    return { page: runtimePage.value }
  }
  if (section.value == 'cmd-guide') {
    return { page: cmdPage.value }
  }
  return {}
})
</script>

<template>
  <div class="docs-layout" :class="{ 'sidebar-open': sidebarOpen }">
    <nav class="docs-sidebar">
      <h2 class="sidebar-heading" @click="sidebarOpen = !sidebarOpen">文档</h2>
      <ul class="docs-nav">
        <li
          v-for="n in NAV"
          :key="n.id"
          class="docs-nav-group"
        >
          <div
            class="docs-nav-item"
            :class="{ active: isSectionActive(n.id) }"
            @click="go(n.id)"
          >{{ n.label }}</div>

          <ul
            v-if="n.children && isSectionActive(n.id)"
            class="docs-nav-children"
          >
            <li
              v-for="child in n.children"
              :key="child.id"
              class="docs-nav-child"
              :class="{ active: currentChildPage === child.id }"
              @click.stop="goChildPage(n.id, child.id)"
            >{{ child.label }}</li>
          </ul>
        </li>
      </ul>
    </nav>

    <main class="docs-content">
      <Suspense>
        <component :is="activeDoc" v-if="activeDoc" v-bind="activeDocProps" />
        <article v-else>
          <h1>未找到内容</h1>
          <p>文档分区 <code>{{ rawSection }}</code> 不存在。</p>
        </article>
        <template #fallback>
          <div class="docs-loading">加载中…</div>
        </template>
      </Suspense>
    </main>
  </div>
</template>

<style scoped>
.docs-layout {
  display: grid;
  grid-template-columns: 240px minmax(0, 1fr);
  min-height: calc(100vh - 170px);
  max-width: var(--content-width);
  margin: 0 auto;
  padding: 24px 20px 32px;
  gap: 24px;
  align-items: start;
}

.docs-sidebar {
  border: 1px solid var(--line);
  border-radius: var(--radius-lg);
  padding: 14px 0;
  overflow-y: auto;
  position: sticky;
  top: 80px;
  background: var(--surface);
  box-shadow: var(--shadow-sm);
}

.sidebar-heading {
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--text-soft);
  padding: 0 18px 10px;
  margin: 0;
}

.docs-nav {
  list-style: none;
  margin: 0;
  padding: 0;
}

.docs-nav-group {
  margin: 0;
}

.docs-nav-item {
  margin: 0;
  padding: 12px 18px;
  cursor: pointer;
  font-size: 14px;
  color: var(--text-muted);
  border-left: 2px solid transparent;
  transition: background 0.18s, border-color 0.18s, color 0.18s;
}

.docs-nav-item:hover {
  background: var(--surface-3);
  color: var(--text-h);
}

.docs-nav-item.active {
  border-left-color: var(--accent);
  color: var(--text-h);
  font-weight: 600;
  background: var(--surface-3);
}

.docs-nav-children {
  list-style: none;
  margin: 0 0 8px;
  padding: 4px 0 4px 12px;
}

.docs-nav-child {
  margin: 0;
  padding: 9px 18px 9px 22px;
  cursor: pointer;
  font-size: 13px;
  color: var(--text-soft);
  border-left: 2px solid transparent;
  transition: background 0.18s, border-color 0.18s, color 0.18s;
}

.docs-nav-child:hover {
  background: var(--surface-3);
  color: var(--text-h);
}

.docs-nav-child.active {
  border-left-color: var(--accent);
  color: var(--text-h);
  font-weight: 600;
  background: var(--surface-3);
}

.docs-content {
  min-height: 680px;
  overflow-y: auto;
  padding: 36px 42px;
  border: 1px solid var(--line);
  border-radius: var(--radius-lg);
  background: var(--surface);
  box-shadow: var(--shadow-sm);
}

.docs-loading {
  padding: 24px 0;
  color: var(--text-muted);
  font-size: 14px;
}

.docs-content :deep(article) {
  max-width: var(--reading-width);
  margin: 0 auto;
}

.docs-content :deep(article h1) {
  font-size: clamp(34px, 4vw, 48px);
  font-weight: 600;
  margin: 0 0 18px;
  color: var(--text-h);
}

.docs-content :deep(article h2) {
  font-size: 24px;
  font-weight: 600;
  margin: 36px 0 12px;
  color: var(--text-h);
}

.docs-content :deep(article h3) {
  font-size: 18px;
  font-weight: 600;
  margin: 24px 0 10px;
  color: var(--text-h);
}

.docs-content :deep(article p) {
  line-height: 1.85;
  color: var(--text-muted);
  margin: 0 0 16px;
}

.docs-content :deep(article ul) {
  margin: 0 0 16px;
  padding-left: 20px;
  line-height: 1.9;
  color: var(--text-muted);
}

.docs-content :deep(article li) {
  margin-bottom: 6px;
}

.docs-content :deep(article table) {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
  margin: 16px 0 24px;
  background: var(--surface);
}

.docs-content :deep(article th),
.docs-content :deep(article td) {
  padding: 10px 12px;
  border: 1px solid var(--line);
  text-align: left;
  vertical-align: top;
}

.docs-content :deep(article th) {
  background: var(--surface-3);
  font-weight: 600;
  color: var(--text-h);
}

.docs-content :deep(article pre) {
  background: var(--surface-4);
  border: 1px solid var(--line);
  border-radius: var(--radius-md);
  padding: 16px 18px;
  font-size: 13px;
  line-height: 1.65;
  overflow-x: auto;
  margin: 16px 0 24px;
  font-family: var(--mono, ui-monospace, Consolas, monospace);
}

.docs-content :deep(article code) {
  display: inline;
  background: var(--surface-4);
  border: 1px solid var(--line);
  padding: 0.08rem 0.32rem;
  border-radius: var(--radius-sm);
  font-size: 0.88em;
  color: var(--text-h);
  font-family: var(--mono, ui-monospace, Consolas, monospace);
}

.docs-content :deep(article pre code) {
  display: block;
  background: none;
  border: 0;
  padding: 0;
  font-size: inherit;
  color: var(--text-h);
}

@media (max-width: 700px) {
  .docs-layout {
    grid-template-columns: 1fr;
    grid-template-rows: auto 1fr;
    padding: 12px;
    gap: 12px;
  }

  .docs-sidebar {
    position: static;
  }

  .docs-content {
    padding: 24px 20px;
  }
}
</style>
