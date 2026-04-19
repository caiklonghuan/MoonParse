<template>
  <article>
    <h1>I/O 与报告</h1>
    <p>CLI 的可用性很大程度上取决于输出约定是否稳定。<code>cmd/main</code> 当前把“结果输出”和“诊断输出”分成两条通道：<code>print_info</code> 走 stdout，<code>print_err</code>、warning 和 error 走 stderr。</p>

    <h2>stdout / stderr 约定</h2>
    <table>
      <thead><tr><th>类型</th><th>默认通道</th><th>说明</th></tr></thead>
      <tbody>
        <tr><td>parse 树正文</td><td>stdout</td><td><code>parse</code> 的 S-expression、JSON、DOT 结果都经由 <code>print_info</code> 输出。</td></tr>
        <tr><td>query 捕获</td><td>stdout</td><td>文本 capture、JSON 和 <code>--count</code> 都是主要结果流。</td></tr>
        <tr><td>fmt --stdout</td><td>stdout</td><td>格式化后的 grammar 文本直接写到 stdout。</td></tr>
        <tr><td>状态消息</td><td>stdout 或 stderr</td><td>如 <code>written: ...</code>、<code>no errors</code> 走 stdout；汇总与告警走 stderr。</td></tr>
        <tr><td>调试辅助</td><td>stderr</td><td><code>parse --tokens</code> 的 token 列表、<code>generate --diagnostic</code> 的表 JSON 都走 stderr。</td></tr>
        <tr><td>错误定位</td><td>stderr</td><td>grammar、runtime、query 的失败诊断都附带文件位置与插入符。</td></tr>
      </tbody>
    </table>

    <h2>quiet 的实际语义</h2>
    <p><code>-q</code> / <code>--quiet</code> 并不是“只关掉状态日志”，而是直接关闭所有 <code>print_info</code> 输出。因此它会一并静默 parse 树、query 结果、<code>fmt --stdout</code>、help、version 以及部分成功摘要。warning 和 error 仍然会继续输出到 stderr。</p>

    <h2>颜色输出</h2>
    <p><code>init_reporter()</code> 默认根据 <code>isatty(2)</code> 检测 stderr 是否连接终端，再决定是否启用 ANSI 颜色；<code>--no-color</code> 则会在参数解析的最前面调用 <code>set_color_output(false)</code> 强制关闭颜色。</p>

    <h2>源码片段渲染</h2>
    <p>Reporter 会为 grammar 解析错误、validation 错误、runtime parse error 和 query compile error 渲染定位块，包含：</p>
    <ul>
      <li>带颜色的 <code>error</code> / <code>warning</code> / <code>help</code> 标签。</li>
      <li><code>--&gt; path:line:col</code> 形式的位置头。</li>
      <li>源代码行与 <code>^</code> 插入符，必要时附带 hint。</li>
    </ul>

    <h2>I/O 辅助函数</h2>
    <pre><code>read_file(path) -> Result[String, String]
read_bytes(path) -> Result[Bytes, String]
read_stdin() -> String

write_file(path, content) -> Result[Unit, String]
write_bytes(path, content) -> Result[Unit, String]

process_exit(code) -> Unit</code></pre>
    <p>这些函数把平台差异藏在实现层，对上面的命令处理器保持统一接口。文档层面更重要的是：大多数命令都明确区分“用户真正需要消费的结果”和“辅助诊断”，方便 shell pipeline 与 CI 只截取其中一部分。</p>
  </article>
</template>