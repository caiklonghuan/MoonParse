<template>
  <article>
    <h1>概览</h1>
    <p><code>tablegen/</code> 是 MoonParse 的离线解析表编译模块，负责把 <code>grammar/</code> 产出的 <code>Grammar</code> 编译成可供 <code>runtime/</code> 直接加载的 <code>ParseTable</code>。</p>

    <h2>模块定位</h2>
    <ul>
      <li>将 <code>Grammar</code> 规范化为增广文法。</li>
      <li>计算 <code>nullable</code>、<code>FIRST</code>、<code>FOLLOW</code> 等集合。</li>
      <li>构建 LR 项目集、GOTO 转移和 LALR(1) 解析表。</li>
      <li>处理 shift/reduce、reduce/reduce 冲突并输出诊断报告。</li>
      <li>生成上下文敏感词法 DFA，并把最终表序列化为 JSON 或二进制。</li>
    </ul>

    <h2>在整体系统中的位置</h2>
    <pre><code>Grammar DSL / Builder API
          |
          v
      grammar/
          |
          v
       Grammar
          |
          v
      tablegen/
          |
          v
      ParseTable
          |
          v
       runtime/</code></pre>
    <p>可以把 <code>grammar/</code> 理解成“语法表示层”，<code>tablegen/</code> 是“语法编译层”，<code>runtime/</code> 则是“执行编译结果的运行时”。</p>

    <h2>编译链路</h2>
    <pre><code>Grammar
  |
  v
normalize.mbt
  |
  v
AugmentedGrammar
  |
  +--&gt; sets.mbt      计算 nullable / FIRST / FOLLOW
  |
  +--&gt; items.mbt     构造 LR 项目集族与 GOTO
  |
  +--&gt; lalr.mbt      生成原始 LALR 表
  |
  +--&gt; conflicts.mbt 按优先级、结合性与冲突声明做消解
  |
  +--&gt; lexer.mbt     生成上下文敏感词法 DFA
  |
  +--&gt; serialize.mbt 输出 JSON / Bytes
  |
  v
ParseTable</code></pre>

    <h2>公开能力一览</h2>
    <table>
      <thead>
        <tr>
          <th>类别</th>
          <th>主要 API</th>
          <th>说明</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td>一键编译入口</td>
          <td><code>generate_parse_table</code></td>
          <td>从 <code>Grammar</code> 一步生成最终 <code>ParseTable</code> 与冲突报告。</td>
        </tr>
        <tr>
          <td>规范化</td>
          <td><code>augment_grammar</code></td>
          <td>把高阶 Pattern 展开为更适合自动机构造的中间文法。</td>
        </tr>
        <tr>
          <td>集合计算</td>
          <td><code>nullable</code>、<code>first_set</code>、<code>first_seq</code>、<code>follow_set</code></td>
          <td>供 closure、lookahead 和规约分析使用。</td>
        </tr>
        <tr>
          <td>LR 自动机</td>
          <td><code>closure</code>、<code>goto_set</code>、<code>build_item_sets</code>、<code>build_goto_map</code></td>
          <td>构造 LR 项目集族与状态转移。</td>
        </tr>
        <tr>
          <td>LALR 表构造</td>
          <td><code>build_lalr_table</code>、<code>resolve_conflicts</code></td>
          <td>生成并消解冲突。</td>
        </tr>
        <tr>
          <td>词法 DFA</td>
          <td><code>build_lexer_dfa</code></td>
          <td>构建受 LR 状态约束的上下文敏感词法器。</td>
        </tr>
        <tr>
          <td>序列化</td>
          <td><code>table_to_json</code>、<code>table_from_json</code>、<code>serialize_table</code>、<code>deserialize_table</code></td>
          <td>解析表落盘与回读。</td>
        </tr>
      </tbody>
    </table>

    <h2>推荐使用流程</h2>
    <ol>
      <li>使用 <code>grammar/</code> 构造或解析得到 <code>Grammar</code>。</li>
      <li>视调用方策略决定是否先执行 <code>validate_grammar</code>。</li>
      <li>调用 <code>generate_parse_table</code> 生成 <code>ParseTable</code>。</li>
      <li>检查 <code>ConflictReport</code>。</li>
      <li>按需要把表序列化为 JSON 或二进制。</li>
      <li>把最终产物交给 <code>runtime/</code> 或其他工具链下游。</li>
    </ol>
    <p>需要特别记住的一点是：<code>tablegen.generate_parse_table()</code> <strong>不会自动调用</strong> <code>grammar.validate_grammar()</code>。如果你的构建链路要求先做 Grammar 级诊断，必须由调用方自己决定校验策略。</p>
  </article>
</template>