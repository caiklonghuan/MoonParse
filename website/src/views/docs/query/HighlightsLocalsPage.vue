<template>
  <article>
    <h1>高亮与 Locals</h1>
    <p><code>query/</code> 不只是“找节点”。它还把通用查询结果继续加工成两类编辑器友好的产物：高亮区间和局部变量解析结果。</p>

    <h2><code>apply_highlights()</code></h2>
    <pre><code>apply_highlights(root, input, table, highlightQuery)
  -> Array[HighlightRange]</code></pre>
    <p>这个函数会先调用 <code>exec()</code>，再把捕获结果转成高亮区间。高亮名来自捕获名本身，例如查询中的 <code>@number</code> 会生成 <code>highlight_name = "number"</code>。</p>

    <h3>它会做的过滤与整理</h3>
    <ul>
      <li>跳过零宽且不是 <code>ERROR</code> 的节点。</li>
      <li>跳过所有 <code>local.*</code> 系列捕获，因为这些名称供 locals 引擎使用，不直接映射为颜色。</li>
      <li>按 <code>start_byte</code> 升序排序；若起点相同，则让更宽的区间排在前面。</li>
    </ul>

    <h2><code>highlight_names</code></h2>
    <p><code>highlight_names</code> 是一个公开常量，列出了当前系统预期支持的高亮类型名。它覆盖常见的语法高亮命名，例如：</p>
    <pre><code>keyword
string
number
function
type
variable
variable.local
variable.parameter.local</code></pre>
    <p>如果上层要和 LSP、VS Code、Neovim 或 Helix 的 token 类型做映射，这个列表就是一份稳定的名称边界。</p>

    <h2><code>resolve_locals()</code></h2>
    <pre><code>resolve_locals(root, input, table, localsQuery)
  -> LocalResolution</code></pre>
    <p>locals 查询通过三类约定捕获工作：</p>
    <ul>
      <li><code>@local.scope</code></li>
      <li><code>@local.definition</code>，以及 <code>@local.definition.*</code></li>
      <li><code>@local.reference</code></li>
    </ul>
    <p>实现上会先收集所有 scope 区间，再把 definition 归入“最内层包含它的 scope”，最后对每个 reference 从内到外查找同名定义。命中后会按节点的 <code>start_byte</code> 记录为本地引用。</p>

    <h2><code>apply_highlights_with_locals()</code></h2>
    <pre><code>apply_highlights_with_locals(
  root,
  input,
  table,
  highlightQuery,
  localsQuery,
)</code></pre>
    <p>这个函数会先执行普通高亮，再执行 locals 解析。如果某个高亮区间的 <code>start_byte</code> 被识别为本地引用，它的高亮名会被追加 <code>.local</code> 后缀，例如：</p>
    <ul>
      <li><code>variable</code> 变成 <code>variable.local</code></li>
      <li><code>variable.parameter</code> 变成 <code>variable.parameter.local</code></li>
    </ul>

    <h2>适合的应用场景</h2>
    <ul>
      <li>编辑器语法高亮和语义高亮。</li>
      <li>区分局部变量与全局引用。</li>
      <li>构建简单的“跳转到定义”或悬浮信息前置层。</li>
      <li>在不引入额外 AST 语义分析器的前提下，快速做代码着色和局部作用域增强。</li>
    </ul>
  </article>
</template>