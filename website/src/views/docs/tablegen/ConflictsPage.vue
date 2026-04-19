<template>
  <article>
    <h1>冲突处理</h1>
    <p><code>generate_parse_table()</code> 返回的第二项就是 <code>Array[ConflictReport]</code>。它不是附带信息，而是编译产物诊断的一部分，调用方应明确决定哪些冲突可接受、哪些要阻塞构建。</p>

    <h2>四类严重级别</h2>
    <table>
      <thead>
        <tr>
          <th>级别</th>
          <th>典型含义</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td><code>Warn</code></td>
          <td>优先级或结合性已经成功消解，但仍值得报告。</td>
        </tr>
        <tr>
          <td><code>Ambiguous</code></td>
          <td>编译期无法完全消解，需要 GLR 在运行时保留歧义路径。</td>
        </tr>
        <tr>
          <td><code>DynamicConflict</code></td>
          <td>依赖 <code>prec.dynamic</code> 一类运行时动态优先级机制。</td>
        </tr>
        <tr>
          <td><code>Declared</code></td>
          <td>这组冲突已被 grammar 显式声明为预期歧义。</td>
        </tr>
      </tbody>
    </table>

    <h2>按严重级别打印冲突报告</h2>
    <pre><code>fn print_conflict_reports(reports : Array[@tablegen.ConflictReport]) -&gt; Unit {
  for report in reports {
    let level = match report.severity {
      @tablegen.ConflictSeverity::Warn(_) =&gt; "warn"
      @tablegen.ConflictSeverity::Ambiguous(_) =&gt; "ambiguous"
      @tablegen.ConflictSeverity::DynamicConflict(_) =&gt; "dynamic"
      @tablegen.ConflictSeverity::Declared(_) =&gt; "declared"
    }
    println(
      level +
      " conflict at state=" +
      report.state.to_string() +
      " terminal=" +
      report.terminal.to_string(),
    )
  }
}</code></pre>

    <h2>调用方应该怎么判断</h2>
    <ul>
      <li><code>Warn</code>：通常可继续，更多是提示性输出。</li>
      <li><code>Declared</code>：表示预期歧义，通常也可继续。</li>
      <li><code>DynamicConflict</code>：是否接受取决于运行时策略。</li>
      <li><code>Ambiguous</code>：很多正式构建链路会选择阻塞，或要求显式容忍 GLR 歧义。</li>
    </ul>

    <h2>声明冲突不是“关闭冲突检查”</h2>
    <pre><code>conflicts [[expr, type_expr]]</code></pre>
    <p>这类声明的含义是：这组规则之间的多解是预期行为，应按 <code>Declared</code> 报告，而不是继续当作“未声明歧义”。它并不会强制把冲突“优化掉”。</p>

    <h2>注意事项</h2>
    <p><code>ConflictReport</code> 和 <code>ParseTable</code> 是分开返回的。无论走 <code>table_to_json()</code> 还是 <code>serialize_table()</code>，都只会序列化最终表本身，不会把冲突报告自动打包进去。需要缓存或展示报告时，请在调用层自行保存。</p>
  </article>
</template>