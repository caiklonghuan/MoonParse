<template>
  <article>
    <h1>核心概念</h1>
    <p><code>query/</code> 的 API 面不大，但背后有几组关键数据结构。先理解这些类型，后面读查询语言和调用方式会更顺。</p>

    <h2><code>CompiledQuery</code></h2>
    <p><code>CompiledQuery</code> 是一次查询编译的结果。它内部包含两部分：</p>
    <ul>
      <li><code>patterns</code>：顶层模式数组，每项是 <code>(QueryPattern, String?)</code>，第二个元素表示可选的顶层捕获名。</li>
      <li><code>predicates</code>：与顶层模式一一对应的谓词数组。</li>
    </ul>
    <p>这意味着一个查询字符串可以包含多条并列顶层模式，而且每条模式都维护自己的谓词集合。</p>

    <h2><code>QueryPattern</code> 与 <code>PatternChild</code></h2>
    <pre><code>enum QueryPattern {
  NodePattern(String, Array[PatternChild])
  AnonPattern(String)
  Wildcard
  Alternation(Array[QueryPattern])
}</code></pre>
    <p><code>QueryPattern</code> 描述“匹配什么”，而 <code>PatternChild</code> 描述“某个子位置需要满足的完整约束”。一个 <code>PatternChild</code> 同时携带字段约束、子模式、捕获名、量词和首尾锚点，而不是只表示一个简单的子节点类型。</p>

    <h2><code>Predicate</code></h2>
    <pre><code>enum Predicate {
  Eq(String, String)
  NotEq(String, String)
  Match(String, String)
  NotMatch(String, String)
  AnyOf(String, Array[String])
}</code></pre>
    <p>谓词总是在模式已经命中后，基于捕获文本做后置过滤。任何一个谓词失败，都会让这一次顶层命中整体失效。</p>

    <h2><code>CaptureResult</code></h2>
    <p><code>CaptureResult</code> 是 <code>exec()</code> 的核心返回单元，包含：</p>
    <ul>
      <li><code>match_id</code>：该捕获属于哪一次顶层模式命中。</li>
      <li><code>capture_name</code>：捕获名称，不带 <code>@</code>。</li>
      <li><code>node</code>：命中的 CST 节点。</li>
    </ul>
    <p>它不会直接拷贝文本内容。如果需要文本，应通过 <code>node_text(capture.node, input)</code> 获取。</p>

    <h2><code>HighlightRange</code> 与 <code>LocalResolution</code></h2>
    <table>
      <thead><tr><th>类型</th><th>面向场景</th><th>关键字段</th></tr></thead>
      <tbody>
        <tr><td><code>HighlightRange</code></td><td>语法高亮与语义高亮</td><td><code>start_byte</code>、<code>end_byte</code>、<code>start_point</code>、<code>end_point</code>、<code>highlight_name</code></td></tr>
        <tr><td><code>LocalResolution</code></td><td>局部变量引用识别</td><td><code>local_refs</code>，以及查询方法 <code>is_local_ref(start_byte)</code></td></tr>
      </tbody>
    </table>

    <h2><code>node_type_name()</code> 与 <code>node_text()</code></h2>
    <p>这两个函数是最常用的辅助工具：</p>
    <ul>
      <li><code>node_type_name(node, table)</code> 返回查询语义下的节点类型名，会优先尊重别名。</li>
      <li><code>node_text(node, input)</code> 返回节点覆盖的原始文本切片。</li>
    </ul>
    <p>如果调用方要做导航、消息格式化或二次过滤，通常都会先用这两个函数把结果转成更稳定的人类可读形式。</p>
  </article>
</template>