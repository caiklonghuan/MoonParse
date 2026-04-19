<template>
  <article>
    <h1>概览</h1>
    <p>Cmd 页先只保留最常用命令入口、最小示例、常见任务和使用前自检。目标是让你尽快把 grammar 编译、解析、查询和测试这些命令串进真实工程，而不是先看实现细节。</p>

    <h2>用途</h2>
    <ul>
      <li>把 <code>.grammar</code> 编译成可缓存、可分发的 <code>.parse_table</code> 或 JSON 表。</li>
      <li>对输入执行解析和查询，并把结果稳定输出到 stdout / stderr。</li>
      <li>把 grammar 检查、格式化和 corpus 回归测试接进脚本或 CI。</li>
    </ul>

    <h2>最小示例</h2>
    <p>普通项目里最常见的一条命令链就是先检查、再生成、再消费预编译表。</p>
    <pre><code>moonparse check grammars/json.grammar
moonparse generate grammars/json.grammar -o build/json.parse_table
moonparse parse --table build/json.parse_table sample.json</code></pre>
    <table>
      <thead><tr><th>命令</th><th>作用</th></tr></thead>
      <tbody>
        <tr><td><code>check</code></td><td>先看 grammar 质量门禁和冲突诊断，不写文件。</td></tr>
        <tr><td><code>generate</code></td><td>把 grammar 编译成可复用的 ParseTable。</td></tr>
        <tr><td><code>parse</code></td><td>消费预编译表，输出 CST。</td></tr>
      </tbody>
    </table>

    <h2>常见任务从哪里进入</h2>
    <table>
      <thead><tr><th>现在要做什么</th><th>建议先看</th><th>原因</th></tr></thead>
      <tbody>
        <tr><td>想直接照着命令串起来</td><td>示例</td><td>这里给的是最常见 CLI 组合用法，而不是零散 flag 说明。</td></tr>
        <tr><td>想看某条命令支持哪些输入和退出码</td><td>命令总览</td><td>先建立整套 CLI 的命令边界和参数规则。</td></tr>
        <tr><td>想单独查 <code>generate</code> / <code>parse</code> / <code>query</code></td><td>对应命令页</td><td>集中看该命令的参数、输出和常见用法。</td></tr>
        <tr><td>想把命令结果接进脚本或 CI</td><td>I/O 与报告</td><td>这里集中说明 stdout / stderr、quiet 和诊断输出约定。</td></tr>
      </tbody>
    </table>

    <h2>使用前先自检</h2>
    <ul>
      <li>grammar 稳定后优先先生成表，再用 <code>--table</code> 走 <code>parse</code> / <code>query</code>。</li>
      <li><code>--quiet</code> 会抑制所有 <code>print_info</code> 输出，不只是状态日志，也包括很多命令主结果。</li>
      <li>如果需要缓存或分发结果，优先把 <code>generate</code> 变成单独步骤，而不是每次都现编 grammar。</li>
    </ul>
  </article>
</template>