<template>
  <article>
    <h1>生成与分发</h1>
    <p><code>cmd/</code> 里与“产物”相关的命令并不只有 <code>generate</code>。当前应当把它们分成四类来看：单文件建表、目录化产物、JS 分发包，以及只读调试视图。</p>

    <h2>四条命令的职责边界</h2>
    <table>
      <thead><tr><th>命令</th><th>输入</th><th>输出</th><th>适用场景</th></tr></thead>
      <tbody>
        <tr><td><code>generate</code></td><td><code>.grammar</code></td><td>单个 <code>.parse_table</code> 或 JSON 文件</td><td>把 grammar 固化成可复用的表文件。</td></tr>
        <tr><td><code>build</code></td><td><code>.grammar</code> 或 <code>.parse_table</code></td><td><code>build/parser.parse_table</code>，可选 <code>parser.wasm</code></td><td>生成标准构建目录，交给其他脚本继续消费。</td></tr>
        <tr><td><code>wasm</code></td><td><code>-g grammar</code> 或 <code>-t table</code></td><td><code>dist/parser.js</code> + <code>parser.parse_table</code></td><td>面向浏览器或 Node.js 宿主的 JS 胶水分发。</td></tr>
        <tr><td><code>dump</code></td><td><code>ir</code> / <code>table</code> / <code>automaton</code> + 文件</td><td>stdout 文本视图</td><td>排查冲突、状态机、表序列化结果。</td></tr>
      </tbody>
    </table>

    <h2><code>generate</code>：单文件建表</h2>
    <pre><code>moon run cmd/main -- generate grammars/json.grammar
moon run cmd/main -- generate grammars/json.grammar -o out/json.parse_table
moon run cmd/main -- generate grammars/json.grammar --json -o out/json.table.json
moon run cmd/main -- generate grammars/expr.grammar --diagnostic --force</code></pre>
    <p><code>generate</code> 会做完整的 grammar 解析、语义校验、tablegen 和序列化。默认输出二进制 <code>.parse_table</code>，加上 <code>--json</code> 后改为输出表 JSON。</p>

    <h3><code>--force</code> 的真实含义</h3>
    <table>
      <thead><tr><th>诊断类型</th><th>默认行为</th><th><code>--force</code> 后</th></tr></thead>
      <tbody>
        <tr><td>左递归 warning</td><td>继续生成</td><td>无变化</td></tr>
        <tr><td>普通 validation error</td><td>停止并返回 <code>2</code></td><td>继续建表并写文件</td></tr>
        <tr><td><code>Ambiguous</code> 冲突</td><td>停止并返回 <code>2</code></td><td>继续写文件</td></tr>
        <tr><td>其他冲突 warning</td><td>继续生成</td><td>无变化</td></tr>
      </tbody>
    </table>
    <p>即便使用了 <code>--force</code>，只要存在 error 或 warning，命令最终仍会返回 <code>1</code>，因为它把“已写出文件”和“无诊断”明确区分开了。</p>

    <h2><code>build</code>：标准构建目录</h2>
    <pre><code>moon run cmd/main -- build grammars/json.grammar
moon run cmd/main -- build out/json.parse_table -o out/build
moon run cmd/main -- build out/json.parse_table --wasm -o out/build</code></pre>
    <p><code>build</code> 总是产出目录，最少会写出 <code>parser.parse_table</code>。开启 <code>--wasm</code> 时，还会额外写出一个同样字节内容的 <code>parser.wasm</code>。</p>
    <p>需要注意的是，<code>build</code> 从 grammar 路径生成时没有 <code>--force</code> 模式；普通 validation error 和 ambiguity 都会直接阻断构建。</p>

    <h2><code>wasm</code>：JS 胶水分发目录</h2>
    <pre><code>moon run cmd/main -- wasm -g grammars/json.grammar
moon run cmd/main -- wasm -t out/json.parse_table -o out/dist</code></pre>
    <p><code>wasm</code> 命令的名字容易误导。它当前做的不是“编译出 WebAssembly 运行时”，而是生成一份宿主侧可直接 import 的 <code>parser.js</code> 与一份配套 parse table。</p>

    <table>
      <thead><tr><th>模式</th><th><code>parser.js</code> 中嵌入的内容</th><th><code>loadParser()</code> 行为</th></tr></thead>
      <tbody>
        <tr><td><code>-g</code> / <code>--grammar</code></td><td>grammar DSL 字符串</td><td>运行时调用 <code>moonparse.createParser()</code></td></tr>
        <tr><td><code>-t</code> / <code>--table</code></td><td>Base64 形式的表字节</td><td>运行时调用 <code>moonparse.createParserFromBytes()</code></td></tr>
      </tbody>
    </table>
    <p>只有 <code>-t</code> 模式额外导出 <code>tableBytes</code>。如果你的目标是发布真实的 wasm 运行时模块，应转向仓库根目录的 <code>wasm/</code> 包，而不是依赖这个 CLI 子命令。</p>

    <h2><code>dump</code>：只读调试视图</h2>
    <pre><code>moon run cmd/main -- dump ir grammars/json.grammar
moon run cmd/main -- dump table grammars/json.grammar
moon run cmd/main -- dump table out/json.parse_table
moon run cmd/main -- dump automaton grammars/json.grammar</code></pre>
    <ul>
      <li><code>ir</code> 输出规范化后的 grammar 文本。</li>
      <li><code>table</code> 输出表 JSON；它既接受 grammar，也接受二进制 <code>.parse_table</code>，还会直接打印传入的 <code>.json</code> 文件。</li>
      <li><code>automaton</code> 输出 LR(0) 项目集和 GOTO 跳转关系，适合排查状态机问题。</li>
    </ul>
  </article>
</template>