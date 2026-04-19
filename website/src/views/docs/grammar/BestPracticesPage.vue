<template>
  <article>
    <h1>注意事项与适用场景</h1>
    <p><code>grammar/README.md</code> 最有价值的一部分其实是“使用边界”。很多 grammar 写起来不难，难的是不要把“能解析”误判成“能稳定进入下游链路”。</p>

    <h2>提交前 checklist</h2>
    <ul>
      <li><code>parse_grammar</code> 通过后，仍要执行 <code>validate_grammar</code>。</li>
      <li>正式构建优先使用 <code>parse_grammar</code>；编辑器或交互场景才优先用 <code>parse_grammar_lenient</code>。</li>
      <li>若 grammar 还要交给 <code>tablegen/</code>，先把 Grammar 级问题清掉，再谈冲突和运行时行为。</li>
      <li>若要缓存或交换 grammar，优先明确是保留 DSL 文本还是只保留 JSON 结构。</li>
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
          <td><code>parse_grammar</code> 通过，不等于 grammar 可用</td>
          <td>未定义规则、左递归、非法 regex、<code>word</code> / <code>extras</code> 约束等问题通常要到 <code>validate_grammar</code> 才会暴露。</td>
        </tr>
        <tr>
          <td>混用两套优先级系统</td>
          <td>顶层 <code>precedence</code> 和内联 <code>prec(...)</code> 必须二选一，否则会得到 <code>MixedPrecSystems</code>。</td>
        </tr>
        <tr>
          <td><code>extras</code> 放了非终结符</td>
          <td><code>extras</code> 只适合终结符模式，例如 literal、regex、any-char。</td>
        </tr>
        <tr>
          <td><code>token rule</code> 引用了普通规则</td>
          <td>会破坏词法层纯度，校验器会直接报错。</td>
        </tr>
        <tr>
          <td><code>word</code> 没指向合法 token</td>
          <td>关键字提升相关元数据无效，并会在校验阶段报错。</td>
        </tr>
        <tr>
          <td>模板规则没有实例化</td>
          <td>模板规则不能像普通规则那样直接引用，必须通过 <code>app(...)</code> 或 DSL 的 <code>name[...]</code> 使用。</td>
        </tr>
        <tr>
          <td>前瞻断言放在错误位置</td>
          <td><code>!p</code> / <code>&amp;p</code> 当前只建议放在序列尾部，否则可能触发警告或被忽略。</td>
        </tr>
        <tr>
          <td>只保留 JSON，不保留原始 DSL 位置</td>
          <td>JSON 往返不会保留源码位置信息，精确诊断仍要依赖原始 DSL 或解析期错误信息。</td>
        </tr>
        <tr>
          <td>重复定义规则后只看最终映射</td>
          <td><code>Grammar.rules</code> 最终只会保留后一次写入结果，不适合拿它做“保留全部原始定义”的编辑器能力。</td>
        </tr>
      </tbody>
    </table>

    <h2>更适合哪些场景</h2>
    <ul>
      <li>编写和加载 MoonParse 的 Grammar DSL。</li>
      <li>构建语法编辑器、grammar 校验器、grammar 预览工具。</li>
      <li>为 <code>tablegen/</code> 提供经过校验的标准输入。</li>
      <li>在工具链中缓存、交换、显示 Grammar 中间表示。</li>
    </ul>
    <p>如果你的目标已经是“把源码解析成 CST”，那就应该继续进入 <code>tablegen/</code> 和 <code>runtime/</code>，而不是停留在 <code>grammar/</code> 层。</p>
  </article>
</template>