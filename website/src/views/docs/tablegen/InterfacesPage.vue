<template>
  <article>
    <h1>公共接口</h1>
    <p>这一页对齐 <code>tablegen/README.md</code> 的公开能力表。对大多数调用方，核心接口仍然只有一个：<code>generate_parse_table(grammar)</code>；其余 API 更多面向调试、分析、教学或自定义编译流水线。</p>

    <h2>一键编译入口</h2>
    <pre><code>generate_parse_table(grammar)
  -> Result[(ParseTable, Array[ConflictReport]), String]</code></pre>

    <h2>阶段性入口</h2>
    <pre><code>augment_grammar(grammar)                    -> AugmentedGrammar
nullable(aug, seq)
first_set(aug, symbol)
first_seq(aug, seq)
follow_set(aug, nonterminal)
closure(...)
goto_set(...)
build_item_sets(aug)
build_goto_map(aug, item_sets)
build_lalr_table(aug, item_sets, goto_map)
resolve_conflicts(table, aug)
build_lexer_dfa(aug, table)</code></pre>

    <h2>序列化入口</h2>
    <pre><code>table_to_json(table)        -> String
table_from_json(json)       -> Result[ParseTable, String]
serialize_table(table)      -> Bytes
deserialize_table(bytes)    -> Result[ParseTable, String]</code></pre>

    <h2>核心类型</h2>
    <table>
      <thead>
        <tr>
          <th>类型</th>
          <th>说明</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td><code>AugmentedGrammar</code></td>
          <td>规范化和增广后的中间文法，是所有核心算法的输入基础。</td>
        </tr>
        <tr>
          <td><code>ParseTable</code></td>
          <td>最终核心产物，也是 <code>runtime/</code> 的直接输入。</td>
        </tr>
        <tr>
          <td><code>Production</code></td>
          <td>扁平化产生式，常用于调试 normalize、冲突消解和运行时规约行为。</td>
        </tr>
        <tr>
          <td><code>ConflictReport</code></td>
          <td>编译诊断结果，记录冲突状态、lookahead、候选动作和严重级别。</td>
        </tr>
        <tr>
          <td><code>LexerDfa</code></td>
          <td>受 LR 状态约束的上下文敏感词法器。</td>
        </tr>
      </tbody>
    </table>

    <h2>调用建议</h2>
    <ul>
      <li>普通调用方默认优先使用 <code>generate_parse_table()</code>。</li>
      <li>如果目标是观察中间状态、做算法教学或写可视化工具，再拆开阶段性入口。</li>
      <li>最终可交付的成品表需要补齐一系列运行时字段，所以不要把中间阶段的返回值误当成最终表。</li>
    </ul>
  </article>
</template>