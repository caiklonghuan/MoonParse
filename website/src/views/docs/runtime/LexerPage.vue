<template>
  <article>
    <h1>词法引擎</h1>
    <p><code>LexerEngine</code> 的工作不是“独立把整个输入切成 token”，而是结合当前 LR 状态做 context-aware 扫描。它直接消费 <code>ParseTable.lexer_dfa</code> 和 <code>valid_tokens</code>，这也是 runtime 和 tablegen 紧密耦合的核心点之一。</p>

    <h2>基本接口</h2>
    <pre><code>LexerEngine::new(dfa)
LexerEngine::new_with_external(dfa, scanner)
LexerEngine::next_token(self, input, pos, table, state)
  -> (Token?, new_pos)</code></pre>

    <h2>单槽缓存</h2>
    <p>GLR 会让多个解析版本停在同一字节位置请求下一个 token。为了避免重复跑 DFA，<code>LexerEngine</code> 用一个单槽缓存保存最近一次的扫描结果，并通过 <code>cached_pos</code>、<code>cached_valid_hash</code> 和合法 token 数组做精确复用。</p>

    <h2>extras 的处理方式</h2>
    <p>空白和注释不会被简单丢弃。runtime 会把它们作为 <code>extra=true</code> 的叶节点保留在 CST 中，同时在 shift 时维持 LR 状态不变。这让格式化工具、注释附着和源码还原都可以继续依赖这些节点。</p>

    <h2>外部词法器回调</h2>
    <pre><code>type ExternalScanner =
  (String, Int, Array[Int]) -> (Int, Int)?</code></pre>
    <p>回调拿到完整输入、当前字节位置和当前上下文允许的外部 token ID。返回 <code>Some((terminal_id, end_pos))</code> 表示匹配成功，返回 <code>None</code> 表示让内置 DFA 继续决定。它非常适合布局敏感 token、缩进/退格、零宽 dedent 等场景。</p>
  </article>
</template>