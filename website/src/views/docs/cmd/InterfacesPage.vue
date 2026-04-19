<template>
  <article>
    <h1>公共接口</h1>
    <p>虽然 <code>cmd/main</code> 主要是 CLI 入口包，但它对外暴露的接口并不只有一个 <code>main</code>。如果你要在别的 MoonBit 包里复用参数解析、命令处理器或 reporter，这一页是最直接的索引。</p>

    <h2>命令处理器</h2>
    <pre><code>cmd_generate(GenerateArgs) -> Int
cmd_parse(ParseArgs) -> Int
cmd_query(QueryArgs) -> Int
cmd_check(CheckArgs) -> Int
cmd_fmt(FmtArgs) -> Int
cmd_run_tests(TestArgs) -> Int</code></pre>

    <h2>参数与命令模型</h2>
    <pre><code>parse_args(Array[String]) -> Result[Command, String]

enum Command {
  Generate(GenerateArgs)
  Parse(ParseArgs)
  Check(CheckArgs)
  Fmt(FmtArgs)
  Query(QueryArgs)
  Test(TestArgs)
  Help(String?)
  Version
}

enum OutputFormat {
  Sexp
  Json
  Dot
}</code></pre>

    <h2>参数结构体</h2>
    <table>
      <thead><tr><th>类型</th><th>关键字段</th></tr></thead>
      <tbody>
        <tr><td><code>GenerateArgs</code></td><td><code>grammar_file</code>、<code>output</code>、<code>json</code>、<code>diagnostic</code>、<code>force</code></td></tr>
        <tr><td><code>ParseArgs</code></td><td><code>grammar_file</code>、<code>table_file</code>、<code>input_file</code>、<code>format</code>、<code>tokens</code>、<code>error_summary</code></td></tr>
        <tr><td><code>QueryArgs</code></td><td><code>pattern</code>、<code>input_file</code>、<code>grammar_file</code>、<code>table_file</code>、<code>json</code>、<code>count</code></td></tr>
        <tr><td><code>CheckArgs</code></td><td><code>grammar_file</code></td></tr>
        <tr><td><code>FmtArgs</code></td><td><code>grammar_file</code>、<code>check</code>、<code>stdout</code></td></tr>
        <tr><td><code>TestArgs</code></td><td><code>test_dir</code>，当前语义其实更接近单个 test spec</td></tr>
      </tbody>
    </table>

    <h2>Reporter 与 I/O 辅助</h2>
    <pre><code>init_reporter() -> Unit
set_color_output(Bool?) -> Unit
set_quiet(Bool) -> Unit

print_info(String) -> Unit
print_warning(String) -> Unit
print_err(String) -> Unit

report_grammar_parse_error(ParseError, String?, String?) -> Unit
report_validation_errors(Array[ValidationError], String?) -> Unit
report_validation_warnings(Array[ValidationError], String?) -> Unit
report_conflicts(Array[ConflictReport]) -> Unit
report_parse_error(runtime.ParseError, String?, String?) -> Unit
report_query_error(query.QueryError, String?) -> Unit
report_summary(Int, Int) -> Unit

read_file(String) -> Result[String, String]
read_bytes(String) -> Result[Bytes, String]
read_stdin() -> String
write_file(String, String) -> Result[Unit, String]
write_bytes(String, Bytes) -> Result[Unit, String]
process_exit(Int) -> Unit
isatty(Int) -> Bool</code></pre>

    <h2>入口选择</h2>
    <p>如果你只是想做“命令行参数转结构化命令”的前处理，可以复用 <code>parse_args</code>；如果你已经有自己的 shell 外壳，但希望沿用 MoonParse 的诊断风格，也可以直接复用 reporter 和各个 <code>report_*</code> 函数。</p>
  </article>
</template>