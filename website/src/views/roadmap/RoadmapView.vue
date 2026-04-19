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
    version: 'v0.1',
    status: 'done',
    statusLabel: '已完成',
    title: 'GLR 内核与 WASM',
    desc: '完整的 GLR 解析器已编译为 WebAssembly，支持歧义文法、增量重新解析，并以单个零依赖 WASM 文件发布。',
    tags: ['GLR', 'WASM', '增量'],
  },
  {
    version: 'v0.2',
    status: 'done',
    statusLabel: '已完成',
    title: '树查询',
    desc: '已提供带命名捕获的 CST 查询语言，可从语法树中提取节点、类型和文本范围。',
    tags: ['查询', '捕获'],
  },
  {
    version: 'v0.3',
    status: 'done',
    statusLabel: '已完成',
    title: '错误恢复',
    desc: '解析器始终会生成完整语法树，语法错误通过 MISSING 或 EXTRA 节点表达，而不是直接硬失败。',
    tags: ['错误恢复', 'CST'],
  },
  {
    version: 'v0.4',
    status: 'done',
    statusLabel: '已完成',
    title: '在线使用页',
    desc: '浏览器内四面板工具已经可用，包含语法编辑、源码编辑、实时语法树和查询执行，并支持主题切换与 URL 状态分享。',
    tags: ['在线使用', 'CodeMirror 6'],
  },
  {
    version: 'v0.5',
    status: 'active',
    statusLabel: '进行中',
    title: '语法高亮',
    desc: '基于查询导出高亮范围，已在在线使用页中接入 CM6，并继续整理对外可复用的高亮 API。',
    tags: ['高亮', 'CM6', 'API'],
  },
  {
    version: 'v0.6',
    status: 'planned',
    statusLabel: '计划中',
    title: 'MoonBit 绑定与 NPM 包',
    desc: '提供一等公民的 MoonBit API，让 MoonBit 程序能直接使用 MoonParse；同时发布带完整 TypeScript 类型的 npm 包。',
    tags: ['MoonBit', 'npm'],
  },
  {
    version: 'v0.7',
    status: 'planned',
    statusLabel: '计划中',
    title: 'LSP 集成',
    desc: '围绕 MoonParse 文法提供 Language Server Protocol 能力，包括诊断、悬停、跳转定义和语义高亮。',
    tags: ['LSP', '编辑器'],
  },
  {
    version: 'v0.8',
    status: 'planned',
    statusLabel: '计划中',
    title: '流式解析',
    desc: '支持从字节流中增量解析，而无需先缓存完整输入，以便处理大文件和实时网络流。',
    tags: ['流式', '性能'],
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
