<template>
  <article>
    <h1>错误恢复</h1>
    <p>MoonParse 的恢复目标不是“尽快失败”，而是“尽量继续产出一棵结构可用的树”。这使它特别适合编辑器、在线 playground 和半成品源码等场景，因为这些场景里输入经常暂时不完整。</p>

    <h2>恢复成本模型</h2>
    <table>
      <thead><tr><th>配置项</th><th>默认值</th><th>作用</th></tr></thead>
      <tbody>
        <tr><td><code>error_cost_per_skipped_tree</code></td><td>100</td><td>跳过一棵已有子树的代价。</td></tr>
        <tr><td><code>error_cost_per_skipped_char</code></td><td>1</td><td>逐字符跳过输入的代价。</td></tr>
        <tr><td><code>error_cost_per_skipped_line</code></td><td>30</td><td>跨整行跳过的额外倾向。</td></tr>
        <tr><td><code>error_cost_per_missing_tree</code></td><td>110</td><td>插入一个零宽缺失节点的代价。</td></tr>
        <tr><td><code>error_cost_per_recovery</code></td><td>500</td><td>进入恢复模式本身的固定惩罚。</td></tr>
      </tbody>
    </table>

    <h2>恢复会做什么</h2>
    <ul>
      <li>跳过字符或节点，直到找到代价更低的同步点。</li>
      <li>插入零宽 <code>MISSING</code> 节点，让结构仍然能挂接到当前规则上。</li>
      <li>在多个恢复候选之间按总代价比较，保留更合理的版本。</li>
    </ul>

    <h2>恢复结果怎样体现在树里</h2>
    <p>恢复不会只停留在日志里，而是会直接写进 CST。你会看到 <code>is_missing=true</code> 的缺失节点、<code>is_error=true</code> 的错误节点，以及与恢复路径相关的边界与代价差异。</p>

    <h2><code>Ok(root)</code> 和 <code>Err(ParseError)</code> 的区别</h2>
    <table>
      <thead><tr><th>结果</th><th>语义</th></tr></thead>
      <tbody>
        <tr><td><code>Ok(root)</code></td><td>runtime 给出了一棵可用树，哪怕其中带有恢复留下的错误或缺失节点。</td></tr>
        <tr><td><code>Err(ParseError)</code></td><td>运行时未能继续给出可接受结果，更接近“硬失败”而不是普通语法错误。</td></tr>
      </tbody>
    </table>

    <h2>何时需要自定义 <code>ParseConfig</code></h2>
    <ul>
      <li>你想调节“插入缺失节点”与“跳过输入”之间的偏好。</li>
      <li>你的语言更接近行导向文本，需要提高按行跳过的影响。</li>
      <li>你正在调试歧义文法，需要同时观察恢复代价与 GLR 分支数。</li>
    </ul>
    <p>如果没有明确证据，不建议随意改动默认值。默认配置已经是在真实编辑器场景下比较平衡的折中方案。</p>

    <h2>消费恢复结果的正确方式</h2>
    <pre><code>match @runtime.parse_with_config(table, input, config) {
  Ok(root) =>
    match @runtime.check_clean_root(root, input) {
      None => println("clean tree")
      Some(msg) => println("tree contains recovery markers: " + msg)
    }
  Err(err) => println(err.message)
}</code></pre>
    <p>只看 <code>Result</code> 只能知道 runtime 有没有返回树；要判断上层业务是否接受这棵树，还要再检查 <code>is_error</code>、<code>is_missing</code> 或直接调用 <code>check_clean_root()</code>。</p>
  </article>
</template>