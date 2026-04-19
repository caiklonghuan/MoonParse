import { createRouter, createWebHistory } from 'vue-router'

const routes = [
  {
    path: '/',
    name: 'home',
    component: () => import('@/views/home/HomeView.vue'),
  },
  {
    path: '/guide',
    redirect: (to) => ({ path: '/docs/getting-started', query: to.query, hash: to.hash }),
  },
  {
    path: '/reference',
    redirect: (to) => ({ path: '/docs/api-reference', query: to.query, hash: to.hash }),
  },
  {
    path: '/features',
    redirect: { path: '/', hash: '#features' },
  },
  {
    path: '/online',
    name: 'online',
    component: () => import('@/views/playground/PlaygroundView.vue'),
  },
  {
    path: '/playground',
    redirect: (to) => ({ path: '/online', query: to.query, hash: to.hash }),
  },
  {
    path: '/docs/grammar/:page?',
    name: 'docs-grammar',
    component: () => import('@/views/docs/DocsView.vue'),
  },
  {
    path: '/docs/tablegen/:page?',
    name: 'docs-tablegen',
    component: () => import('@/views/docs/DocsView.vue'),
  },
  {
    path: '/docs/runtime/:page?',
    name: 'docs-runtime',
    component: () => import('@/views/docs/DocsView.vue'),
  },
  {
    path: '/docs/cmd/:page?',
    name: 'docs-cmd',
    component: () => import('@/views/docs/DocsView.vue'),
  },
  {
    path: '/docs/:section?',
    name: 'docs',
    component: () => import('@/views/docs/DocsView.vue'),
  },
  {
    path: '/:pathMatch(.*)*',
    redirect: '/',
  },
]

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes,
  scrollBehavior(to, _from, savedPosition) {
    if (savedPosition) return savedPosition
    if (to.hash) {
      return {
        el: to.hash,
        top: 96,
      }
    }
    return { top: 0 }
  },
})

export default router
