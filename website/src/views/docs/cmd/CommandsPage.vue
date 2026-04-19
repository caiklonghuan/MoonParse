<template>
  <article>
    <h1>命令总览</h1>
    <p>这一页按当前实现列出所有子命令、全局参数和位置参数规则。重点不是“理论上想支持什么”，而是“今天这个 CLI 实际会怎么解析和返回”。</p>

    <h2>子命令矩阵</h2>
    <table>
      <thead><tr><th>命令</th><th>主要输入</th><th>主要输出</th><th>退出码</th><th>备注</th></tr></thead>
      <tbody>
        <tr><td><code>generate</code></td><td><code>.grammar</code></td><td><code>.parse_table</code> 或 table JSON</td><td>0 / 1 / 2</td><td><code>--force</code> 可在存在 error 或 ambiguity 时继续写文件。</td></tr>
        <tr><td><code>build</code></td><td><code>.grammar</code> 或 <code>.parse_table</code></td><td><code>build/parser.parse_table</code>，可选 <code>parser.wasm</code></td><td>0 / 1 / 2</td><td><code>parser.wasm</code> 只是同字节内容的别名文件。</td></tr>
        <tr><td><code>wasm</code></td><td><code>-g grammar</code> 或 <code>-t table</code></td><td><code>dist/parser.js</code> + <code>parser.parse_table</code></td><td>0 / 1 / 2</td><td>不会直接产出真正的 wasm 运行时二进制。</td></tr>
        <tr><td><code>dump</code></td><td><code>ir</code> / <code>table</code> / <code>automaton</code> + 文件</td><td>stdout 调试视图</td><td>0 / 2</td><td><code>table</code> 目标还可直接读取 <code>.parse_table</code> 或 <code>.json</code>。</td></tr>
        <tr><td><code>parse</code></td><td>grammar 或 table + 输入</td><td>S-expression、JSON、DOT 或错误摘要</td><td>0 / 1 / 2</td><td><code>1</code> 表示解析树里存在 <code>ERROR</code> 节点。</td></tr>
        <tr><td><code>query</code></td><td>pattern + grammar/table + 输入</td><td>文本捕获、JSON 或匹配数量</td><td>0 / 2</td><td>成功时不区分“树干净”与“树含 ERROR 节点”。</td></tr>
        <tr><td><code>check</code></td><td><code>.grammar</code></td><td>stderr 诊断与汇总</td><td>0 / 1 / 2</td><td><code>1</code> 表示 warning，<code>2</code> 表示 error。</td></tr>
        <tr><td><code>fmt</code></td><td><code>.grammar</code></td><td>原地改写、stdout 文本或 stderr 状态</td><td>0 / 1 / 2</td><td><code>--check</code> 不一致时返回 <code>1</code>。</td></tr>
        <tr><td><code>test</code></td><td>corpus spec</td><td>通过/失败摘要</td><td>0 / 1 / 2</td><td>当前是单 spec 模式，不做目录扫描。</td></tr>
        <tr><td><code>clean</code></td><td>无</td><td>删除标准产物目录</td><td>0 / 2</td><td>当前 native 实现是 best-effort，通常返回 <code>0</code>。</td></tr>
        <tr><td><code>help</code></td><td>可选子命令名</td><td>usage 文本</td><td>0</td><td>通过 <code>print_info</code> 输出，因此会受 <code>--quiet</code> 影响。</td></tr>
        <tr><td><code>version</code></td><td>无</td><td>版本字符串</td><td>0</td><td>同样走 <code>print_info</code>。</td></tr>
      </tbody>
    </table>

    <h2>全局参数</h2>
    <pre><code>moon run cmd/main -- [global-options] &lt;command&gt; [options]

--no-color      禁用 ANSI 颜色输出
-q, --quiet     关闭所有 print_info 输出</code></pre>
    <p>这两个 flag 只在子命令之前解析。把它们放到子命令之后，并不会被当成通用参数处理。</p>

    <h2>位置参数与互斥规则</h2>
    <ul>
      <li><code>generate</code>、<code>check</code>、<code>fmt</code>：第一个非 flag 参数就是 grammar 文件。</li>
      <li><code>parse</code>：如果没有出现 <code>-g</code> / <code>-t</code>，第一个位置参数会被当成 grammar 文件，第二个位置参数才是输入文件；<code>-g</code> 与 <code>-t</code> 互斥。</li>
      <li><code>query</code>：第一个位置参数始终是 pattern，第二个才是输入文件；grammar 或 table 必须通过 <code>-g</code> / <code>-t</code> 显式给出。</li>
      <li><code>wasm</code>：位置参数只会被当成 grammar 文件；如果想走 table 路径，必须使用 <code>-t</code>。</li>
      <li><code>dump</code>：第一个位置参数是目标类型，第二个是输入文件。</li>
      <li><code>test</code>：只接收一个 spec 字符串，支持 <code>grammar:corpus</code> 或单独 <code>corpus.txt</code>。</li>
    </ul>

    <h2>帮助与版本</h2>
    <pre><code>moon run cmd/main -- --help
moon run cmd/main -- help wasm
moon run cmd/main -- --version</code></pre>
    <p>当前 <code>main</code> 已经接通了 <code>generate</code>、<code>parse</code>、<code>check</code>、<code>fmt</code>、<code>query</code>、<code>test</code>、<code>build</code>、<code>wasm</code>、<code>dump</code>、<code>clean</code> 的帮助文本。</p>
  </article>
</template>