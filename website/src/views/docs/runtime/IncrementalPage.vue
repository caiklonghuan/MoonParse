<template>
  <article>
    <h1>增量解析</h1>
    <p>增量解析的目标不是“尽量复用一切”，而是在保持正确性的前提下复用未受影响的旧子树。MoonParse 采用的是偏保守的复用策略：先标记旧树受影响区域，再在新一轮解析中查找满足起点、状态和前瞻边界要求的节点。</p>

    <h2>核心入口</h2>
    <pre><code>parse_with_old_tree(table, input, old_tree, edit)
parse_with_old_tree_and_config(table, input, old_tree, edit, config)
parse_with_old_tree_and_external_scanner(table, input, old_tree, edit, scanner)
parse_with_old_tree_and_stateful_scanner(table, input, old_tree, edit, scanner)

parse_incremental(table, input, old_tree, edit)
parse_incremental_with_config(table, input, old_tree, edit, config)</code></pre>

    <h2>增量所需的两份输入</h2>
    <table>
      <thead><tr><th>结构</th><th>作用</th></tr></thead>
      <tbody>
        <tr><td><code>OldTree</code></td><td>绑定旧根节点和旧输入文本，表示“上一版本的解析快照”。</td></tr>
        <tr><td><code>InputEdit</code></td><td>描述本次从旧输入到新输入的局部修改，同时包含字节区间和前后 <code>Point</code>。</td></tr>
      </tbody>
    </table>
    <p><code>OldTree</code> 不应该脱离原始旧文本单独保存和复用。只要旧树和旧文本失配，后续复用判断就失去可信度。</p>

    <h2>辅助接口</h2>
    <pre><code>apply_edit(old_tree, edit) -> OldTree
find_reusable_node(old_tree, new_pos, lr_state, edit_start, old_end_byte)
  -> CstNode?
is_reusable(node, new_pos, lr_state, edit_start, old_end_byte) -> Bool
check_incremental_invariants(root, edit) -> String?</code></pre>
    <p>这些接口主要用于调试和理解复用行为。高层调用通常只需要准备 <code>OldTree</code> 和 <code>InputEdit</code>，然后走 <code>parse_with_old_tree()</code>。</p>

    <h2>哪些节点不会被复用</h2>
    <ul>
      <li>与编辑区间相交，或者已经被标记为 <code>has_changes=true</code> 的节点。</li>
      <li>错误节点和缺失节点。</li>
      <li><code>fragile_left</code> 或 <code>fragile_right</code> 为真的 GLR 合并节点。</li>
      <li>起始状态不再匹配，或 lookahead 边界不再安全的节点。</li>
    </ul>

    <h2>输入编辑最容易出错的地方</h2>
    <ul>
      <li><code>start_byte</code>、<code>old_end_byte</code>、<code>new_end_byte</code> 和实际文本改动不一致。</li>
      <li><code>start_point</code>、<code>old_end_point</code>、<code>new_end_point</code> 和 byte offset 对不上。</li>
      <li>把字符列当成字节列传入，尤其是在包含多字节字符的输入里。</li>
    </ul>

    <h2>实战建议</h2>
    <p>如果上层编辑器已经能提供准确的 LSP 风格编辑范围，那么最值得优先保证的是 byte 和 point 的一致性。增量正确性的第一前提不是更复杂的算法，而是更准确的编辑描述。</p>
  </article>
</template>