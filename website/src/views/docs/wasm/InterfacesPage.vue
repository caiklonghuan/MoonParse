<template>
  <article>
    <h1>公共接口</h1>
    <p>这一页对应的是 <code>wasm/pkg.generated.mbti</code> 当前真正导出的低层接口，并补充 <code>moonparse.js</code> / <code>moonparse.d.ts</code> 暴露给 JS/TS 调用方的高层 API。</p>

    <h2>低层导出分组</h2>
    <table>
      <thead><tr><th>类别</th><th>主要 API</th></tr></thead>
      <tbody>
        <tr><td>Parser 生命周期</td><td><code>parser_create_from_dsl</code>、<code>parser_create_from_json</code>、<code>parser_create_from_json_with_builtin</code>、<code>parser_create_from_bytes</code>、<code>parser_create_from_base64</code>、<code>parser_create_from_grammar_json</code>、<code>parser_free</code></td></tr>
        <tr><td>Parser 元信息</td><td><code>parser_get_dsl</code>、<code>parser_diagnostics_json</code>、<code>parser_dsl_error_last</code>、<code>parser_table_to_json</code>、<code>parser_table_to_bytes</code>、<code>parser_table_to_base64</code></td></tr>
        <tr><td>解析与树生命周期</td><td><code>parse_full</code>、<code>parse_incremental</code>、<code>tree_to_json</code>、<code>tree_root_sexp</code>、<code>tree_error_summary</code>、<code>tree_free</code></td></tr>
        <tr><td>游标</td><td><code>cursor_new</code>、<code>cursor_free</code>、<code>cursor_goto_*</code>、<code>cursor_node_*</code></td></tr>
        <tr><td>查询与高亮</td><td><code>query_compile</code>、<code>query_compile_error_last</code>、<code>query_exec</code>、<code>query_resolve_locals</code>、<code>query_free</code>、<code>highlight_exec</code>、<code>highlight_exec_with_locals</code>、<code>highlight_names_json</code></td></tr>
        <tr><td>配置与辅助</td><td><code>parse_config_set</code>、<code>parse_config_reset</code>、<code>parse_error_last</code>、<code>grammar_validate_dsl</code>、<code>builtin_grammars_json</code>、<code>tree_byte_offset_to_char_col</code>、<code>moonparse_version</code></td></tr>
        <tr><td>兼容性薄封装</td><td><code>wasm_create_parser</code>、<code>wasm_create_parser_from_json</code>、<code>wasm_parse</code>、<code>wasm_parse_incremental</code>、<code>wasm_node_sexp</code>、<code>wasm_query</code>、<code>wasm_free_tree</code>、<code>wasm_free_parser</code></td></tr>
      </tbody>
    </table>

    <h2>高层 JS / TS API</h2>
    <pre><code>loadMoonParse(wasmUrl?) -> Promise[MoonParseInstance]

MoonParseInstance:
  createParser(dsl)
  createParserFromJson(tableJson, builtinId?)
  createParserFromBytes(bytes)
  createParserFromGrammarObject(grammarObj)
  compileQuery(pattern)
  highlightNames()
  validateDsl(dsl)
  validateDslErrors(dsl)
  version()
  parseErrorLast()
  setParseConfig(config)
  resetParseConfig()
  byteOffsetToCharCol(source, line, colBytes)</code></pre>

    <h2>JS wrapper 核心对象</h2>
    <table>
      <thead><tr><th>对象</th><th>主要方法</th></tr></thead>
      <tbody>
        <tr><td><code>MoonParser</code></td><td><code>parse()</code>、<code>parseIncremental()</code>、<code>tableJson()</code>、<code>tableBytes()</code>、<code>diagnosticsJson()</code>、<code>free()</code></td></tr>
        <tr><td><code>ParseTree</code></td><td><code>json</code>、<code>root</code>、<code>sexp()</code>、<code>errorSummary()</code>、<code>query()</code>、<code>walk()</code>、<code>highlight()</code>、<code>free()</code></td></tr>
        <tr><td><code>TreeCursor</code></td><td>节点属性 getter 与 <code>gotoFirstChild()</code> / <code>gotoNextSibling()</code> / <code>gotoParent()</code></td></tr>
        <tr><td><code>MoonQuery</code></td><td><code>exec(tree)</code>、<code>resolveLocals(tree)</code>、<code>free()</code></td></tr>
      </tbody>
    </table>

    <h2>接口边界上的几个细节</h2>
    <ul>
      <li>低层导出通常返回句柄或 JSON 字符串；高层 JS wrapper 则把部分失败转换为异常并返回对象。</li>
      <li><code>cursor_node_*()</code> 在低层导出里是散开的多个函数，而 JS wrapper 把它们汇总成了属性式 API。</li>
      <li><code>query_resolve_locals()</code> 是低层导出，但 JS wrapper 只把它包进了 <code>MoonQuery.resolveLocals()</code>，没有做额外数据模型层。</li>
    </ul>
  </article>
</template>