<template>
  <article>
    <h1>概览</h1>
    <p><code>wasm/</code> 是 MoonParse 面向 WebAssembly 宿主环境的桥接模块。它把 <code>grammar/</code>、<code>tablegen/</code>、<code>runtime/</code> 和 <code>query/</code> 的能力整理成浏览器、Node.js 或其他 WASM 宿主可以直接调用的导出 API。</p>

    <h2>整体位置</h2>
    <pre><code>Grammar DSL / Grammar JSON / ParseTable JSON / ParseTable Bytes
                           |
                           v
                        wasm/
                           |
                           v
               Parser Handle / Tree Handle / Query Handle
                           |
                           v
         JSON / S-expression / Cursor Navigation / Highlight Ranges</code></pre>

    <h2>模块分工</h2>
    <table>
      <thead><tr><th>文件</th><th>主要职责</th></tr></thead>
      <tbody>
        <tr><td><code>wasm.mbt</code></td><td>聚合主要导出，负责 parser 创建、全量解析、增量解析和兼容封装。</td></tr>
        <tr><td><code>handles.mbt</code></td><td>维护 parser、tree、cursor、query 的全局注册表。</td></tr>
        <tr><td><code>cursor.mbt</code></td><td>提供跨边界游标导航与节点属性查询。</td></tr>
        <tr><td><code>query.mbt</code></td><td>查询编译、执行和 locals 结果的 JSON 导出。</td></tr>
        <tr><td><code>highlight.mbt</code></td><td>高亮范围和 locals 联动高亮的 JSON 导出。</td></tr>
        <tr><td><code>cst_json.mbt</code></td><td>把 <code>CstNode</code> 序列化为树形 JSON。</td></tr>
        <tr><td><code>moonparse.js</code> / <code>moonparse.d.ts</code></td><td>浏览器和 Node.js 侧的高层 ES Module 封装与 TS 类型。</td></tr>
      </tbody>
    </table>

    <h2>两种调用风格</h2>
    <table>
      <thead><tr><th>风格</th><th>代表 API</th><th>适合场景</th></tr></thead>
      <tbody>
        <tr><td>低层句柄接口</td><td><code>parser_create_*</code>、<code>parse_full</code>、<code>cursor_new</code>、<code>query_compile</code></td><td>长期复用 parser、tree、cursor 和 query 的编辑器或 IDE 集成。</td></tr>
        <tr><td>高层便捷接口</td><td><code>wasm_create_parser</code>、<code>wasm_parse</code>、<code>wasm_query</code>，以及 <code>moonparse.js</code> 里的 <code>loadMoonParse()</code></td><td>快速接入、调试、一次性动作或 JS/TS 侧直接消费。</td></tr>
      </tbody>
    </table>

    <h2>先知道的三件事</h2>
    <ul>
      <li><code>wasm/</code> 的核心设计不是直接暴露 MoonBit 对象，而是通过整数句柄把 parser、tree、cursor 和 query 挂到全局注册表里。</li>
      <li>跨边界返回值大量采用 JSON 字符串，因为宿主最容易消费；如果追求最低序列化成本，应优先使用句柄加游标的模式。</li>
      <li><code>build --wasm</code> 生成的同名产物不等于这里的真实 WebAssembly runtime；真正面向 JS/浏览器宿主的是 <code>wasm/</code> 目录里的 <code>moonparse.wasm</code> 与 <code>moonparse.js</code>。</li>
    </ul>
  </article>
</template>