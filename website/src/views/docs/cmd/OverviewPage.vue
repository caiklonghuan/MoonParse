<template>
  <article>
    <h1>概览</h1>
    <p><code>cmd/</code> 是 MoonParse 的命令行壳层。它负责把 grammar 校验、建表、分发产物输出、源码解析、结构化查询、corpus 回归测试以及统一的诊断输出整理成一组稳定的 CLI 子命令，供终端、脚本和 CI 直接使用。</p>

    <h2>建议的入口方式</h2>
    <p>本仓库里的示例默认使用仓库内入口：</p>
    <pre><code>moon run cmd/main -- &lt;subcommand&gt; ...</code></pre>
    <p>如果你已经把 CLI 单独封装成可执行文件，只需要把前缀替换成 <code>moonparse</code> 即可，子命令和参数语义保持一致。</p>

    <h2>在整体系统中的位置</h2>
    <pre><code>argv / stdin / files
        |
        v
       cmd/
        |
        +-- grammar   check / fmt / generate / dump
        +-- tablegen  ParseTable 生成、冲突报告、序列化
        +-- runtime   parse / test
        +-- query     query
        +-- reporter  统一诊断、颜色、stdout / stderr 约定</code></pre>

    <h2>能力分组</h2>
    <table>
      <thead><tr><th>类别</th><th>子命令</th><th>作用</th></tr></thead>
      <tbody>
        <tr><td>Grammar 质量门禁</td><td><code>check</code>、<code>fmt</code></td><td>校验 DSL、格式化 grammar，并用退出码区分 warning 与 error。</td></tr>
        <tr><td>产物生成与分发</td><td><code>generate</code>、<code>build</code>、<code>wasm</code></td><td>生成 <code>.parse_table</code>、构建 build/dist 目录，或生成 JS 胶水分发包。</td></tr>
        <tr><td>调试与排障</td><td><code>dump</code></td><td>输出 grammar IR、解析表 JSON 和 LR 自动机，定位冲突或状态机问题。</td></tr>
        <tr><td>输入消费</td><td><code>parse</code>、<code>query</code></td><td>解析源码、输出 CST、执行结构化匹配。</td></tr>
        <tr><td>回归与清理</td><td><code>test</code>、<code>clean</code></td><td>运行 corpus 回归测试，清理标准输出目录。</td></tr>
      </tbody>
    </table>

    <h2>先知道的三件事</h2>
    <ul>
      <li>全局参数只有 <code>--no-color</code> 与 <code>-q</code> / <code>--quiet</code>，而且必须放在子命令之前。</li>
      <li><code>--quiet</code> 会关闭所有 <code>print_info</code> 输出，因此也会一并静默 help、version、parse 树、query 结果和 <code>fmt --stdout</code>。</li>
      <li><code>build --wasm</code> 生成的是“与 parse table 同字节内容、但扩展名为 <code>.wasm</code> 的产物别名”，不是真正的 WebAssembly 运行时模块。</li>
    </ul>

    <h2>推荐阅读顺序</h2>
    <table>
      <thead><tr><th>如果你现在要做什么</th><th>建议先看</th><th>原因</th></tr></thead>
      <tbody>
        <tr><td>想先把命令串起来</td><td>示例</td><td>先从完整工作流建立直觉，再回头看单个 flag。</td></tr>
        <tr><td>想知道某个子命令的输入、输出和退出码</td><td>命令总览</td><td>这里把所有子命令的边界放在一张表里。</td></tr>
        <tr><td>想区分 <code>generate</code>、<code>build</code>、<code>wasm</code>、<code>dump</code></td><td>生成与分发</td><td>这几个命令最容易混淆，但目的并不相同。</td></tr>
        <tr><td>想把输出接进脚本或 CI</td><td>I/O 与报告</td><td>stdout / stderr 与退出码是脚本集成的核心协议。</td></tr>
      </tbody>
    </table>
  </article>
</template>