<template>
  <article>
    <h1>check / fmt / test</h1>
    <p>这三条命令都是“门禁型命令”。它们不以业务树为主要产物，而是负责判断 grammar 是否健康、格式是否规范，以及 corpus 回归是否稳定。</p>

    <h2><code>check</code>：只做诊断，不写文件</h2>
    <pre><code>moon run cmd/main -- check grammars/json.grammar</code></pre>
    <p><code>check</code> 会执行 grammar 解析、语义校验和 tablegen 冲突收集，但不会输出 parse table。</p>
    <table>
      <thead><tr><th>退出码</th><th>含义</th></tr></thead>
      <tbody>
        <tr><td><code>0</code></td><td>没有 validation error，也没有 warning 或冲突。</td></tr>
        <tr><td><code>1</code></td><td>只有 warning，例如左递归或非阻断性冲突。</td></tr>
        <tr><td><code>2</code></td><td>存在普通 validation error，或存在 <code>Ambiguous</code> 冲突。</td></tr>
      </tbody>
    </table>
    <p>如果你想在 CI 里把“可接受但需要注意”的状态与“必须阻断”的状态区分开，<code>check</code> 是最合适的第一步。</p>

    <h2><code>fmt</code>：重新解析后再序列化</h2>
    <pre><code>moon run cmd/main -- fmt grammars/json.grammar
moon run cmd/main -- fmt grammars/json.grammar --check
moon run cmd/main -- fmt grammars/json.grammar --stdout</code></pre>
    <p><code>fmt</code> 不是纯文本替换，而是先把 DSL 解析成 grammar，再通过 <code>@grammar.grammar_to_string</code> 输出规范形式。</p>

    <table>
      <thead><tr><th>模式</th><th>行为</th><th>输出通道</th><th>退出码</th></tr></thead>
      <tbody>
        <tr><td>默认</td><td>原地覆写文件</td><td>状态写到 stderr</td><td><code>0</code> / <code>2</code></td></tr>
        <tr><td><code>--check</code></td><td>比较原文与格式化结果</td><td>状态写到 stderr</td><td><code>0</code> 已格式化，<code>1</code> 未格式化，<code>2</code> 解析失败</td></tr>
        <tr><td><code>--stdout</code></td><td>把格式化后的 grammar 文本打印出来</td><td>正文写到 stdout</td><td><code>0</code> / <code>2</code></td></tr>
      </tbody>
    </table>

    <h2><code>test</code>：单 corpus spec 回归</h2>
    <pre><code>moon run cmd/main -- test corpus/json.txt
moon run cmd/main -- test grammars/json.grammar:corpus/json.txt</code></pre>
    <p>当前实现不是目录扫描器，而是接收一个单独的 spec 字符串。它支持两种格式：</p>
    <pre><code>grammar.grammar:corpus.txt
corpus.txt</code></pre>
    <p>如果只传 <code>corpus.txt</code>，处理器会自动推导同目录、同基名的 <code>.grammar</code> 文件。</p>

    <h3>corpus 文件格式</h3>
    <pre><code>================
case name
================
source text
---
(expected_sexp)</code></pre>
    <p>每条测试都会把实际解析结果转成 S-expression，再与期望文本做字符串级比较。</p>

    <h3>退出码</h3>
    <table>
      <thead><tr><th>退出码</th><th>含义</th></tr></thead>
      <tbody>
        <tr><td><code>0</code></td><td>全部通过，或 corpus 中没有任何测试用例。</td></tr>
        <tr><td><code>1</code></td><td>至少一条用例输出与预期不一致。</td></tr>
        <tr><td><code>2</code></td><td>缺少 spec、读取 corpus 失败或 grammar 编译失败。</td></tr>
      </tbody>
    </table>

    <h2>Windows 路径说明</h2>
    <p><code>test</code> 的 spec 解析会特判索引 1 处的冒号，因此 Windows 绝对路径盘符不会误伤 <code>grammar:corpus</code> 这种语法。例如 <code>C:\a\x.grammar:C:\b\x.txt</code> 是合法的。</p>
  </article>
</template>