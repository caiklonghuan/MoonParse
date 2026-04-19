<template>
  <article>
    <h1>示例</h1>
    <p>这一页给三类最常用的例子：低层句柄流、高层 JS wrapper 流，以及增量和查询的组合用法。</p>

    <h2>示例 1：低层句柄流</h2>
    <pre><code>const parserId = api.parser_create_from_dsl(dsl)
if (parserId &lt; 0) {
  throw new Error(api.parser_dsl_error_last())
}

const treeId = api.parse_full(parserId, source)
if (treeId &lt; 0) {
  throw new Error(api.parse_error_last() || 'parse failed')
}

const json = api.tree_to_json(treeId)
const sexp = api.tree_root_sexp(treeId)
const summary = api.tree_error_summary(treeId)

api.tree_free(treeId)
api.parser_free(parserId)</code></pre>

    <h2>示例 2：高层 JS wrapper</h2>
    <pre><code>import { loadMoonParse } from 'moonparse'

const mp = await loadMoonParse()
const parser = mp.createParser(dsl)
const tree = parser.parse(source)

console.log(tree.root)
console.log(tree.sexp())
console.log(tree.errorSummary())

tree.free()
parser.free()</code></pre>

    <h2>示例 3：从预编译二进制表创建 parser</h2>
    <pre><code>const bytes = new Uint8Array(
  await fetch('./parser.parse_table').then((r) => r.arrayBuffer()),
)

const mp = await loadMoonParse()
const parser = mp.createParserFromBytes(bytes)</code></pre>
    <p>这条路径跳过 DSL 编译和 ParseTable JSON 解析，启动时通常更快。</p>

    <h2>示例 4：增量解析</h2>
    <pre><code>const oldTree = parser.parse('ab')

const newTree = parser.parseIncremental('ad', oldTree, {
  start_byte: 1,
  old_end_byte: 2,
  new_end_byte: 2,
  start_row: 0,
  start_col: 1,
  old_end_row: 0,
  old_end_col: 2,
  new_end_row: 0,
  new_end_col: 2,
})</code></pre>
    <p>JS wrapper 会在成功后把旧树句柄置为失效状态，所以调用方不应再继续使用旧树对象。</p>

    <h2>示例 5：游标遍历</h2>
    <pre><code>const cursor = tree.walk()
console.log(cursor.nodeType)

if (cursor.gotoFirstChild()) {
  console.log(cursor.nodeType)
  console.log(cursor.nodeField)
  console.log(cursor.nodeText)
}

cursor.free()</code></pre>

    <h2>示例 6：缓存查询对象</h2>
    <pre><code>const query = mp.compileQuery('(identifier) @name')
const captures = query.exec(tree)
const locals = query.resolveLocals(tree)

query.free()</code></pre>

    <h2>示例 7：高亮与 locals 联动</h2>
    <pre><code>const hlQuery = mp.compileQuery('(identifier) @variable')
const locsQuery = mp.compileQuery(
  '(block) @local.scope\n(identifier) @local.definition\n(identifier) @local.reference'
)

const ranges = tree.highlight(hlQuery, locsQuery)
console.log(ranges)</code></pre>
  </article>
</template>