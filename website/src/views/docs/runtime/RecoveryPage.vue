<template>
  <article>
    <h1>错误恢复</h1>
    <p>MoonParse 的错误恢复目标不是“尽早报错然后退出”，而是尽量继续构造一棵结构可用的树。这对编辑器、在线 playground 和半成品源码场景尤其重要。</p>

    <h2>恢复成本模型</h2>
    <table>
      <thead><tr><th>配置项</th><th>默认值</th><th>含义</th></tr></thead>
      <tbody>
        <tr><td><code>error_cost_per_skipped_tree</code></td><td>100</td><td>跳过一棵现有子树的成本。</td></tr>
        <tr><td><code>error_cost_per_skipped_char</code></td><td>1</td><td>跳过单个字符的成本。</td></tr>
        <tr><td><code>error_cost_per_skipped_line</code></td><td>30</td><td>跳过整行的额外倾向。</td></tr>
        <tr><td><code>error_cost_per_missing_tree</code></td><td>110</td><td>插入一个缺失节点的成本。</td></tr>
        <tr><td><code>error_cost_per_recovery</code></td><td>500</td><td>进入恢复模式本身的固定惩罚。</td></tr>
      </tbody>
    </table>

    <h2>恢复策略</h2>
    <ul>
      <li>跳过字符或节点，直到找到更便宜的同步点。</li>
      <li>插入零宽缺失节点，使结构仍能挂接到当前规则上。</li>
      <li>在多个恢复候选之间按总代价比较，保留更合理的版本。</li>
    </ul>

    <h2>恢复结果如何体现在树里</h2>
    <p>恢复不会只停留在日志里，而会直接写进 CST。你会看到 <code>is_missing=true</code> 的缺失叶节点、<code>is_error=true</code> 的错误节点，以及由恢复路径带来的额外代价差异。</p>

    <h2>配置的实际意义</h2>
    <p>如果你的语言更接近“行导向文本”，提高按行跳过的权重可能更合理；如果你更希望解析器优先插入缺失标点而不是吞掉整段输入，可以重新平衡缺失成本和跳过成本。</p>

    <h2>注意事项</h2>
    <p>对外的 <code>Result[CstNode, ParseError]</code> 并不意味着“只要返回 <code>Ok</code> 就没有错误”。很多语法错误会被恢复并留在树里，因此上层工具在消费结果时应同时检查节点上的 <code>is_error</code> / <code>is_missing</code> 信息。</p>
  </article>
</template>