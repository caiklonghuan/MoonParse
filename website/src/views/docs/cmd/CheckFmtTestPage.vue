<template>
  <article>
    <h1>check / fmt / test</h1>
    <p>这三条命令不直接输出业务树结果，但它们分别覆盖 grammar 质量门禁、源码规范化和 corpus 回归验证，是把 MoonParse 接进工程流水线时最常用的配套步骤。</p>

    <h2>check</h2>
    <pre><code>moonparse check &lt;file.grammar&gt;</code></pre>
    <p><code>check</code> 会解析 grammar、运行 validation，再调用 tablegen 收集冲突报告，但不会把 ParseTable 写到磁盘。退出码矩阵非常适合 CI：</p>
    <table>
      <thead><tr><th>退出码</th><th>含义</th></tr></thead>
      <tbody>
        <tr><td>0</td><td>没有 validation error，也没有 warning/冲突。</td></tr>
        <tr><td>1</td><td>只有 warning，例如左递归或非阻断性冲突。</td></tr>
        <tr><td>2</td><td>有普通 validation error 或 <code>Ambiguous</code> 冲突。</td></tr>
      </tbody>
    </table>

    <h2>fmt</h2>
    <pre><code>moonparse fmt &lt;file.grammar&gt; [options]

--check    只检查是否已格式化
--stdout   输出格式化结果到 stdout</code></pre>
    <p>默认行为是原地改写文件。<code>--check</code> 会比较原文与 <code>@grammar.grammar_to_string</code> 的结果，一致返回 0，不一致返回 1；<code>--stdout</code> 则适合接到别的工具或手动 diff。</p>

    <h2>test</h2>
    <pre><code>moonparse test &lt;spec&gt;

spec 目前支持两种形式：
  grammar.grammar:corpus.txt
  corpus.txt   # 自动推导同目录同基名的 .grammar</code></pre>
    <p><code>test</code> 当前实现不是目录扫描器，而是接收一个 corpus 规范字符串。处理器会读取 corpus 文件，按 tree-sitter 风格的分隔格式拆出多条测试，再逐条解析输入并把生成的 S-expression 与期望文本比较。</p>

    <h3>corpus 文件格式</h3>
    <pre><code>================
case name
================
source text
---
(expected_sexp)</code></pre>

    <h3>退出码</h3>
    <table>
      <thead><tr><th>退出码</th><th>含义</th></tr></thead>
      <tbody>
        <tr><td>0</td><td>全部通过，或 corpus 中没有任何测试用例。</td></tr>
        <tr><td>1</td><td>至少一条用例输出与预期不一致。</td></tr>
        <tr><td>2</td><td>缺少 spec、读取 corpus 失败或 grammar 编译失败。</td></tr>
      </tbody>
    </table>

    <h2>示例</h2>
    <pre><code>moonparse check grammars/json.grammar
moonparse fmt grammars/json.grammar --check
moonparse fmt grammars/json.grammar --stdout
moonparse test tests/json.txt
moonparse test grammars/json.grammar:tests/json.txt</code></pre>
    <p>如果你在 Windows 上使用绝对路径，尽量避免 <code>grammar:corpus</code> 这种冒号分隔写法，因为盘符本身也包含冒号。当前实现更稳妥的做法是使用相对路径，或仅传入 corpus 文件让 grammar 路径自动推导。</p>
  </article>
</template>