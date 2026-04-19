<template>
  <article>
    <h1>parse 与 query</h1>
    <p><code>parse</code> 和 <code>query</code> 共享同一条前半段路径：加载 parse table、读取输入、调用 runtime 生成 CST。两者的差别只发生在“树拿到以后”：<code>parse</code> 直接输出树，<code>query</code> 则继续编译并执行查询模式。</p>

    <h2><code>parse</code>：输出 CST</h2>
    <pre><code>moon run cmd/main -- parse (-g &lt;file.grammar&gt; | -t &lt;file.parse_table&gt;) [input-file] [options]

-g, --grammar &lt;file&gt;  现场编译 grammar
-t, --table &lt;file&gt;    直接加载预编译表
--format &lt;fmt&gt;        sexp | json | dot
--tokens              先把 token 流打印到 stderr
--error-summary       只输出 ERROR 节点汇总
--stdin               显式声明从 stdin 读取输入</code></pre>
    <p>参数解析上还有一个隐式规则：如果没有出现 <code>-g</code> / <code>-t</code>，第一个位置参数会被当成 grammar 文件，第二个位置参数才是输入文件。</p>

    <h3>输出与退出码</h3>
    <table>
      <thead><tr><th>场景</th><th>stdout / stderr 行为</th><th>退出码</th></tr></thead>
      <tbody>
        <tr><td>正常树且无 <code>ERROR</code> 节点</td><td>stdout 输出树正文</td><td><code>0</code></td></tr>
        <tr><td>runtime 成功，但树中包含 <code>ERROR</code> 节点</td><td>stdout 仍输出树或错误摘要</td><td><code>1</code></td></tr>
        <tr><td>grammar/table 加载失败，或 runtime 硬失败</td><td>stderr 输出诊断</td><td><code>2</code></td></tr>
      </tbody>
    </table>

    <ul>
      <li>默认格式是 S-expression。</li>
      <li><code>--format json</code> 输出树形 JSON；<code>--format dot</code> 输出 Graphviz DOT。</li>
      <li><code>--tokens</code> 会先在 stderr 打印 <code>--- tokens ---</code>、token 列表和 <code>--- tree ---</code>，然后再把正文写到 stdout。</li>
      <li><code>--error-summary</code> 不再输出整棵树，而是在 stdout 输出 <code>ERROR</code> 节点摘要；若没有错误节点，则输出 <code>no errors</code>。</li>
      <li>如果没有显式提供输入文件，命令默认就从 stdin 读取输入，<code>--stdin</code> 只是更显式的写法。</li>
    </ul>

    <h2><code>query</code>：在 CST 上做结构化匹配</h2>
    <pre><code>moon run cmd/main -- query &lt;pattern&gt; [input-file] [options]

-g, --grammar &lt;file&gt;  现场编译 grammar
-t, --table &lt;file&gt;    直接加载预编译表
--json                以 JSON 输出捕获结果
--count               只输出匹配总数</code></pre>
    <p><code>query</code> 的第一个位置参数始终是 pattern，第二个位置参数才是输入文件。与 <code>parse</code> 不同，它不会把位置参数解释成 grammar 路径，因此 <code>-g</code> / <code>-t</code> 是必填的。</p>

    <h3>输出与退出码</h3>
    <table>
      <thead><tr><th>模式</th><th>输出</th></tr></thead>
      <tbody>
        <tr><td>默认文本模式</td><td>按 <code>match id</code> 分组打印每个 capture 的范围和文本。</td></tr>
        <tr><td><code>--json</code></td><td>输出 capture 数组，包含 <code>match_id</code>、capture 名称、起止坐标和文本。</td></tr>
        <tr><td><code>--count</code></td><td>输出 match 数量，而不是 capture 条数。</td></tr>
      </tbody>
    </table>
    <p>命令成功时统一返回 <code>0</code>；只有 grammar/table 加载失败、runtime 失败或 query pattern 编译失败时才返回 <code>2</code>。</p>

    <h2>共享的一个重要限制</h2>
    <p>当 <code>parse</code> 或 <code>query</code> 走“现场编译 grammar”路径时，它们内部使用的是 <code>load_table_from_grammar</code>。这个辅助函数只会把普通 validation error 当成致命错误，但不会把冲突报告打印出来。因此，如果你关心 grammar 质量、冲突类型或 warning 汇总，应先单独运行 <code>check</code> 或 <code>generate</code>，而不要只看 <code>parse</code> / <code>query</code> 的表现。</p>

    <h2>示例</h2>
    <pre><code>moon run cmd/main -- parse grammars/json.grammar sample.json
moon run cmd/main -- parse -t out/json.parse_table sample.json --format json
moon run cmd/main -- parse -t out/json.parse_table --stdin --tokens

moon run cmd/main -- query '(pair key: (string) @key)' sample.json -g grammars/json.grammar
moon run cmd/main -- query '(number) @num' sample.json -t out/json.parse_table --json
moon run cmd/main -- query '(pair) @pair' sample.json -t out/json.parse_table --count</code></pre>
  </article>
</template>