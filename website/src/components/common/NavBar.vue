<script setup>
import { ref, watch } from 'vue'
import { useRoute } from 'vue-router'

const route = useRoute()

const navLinks = [
  { name: '首页', to: '/', match: (path) => path === '/' },
  { name: '文档', to: '/docs/getting-started', match: (path) => path === '/guide' || path === '/docs' || path.startsWith('/docs/') },
  { name: '在线使用', to: '/online', match: (path) => path.startsWith('/online') || path.startsWith('/playground') },
]

const burgerOpen = ref(false)

function toggleBurger() {
  burgerOpen.value = !burgerOpen.value
}

watch(() => route.fullPath, () => {
  burgerOpen.value = false
})
</script>

<template>
  <header class="navbar">
    <nav class="navbar-inner">
      <RouterLink to="/" class="navbar-logo" aria-label="MoonParse 首页">
        <span class="logo-mark">◈</span>
        <span class="logo-copy">
          <strong>MoonParse</strong>
          <span>MoonBit Parser Toolkit</span>
        </span>
      </RouterLink>

      <button
        class="navbar-burger"
        :class="{ open: burgerOpen }"
        :aria-label="burgerOpen ? '关闭导航菜单' : '打开导航菜单'"
        :aria-expanded="burgerOpen"
        @click="toggleBurger"
      >
        <span /><span /><span />
      </button>

      <ul class="navbar-links" :class="{ 'navbar-links--open': burgerOpen }">
        <li v-for="link in navLinks" :key="link.to">
          <RouterLink :to="link.to" class="nav-link" :class="{ 'nav-link--active': link.match(route.path) }">
            {{ link.name }}
          </RouterLink>
        </li>
      </ul>
    </nav>
  </header>
</template>

<style scoped>
.navbar {
  position: sticky;
  top: 0;
  z-index: 100;
  border-bottom: 1px solid var(--line);
  background: color-mix(in srgb, var(--bg-elevated) 92%, transparent);
  backdrop-filter: blur(14px);
}

.navbar-inner {
  display: flex;
  align-items: center;
  gap: 18px;
  max-width: var(--content-width);
  margin: 0 auto;
  min-height: 64px;
  padding: 0 20px;
}

.navbar-logo {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  text-decoration: none;
  color: var(--text-h);
  flex-shrink: 0;
}

.logo-mark {
  width: 32px;
  height: 32px;
  border-radius: var(--radius-md);
  display: inline-flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(180deg, var(--surface-3) 0%, var(--surface) 100%);
  border: 1px solid var(--line);
  color: var(--accent);
  font-size: 14px;
}

.logo-copy {
  display: inline-flex;
  flex-direction: column;
  gap: 2px;
}

.logo-copy strong {
  font-size: 15px;
  font-weight: 600;
  line-height: 1;
  letter-spacing: -0.02em;
}

.logo-copy span {
  font-size: 12px;
  line-height: 1;
  color: var(--text-soft);
}

.navbar-burger {
  flex-shrink: 0;
}

.navbar-links {
  display: flex;
  align-items: center;
  gap: 4px;
  list-style: none;
  margin: 0 0 0 auto;
  padding: 0;
}

.nav-link {
  display: inline-flex;
  align-items: center;
  min-height: 34px;
  padding: 0 10px;
  border-radius: var(--radius-md);
  text-decoration: none;
  color: var(--text-muted);
  font-size: 14px;
  font-weight: 500;
  border: 1px solid transparent;
  transition: background 0.18s ease, border-color 0.18s ease, color 0.18s ease;
}

.nav-link:hover {
  background: var(--surface-3);
  color: var(--text-h);
}

.nav-link--active {
  position: relative;
  background: var(--surface-3);
  border-color: var(--line);
  color: var(--text-h);
}

.nav-link--active::after {
  content: '';
  position: absolute;
  left: 10px;
  right: 10px;
  bottom: 4px;
  height: 2px;
  border-radius: 999px;
  background: var(--accent);
}

@media (max-width: 768px) {
  .navbar-inner {
    min-height: 58px;
    padding: 0 12px;
  }

  .logo-copy span {
    display: none;
  }
}
</style>