<template>
  <article>
    <h1>边界模型</h1>
    <p><code>wasm/</code> 的关键不是“导出了多少函数”，而是它如何在宿主世界和 MoonBit GC 对象之间建立一层可管理的边界。先理解这个模型，再看 API 会更清楚。</p>

    <h2>四类资源句柄</h2>
    <table>
      <thead><tr><th>资源</th><th>句柄</th><th>作用</th></tr></thead>
      <tbody>
        <tr><td>解析器</td><td><code>parser_id</code></td><td>保存编译后的 ParseTable、DSL 和编译诊断。</td></tr>
        <tr><td>语法树</td><td><code>tree_id</code></td><td>保存解析结果树、原始输入和表快照。</td></tr>
        <tr><td>游标</td><td><code>cursor_id</code></td><td>表示树上的当前位置及回溯路径。</td></tr>
        <tr><td>查询对象</td><td><code>query_id</code></td><td>保存已编译的结构化查询。</td></tr>
      </tbody>
    </table>
    <p>这四类资源的生命周期彼此独立。尤其是 <code>tree_id</code> 内部已经保存了输入和表快照，所以后续游标、查询和高亮并不要求原始 parser 仍然存活。</p>

    <h2>返回值约定</h2>
    <ul>
      <li><code>&gt;= 1</code> 通常表示有效句柄。</li>
      <li><code>-1</code> 常表示创建或解析失败。</li>
      <li><code>""</code>、<code>"[]"</code>、<code>"{}"</code>、<code>0</code> 等空值常表示无效输入、失败降级或空结果。</li>
    </ul>
    <p>因此，宿主侧不应假设所有错误都会抛异常。低层导出更接近 C 风格 API，必须显式检查返回值；只有高层 <code>moonparse.js</code> wrapper 才会把部分失败转换成 JavaScript 异常。</p>

    <h2>JSON 字符串为何是主要交换格式</h2>
    <p>完整树、查询结果、高亮区间和诊断信息大量以 JSON 字符串返回，原因是：</p>
    <ul>
      <li>浏览器和 Node.js 可以直接消费。</li>
      <li>不需要共享复杂内存布局。</li>
      <li>适合调试、日志和网络传输。</li>
      <li>和查询结果、高亮范围这类结构化结果天然匹配。</li>
    </ul>
    <p>代价是整树序列化存在额外开销，所以在高频交互场景下，句柄加游标通常比反复导出完整 JSON 更合适。</p>

    <h2>低层导出与高层 JS wrapper 的关系</h2>
    <p><code>moonparse.js</code> 并没有发明一套新能力，而是把底层导出组织成更符合 JS/TS 习惯的对象模型：</p>
    <ul>
      <li><code>MoonParser</code> 包装 parser 句柄。</li>
      <li><code>ParseTree</code> 包装 tree 句柄。</li>
      <li><code>TreeCursor</code> 包装 cursor 句柄。</li>
      <li><code>MoonQuery</code> 包装 query 句柄。</li>
    </ul>
    <p>调用方可以根据需求在两层之间自由选择，而不必被迫只走其中一种。</p>
  </article>
</template>