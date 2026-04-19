<template>
  <article>
    <h1>匹配与谓词</h1>
    <p><code>query/</code> 的执行不是“只要树形结构对上就算完”，它还包含有序子序列匹配、回溯、量词贪心以及谓词过滤。这个页面讲的是运行时行为，而不是语法表面。</p>

    <h2><code>exec()</code> 的整体策略</h2>
    <p><code>exec()</code> 会对整棵 CST 做先序 DFS，并在每个节点上尝试所有顶层模式。某条顶层模式命中后：</p>
    <ul>
      <li>子节点匹配采用“有序子序列 + 回溯”的策略。</li>
      <li>子模式之间的相对顺序必须保持。</li>
      <li>中间允许跳过不相关的语义子节点。</li>
      <li><code>extra</code> 子节点会被自动忽略。</li>
    </ul>

    <h2>量词行为</h2>
    <p>当前支持三类量词：</p>
    <pre><code>(item)?
(item)*
(item)+</code></pre>
    <p>匹配语义上采用“先尽量多吃，再为后续模式回溯”的策略。也就是说：</p>
    <ul>
      <li><code>*</code> 和 <code>+</code> 会先贪心收集尽可能多的候选。</li>
      <li>如果后续模式无法成立，匹配器会回退到较短的消费长度再尝试。</li>
      <li>因此量词和后续模式是协同决定最终边界的。</li>
    </ul>

    <h2>锚点行为</h2>
    <pre><code>(call_expression . (identifier) @callee)
(tuple (identifier)+ @item .)</code></pre>
    <p>前导锚点要求该子模式必须从当前剩余语义子节点的第一个位置开始，不允许先跳过别的节点。尾锚点则要求最后一次匹配结束后，后面不再有剩余语义子节点。即便最后一个子模式带量词，尾锚点同样生效。</p>

    <h2>后置谓词</h2>
    <p>当前实现支持五类谓词：</p>
    <pre><code>#eq? @capture "literal"
#not-eq? @capture "literal"
#match? @capture "regex"
#not-match? @capture "regex"
#any-of? @capture "a" "b" "c"</code></pre>

    <table>
      <thead><tr><th>谓词</th><th>作用</th></tr></thead>
      <tbody>
        <tr><td><code>#eq?</code></td><td>要求捕获文本与某个字面量完全相等。</td></tr>
        <tr><td><code>#not-eq?</code></td><td>要求捕获文本不等于某个字面量。</td></tr>
        <tr><td><code>#match?</code></td><td>要求捕获文本通过正则搜索。</td></tr>
        <tr><td><code>#not-match?</code></td><td>要求捕获文本不通过正则搜索。</td></tr>
        <tr><td><code>#any-of?</code></td><td>要求捕获文本落在给定字符串集合里。</td></tr>
      </tbody>
    </table>

    <h2>谓词的归属规则</h2>
    <p>谓词总是归属到它之前最近的一条顶层模式，而不是全局共享。下面这个查询里，两条模式拥有各自的过滤条件：</p>
    <pre><code>(identifier) @name
#match? @name "^[a-z]+$"

(number_literal) @num
#not-match? @num "^0"</code></pre>

    <h2>正则能力边界</h2>
    <p><code>#match?</code> 和 <code>#not-match?</code> 目前依赖 <code>matcher.mbt</code> 里的极简正则引擎，而不是完整 PCRE。它支持：</p>
    <ul>
      <li><code>^</code> 与行尾 <code>$</code></li>
      <li>字符类和取反字符类</li>
      <li><code>\d</code>、<code>\w</code>、<code>\s</code> 等常见转义</li>
      <li>分组、顶层交替和量词</li>
    </ul>
    <p>如果你要写很复杂的正则语义，最好先确认当前实现支持到哪一层，而不要默认它等价于成熟正则库。</p>
  </article>
</template>