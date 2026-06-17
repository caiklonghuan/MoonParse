<template>
  <div class="roadmap-view">
    <div class="roadmap-inner">
      <h1>路线图</h1>
      <p class="lead">MoonParse 当前已完成和计划中的能力演进。</p>

      <div class="timeline">
        <div v-for="item in items" :key="item.title" class="tl-item" :class="item.status">
          <div class="tl-dot" />
          <div class="tl-body">
            <div class="tl-header">
              <span class="tl-version">{{ item.version }}</span>
              <span class="tl-title">{{ item.title }}</span>
              <span class="tl-badge">{{ item.statusLabel }}</span>
            </div>
            <p class="tl-desc">{{ item.desc }}</p>
            <div v-if="item.tags?.length" class="tl-tags">
              <span v-for="tag in item.tags" :key="tag" class="tl-tag">{{ tag }}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
const items = [
  {
    version: '核心',
    status: 'done',
    statusLabel: '已完成',
    title: 'GLR 内核与 WASM',
    desc: '完整的 GLR 解析器已编译为 WebAssembly，支持歧义文法、增量重新解析，并以单个零依赖 WASM 文件发布。',
    tags: ['GLR', 'WASM', '增量'],
  },
  {
    version: '查询',
    status: 'done',
    statusLabel: '已完成',
    title: '树查询',
    desc: '已提供带命名捕获的 CST 查询语言，可从语法树中提取节点、类型和文本范围。',
    tags: ['查询', '捕获'],
  },
  {
    version: '恢复',
    status: 'done',
    statusLabel: '已完成',
    title: '错误恢复',
    desc: '解析器始终会生成完整语法树，语法错误通过 MISSING 或 EXTRA 节点表达，而不是直接硬失败。',
    tags: ['错误恢复', 'CST'],
  },
  {
    version: 'Web',
    status: 'done',
    statusLabel: '已完成',
    title: '在线使用页',
    desc: '浏览器内四面板工具已经可用，包含语法编辑、源码编辑、实时语法树和查询执行，并支持主题切换与 URL 状态分享。',
    tags: ['在线使用', 'CodeMirror 6'],
  },
  {
    version: '高亮',
    status: 'done',
    statusLabel: '已完成',
    title: '语法高亮',
    desc: '基于查询导出高亮范围，已在在线使用页中接入 CM6，并提供 WASM 与 LSP 可复用入口。',
    tags: ['高亮', 'CM6', 'API'],
  },
  {
    version: '接口',
    status: 'done',
    statusLabel: '已完成',
    title: 'MoonBit 与 JS/WASM 接口',
    desc: '根包提供 MoonBit 高层 API；WASM 目录提供 JavaScript 封装和 TypeScript 声明。正式 npm registry 发布仍属于后续生态阶段。',
    tags: ['MoonBit', 'WASM', 'TypeScript'],
  },
  {
    version: 'LSP',
    status: 'active',
    statusLabel: '实验性',
    title: 'LSP 集成',
    desc: '已提供诊断、悬停、定义、引用、语义高亮、补全、格式化和 Code Action；Rename、Folding 与跨文件索引仍待补齐。',
    tags: ['LSP', '编辑器'],
  },
  {
    version: 'P0',
    status: 'active',
    statusLabel: '进行中',
    title: '稳定化基线',
    desc: '统一模块边界、公开 API 快照、生成物归属、版本、测试与 CI，为后续 Language Pack 重构建立防回归基线。',
    tags: ['API', 'CI', '兼容性'],
  },
]
</script>

<style scoped>
.roadmap-view { overflow-y: auto; padding: 24px 20px 40px; }
.roadmap-inner { max-width: 860px; margin: 0 auto; }
h1 { font-size: clamp(2rem, 3.2vw, 3rem); font-weight: 600; margin-bottom: 12px; }
.lead { color: var(--text-muted); margin-bottom: 28px; max-width: var(--reading-width); line-height: 1.8; }

.timeline { position: relative; padding: 24px 24px 24px 28px; border: 1px solid var(--line); border-radius: var(--radius-lg); background: var(--surface); box-shadow: var(--shadow-sm); border-left-width: 2px; display: flex; flex-direction: column; gap: 28px; }
.tl-item { position: relative; display: flex; gap: 16px; }
.tl-dot { position: absolute; left: -35px; top: 6px; width: 10px; height: 10px; border-radius: 50%; background: var(--border); border: 2px solid var(--bg); flex-shrink: 0; box-shadow: 0 0 0 3px var(--bg); }
.done   .tl-dot { background: #22c55e; }
.active .tl-dot { background: var(--accent); box-shadow: 0 0 0 3px var(--bg), 0 0 0 5px var(--accent-bg); }

.tl-body { flex: 1; }
.tl-header { display: flex; align-items: center; gap: 10px; margin-bottom: 6px; flex-wrap: wrap; }
.tl-version { font-family: var(--mono); font-size: 12px; font-weight: 600; color: var(--text-muted); background: var(--surface-4); padding: 2px 8px; border-radius: var(--radius-sm); border: 1px solid var(--line); }
.tl-title { font-weight: 600; font-size: 16px; }
.tl-badge { font-size: 11px; padding: 2px 8px; border-radius: 999px; background: var(--surface-4); color: var(--text-muted); }
.done   .tl-badge { background: rgba(34,197,94,0.15); color: #22c55e; }
.active .tl-badge { background: var(--accent-bg); color: var(--accent); }

.tl-desc { margin: 0 0 10px; font-size: 14px; color: var(--text-muted); line-height: 1.65; }
.tl-tags { display: flex; flex-wrap: wrap; gap: 6px; }
.tl-tag { font-size: 11px; padding: 2px 8px; border-radius: 999px; background: var(--surface-4); color: var(--text-muted); border: 1px solid var(--line); font-family: var(--mono); }
</style>
