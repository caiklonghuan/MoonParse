<template>
  <article>
    <h1>编译管线</h1>
    <p><code>tablegen/README.md</code> 把编译过程拆得很清楚：先规范化，再算集合和项目集，再生成原始 LALR 表、消解冲突、构建词法 DFA，最后输出最终 <code>ParseTable</code>。普通调用方还是优先使用 <code>generate_parse_table()</code>。</p>

    <h2>阶段入口与产物</h2>
    <table>
      <thead>
        <tr>
          <th>入口</th>
          <th>产物</th>
          <th>什么时候单独看</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td><code>augment_grammar()</code></td>
          <td><code>AugmentedGrammar</code></td>
          <td>确认高阶 Pattern 是否被正确展开，或符号 ID 是否符合预期。</td>
        </tr>
        <tr>
          <td><code>nullable</code> / <code>first_set</code> / <code>follow_set</code></td>
          <td>集合分析结果</td>
          <td>closure、lookahead 或规约分析异常时排查。</td>
        </tr>
        <tr>
          <td><code>build_item_sets()</code> / <code>build_goto_map()</code></td>
          <td>项目集 / goto 图</td>
          <td>状态数异常、goto 缺失或状态传播不符合预期。</td>
        </tr>
        <tr>
          <td><code>build_lalr_table()</code></td>
          <td>原始 LALR 表</td>
          <td>想排查 action / goto 填充情况，但暂时不关心最终词法注入。</td>
        </tr>
        <tr>
          <td><code>resolve_conflicts()</code></td>
          <td>过滤后的表 + <code>ConflictReport[]</code></td>
          <td>想确认某个冲突为何被保留、降级或视为声明冲突。</td>
        </tr>
        <tr>
          <td><code>build_lexer_dfa()</code></td>
          <td><code>LexerDfa</code></td>
          <td>运行时词法异常、<code>valid_tokens</code> 不符合预期。</td>
        </tr>
        <tr>
          <td><code>generate_parse_table()</code></td>
          <td>最终 <code>ParseTable</code> + <code>ConflictReport[]</code></td>
          <td>CLI、runtime、缓存、分发和前端加载的默认入口。</td>
        </tr>
      </tbody>
    </table>

    <h2>调试建议</h2>
    <table>
      <thead>
        <tr>
          <th>现象</th>
          <th>优先检查</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td>高阶 Pattern 展开不符合预期</td>
          <td>先看 <code>augment_grammar()</code> 产出的 <code>AugmentedGrammar</code>。</td>
        </tr>
        <tr>
          <td>状态数异常或 goto 缺失</td>
          <td>先看 <code>build_item_sets()</code> 和 <code>build_goto_map()</code>。</td>
        </tr>
        <tr>
          <td>冲突数量过多</td>
          <td>先分清是可消解冲突、声明冲突，还是确实要保留给 GLR。</td>
        </tr>
        <tr>
          <td>运行时词法行为异常</td>
          <td>重点检查 <code>terminal_patterns</code>、<code>extras</code> 和 <code>valid_tokens</code>。</td>
        </tr>
      </tbody>
    </table>
  </article>
</template>