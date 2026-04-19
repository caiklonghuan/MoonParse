<template>
  <article>
    <h1>Cursor、Query 与高亮</h1>
    <p>树一旦生成，后续的消费主要分成三类：按需遍历节点、结构化查询，以及生成高亮范围。这三条路径都依赖有效的 <code>tree_id</code>。</p>

    <h2>Cursor API</h2>
    <pre><code>cursor_new(treeId)
cursor_goto_first_child(cursorId)
cursor_goto_next_sibling(cursorId)
cursor_goto_parent(cursorId)

cursor_node_type(cursorId)
cursor_node_text(cursorId)
cursor_node_field(cursorId)
cursor_node_start_byte(cursorId)
cursor_node_end_byte(cursorId)
...</code></pre>
    <p>Cursor 适合宿主按需遍历，不必先拿到整棵树 JSON。导航函数返回的是 <code>1</code> 或 <code>0</code>，而不是布尔值；高层 JS wrapper 则把它们包成了真正的布尔返回。</p>

    <h2>低层查询接口</h2>
    <pre><code>query_compile(pattern) -> queryId
query_compile_error_last() -> String
query_exec(queryId, treeId) -> String
query_resolve_locals(queryId, treeId) -> String
query_free(queryId)</code></pre>
    <p>这里的返回值全部是 JSON 字符串。<code>query_exec()</code> 返回 capture 数组 JSON，<code>query_resolve_locals()</code> 返回 <code>{ start_byte: true }</code> 形式的映射 JSON。</p>

    <h2>高亮接口</h2>
    <pre><code>highlight_exec(queryId, treeId) -> String
highlight_exec_with_locals(hlQueryId, localsQueryId, treeId) -> String
highlight_names_json() -> String</code></pre>
    <p>高亮返回的是范围数组 JSON，而不是宿主对象。<code>highlight_exec_with_locals()</code> 会在普通高亮基础上叠加 locals 解析，把本地引用追加为 <code>.local</code> 名称后缀。</p>

    <h2><code>wasm_query()</code> 与编译后查询的区别</h2>
    <p><code>wasm_query(treeId, pattern)</code> 是一次性薄封装，适合快速调试或偶发查询；而 <code>query_compile()</code> 加 <code>query_exec()</code> 更适合缓存并反复执行相同查询模式。</p>

    <h2>JS wrapper 对应对象</h2>
    <table>
      <thead><tr><th>对象</th><th>典型方法</th><th>说明</th></tr></thead>
      <tbody>
        <tr><td><code>ParseTree</code></td><td><code>query(pattern)</code>、<code>highlight(hlQuery, locsQuery)</code>、<code>walk()</code></td><td>对单棵树做一次性查询、高亮或创建游标。</td></tr>
        <tr><td><code>MoonQuery</code></td><td><code>exec(tree)</code>、<code>resolveLocals(tree)</code></td><td>缓存已编译的查询对象。</td></tr>
        <tr><td><code>TreeCursor</code></td><td><code>gotoFirstChild()</code>、<code>gotoNextSibling()</code>、<code>gotoParent()</code></td><td>对象式包装底层 cursor 句柄。</td></tr>
      </tbody>
    </table>
    <p>值得注意的一点是：<code>ParseTree.query(pattern)</code> 走的是一次性 <code>wasm_query()</code> 路径，而不是复用 <code>MoonQuery</code> 对象。如果调用方会重复执行相同模式，应该显式使用 <code>compileQuery()</code>。</p>
  </article>
</template>