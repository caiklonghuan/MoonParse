<template>
  <article>
    <h1>增量解析</h1>
    <p>增量解析的目标是在输入只改了一小块时，不必重跑整棵树。MoonParse 通过 <code>OldTree</code> 和 <code>InputEdit</code> 标记受影响区域，再在新解析过程中查找可安全复用的旧节点。</p>

    <h2>核心入口</h2>
    <pre><code>parse_with_old_tree(table, input, old_tree, edit)
parse_with_old_tree_and_config(table, input, old_tree, edit, config)
parse_with_old_tree_and_external_scanner(table, input, old_tree, edit, scanner)</code></pre>

    <h2><code>InputEdit</code> 要求</h2>
    <p>运行时会同时依赖字节范围和 Point 坐标来传播变更。如果 <code>start_byte</code>、<code>old_end_byte</code>、<code>new_end_byte</code> 或行列坐标不准确，旧树节点的边界就会和新输入错位，结果只能退化为无法复用，甚至错误复用。</p>

    <h2>哪些节点不能复用</h2>
    <ul>
      <li>与编辑区间相交、<code>has_changes=true</code> 的节点。</li>
      <li>错误节点和缺失节点。</li>
      <li><code>fragile_left</code> 或 <code>fragile_right</code> 为真的 GLR 合并节点。</li>
      <li>lookahead 边界不再安全的节点。</li>
    </ul>

    <h2>注意事项</h2>
    <p>如果你的上层编辑器已经能提供准确的 LSP 风格改动范围，那么最值得先做的是保证 byte offset 和 row/column 计算一致。增量正确性的第一前提不是更复杂的算法，而是更准确的输入编辑描述。</p>
  </article>
</template>