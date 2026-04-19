<template>
  <article>
    <h1>公共接口</h1>
    <p>这一页对应的是 <code>query/pkg.generated.mbti</code> 当前导出的公开接口，也就是其他 MoonBit 包能直接复用的稳定 API 面。</p>

    <h2>核心函数</h2>
    <pre><code>compile(String) -> Result[CompiledQuery, QueryError]
exec(CompiledQuery, CstNode, String, ParseTable) -> Array[CaptureResult]

apply_highlights(CstNode, String, ParseTable, CompiledQuery)
  -> Array[HighlightRange]

apply_highlights_with_locals(
  CstNode,
  String,
  ParseTable,
  CompiledQuery,
  CompiledQuery,
) -> Array[HighlightRange]

resolve_locals(CstNode, String, ParseTable, CompiledQuery)
  -> LocalResolution

node_type_name(CstNode, ParseTable) -> String
node_text(CstNode, String) -> String</code></pre>

    <h2>公开常量</h2>
    <pre><code>highlight_names : Array[String]</code></pre>
    <p>这是高亮名称的白名单常量，供上层主题系统或 token 映射层参考。</p>

    <h2>主要类型</h2>
    <table>
      <thead><tr><th>类型</th><th>关键字段</th><th>说明</th></tr></thead>
      <tbody>
        <tr><td><code>CompiledQuery</code></td><td><code>patterns</code>、<code>predicates</code></td><td>查询编译结果，保存顶层模式与对应谓词。</td></tr>
        <tr><td><code>CaptureResult</code></td><td><code>match_id</code>、<code>capture_name</code>、<code>node</code></td><td><code>exec()</code> 的返回单元。</td></tr>
        <tr><td><code>HighlightRange</code></td><td><code>start_byte</code>、<code>end_byte</code>、<code>start_point</code>、<code>end_point</code>、<code>highlight_name</code></td><td>高亮区间。</td></tr>
        <tr><td><code>LocalResolution</code></td><td><code>local_refs</code></td><td>局部引用解析结果，并提供 <code>is_local_ref()</code>。</td></tr>
        <tr><td><code>PatternChild</code></td><td><code>field</code>、<code>pattern</code>、<code>capture</code>、<code>quantifier</code>、<code>anchor_before</code>、<code>anchor_after</code></td><td>对子模式的完整约束包装。</td></tr>
      </tbody>
    </table>

    <h2>枚举类型</h2>
    <pre><code>enum QueryPattern {
  NodePattern(String, Array[PatternChild])
  AnonPattern(String)
  Wildcard
  Alternation(Array[QueryPattern])
}

enum Predicate {
  Eq(String, String)
  NotEq(String, String)
  Match(String, String)
  NotMatch(String, String)
  AnyOf(String, Array[String])
}

enum Quantifier {
  One
  ZeroOrOne
  ZeroOrMore
  OneOrMore
}

enum QueryError {
  ParseError(Int, String)
}</code></pre>

    <h2>接口边界</h2>
    <ul>
      <li><code>query/</code> 对外不暴露内部 parser 或 matcher 的实现细节，只暴露编译结果、执行结果和派生工具。</li>
      <li><code>QueryError</code> 目前只有 <code>ParseError(offset, message)</code> 一种错误形态，因此错误定位以字符偏移为核心。</li>
      <li>高亮和 locals 都建立在同一套 <code>CompiledQuery</code> 之上，而不是单独定义另一套 DSL。</li>
    </ul>
  </article>
</template>