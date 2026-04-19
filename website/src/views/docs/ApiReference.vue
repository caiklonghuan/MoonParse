<template>
  <article>
    <h1>API 参考</h1>
    <p>本页汇总 <code>moonparse.js</code> 对外暴露的核心类、方法和数据结构，基于 <code>src/lib/moonparse.js</code> 实际实现。</p>

    <h2>loadMoonParse(wasmUrl?)</h2>
    <p>异步加载并实例化 WASM 运行时，返回一个 <code>MoonParseInstance</code>。</p>
    <pre><code>import { loadMoonParse } from './moonparse.js'
const mp = await loadMoonParse('./moonparse.wasm')</code></pre>
    <table>
      <thead><tr><th>参数</th><th>类型</th><th>说明</th></tr></thead>
      <tbody>
        <tr><td><code>wasmUrl</code></td><td><code>string?</code></td><td><code>moonparse.wasm</code> 的访问地址，默认是 <code>./moonparse.wasm</code>。</td></tr>
      </tbody>
    </table>

    <h2>MoonParseInstance</h2>
    <p>由 <code>loadMoonParse()</code> 返回的顶层对象，持有整个 MoonParse WASM 实例。</p>

    <h3>mp.createParser(dsl)</h3>
    <p>编译文法 DSL 并返回一个 <code>MoonParser</code>。若文法非法会抛出错误信息。创建后的解析器需要调用 <code>parser.free()</code> 释放。</p>
    <table>
      <thead><tr><th>参数</th><th>类型</th><th>说明</th></tr></thead>
      <tbody>
        <tr><td><code>dsl</code></td><td><code>string</code></td><td>文法 DSL 源码。</td></tr>
      </tbody>
    </table>

    <h3>mp.createParserFromJson(tableJson, builtinId?)</h3>
    <p>使用 <code>parser.tableJson()</code> 导出的解析表 JSON 恢复解析器，适合做缓存或预编译加载。当提供 <code>builtinId</code> 时，会使用 <code>parser_create_from_json_with_builtin</code> 来关联内置词法规则。</p>
    <table>
      <thead><tr><th>参数</th><th>类型</th><th>说明</th></tr></thead>
      <tbody>
        <tr><td><code>tableJson</code></td><td><code>string</code></td><td>由 <code>parser.tableJson()</code> 序列化的解析表 JSON。</td></tr>
        <tr><td><code>builtinId</code></td><td><code>string?</code></td><td>内置文法 ID（如 <code>"json"</code>），默认为 <code>null</code>。</td></tr>
      </tbody>
    </table>

    <h3>mp.validateGrammarDsl(dsl)</h3>
    <p>对 DSL 进行语法和语义校验，返回 <code>Diagnostic[]</code> 错误数组，合法时返回空数组。不抛异常，适合用于编辑器实时反馈。每条诊断对象包含 <code>rule</code>（相关规则名）和 <code>message</code>（错误描述）字段。</p>
    <table>
      <thead><tr><th>参数</th><th>类型</th><th>说明</th></tr></thead>
      <tbody>
        <tr><td><code>dsl</code></td><td><code>string</code></td><td>待校验的文法 DSL 源码。</td></tr>
      </tbody>
    </table>
    <pre><code>// 返回示例（有错误时）
[{ "rule": "expr", "message": "undefined rule: expr" }]</code></pre>

    <h3>mp.compileQuery(pattern)</h3>
    <p>编译查询模式并返回 <code>MoonQuery</code>。如果模式语法错误会抛出异常，用完后应调用 <code>q.free()</code>。</p>

    <h3>mp.highlightNames()</h3>
    <p>返回内置高亮查询支持的捕获名列表（<code>string[]</code>），例如 <code>"string"</code>、<code>"number"</code>、<code>"keyword"</code> 等。</p>

    <h3>mp.builtinGrammars()</h3>
    <p>返回内置文法字典 <code>Record&lt;string, string&gt;</code>，键为文法 ID（如 <code>"json"</code>、<code>"moonbit"</code>），值为对应 DSL 源码。可用于列举可用语言或恢复预编译解析器。</p>
    <pre><code>const grammars = mp.builtinGrammars()
// { "json": "start value\n...", "moonbit": "...", ... }</code></pre>

    <h3>mp.setParseConfig(cfg)</h3>
    <p>调整解析器的容错代价参数，影响错误恢复行为。所有字段均可选，省略时沿用 WASM 内部默认值（传 <code>-1</code> 表示不更新）。</p>
    <table>
      <thead><tr><th>字段</th><th>类型</th><th>说明</th></tr></thead>
      <tbody>
        <tr><td><code>error_cost_per_skipped_tree</code></td><td><code>number?</code></td><td>跳过一棵子树的代价。</td></tr>
        <tr><td><code>error_cost_per_skipped_char</code></td><td><code>number?</code></td><td>跳过一个字符的代价。</td></tr>
        <tr><td><code>error_cost_per_skipped_line</code></td><td><code>number?</code></td><td>跳过一行的代价。</td></tr>
        <tr><td><code>error_cost_per_missing_tree</code></td><td><code>number?</code></td><td>插入缺失节点的代价。</td></tr>
        <tr><td><code>error_cost_per_recovery</code></td><td><code>number?</code></td><td>进行一次错误恢复的代价。</td></tr>
        <tr><td><code>max_version_count</code></td><td><code>number?</code></td><td>GLR 解析版本数上限。</td></tr>
        <tr><td><code>max_version_count_overflow</code></td><td><code>number?</code></td><td>GLR 版本溢出时允许的额外数量。</td></tr>
      </tbody>
    </table>

    <h3>mp.resetParseConfig()</h3>
    <p>将解析代价配置重置为 WASM 内部默认值，等价于撤销所有 <code>setParseConfig()</code> 的修改。</p>

    <h3>mp.version()</h3>
    <p>返回当前运行时版本号字符串，例如 <code>"0.1.0"</code>。</p>

    <h2>MoonParser</h2>
    <p>编译好的文法解析器，由 <code>mp.createParser()</code>、<code>mp.createParserFromJson()</code> 或 <code>mp.createParserFromGrammarObject()</code> 创建。</p>

    <h3>parser.parse(source)</h3>
    <p>对 <code>source</code> 做一次完整解析，返回新的 <code>ParseTree</code>。</p>
    <table>
      <thead><tr><th>参数</th><th>类型</th><th>说明</th></tr></thead>
      <tbody>
        <tr><td><code>source</code></td><td><code>string</code></td><td>待解析的源码文本。</td></tr>
      </tbody>
    </table>

    <h3>parser.parseIncremental(source, oldTree, edit)</h3>
    <p>执行增量重新解析。MoonParse 会复用 <code>oldTree</code> 中未受修改影响的子树，并返回一棵新的 <code>ParseTree</code>。<strong>调用完成后 <code>oldTree</code> 的 WASM 句柄会被置为 <code>-1</code>（失效），调用方不应再继续使用该对象。</strong></p>
    <table>
      <thead><tr><th>参数</th><th>类型</th><th>说明</th></tr></thead>
      <tbody>
        <tr><td><code>source</code></td><td><code>string</code></td><td>修改后的完整源码。</td></tr>
        <tr><td><code>oldTree</code></td><td><code>ParseTree</code></td><td>上一次解析得到的旧树。</td></tr>
        <tr><td><code>edit</code></td><td><code>InputEdit</code></td><td>描述变更范围的结构体。</td></tr>
      </tbody>
    </table>
    <pre><code>{
  start_byte: number,
  old_end_byte: number,
  new_end_byte: number,
  start_row: number,
  start_col: number,
  old_end_row: number,
  old_end_col: number,
  new_end_row: number,
  new_end_col: number,
}</code></pre>

    <h3>parser.dsl</h3>
    <p><code>readonly string</code>，创建解析器时保存的原始文本。对于 <code>mp.createParser()</code> 它是 DSL 文本；对于 <code>mp.createParserFromGrammarObject()</code>，底层保存的是对应的 Grammar JSON 字符串。</p>

    <h3>parser.tableJson()</h3>
    <p>返回序列化后的解析表 JSON，可用于缓存或预编译恢复。</p>

    <h3>parser.diagnosticsJson()</h3>
    <p>返回文法编译阶段的诊断信息 JSON 数组，例如冲突、警告等。</p>

    <h3>parser.free()</h3>
    <p>释放解析器持有的 WASM 句柄。</p>

    <h2>ParseTree</h2>
    <p>由 <code>parser.parse()</code> 或 <code>parser.parseIncremental()</code> 生成的具体语法树。</p>

    <h3>tree.sexp()</h3>
    <p>返回整棵树的 S 表达式字符串，适合调试和快照输出。</p>

    <h3>tree.errorSummary()</h3>
    <p>返回错误摘要字符串；如果没有错误，通常会返回一个表示正常状态的短字符串。</p>

    <h3>tree.walk()</h3>
    <p>创建一个定位在根节点上的 <code>TreeCursor</code>。调用方需要负责释放它。</p>

    <h3>tree.query(pattern)</h3>
    <p>一次性查询辅助方法：内部会编译模式、执行查询并释放编译结果，最后返回 <code>CaptureResult[]</code>。高频场景建议改用 <code>mp.compileQuery()</code> 复用查询对象。</p>

    <h3>tree.highlight(hlQuery, locsQuery?)</h3>
    <p>执行高亮查询，返回 <code>HighlightRange[]</code>。<code>hlQuery</code> 是高亮捕获查询，<code>locsQuery</code> 是可选的 locals 作用域查询（用于区分定义与引用）。两者均为 <code>MoonQuery</code> 对象，需提前通过 <code>mp.compileQuery()</code> 创建。</p>
    <table>
      <thead><tr><th>参数</th><th>类型</th><th>说明</th></tr></thead>
      <tbody>
        <tr><td><code>hlQuery</code></td><td><code>MoonQuery</code></td><td>包含 <code>@highlight.*</code> 捕获的高亮查询。</td></tr>
        <tr><td><code>locsQuery</code></td><td><code>MoonQuery?</code></td><td>包含 <code>@local.*</code> 捕获的 locals 查询，可省略。</td></tr>
      </tbody>
    </table>
    <pre><code>{
  highlight: string,   // 捕获名，例如 "keyword"、"string"
  start_byte: number,
  end_byte: number,
  start_row: number,
  start_col: number,
  end_row: number,
  end_col: number,
}</code></pre>

    <h3>tree.root</h3>
    <p><code>readonly CstNode</code>，整棵树的根节点对象。</p>

    <h3>tree.json</h3>
    <p><code>readonly string</code>，整棵树的懒序列化 JSON 字符串。</p>

    <h3>tree.free()</h3>
    <p>释放语法树占用的 WASM 句柄。</p>

    <h2>TreeCursor</h2>
    <p>可变游标对象，用于高效遍历语法树而不频繁分配节点对象。</p>

    <h3>只读属性</h3>
    <table>
      <thead><tr><th>属性</th><th>类型</th><th>说明</th></tr></thead>
      <tbody>
        <tr><td><code>nodeType</code></td><td><code>string</code></td><td>当前节点类型名或匿名 token 文本。</td></tr>
        <tr><td><code>nodeText</code></td><td><code>string</code></td><td>当前节点覆盖的源码文本。</td></tr>
        <tr><td><code>nodeField</code></td><td><code>string | null</code></td><td>若该节点带字段名则返回字段名，否则为 null。</td></tr>
        <tr><td><code>isNamed</code></td><td><code>boolean</code></td><td>是否为命名节点。</td></tr>
        <tr><td><code>isError</code></td><td><code>boolean</code></td><td>是否为错误恢复节点。</td></tr>
        <tr><td><code>isMissing</code></td><td><code>boolean</code></td><td>是否为插入的缺失节点。</td></tr>
        <tr><td><code>isExtra</code></td><td><code>boolean</code></td><td>是否由 <code>extras</code> 匹配得到。</td></tr>
        <tr><td><code>childCount</code></td><td><code>number</code></td><td>全部子节点数量。</td></tr>
        <tr><td><code>namedChildCount</code></td><td><code>number</code></td><td>命名子节点数量。</td></tr>
        <tr><td><code>startByte</code> / <code>endByte</code></td><td><code>number</code></td><td>源码中的字节偏移。</td></tr>
        <tr><td><code>startRow</code> / <code>startCol</code></td><td><code>number</code></td><td>起始位置，0 基。</td></tr>
        <tr><td><code>endRow</code> / <code>endCol</code></td><td><code>number</code></td><td>结束位置，0 基。</td></tr>
      </tbody>
    </table>

    <h3>导航方法</h3>
    <table>
      <thead><tr><th>方法</th><th>返回值</th><th>说明</th></tr></thead>
      <tbody>
        <tr><td><code>gotoFirstChild()</code></td><td><code>boolean</code></td><td>移动到第一个子节点。</td></tr>
        <tr><td><code>gotoNextSibling()</code></td><td><code>boolean</code></td><td>移动到下一个兄弟节点。</td></tr>
        <tr><td><code>gotoParent()</code></td><td><code>boolean</code></td><td>移动回父节点。</td></tr>
        <tr><td><code>free()</code></td><td><code>void</code></td><td>释放游标句柄。</td></tr>
      </tbody>
    </table>

    <h2>MoonQuery</h2>
    <p>由 <code>mp.compileQuery(pattern)</code> 创建的查询对象。</p>

    <h3>q.exec(tree)</h3>
    <p>在指定的 <code>tree</code> 上执行查询，返回 <code>CaptureResult[]</code>。</p>
    <pre><code>{
  match_id: number,
  capture: string,
  start: number,
  start_row: number,
  start_col: number,
  end: number,
  end_row: number,
  end_col: number,
  text: string,
}</code></pre>

    <h3>q.free()</h3>
    <p>释放查询对象占用的 WASM 句柄。</p>

    <h2>CstNode</h2>
    <p>普通的 JSON 可序列化对象，可通过 <code>tree.root</code> 或 <code>tree.json</code> 获取。</p>
    <table>
      <thead><tr><th>字段</th><th>类型</th><th>说明</th></tr></thead>
      <tbody>
        <tr><td><code>type</code></td><td><code>string</code></td><td>节点类型或匿名 token。</td></tr>
        <tr><td><code>is_named</code></td><td><code>boolean</code></td><td>是否为命名节点。</td></tr>
        <tr><td><code>is_error</code></td><td><code>boolean</code></td><td>是否为错误节点。</td></tr>
        <tr><td><code>is_missing</code></td><td><code>boolean</code></td><td>是否为缺失节点。</td></tr>
        <tr><td><code>extra</code></td><td><code>boolean</code></td><td>是否命中 <code>extras</code>。</td></tr>
        <tr><td><code>field</code></td><td><code>string?</code></td><td>字段名。</td></tr>
        <tr><td><code>start_byte</code> / <code>end_byte</code></td><td><code>number</code></td><td>字节偏移。</td></tr>
        <tr><td><code>start_row</code> / <code>start_col</code></td><td><code>number</code></td><td>起始位置，0 基。</td></tr>
        <tr><td><code>end_row</code> / <code>end_col</code></td><td><code>number</code></td><td>结束位置，0 基。</td></tr>
        <tr><td><code>text</code></td><td><code>string?</code></td><td>叶子节点文本。</td></tr>
        <tr><td><code>children</code></td><td><code>CstNode[]?</code></td><td>子节点数组。</td></tr>
      </tbody>
    </table>
  </article>
</template>
