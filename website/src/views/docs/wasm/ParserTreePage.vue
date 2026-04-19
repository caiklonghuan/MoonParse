<template>
  <article>
    <h1>Parser 与 Tree</h1>
    <p>大多数宿主集成都会先接触两类资源：解析器句柄和语法树句柄。这一页只讲这条主线，不把增量、游标和查询掺进来。</p>

    <h2>四种 parser 创建来源</h2>
    <table>
      <thead><tr><th>入口</th><th>输入</th><th>适合场景</th></tr></thead>
      <tbody>
        <tr><td><code>parser_create_from_dsl</code></td><td>Grammar DSL 文本</td><td>开发期、调试期、在线 grammar 编辑。</td></tr>
        <tr><td><code>parser_create_from_grammar_json</code></td><td><code>grammar_to_json()</code> 导出的 Grammar JSON</td><td>grammar 已结构化持久化。</td></tr>
        <tr><td><code>parser_create_from_json</code></td><td><code>table_to_json()</code> 导出的 ParseTable JSON</td><td>离线建表，运行时直接回载。</td></tr>
        <tr><td><code>parser_create_from_bytes</code> / <code>parser_create_from_base64</code></td><td>二进制 ParseTable 或其 Base64 形式</td><td>启动速度更敏感的生产环境。</td></tr>
      </tbody>
    </table>
    <p>额外还有一个 <code>parser_create_from_json_with_builtin</code>，用于需要显式传入内置 grammar id 的预编译表路径，例如 Python 这类需要额外 scanner 语义的内置文法。</p>

    <h2>创建成功后能做什么</h2>
    <pre><code>parser_get_dsl(parserId)
parser_diagnostics_json(parserId)
parser_table_to_json(parserId)
parser_table_to_bytes(parserId)
parser_table_to_base64(parserId)</code></pre>
    <p>这些接口让 parser 不只是“可解析的黑盒”，还可以回读原始 DSL、查看冲突诊断，以及导出解析表到不同格式。</p>

    <h2>全量解析</h2>
    <pre><code>const treeId = api.parse_full(parserId, source)</code></pre>
    <p>低层 API 的 <code>parse_full()</code> 返回的是新的 <code>tree_id</code>。它只有在参数无效、解析表损坏等极端运行时异常时才返回 <code>-1</code>；对于普通的源码语法错误，通常仍会返回一棵包含 <code>ERROR</code> 或 <code>MISSING</code> 节点的树。</p>

    <h2>树级导出</h2>
    <table>
      <thead><tr><th>接口</th><th>用途</th></tr></thead>
      <tbody>
        <tr><td><code>tree_to_json(treeId)</code></td><td>导出完整树 JSON，适合宿主侧直接反序列化或序列化传输。</td></tr>
        <tr><td><code>tree_root_sexp(treeId)</code></td><td>导出 Tree-Sitter 风格的 S-expression，适合调试和快照对比。</td></tr>
        <tr><td><code>tree_error_summary(treeId)</code></td><td>导出简短状态摘要，例如 <code>ok</code> 或首个错误位置。</td></tr>
      </tbody>
    </table>

    <h2><code>parse_error_last()</code> 与 <code>tree_error_summary()</code> 的区别</h2>
    <p>这两个通道服务的不是同一类问题：</p>
    <ul>
      <li><code>parse_error_last()</code> 只在 <code>parse_full()</code> / <code>parse_incremental()</code> 返回 <code>-1</code> 的 fatal 场景下才有意义。</li>
      <li><code>tree_error_summary()</code> 用来描述一棵已经成功生成的树里是否存在语法恢复痕迹。</li>
    </ul>
    <p>不要把 <code>parse_error_last()</code> 当成“普通源码语法错误摘要”。普通源码错误通常仍然表现为一棵可用但带恢复节点的树。</p>
  </article>
</template>