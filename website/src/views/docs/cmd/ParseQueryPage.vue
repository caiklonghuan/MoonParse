<template>
  <article>
    <h1>parse 与 query</h1>
    <p><code>parse</code> 和 <code>query</code> 共享同一条“加载解析表 + 读取输入 + runtime 解析”的前半段路径。区别只在于前者把 CST 直接输出，后者会继续编译并执行查询模式。</p>

    <h2>parse</h2>
    <pre><code>moonparse parse &lt;file.grammar&gt; [input-file] [options]

-g, --grammar &lt;file&gt;  显式指定 grammar 文件
-t, --table &lt;file&gt;    显式指定 parse table 文件
--format &lt;fmt&gt;        sexp | json | dot
--tokens              先在 stderr 输出 token 流
--error-summary       只输出 ERROR 节点摘要
--stdin               明确声明从 stdin 读取输入</code></pre>
    <p>当前实现允许两种来源：直接给 grammar 现编，或给 <code>.parse_table</code> 直接加载。若没有显式指定 <code>--grammar</code> / <code>--table</code>，第一个位置参数会被当成 grammar 文件。</p>

    <h3>parse 的输出规则</h3>
    <ul>
      <li>默认输出 S-expression 形式的 CST。</li>
      <li><code>--format json</code> 输出节点的结构化 JSON；<code>--format dot</code> 输出 Graphviz DOT。</li>
      <li><code>--tokens</code> 会把 token 列表打印到 stderr，再继续输出树正文。</li>
      <li><code>--error-summary</code> 不再输出整棵树，而是输出 ERROR 节点汇总。</li>
      <li>即使 runtime 成功返回 CST，只要树中存在 ERROR 节点，退出码仍然是 1。</li>
    </ul>

    <h2>query</h2>
    <pre><code>moonparse query &lt;pattern&gt; [input-file] [options]

-g, --grammar &lt;file&gt;  从 grammar 现编表
-t, --table &lt;file&gt;    直接加载预编译表
--json                以 JSON 形式输出 capture 结果
--count               只输出 match 数量</code></pre>
    <p><code>query</code> 会先用 runtime 解析输入，再调用 <code>@query.compile</code> 编译模式，最后执行 <code>@query.exec</code>。因此它的失败来源包括三类：grammar / table 加载失败、runtime 解析失败、query pattern 编译失败。</p>

    <h3>query 的输出规则</h3>
    <ul>
      <li>默认按 <code>match id</code> 分组输出每个 capture 的位置和原文。</li>
      <li><code>--json</code> 输出 capture 数组，每项包含 <code>match_id</code>、capture 名称、起止位置和文本。</li>
      <li><code>--count</code> 输出的是 match 数量，不是 capture 行数。</li>
    </ul>

    <h2>示例</h2>
    <pre><code>moonparse parse grammars/json.grammar sample.json
moonparse parse --table build/json.parse_table sample.json --format json
moonparse parse grammars/json.grammar --stdin --tokens

moonparse query '(pair key: (string) @key)' sample.json --grammar grammars/json.grammar
moonparse query '(number) @num' sample.json --table build/json.parse_table --json
moonparse query '(pair) @pair' sample.json --table build/json.parse_table --count</code></pre>
  </article>
</template>