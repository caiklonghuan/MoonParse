<template>
  <article>
    <h1>注意事项与适用场景</h1>
    <p><code>tablegen/README.md</code> 的重点不是“怎么多写几种 API 用法”，而是不要把中间状态误当成最终契约，也不要把“有冲突报告”简单等价为“不能继续构建”。</p>

    <h2>提交前 checklist</h2>
    <ul>
      <li>确认是否要先跑 <code>grammar.validate_grammar()</code>，因为 <code>generate_parse_table()</code> 不会自动做 Grammar 级校验。</li>
      <li>默认优先使用 <code>generate_parse_table()</code>，不要手工拼中间流水线当最终产物。</li>
      <li>确定你的冲突策略：哪些级别可以继续，哪些必须阻塞。</li>
      <li>如果要缓存或分发，明确走 JSON 还是二进制。</li>
    </ul>

    <h2>最容易踩的边界</h2>
    <table>
      <thead>
        <tr>
          <th>事项</th>
          <th>影响</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td><code>generate_parse_table()</code> 不自动做 Grammar 级校验</td>
          <td>未定义规则、非法 regex、<code>extras</code> 非终结符、模板参数问题等都应该在进入 tablegen 前由 <code>grammar.validate_grammar()</code> 处理。</td>
        </tr>
        <tr>
          <td>不是所有校验错误都必须一刀切阻塞</td>
          <td>例如某些左递归在 GLR 运行时是可处理的，是否继续编译是调用方策略。</td>
        </tr>
        <tr>
          <td>手工拼中间流水线代替最终入口</td>
          <td>中间阶段函数不会自动补齐最终成品表所需的运行时字段。</td>
        </tr>
        <tr>
          <td>冲突报告非空，不等于表不可用</td>
          <td>应按 <code>ConflictSeverity</code> 做策略判断，而不是只看“有没有报告”。</td>
        </tr>
        <tr>
          <td>把 JSON 和二进制混用为同一种用途</td>
          <td>JSON 更适合调试和展示，二进制更适合真正分发和运行时加载。</td>
        </tr>
        <tr>
          <td>把 ParseTable 当成普通编译中间值随意改写</td>
          <td>它实际是运行时协议，篡改后可能直接影响真实解析行为。</td>
        </tr>
      </tbody>
    </table>

    <h2>更适合哪些场景</h2>
    <ul>
      <li>构建 MoonParse grammar 对应的离线解析表。</li>
      <li>编写 parser generator CLI。</li>
      <li>做 LR / LALR 教学、项目集可视化或冲突分析工具。</li>
      <li>生成可序列化、可缓存、可部署的运行时解析产物。</li>
      <li>在 IDE 或 Web 工具里展示 grammar 编译结果和冲突信息。</li>
    </ul>
  </article>
</template>