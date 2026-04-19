<template>
  <article>
    <h1>词法引擎</h1>
    <p><code>LexerEngine</code> 不是一个“先把整份输入切成 token 流，再交给 parser”的独立阶段。它会结合当前 LR 状态或 GLR 活跃状态集合，按“当前上下文允许哪些 token”去执行扫描，因此它本质上是由解析上下文驱动的运行时扫描器。</p>

    <h2>核心接口</h2>
    <pre><code>LexerEngine::new(dfa)
LexerEngine::new_with_external(dfa, scanner)
LexerEngine::new_with_stateful(dfa, scanner)
LexerEngine::next_token(self, input, pos, table, state)
  -> (Token?, new_pos)</code></pre>
    <p>词法器直接消费 <code>ParseTable.lexer_dfa</code> 和当前状态可接受 token 集，因此它和 <code>tablegen/</code> 产物是强耦合的。</p>

    <h2>为什么这是上下文敏感扫描</h2>
    <ul>
      <li>同一份 DFA 会根据当前 LR 状态的合法 token 集，表现出不同的扫描结果。</li>
      <li>在 GLR 场景下，runtime 会根据多个活跃路径的合法 token 并集决定可接受候选。</li>
      <li>这样可以避免在明显不合法的上下文里产生没有意义的 token。</li>
    </ul>

    <h2>单槽缓存</h2>
    <p>GLR 常常让多个版本停在同一字节位置请求下一个 token。为了避免反复跑 DFA，<code>LexerEngine</code> 会缓存最近一次扫描结果，并使用 <code>cached_pos</code>、<code>cached_valid_hash</code> 和合法 token 数组做精确复用。</p>

    <h2>extras 的处理方式</h2>
    <p>空白和注释不会被直接丢弃。runtime 会把它们作为 <code>extra=true</code> 的叶节点保留在 CST 中，同时在 shift 时维持 LR 状态不变。这样格式化、注释附着和源码还原仍然可以依赖这些节点。</p>

    <h2>外部 scanner 约定</h2>
    <pre><code>type ExternalScanner =
  (String, Int, Array[Int]) -> (Int, Int)?</code></pre>
    <ul>
      <li>参数依次是完整输入、当前位置字节偏移、当前上下文允许的外部 token 集。</li>
      <li>返回 <code>Some((terminal_id, end_pos))</code> 表示识别成功，范围是 <code>[pos, end_pos)</code>。</li>
      <li>返回 <code>None</code> 表示本次让内置 DFA 继续决定。</li>
      <li>scanner 使用的是字节偏移，不是字符索引。</li>
    </ul>

    <h2>何时改用 <code>StatefulScanner</code></h2>
    <p>如果 scanner 需要维护缩进栈、模式切换或其他分支相关状态，应实现 <code>StatefulScanner</code> trait，而不是把状态塞进外部全局变量。GLR 分叉时 runtime 会通过 <code>clone_scanner()</code> 给每条解析路径复制一份独立状态。</p>

    <h2>实战建议</h2>
    <ul>
      <li>外部 scanner 只应返回当前 <code>valid_external_tids</code> 中允许的 token。</li>
      <li>当 DFA 和外部 scanner 同时可匹配时，要确认优先级和最长匹配行为符合预期。</li>
      <li>如果遇到词法问题，先检查合法 token 集和字节偏移，再去怀疑语法规则。</li>
    </ul>
  </article>
</template>