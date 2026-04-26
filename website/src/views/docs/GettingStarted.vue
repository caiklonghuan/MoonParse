

<template>
<article>
 <h1>快速开始</h1>
 <p>MoonParse 是用 MoonBit 实现的解析器生成器与语言工具链基础设施。当前仓库已经打通 Grammar DSL、ParseTable 生成、GLR 全量解析、增量解析、错误恢复、query / highlight 和 Wasm 集成，既能在仓库内做命令行和文法实验，也能嵌入浏览器或 Node.js 宿主。</p>

 <h2>先选一条入口</h2>
 <p>根目录 README 里的主线可以概括成四种常用入口：</p>
 <table>
 <thead><tr><th>入口</th><th>适合场景</th><th>下一步</th></tr></thead>
 <tbody>
 <tr><td><code>MoonBit 根包 API</code></td><td>整个项目本身就写在 MoonBit 里，希望直接调用高层解析入口。</td><td>看 Grammar、Runtime 与 Query 分区。</td></tr>
 <tr><td><code>Cmd</code></td><td>想在仓库内做文法校验、建表、解析、查询、测试。</td><td>继续看 <router-link to="/docs/cmd/overview">Cmd 文档</router-link>。</td></tr>
 <tr><td><code>Wasm / JS 宿主</code></td><td>要把解析能力嵌进浏览器、Node.js、Electron 或前端编辑器。</td><td>继续看本页和 <router-link to="/docs/wasm/overview">Wasm 文档</router-link>。</td></tr>
 <tr><td><code>在线 playground</code></td><td>先验证效果、熟悉 DSL、看语法树和 query 结果。</td><td>直接打开 <router-link to="/online">在线使用</router-link>。</td></tr>
 </tbody>
 </table>

 <h2>仓库内最常用的启动命令</h2>
 <p>如果你当前就在 MoonParse 仓库里工作，根目录最常用的几条命令就是这些：</p>
 <pre><code># 构建主模块与分包
moon build

# 查看 CLI 帮助
moon run cmd/main -- --help

# 构建 release wasm 产物
moon build --target wasm-gc --release --strip

# 启动 website 开发环境
Push-Location website
npm install
npm run dev
Pop-Location</code></pre>
 <p>其中 <code>moon build</code> 覆盖根包 API 与各分包；website 目录则提供文档站和在线 playground。</p>

 <h2>浏览器 / Node.js 的最短接入路径</h2>
 <p>如果你的目标是把 MoonParse 当成一个可嵌入的解析能力来使用，建议先跑通下面这条最短路径：加载运行时 → 用 DSL 创建解析器 → 解析源码 → 读取树 → 查询 → 释放句柄。</p>

 <h3>1. 准备文件</h3>
 <p>把发布包中的 <code>moonparse.js</code> 和 <code>moonparse.wasm</code> 放进你的项目。前者是 ES Module 入口，后者会在运行时被加载。</p>
 <pre><code>your-project/
├─ public/
│ └─ moonparse.wasm
├─ src/
│ ├─ moonparse.js
│ └─ main.js</code></pre>
<p>如果你使用 Vite、webpack 或 esbuild，通常把 <code>moonparse.wasm</code> 放在 <code>public/</code> 下最省事，因为浏览器可以按静态资源地址直接访问它。</p>

 <h3>2. 加载运行时</h3>
 <p>调用 <code>loadMoonParse(wasmUrl)</code> 并等待 Promise 完成。返回值是一个可以在整个应用生命周期内复用的 <code>MoonParseInstance</code>。</p>
 <pre><code>import { loadMoonParse } from './moonparse.js'

const mp = await loadMoonParse('./moonparse.wasm')</code></pre>

 <h3>3. 用 DSL 创建解析器</h3>
 <p>把文法 DSL 文本传给 <code>mp.createParser(dsl)</code>。MoonParse 会先编译文法，再返回一个 <code>MoonParser</code>。解析器持有 WASM 句柄，不再使用时要调用 <code>parser.free()</code>。</p>
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

 <h3>4. 解析源码并读取树</h3>
 <p><code>parser.parse(source)</code> 会返回新的 <code>ParseTree</code>。你可以直接看 <code>tree.sexp()</code>，也可以通过 <code>tree.root</code> 读取 JSON 形式的 CST。</p>
 <pre><code>const tree = parser.parse('{"name": "MoonParse", "version": 1}')

console.log(tree.sexp())
console.log(tree.root.type)
console.log(tree.errorSummary())</code></pre>
 <p>MoonParse 遇到语法错误时通常也会尽量生成一棵可用的树，所以 <code>errorSummary()</code> 往往比“直接抛异常”更适合做编辑器或诊断界面。</p>

 <h3>5. 遍历树与执行查询</h3>
 <p>需要高效遍历时，用 <code>tree.walk()</code> 获取 <code>TreeCursor</code>；需要按模式提取节点时，用 <code>mp.compileQuery(pattern)</code> 编译查询对象，再调用 <code>q.exec(tree)</code>。</p>
 <pre><code>const cursor = tree.walk()
console.log(cursor.nodeType)
cursor.free()

const q = mp.compileQuery('(pair (string) @key ":" (value) @val)')

for (const c of q.exec(tree)) {
 console.log(`@${c.capture}: ${c.text}`)
}

q.free()</code></pre>

 <h3>6. 释放对象</h3>
 <p>MoonParse 的解析器、语法树、游标和查询对象都持有底层 WASM 句柄。一个最稳妥的习惯是：谁创建，谁释放。</p>
 <pre><code>tree.free()
parser.free()</code></pre>

 <h3>7. 增量重新解析</h3>
 <p>编辑器场景下，通常会在每次文本变更后构造一个 <code>InputEdit</code>，再调用 <code>parser.parseIncremental()</code>。这样 MoonParse 只需要重新检查受影响区域，而不是整份源码。</p>
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

// 调用后旧 tree 已失效，不要继续使用它
console.log(nextTree.sexp())
nextTree.free()</code></pre>

 <h3>8. 从 DSL 走向预编译</h3>
 <p>开发阶段通常直接用 <code>createParser(dsl)</code> 就够了。等文法稳定后，可以把解析表序列化出来，再用 <code>createParserFromJson(tableJson, builtinId?)</code> 恢复，以减少运行时建表开销。对于内置文法（例如 <code>json</code>、<code>python</code>、<code>moonbit</code>），恢复时建议传入匹配的 <code>builtinId</code>，这样内置词法行为才能完整保留。</p>

 <h2>Node.js 与浏览器示例</h2>

 <h3>Node.js</h3>
 <pre><code>import { loadMoonParse } from './moonparse.js'

const mp = await loadMoonParse(new URL('./moonparse.wasm', import.meta.url).href)
const parser = mp.createParser(`start n\nrule n: /[0-9]+/`)
const tree = parser.parse('42')

console.log(tree.sexp())

tree.free()
parser.free()</code></pre>

 <h3>浏览器</h3>
 <pre><code>&lt;script type="module"&gt;
 import { loadMoonParse } from './moonparse.js'

 const mp = await loadMoonParse(new URL('./moonparse.wasm', import.meta.url).href)
 const parser = mp.createParser(`start n\nrule n: /[0-9]+/`)
 const tree = parser.parse('99')

 console.log(tree.sexp())

 tree.free()
 parser.free()
&lt;/script&gt;</code></pre>

 <h2>下一步读哪里</h2>
 <ul>
 <li>想看底层导出与 JS 包装层：去 <router-link to="/docs/api-reference">API 参考</router-link>。</li>
 <li>想系统了解宿主桥接、Cursor、Query、高亮与最佳实践：去 <router-link to="/docs/wasm/overview">Wasm 文档</router-link>。</li>
 <li>想在仓库里直接跑命令：去 <router-link to="/docs/cmd/overview">Cmd 文档</router-link>。</li>
 </ul>
 </article>
</template>

