<template>
  <article>
    <h1>快速开始</h1>
    <p>MoonParse 是一个编译到 WebAssembly 的 GLR 解析工具包。你可以用简洁的文本 DSL 定义文法，把字符串解析成具体语法树（CST），再通过查询模式提取节点信息，全程无需本地原生依赖。</p>

    <h2>准备文件</h2>
    <p>把发布包中的 <code>moonparse.js</code> 和 <code>moonparse.wasm</code> 放进你的项目。前者是 ES Module 入口，后者会在运行时被加载。</p>
    <pre><code>your-project/
├─ public/
│  └─ moonparse.wasm
├─ src/
│  ├─ moonparse.js
│  └─ main.js</code></pre>
    <p>如果你使用 Vite、webpack 或 esbuild，通常把 <code>moonparse.wasm</code> 放在 <code>public/</code> 下最省事，这样浏览器能直接按静态资源地址访问它。</p>

    <h2>1. 加载运行时</h2>
    <p>调用 <code>loadMoonParse(wasmUrl)</code> 并等待 Promise 完成。返回值是一个可在整个应用生命周期内复用的 <code>MoonParseInstance</code>。</p>
    <pre><code>import { loadMoonParse } from './moonparse.js'

const mp = await loadMoonParse('./moonparse.wasm')</code></pre>

    <h2>2. 创建解析器</h2>
    <p>将文法 DSL 字符串传给 <code>mp.createParser(dsl)</code>。MoonParse 会先把 DSL 编译成解析表，然后返回一个 <code>MoonParser</code>。不再使用时记得调用 <code>parser.free()</code> 释放 WASM 句柄。</p>
    <pre><code>const parser = mp.createParser(`
  start json
  extras [/[ \t\n\r]+/]
  rule json: value
  rule value: object | array | string | number | "true" | "false" | "null"
  rule object: "{" (pair ("," pair)*)? "}"
  rule pair: string ":" value
  rule array: "[" (value ("," value)*)? "]"
  rule string: /"[^"]*"/
  rule number: /-?[0-9]+(\.[0-9]+)?/
`)</code></pre>

    <h2>3. 解析源码</h2>
    <p><code>parser.parse(source)</code> 会返回一棵新的 <code>ParseTree</code>。和其他 WASM 对象一样，用完后需要显式调用 <code>tree.free()</code>。</p>
    <pre><code>const tree = parser.parse('{"name": "MoonParse", "version": 1}')

console.log(tree.sexp())
tree.free()</code></pre>

    <h2>4. 检查语法错误</h2>
    <p>MoonParse 即使遇到语法错误，也会尽量生成一棵完整的树。你可以通过 <code>tree.errorSummary()</code> 读取一段可读性较好的错误摘要。</p>
    <pre><code>const tree = parser.parse('{"broken": }')
console.log(tree.errorSummary())</code></pre>

    <h2>5. 使用游标遍历语法树</h2>
    <p><code>tree.walk()</code> 返回一个定位在根节点上的 <code>TreeCursor</code>。通过 <code>gotoFirstChild()</code>、<code>gotoNextSibling()</code>、<code>gotoParent()</code> 可以在树中移动。遍历结束后记得调用 <code>cursor.free()</code>。</p>
    <pre><code>const cursor = tree.walk()

function visit(depth = 0) {
  const indent = '  '.repeat(depth)
  const field = cursor.nodeField ? `${cursor.nodeField}: ` : ''
  console.log(`${indent}${field}[${cursor.nodeType}] ${JSON.stringify(cursor.nodeText)}`)

  if (cursor.gotoFirstChild()) {
    do { visit(depth + 1) }
    while (cursor.gotoNextSibling())
    cursor.gotoParent()
  }
}

visit()
cursor.free()</code></pre>

    <h2>6. 执行查询</h2>
    <p>先通过 <code>mp.compileQuery(pattern)</code> 编译查询，再使用 <code>q.exec(tree)</code> 执行。每条捕获结果都包含捕获名、文本内容和位置范围等信息。</p>
    <pre><code>const q = mp.compileQuery('(pair (string) @key ":" (value) @val)')

for (const c of q.exec(tree)) {
  console.log(`@${c.capture}: ${c.text}`)
}

q.free()</code></pre>

    <h2>7. 增量重新解析</h2>
    <p>编辑器场景下，通常会在每次文本变更后构造一个 <code>InputEdit</code>，再调用 <code>parser.parseIncremental()</code>。这样 MoonParse 只需要重新检查受影响的区域，而不是整份源码。</p>
    <pre><code>const edit = {
  start_byte: 9,
  old_end_byte: 20,
  new_end_byte: 25,
  start_row: 0,
  start_col: 9,
  old_end_row: 0,
  old_end_col: 20,
  new_end_row: 0,
  new_end_col: 25,
}

const nextSource = '{"name": "MoonBit", "version": 2}'
const nextTree = parser.parseIncremental(nextSource, tree, edit)
tree.free()</code></pre>

    <h2>在 Node.js 中运行</h2>
    <pre><code>import { loadMoonParse } from './moonparse.js'

const mp = await loadMoonParse(new URL('./moonparse.wasm', import.meta.url).pathname)
const parser = mp.createParser(`start n\nrule n: /[0-9]+/`)
const tree = parser.parse('42')
console.log(tree.sexp())
tree.free()
parser.free()</code></pre>

    <h2>在浏览器中运行</h2>
    <pre><code>&lt;script type="module"&gt;
  import { loadMoonParse } from '/moonparse.js'

  const mp = await loadMoonParse('/moonparse.wasm')
  const parser = mp.createParser(`start n\nrule n: /[0-9]+/`)
  console.log(parser.parse('99').sexp())
&lt;/script&gt;</code></pre>
  </article>
</template>
