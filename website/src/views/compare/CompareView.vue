<template>
  <div class="compare-view">
    <div class="compare-inner">
      <h1>MoonParse 与 tree-sitter</h1>
      <p class="lead">
        这是一个并排能力对比。两者都会把源码解析成具体语法树，但在算法、集成方式和工程取向上有明显差异。
      </p>

      <div v-for="section in sections" :key="section.title" class="compare-section">
        <h2 class="section-heading">{{ section.title }}</h2>
        <table class="compare-table">
          <thead>
            <tr>
              <th>能力项</th>
              <th>MoonParse</th>
              <th>tree-sitter</th>
              <th>说明</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in section.rows" :key="row.feature">
              <td class="feat-col">{{ row.feature }}</td>
              <td :class="row.mpClass">{{ row.mp }}</td>
              <td :class="row.tsClass">{{ row.ts }}</td>
              <td class="notes-col">{{ row.notes }}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <p class="disclaimer">
        以上对比基于公开文档整理。两个项目都还在快速演进，请以各自仓库中的最新信息为准。
      </p>
    </div>
  </div>
</template>

<script setup>
function row(feature, mp, ts, notes = '') {
  const yes  = v => v === '✓' ? 'yes' : ''
  const no   = v => v === '✗' ? 'no'  : ''
  const cls  = v => yes(v) || no(v) || ''
  return { feature, mp, ts, notes, mpClass: cls(mp), tsClass: cls(ts) }
}

const sections = [
  {
    title: '解析算法',
    rows: [
      row('核心算法', 'GLR', 'LR(1)', 'MoonParse 会并行探索多条解析路径；tree-sitter 采用确定性的 LR(1) 运行时。'),
      row('歧义文法', '✓', '✗', 'GLR 天然支持 shift/reduce 与 reduce/reduce 冲突场景。'),
      row('冲突处理', '可消解或保留', '构建报错', 'MoonParse 可用优先级规则消歧，也可以保留冲突供调试。'),
      row('建表基础', 'LALR(1) + GLR', 'LR(1)', 'MoonParse 用 LALR(1) 构建表，再用 GLR 运行时处理冲突。'),
    ],
  },
  {
    title: '解析能力',
    rows: [
      row('增量解析', '✓', '✓', '两者都会在编辑后复用未变化的子树。'),
      row('错误恢复', '✓', '✓', '都会尽量返回完整语法树，并通过错误节点表达异常位置。'),
      row('树查询', '✓', '✓', '都支持基于模式的 CST 查询和命名捕获。'),
      row('语法高亮', '✓', '✓', '都能通过查询导出高亮范围。'),
      row('动态优先级', '✓', '✓', '都支持类似 prec.left、prec.right、prec.dynamic 的消歧能力。'),
      row('字段名', '✓', '✓', '规则可以给子节点添加字段名，方便后续查询和导航。'),
      row('外部 token', '✓', '✓', '都能通过额外声明接入自定义词法 token。'),
    ],
  },
  {
    title: '集成与生态',
    rows: [
      row('WASM 运行时', '✓', '✓', '两者都可在浏览器和 Node.js 中以 WASM 形式运行。'),
      row('文法描述方式', '文本 DSL', 'JS / JSON DSL', 'MoonParse 使用声明式文本 DSL；tree-sitter 通常使用 JavaScript 配置文法。'),
      row('MoonBit 原生支持', '✓', '✗', 'MoonParse 直接用 MoonBit 实现，可提供无需 FFI 的原生 MoonBit API。'),
      row('零 JS 运行时依赖', '✓', '✗', 'MoonParse 可仅以单个 WASM 文件分发；tree-sitter 常见集成仍依赖额外绑定。'),
      row('Node.js 支持', '✓', '✓', 'tree-sitter 的 Node 生态更成熟；MoonParse 则通过 WASM 直接接入 Node。'),
      row('编辑器集成', '规划中', '✓', 'tree-sitter 已广泛用于 Neovim、Helix、Emacs；MoonParse 的 LSP 集成仍在推进。'),
      row('现成文法生态', '持续增长', '500+', 'tree-sitter 的成熟文法数量更多；MoonParse 当前已提供 JSON、MoonBit、C 等示例。'),
    ],
  },
]
</script>

<style scoped>
.compare-view { overflow-y: auto; padding: 24px 20px 40px; }
.compare-inner { max-width: var(--content-width); margin: 0 auto; }
h1 { font-size: clamp(2rem, 3.2vw, 3rem); font-weight: 600; margin-bottom: 12px; }
.lead { color: var(--text-muted); margin-bottom: 28px; line-height: 1.8; max-width: var(--reading-width); }
.compare-section { margin-bottom: 16px; border: 1px solid var(--line); border-radius: var(--radius-lg); background: var(--surface); box-shadow: var(--shadow-sm); overflow: hidden; }
.section-heading { font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.08em; color: var(--text-soft); margin: 0; padding: 16px 18px; border-bottom: 1px solid var(--line); background: var(--surface-3); }
.compare-table { width: 100%; border-collapse: collapse; font-size: 13px; }
.compare-table th, .compare-table td { padding: 12px 14px; border: 1px solid var(--line); text-align: left; vertical-align: top; }
.compare-table thead { background: var(--surface-3); }
.compare-table th { font-weight: 600; font-size: 11px; letter-spacing: 0.08em; text-transform: uppercase; color: var(--text-soft); }
.feat-col { font-weight: 600; white-space: nowrap; }
.notes-col { color: var(--text-muted); font-size: 12px; }
.yes { color: #22c55e; font-weight: 700; }
.no  { color: #ef4444; font-weight: 700; }
.disclaimer { margin-top: 16px; font-size: 12px; color: var(--text-muted); }
</style>
