<template>
  <article>
    <h1>公共接口</h1>
    <p>这一页对应的是 <code>cmd/main/pkg.generated.mbti</code> 当前真正导出的包接口，而不是单纯的 CLI 概念说明。换句话说，它描述的是“别的 MoonBit 包可以直接调用什么”。</p>

    <h2>当前公开的命令处理器</h2>
    <pre><code>cmd_build(BuildArgs) -> Int
cmd_check(CheckArgs) -> Int
cmd_clean(CleanArgs) -> Int
cmd_dump(DumpArgs) -> Int
cmd_fmt(FmtArgs) -> Int
cmd_generate(GenerateArgs) -> Int
cmd_parse(ParseArgs) -> Int
cmd_query(QueryArgs) -> Int
cmd_run_tests(TestArgs) -> Int
cmd_wasm(WasmArgs) -> Int</code></pre>
    <p>这些函数都返回整型退出码，因此它们既能被 <code>main</code> 调度，也能被上层封装到你自己的命令行外壳或测试驱动里。</p>

    <h2>参数解析与命令 AST</h2>
    <pre><code>parse_args(Array[String]) -> Result[Command, String]

enum Command {
  Generate(GenerateArgs)
  Parse(ParseArgs)
  Check(CheckArgs)
  Fmt(FmtArgs)
  Query(QueryArgs)
  Test(TestArgs)
  Build(BuildArgs)
  Wasm(WasmArgs)
  Dump(DumpArgs)
  Clean(CleanArgs)
  Help(String?)
  Version
}</code></pre>
    <p><code>parse_args</code> 会先消费全局 flag，再把命令行转换为强类型的 <code>Command</code>。这意味着如果你要复用 CLI 语法，可以直接消费命令 AST，而不必自己再写一层字符串分发。</p>

    <h2>关键类型</h2>
    <table>
      <thead><tr><th>类型</th><th>关键字段</th><th>用途</th></tr></thead>
      <tbody>
        <tr><td><code>GenerateArgs</code></td><td><code>grammar_file</code>、<code>output</code>、<code>json</code>、<code>diagnostic</code>、<code>force</code></td><td>生成单文件 parse table 或 JSON 表。</td></tr>
        <tr><td><code>BuildArgs</code></td><td><code>input</code>、<code>outdir</code>、<code>wasm</code></td><td>构建标准 build 目录。</td></tr>
        <tr><td><code>WasmArgs</code></td><td><code>grammar_file</code>、<code>table_file</code>、<code>outdir</code></td><td>构建 JS 胶水 + parse table 的 dist 目录。</td></tr>
        <tr><td><code>ParseArgs</code></td><td><code>grammar_file</code>、<code>table_file</code>、<code>input_file</code>、<code>format</code>、<code>tokens</code>、<code>error_summary</code></td><td>控制解析输入和 CST 输出格式。</td></tr>
        <tr><td><code>QueryArgs</code></td><td><code>pattern</code>、<code>input_file</code>、<code>grammar_file</code>、<code>table_file</code>、<code>json</code>、<code>count</code></td><td>执行结构化查询并决定输出形式。</td></tr>
        <tr><td><code>FmtArgs</code> / <code>CheckArgs</code> / <code>TestArgs</code></td><td>grammar 路径、模式标志、spec</td><td>分别对应格式化、校验和 corpus 回归。</td></tr>
        <tr><td><code>DumpArgs</code></td><td><code>target</code>、<code>input</code></td><td>选择 IR、table 或 automaton 调试视图。</td></tr>
        <tr><td><code>CleanArgs</code></td><td><code>force</code></td><td>目前是保留字段，当前实现总是直接执行清理。</td></tr>
      </tbody>
    </table>

    <h2>辅助枚举</h2>
    <pre><code>enum OutputFormat {
  Sexp
  Json
  Dot
}

enum DumpTarget {
  Ir
  Table
  Automaton
}</code></pre>

    <h2>Reporter 与 I/O 公共面</h2>
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
make_dir(String) -> Result[Unit, String]
remove_dir_all(String) -> Result[Unit, String]
process_exit(Int) -> Unit
isatty(Int) -> Bool</code></pre>

    <h2>当前没有公开的部分</h2>
    <ul>
      <li><code>main()</code> 是可执行入口，不属于包公开接口。</li>
      <li><code>cmd_util</code> 里的 <code>load_table_from_grammar</code>、<code>cst_to_sexp</code>、<code>cst_to_dot</code> 等工具函数都保持为包内私有。</li>
    </ul>
  </article>
</template>