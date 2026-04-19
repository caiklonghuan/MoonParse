<template>
  <article>
    <h1>查询语言</h1>
    <p><code>query/</code> 使用的是 Tree-Sitter 风格的 S-表达式查询语法。它不是再走一遍 Grammar DSL，而是一套专门用于“描述树上结构模式”的小语言。</p>

    <h2>支持的基本语法</h2>
    <table>
      <thead><tr><th>语法</th><th>示例</th><th>说明</th></tr></thead>
      <tbody>
        <tr><td>命名节点匹配</td><td><code>(identifier)</code></td><td>按节点类型名匹配。</td></tr>
        <tr><td>匿名字面量匹配</td><td><code>"+"</code></td><td>按叶节点原文匹配。</td></tr>
        <tr><td>通配符</td><td><code>_</code></td><td>匹配任意单节点。</td></tr>
        <tr><td>字段约束</td><td><code>left: (identifier)</code></td><td>要求命中的子节点来自指定字段。</td></tr>
        <tr><td>子节点捕获</td><td><code>(identifier) @name</code></td><td>把命中的子模式节点加入返回结果。</td></tr>
        <tr><td>顶层捕获</td><td><code>(call_expression) @call</code></td><td>给整个顶层模式的命中节点打捕获。</td></tr>
        <tr><td>交替模式</td><td><code>[(identifier) (number)]</code></td><td>多个模式中命中任意一个即可。</td></tr>
        <tr><td>量词</td><td><code>(argument)*</code>、<code>(item)+</code>、<code>(type)?</code></td><td>作用于子节点模式。</td></tr>
        <tr><td>锚点</td><td><code>. (identifier)</code>、<code>(identifier) .</code></td><td>约束匹配贴近首个或末尾语义子节点。</td></tr>
        <tr><td>注释</td><td><code>; comment</code></td><td>从分号到行尾。</td></tr>
      </tbody>
    </table>

    <h2>典型结构模式</h2>
    <pre><code>(binary_expression
  left: (identifier) @lhs
  right: (identifier) @rhs)</code></pre>
    <p>这表示：</p>
    <ul>
      <li>匹配一个 <code>binary_expression</code> 节点。</li>
      <li>它的 <code>left</code> 字段必须命中一个 <code>identifier</code>。</li>
      <li>它的 <code>right</code> 字段也必须命中一个 <code>identifier</code>。</li>
      <li>左右两侧都作为捕获结果返回。</li>
    </ul>

    <h2>多条顶层模式</h2>
    <pre><code>(function_definition) @fn
(class_definition) @class</code></pre>
    <p>一个查询字符串可以包含多条顶层模式。它们会独立匹配、独立维护谓词，但最终结果会合并到同一个 <code>CaptureResult[]</code> 里，并通过 <code>match_id</code> 区分属于哪一次顶层命中。</p>

    <h2>顶层捕获与子捕获的区别</h2>
    <p>顶层捕获写在整个模式之后，子捕获写在子模式之后：</p>
    <pre><code>(call_expression
  function: (identifier) @callee
  arguments: (arguments)) @call</code></pre>
    <p>这个查询同时会返回 <code>callee</code> 和 <code>call</code> 两类捕获，但它们拥有相同的 <code>match_id</code>，因为都来自同一次顶层模式命中。</p>

    <h2>命名约定</h2>
    <p>查询字符串里捕获写作 <code>@name</code>，但 API 返回时会存为不带前缀的纯名称 <code>name</code>。同样地，locals 系列约定名称写成：</p>
    <ul>
      <li><code>@local.scope</code></li>
      <li><code>@local.definition</code></li>
      <li><code>@local.reference</code></li>
    </ul>
    <p>对调用方来说，这些会分别表现为 <code>local.scope</code>、<code>local.definition</code>、<code>local.reference</code>。</p>
  </article>
</template>