<template>
  <article>
    <h1>I/O 与报告</h1>
    <p><code>cmd/</code> 的一个核心价值不是“有多少命令”，而是“输出协议是否稳定”。当前实现把结果流、诊断流、颜色和静默模式都集中在 reporter 与 I/O 适配层里。</p>

    <h2>stdout / stderr 分工</h2>
    <table>
      <thead><tr><th>内容</th><th>默认通道</th><th>说明</th></tr></thead>
      <tbody>
        <tr><td><code>parse</code> 树正文</td><td>stdout</td><td>S-expression、JSON、DOT 和错误摘要都通过 <code>print_info</code> 输出。</td></tr>
        <tr><td><code>query</code> 结果</td><td>stdout</td><td>文本捕获、JSON 和 <code>--count</code> 都是主要结果流。</td></tr>
        <tr><td><code>fmt --stdout</code></td><td>stdout</td><td>格式化后的 grammar 文本属于主结果。</td></tr>
        <tr><td><code>written: ...</code>、<code>no tests found</code> 等普通信息</td><td>stdout</td><td>统一走 <code>print_info</code>。</td></tr>
        <tr><td>warning、error、summary、源码定位</td><td>stderr</td><td>通过 <code>print_warning</code>、<code>print_err</code> 和 <code>report_*</code> 系列函数输出。</td></tr>
        <tr><td>调试辅助</td><td>stderr</td><td>例如 <code>parse --tokens</code> 的 token 流，或 <code>generate --diagnostic</code> 的 parse table JSON。</td></tr>
      </tbody>
    </table>

    <h2><code>--quiet</code> 的真实语义</h2>
    <p><code>set_quiet(true)</code> 只关闭 <code>print_info</code>，不会关闭 <code>print_warning</code>、<code>print_err</code> 或任何 <code>report_*</code> 诊断。这意味着：</p>
    <ul>
      <li><code>parse</code> 的树正文会被静默。</li>
      <li><code>query</code> 的匹配结果会被静默。</li>
      <li><code>fmt --stdout</code>、help、version 也会被静默。</li>
      <li>warning 和 error 仍然会继续打印到 stderr。</li>
    </ul>
    <p>因此，<code>--quiet</code> 不是普通的“降噪日志级别”，而是会影响主结果输出的强语义开关。</p>

    <h2>颜色与源码定位</h2>
    <p><code>init_reporter()</code> 会通过 <code>isatty(2)</code> 检查 stderr 是否连接终端，再决定是否启用 ANSI 颜色。命令行上的 <code>--no-color</code> 则会在参数解析最前面调用 <code>set_color_output(false)</code> 强制关闭颜色。</p>
    <p>Reporter 当前会为以下错误输出源码定位块：</p>
    <ul>
      <li>grammar DSL 解析错误</li>
      <li>grammar validation 错误与 warning</li>
      <li>runtime 解析错误</li>
      <li>query pattern 编译错误</li>
    </ul>
    <p>定位块通常包含带颜色的 <code>error</code> / <code>warning</code> / <code>help</code> 标签、<code>--&gt; path:line:col</code> 位置头，以及带 <code>^</code> 的源码片段。</p>

    <h2>Reporter 公共函数</h2>
    <pre><code>init_reporter() -> Unit
set_color_output(Bool?) -> Unit
set_quiet(Bool) -> Unit

print_info(String) -> Unit
print_warning(String) -> Unit
print_err(String) -> Unit

report_grammar_parse_error(...) -> Unit
report_validation_errors(...) -> Unit
report_validation_warnings(...) -> Unit
report_conflicts(...) -> Unit
report_parse_error(...) -> Unit
report_query_error(...) -> Unit
report_summary(Int, Int) -> Unit</code></pre>

    <h2>I/O 适配层</h2>
    <pre><code>read_file(String) -> Result[String, String]
write_file(String, String) -> Result[Unit, String]
read_bytes(String) -> Result[Bytes, String]
write_bytes(String, Bytes) -> Result[Unit, String]
read_stdin() -> String
make_dir(String) -> Result[Unit, String]
remove_dir_all(String) -> Result[Unit, String]
process_exit(Int) -> Unit
isatty(Int) -> Bool</code></pre>
    <p>命令处理器全部依赖这层 facade，而不是直接触碰 native / wasm 平台差异。对调用者来说，更重要的是这层接口稳定地区分了“主结果”和“辅助诊断”，便于 shell pipeline、日志收集和 IDE 集成分别处理两类输出。</p>
  </article>
</template>