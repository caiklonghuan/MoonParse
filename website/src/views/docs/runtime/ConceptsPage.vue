<template>
  <article>
    <h1>核心概念</h1>
    <p>这页只保留 runtime 里最常用的几类结构，方便你在接口、日志和调试输出里快速判断“当前拿到的是结果、配置，还是增量辅助结构”。</p>

    <h2>关键类型</h2>
    <table>
      <thead><tr><th>类型</th><th>角色</th><th>关键字段</th></tr></thead>
      <tbody>
        <tr><td><code>CstNode</code></td><td>运行时返回的语法树节点</td><td><code>symbol</code>、<code>children</code>、<code>field_names</code>、<code>extra</code>、<code>is_missing</code>、<code>is_error</code>、<code>fragile_left/right</code></td></tr>
        <tr><td><code>Point</code></td><td>0-based 行列坐标</td><td><code>row</code>、<code>column</code>；列是 Unicode codepoint 偏移，不是 UTF-8 byte offset</td></tr>
        <tr><td><code>ParseError</code></td><td>硬失败时的错误描述</td><td><code>position</code>、<code>point</code>、<code>message</code></td></tr>
        <tr><td><code>ParseConfig</code></td><td>错误恢复和并行版本裁剪配置</td><td>跳过/缺失/恢复代价、<code>max_version_count</code></td></tr>
        <tr><td><code>InputEdit</code></td><td>一次编辑的字节和坐标变化</td><td><code>start_byte</code>、<code>old_end_byte</code>、<code>new_end_byte</code> 以及前后 Point</td></tr>
        <tr><td><code>OldTree</code></td><td>旧树快照</td><td>旧根节点和旧输入文本，供增量复用查找</td></tr>
      </tbody>
    </table>

    <h2>特殊节点</h2>
    <ul>
      <li><code>extra=true</code> 表示这是 extras token，例如空白或注释，它会保留在 CST 中但不改变 LR 状态。</li>
      <li><code>is_missing=true</code> 表示这是恢复阶段插入的零宽缺失节点。</li>
      <li><code>is_error=true</code> 或 <code>symbol = sym_error</code> 表示这是错误节点。</li>
      <li><code>fragile_left/right=true</code> 表示该节点来自 GLR 多路径合并边界，不能安全参与增量复用。</li>
    </ul>

    <h2>默认配置</h2>
    <pre><code>ParseConfig::default() = {
  error_cost_per_skipped_tree: 100,
  error_cost_per_skipped_char: 1,
  error_cost_per_skipped_line: 30,
  error_cost_per_missing_tree: 110,
  error_cost_per_recovery: 500,
  max_version_count: 6,
  max_version_count_overflow: 4,
}</code></pre>

    <h2>最短判断方式</h2>
    <ul>
      <li><code>CstNode</code> 是最终解析结果，不是中间 token 流；错误恢复和增量信息会直接写在节点上。</li>
      <li><code>ParseConfig</code> 主要影响恢复代价和并行版本裁剪；多数场景先用默认值即可。</li>
      <li><code>InputEdit</code> 和 <code>OldTree</code> 只在增量解析时需要，普通解析不必准备它们。</li>
    </ul>

    <h2>常见误区</h2>
    <ul>
      <li>把 <code>Ok(root)</code> 当成“没有语法错误”；实际错误可能已经以内嵌节点形式保留在树里。</li>
      <li>把 <code>Point.column</code> 当成 UTF-8 字节偏移；它表示的是 0-based Unicode codepoint 列。</li>
      <li>只根据编辑区间判断节点是否可复用；增量复用还依赖状态、错误标记和 fragile 边界。</li>
    </ul>
  </article>
</template>