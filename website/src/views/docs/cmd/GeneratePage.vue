<template>
  <article>
    <h1>generate</h1>
    <p><code>generate</code> 是 CLI 里最接近“编译步骤”的命令。它会读取 grammar DSL，做语法解析与语义校验，生成 ParseTable，并把结果以二进制或 JSON 形式写回磁盘。</p>

    <h2>使用方式</h2>
    <pre><code>moonparse generate &lt;file.grammar&gt; [options]

-o, --output &lt;path&gt;   输出文件路径，默认是 &lt;base&gt;.parse_table
--json                输出 JSON 形式的解析表
--diagnostic          把完整 parse table JSON 打到 stderr
--force               即使存在阻断性诊断也继续输出</code></pre>

    <h2>关于冲突与 force</h2>
    <table>
      <thead><tr><th>诊断类型</th><th>默认行为</th><th><code>--force</code> 后</th></tr></thead>
      <tbody>
        <tr><td>左递归</td><td>warning，继续生成</td><td>无变化</td></tr>
        <tr><td>普通 validation error</td><td>停止并返回 2</td><td>允许继续走 tablegen</td></tr>
        <tr><td><code>Ambiguous</code> 冲突</td><td>停止并返回 2</td><td>允许继续输出</td></tr>
        <tr><td><code>Warn</code> / <code>DynamicConflict</code> / <code>Declared</code></td><td>记录诊断但继续</td><td>无变化</td></tr>
      </tbody>
    </table>

    <h2>退出码</h2>
    <table>
      <thead><tr><th>退出码</th><th>含义</th></tr></thead>
      <tbody>
        <tr><td>0</td><td>无 warning、无 error，成功写出目标文件。</td></tr>
        <tr><td>1</td><td>文件已写出，但存在 warning 或 ambiguity 之外的诊断汇总。</td></tr>
        <tr><td>2</td><td>读取失败、grammar parse 失败、阻断性校验失败、表生成失败，或未加 <code>--force</code> 时遇到 ambiguity。</td></tr>
      </tbody>
    </table>

    <h2>示例</h2>
    <pre><code>moonparse generate grammars/json.grammar
moonparse generate grammars/json.grammar --json -o build/json.table.json
moonparse generate grammars/expr.grammar --diagnostic --force</code></pre>
    <p>如果后续会频繁执行 <code>parse</code> 或 <code>query</code>，优先把生成结果缓存成 <code>.parse_table</code>，避免每次都重新走 grammar 与 tablegen。</p>
  </article>
</template>