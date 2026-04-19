<template>
  <article>
    <h1>概览</h1>
    <p><code>query/</code> 是 MoonParse 的结构化查询模块。它不负责把文本解析成树，而是消费已经由 <code>runtime/</code> 生成好的 CST，在树上执行 Tree-Sitter 风格的 S-表达式模式匹配，并把结果整理成捕获列表、高亮区间或局部变量解析结果。</p>

    <h2>模块位置</h2>
    <pre><code>Grammar DSL / Builder API
          |
          v
      grammar/
          |
          v
      tablegen/
          |
          v
      runtime/
          |
          v
         CST
          |
          v
       query/
          |
          v
captures / highlight ranges / local resolution</code></pre>
    <p>从职责上看，<code>grammar/</code> 负责定义语言，<code>tablegen/</code> 负责编译表，<code>runtime/</code> 负责生成 CST，而 <code>query/</code> 则负责从树里提取结构信息。它是一层典型的“语法树消费模块”。</p>

    <h2>最常用的能力</h2>
    <table>
      <thead><tr><th>能力</th><th>API</th><th>用途</th></tr></thead>
      <tbody>
        <tr><td>查询编译</td><td><code>compile</code></td><td>把查询字符串编译为 <code>CompiledQuery</code>。</td></tr>
        <tr><td>查询执行</td><td><code>exec</code></td><td>在 CST 上执行模式匹配，返回扁平的 <code>CaptureResult[]</code>。</td></tr>
        <tr><td>高亮</td><td><code>apply_highlights</code>、<code>apply_highlights_with_locals</code></td><td>把查询结果转成可直接喂给编辑器的高亮区间。</td></tr>
        <tr><td>局部变量解析</td><td><code>resolve_locals</code></td><td>识别 <code>@local.scope</code>、<code>@local.definition</code>、<code>@local.reference</code> 之间的绑定关系。</td></tr>
        <tr><td>节点工具</td><td><code>node_type_name</code>、<code>node_text</code></td><td>获取查询语言视角下的节点名与节点原文。</td></tr>
      </tbody>
    </table>

    <h2>内部结构</h2>
    <table>
      <thead><tr><th>文件</th><th>主要职责</th></tr></thead>
      <tbody>
        <tr><td><code>types.mbt</code></td><td>定义查询 AST、捕获结果、谓词、量词和辅助类型。</td></tr>
        <tr><td><code>parser.mbt</code></td><td>手写递归下降查询编译器。</td></tr>
        <tr><td><code>matcher.mbt</code></td><td>查询执行、回溯匹配和谓词过滤。</td></tr>
        <tr><td><code>highlight.mbt</code></td><td>高亮区间生成与排序。</td></tr>
        <tr><td><code>locals.mbt</code></td><td>局部变量作用域和引用解析。</td></tr>
      </tbody>
    </table>

    <h2>先知道的三件事</h2>
    <ul>
      <li>查询输入不只是树，还必须带上原始 <code>input</code> 文本，因为字面量匹配、谓词和高亮都依赖节点原文。</li>
      <li><code>exec()</code> 返回的是按捕获展开后的扁平数组，而不是按模式分组的树结构；若要还原一次顶层命中里的所有捕获，需要看 <code>match_id</code>。</li>
      <li>公开 API 中的 <code>capture_name</code> 不带 <code>@</code> 前缀，例如查询里写 <code>@name</code>，返回结果里会是 <code>name</code>。</li>
    </ul>
  </article>
</template>