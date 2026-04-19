<script setup>
const features = [
  {
    icon: '⚙️',
    title: 'GLR 运行时',
    description: '原生支持歧义文法，不要求提前消歧。先把语言跑起来，再逐步收敛冲突。',
  },
  {
    icon: '📝',
    title: '文法 DSL',
    description: '用简洁的文本 DSL 描述语言结构，rule、precedence、字段和 externals 集中在一处。',
  },
  {
    icon: '🔍',
    title: '树查询',
    description: '对解析树做模式匹配，捕获节点、字段和值范围，直接服务导航、高亮和 lint。',
  },
  {
    icon: '🔄',
    title: '增量解析',
    description: '编辑事件直接映射到增量重新解析，未改动的子树可复用，适合编辑器和 LSP 场景。',
  },
  {
    icon: '🛟',
    title: '错误恢复',
    description: '源码不完整时仍能给出可用的树，MISSING 和 EXTRA 节点携带诊断信息供上层消费。',
  },
  {
    icon: '🌐',
    title: 'WebAssembly',
    description: '同一份 WASM 二进制在浏览器和 Node.js 都可运行，在线演示与服务端工具共用同一套接口。',
  },
]

const links = [
  { label: '快速开始', to: '/docs/getting-started' },
  { label: '文法指南', to: '/docs/grammar-guide' },
  { label: 'Query 指南', to: '/docs/query/overview' },
  { label: 'Wasm 指南', to: '/docs/wasm/overview' },
  { label: 'API 参考', to: '/docs/api-reference' },
  { label: '在线试用', to: '/online' },
]
</script>

<template>
  <div class="home">
    <section class="hero">
      <h1 class="hero-title">MoonParse</h1>
      <p class="hero-sub">面向真实语言工具链的解析器工作流。</p>
      <p class="hero-desc">
        用文本 DSL 描述文法，编译出支持 GLR、增量解析、错误恢复和树查询的运行时。
        同一份 WebAssembly 产物同时适用于浏览器与 Node.js。
      </p>
      <div class="hero-actions">
        <RouterLink to="/docs/getting-started" class="btn btn-primary">快速开始</RouterLink>
        <RouterLink to="/online" class="btn btn-secondary">在线试用</RouterLink>
      </div>
    </section>

    <section class="features">
      <div class="feature-grid">
        <div v-for="f in features" :key="f.title" class="feature-card">
          <span class="feature-icon">{{ f.icon }}</span>
          <h3 class="feature-title">{{ f.title }}</h3>
          <p class="feature-desc">{{ f.description }}</p>
        </div>
      </div>
    </section>

    <section class="extra-links">
      <h2 class="extra-title">更多链接</h2>
      <ul class="extra-list">
        <li v-for="l in links" :key="l.label">
          <RouterLink :to="l.to">{{ l.label }}</RouterLink>
        </li>
      </ul>
    </section>
  </div>
</template>

<style scoped>
.home {
  max-width: 860px;
  margin: 0 auto;
  padding: 64px 24px 80px;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 64px;
}

.hero {
  text-align: center;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 16px;
}

.hero-title {
  font-size: 52px;
  font-weight: 700;
  line-height: 1.1;
  color: var(--text-h);
  margin: 0;
}

.hero-sub {
  font-size: 22px;
  color: var(--text-muted);
  margin: 0;
}

.hero-desc {
  max-width: 600px;
  font-size: 16px;
  line-height: 1.8;
  color: var(--text-muted);
  margin: 0;
}

.hero-actions {
  display: flex;
  gap: 12px;
  margin-top: 8px;
}

.btn {
  display: inline-block;
  padding: 10px 22px;
  border-radius: var(--radius-md);
  font-size: 15px;
  font-weight: 500;
  text-decoration: none;
  transition: opacity 0.15s;
}

.btn:hover { opacity: 0.85; }

.btn-primary {
  background: var(--accent);
  color: #fff;
}

.btn-secondary {
  background: var(--surface);
  color: var(--text-h);
  border: 1px solid var(--line-strong);
}

.features {
  width: 100%;
}

.feature-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 20px;
}

.feature-card {
  padding: 24px;
  border: 1px solid var(--line);
  border-radius: var(--radius-lg);
  background: var(--surface);
}

.feature-icon {
  font-size: 26px;
}

.feature-title {
  margin: 12px 0 8px;
  font-size: 17px;
  color: var(--text-h);
}

.feature-desc {
  margin: 0;
  font-size: 14px;
  line-height: 1.75;
  color: var(--text-muted);
}

.extra-links {
  text-align: center;
}

.extra-title {
  font-size: 18px;
  color: var(--text-h);
  margin: 0 0 16px;
}

.extra-list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: 8px 24px;
}

.extra-list a {
  color: var(--accent);
  text-decoration: none;
  font-size: 15px;
}

.extra-list a:hover {
  text-decoration: underline;
}

@media (max-width: 700px) {
  .hero-title { font-size: 36px; }
  .feature-grid { grid-template-columns: 1fr; }
  .hero-actions { flex-direction: column; align-items: stretch; }
}

@media (max-width: 900px) {
  .feature-grid { grid-template-columns: repeat(2, 1fr); }
}
</style>