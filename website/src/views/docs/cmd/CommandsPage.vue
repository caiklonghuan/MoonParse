<template>
  <article>
    <h1>命令总览</h1>
    <p>这一页把 <code>cmd/main</code> 当前暴露的所有子命令、全局参数和参数解析规则放到一处，便于先建立“CLI 能做什么”的整体认知。</p>

    <h2>子命令列表</h2>
    <table>
      <thead><tr><th>命令</th><th>主要输入</th><th>主要输出</th><th>典型退出码</th></tr></thead>
      <tbody>
        <tr><td><code>generate</code></td><td><code>.grammar</code></td><td><code>.parse_table</code> 或 table JSON</td><td>0 成功，1 有诊断，2 致命错误</td></tr>
        <tr><td><code>parse</code></td><td>grammar / table + source</td><td>S-expression、JSON 或 DOT 形式的 CST</td><td>0 无 ERROR 节点，1 有 ERROR 节点，2 硬失败</td></tr>
        <tr><td><code>query</code></td><td>pattern + grammar / table + source</td><td>capture 文本、JSON 或 match 数量</td><td>0 成功，2 加载/编译/解析失败</td></tr>
        <tr><td><code>check</code></td><td><code>.grammar</code></td><td>校验与冲突诊断</td><td>0 正常，1 警告，2 错误</td></tr>
        <tr><td><code>fmt</code></td><td><code>.grammar</code></td><td>原地改写或 stdout 格式化结果</td><td>0 成功，1 仅 <code>--check</code> 时未格式化，2 错误</td></tr>
        <tr><td><code>test</code></td><td>corpus 规范字符串</td><td>通过/失败摘要</td><td>0 全通过，1 有失败，2 加载或编译失败</td></tr>
        <tr><td><code>help</code></td><td>可选子命令名</td><td>usage 文本</td><td>0</td></tr>
        <tr><td><code>version</code></td><td>无</td><td>版本字符串</td><td>0</td></tr>
      </tbody>
    </table>

    <h2>全局参数</h2>
    <pre><code>moonparse [global-options] &lt;command&gt; [options]

--no-color      禁用 ANSI 颜色输出
-q, --quiet     抑制所有经由 print_info 输出的内容</code></pre>
    <p>这两个全局参数只在子命令名前解析。也就是说，<code>moonparse --quiet parse grammar.grammar</code> 会生效，但把 <code>--quiet</code> 放到子命令后面，当前实现并不会把它当成通用 flag。</p>

    <h2>参数解析规则</h2>
    <table>
      <thead><tr><th>命令</th><th>位置参数规则</th></tr></thead>
      <tbody>
        <tr><td><code>generate</code></td><td>第一个非 flag 参数视为 grammar 文件。</td></tr>
        <tr><td><code>parse</code></td><td>若未出现 <code>--grammar</code> / <code>--table</code>，第一个位置参数视为 grammar 文件，第二个视为 input 文件。</td></tr>
        <tr><td><code>query</code></td><td>第一个位置参数是 query pattern，第二个位置参数是 input 文件；grammar 与 table 必须通过 flag 指定或提前用位置参数分配好上下文。</td></tr>
        <tr><td><code>test</code></td><td>当前只接收一个 corpus 规范字符串，而不是目录扫描模式。</td></tr>
      </tbody>
    </table>

    <h2>帮助与版本</h2>
    <pre><code>moonparse --help
moonparse help generate
moonparse --version</code></pre>
    <p><code>parse_args</code> 支持全局帮助、子命令帮助和版本查询。不过当前 <code>main.mbt</code> 只显式接通了 <code>generate</code>、<code>parse</code>、<code>check</code>、<code>fmt</code>、<code>query</code> 的帮助文本，<code>help test</code> 仍会回落到 unknown command 分支。</p>
  </article>
</template>