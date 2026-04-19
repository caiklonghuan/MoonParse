<script setup>
const version = '__VERSION__'
const year = new Date().getFullYear()

const footerSections = [
  {
    title: 'Documentation',
    items: [
      { label: '快速开始', to: '/docs/getting-started' },
      { label: '文法指南', to: '/docs/grammar-guide' },
      { label: 'Tablegen 指南', to: '/docs/tablegen/overview' },
      { label: 'Runtime 指南', to: '/docs/runtime/overview' },
      { label: 'Cmd 指南', to: '/docs/cmd/overview' },
      { label: 'API 参考', to: '/docs/api-reference' },
    ],
  },
  {
    title: 'Tools',
    items: [
      { label: '在线使用', to: '/online' },
    ],
  },
]
</script>

<template>
  <footer class="footer">
    <div class="footer-inner">
      <div class="footer-brand">
        <span class="footer-logo">MoonParse</span>
        <p class="footer-copy">面向 MoonBit 与 WebAssembly 的解析器工具链，把文法 DSL、解析运行时和树查询整理成一套连续的工程体验。</p>
      </div>

      <div class="footer-columns">
        <section v-for="section in footerSections" :key="section.title" class="footer-section">
          <h2 class="footer-heading">{{ section.title }}</h2>
          <div class="footer-links">
            <template v-for="item in section.items" :key="item.label">
              <RouterLink v-if="item.to" :to="item.to">{{ item.label }}</RouterLink>
              <a v-else :href="item.href" target="_blank" rel="noopener">{{ item.label }}</a>
            </template>
          </div>
        </section>
      </div>

      <div class="footer-meta">
        <span class="footer-version">{{ version }}</span>
        <a class="footer-repo" href="https://github.com/moonbitlang/MoonParse" target="_blank" rel="noopener">GitHub</a>
        <span class="footer-right">© {{ year }} MoonBit</span>
      </div>
    </div>
  </footer>
</template>

<style scoped>
.footer {
  margin-top: auto;
  padding: 24px 20px 28px;
  position: relative;
  z-index: 1;
}

.footer-inner {
  display: grid;
  grid-template-columns: minmax(0, 1.35fr) minmax(0, 1fr) auto;
  gap: 24px;
  max-width: var(--content-width);
  margin: 0 auto;
  padding: 18px 0 0;
  font-size: 13px;
  color: var(--text-muted);
  border-top: 1px solid var(--line);
}

.footer-brand {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.footer-logo {
  color: var(--text-h);
  font-weight: 600;
  font-size: 18px;
  letter-spacing: -0.02em;
}

.footer-copy {
  max-width: 520px;
  font-size: 14px;
  line-height: 1.75;
  color: var(--text-muted);
}

.footer-columns {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 20px;
}

.footer-section {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.footer-heading {
  margin: 0;
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--text-soft);
}

.footer-version {
  font-family: var(--mono);
  font-size: 12px;
  opacity: 0.72;
}

.footer-links {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.footer-links a {
  color: var(--text-muted);
  text-decoration: none;
  transition: color 0.18s ease;
  display: inline-flex;
  align-items: center;
  min-height: 28px;
}

.footer-links a:hover {
  color: var(--text-h);
}

.footer-meta {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  justify-content: flex-start;
  gap: 8px;
}

.footer-right {
  color: var(--text-soft);
}

.footer-repo {
  color: var(--text-muted);
  text-decoration: none;
}

.footer-repo:hover {
  color: var(--text-h);
}

@media (max-width: 900px) {
  .footer-inner {
    grid-template-columns: 1fr;
  }

  .footer-columns {
    grid-template-columns: 1fr;
  }

  .footer-meta {
    align-items: flex-start;
  }
}
</style>
