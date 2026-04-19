<template>
  <article>
    <h1>公共接口</h1>
    <p>这一页按“正式解析、增量解析、扫描器接入、调试辅助”四类整理 <code>runtime/</code> 的公开入口。需要记住的一点是：绝大多数高层入口最后都会落到 GLR 运行时，而不是单路径 LR。</p>

    <h2>正式解析入口</h2>
    <pre><code>parse(table, input) -> Result[CstNode, ParseError]
parse_with_config(table, input, config) -> Result[CstNode, ParseError]
parse_linear(table, input) -> Result[CstNode, ParseError]
parse_from_dsl(dsl, input) -> Result[CstNode, ParseError]</code></pre>
    <table>
      <thead><tr><th>入口</th><th>适用场景</th></tr></thead>
      <tbody>
        <tr><td><code>parse()</code></td><td>默认生产入口；已经有 <code>ParseTable</code> 时优先使用。</td></tr>
        <tr><td><code>parse_with_config()</code></td><td>需要调节恢复代价或 GLR 活跃版本上限。</td></tr>
        <tr><td><code>parse_linear()</code></td><td>非歧义文法、白盒测试和基准对照。</td></tr>
        <tr><td><code>parse_from_dsl()</code></td><td>快速验证 DSL 和样例，不适合高频调用。</td></tr>
      </tbody>
    </table>

    <h2>增量解析入口</h2>
    <pre><code>parse_with_old_tree(table, input, old_tree, edit)
parse_with_old_tree_and_config(table, input, old_tree, edit, config)

parse_incremental(table, input, old_tree, edit)
parse_incremental_with_config(table, input, old_tree, edit, config)</code></pre>
    <p><code>parse_with_old_tree*</code> 是面向调用方的直观入口，<code>parse_incremental*</code> 是同一能力的底层公开函数。两类接口都要求 <code>OldTree</code> 与 <code>InputEdit</code> 严格对应旧输入和本次编辑。</p>

    <h2>外部 scanner 入口</h2>
    <pre><code>parse_with_external_scanner(table, input, scanner)
parse_with_old_tree_and_external_scanner(table, input, old_tree, edit, scanner)

parse_with_stateful_scanner(table, input, scanner)
parse_with_stateful_scanner_and_config(table, input, scanner, config)
parse_with_old_tree_and_stateful_scanner(table, input, old_tree, edit, scanner)
parse_with_old_tree_and_stateful_scanner_and_config(
  table, input, old_tree, edit, scanner, config,
)

external_scanner_to_stateful(scanner) -> &StatefulScanner</code></pre>
    <p>如果 scanner 没有内部状态，无状态回调就足够；如果 scanner 需要维护缩进栈、上下文模式或其他分支相关状态，优先使用 <code>StatefulScanner</code>。</p>

    <h2>辅助与诊断接口</h2>
    <pre><code>apply_edit(old_tree, edit) -> OldTree
find_reusable_node(old_tree, new_pos, lr_state, edit_start, old_end_byte)
  -> CstNode?
is_reusable(node, new_pos, lr_state, edit_start, old_end_byte) -> Bool

bytes_to_point(source, byte_offset, origin, start_byte) -> Point
byte_offset_to_char_col(source, line_start_byte, col_bytes) -> Int

check_cst_invariants(root, input) -> String?
check_clean_root(root, input) -> String?
check_incremental_invariants(root, edit) -> String?
grammar_coverage_report(table, samples, min_count) -> String</code></pre>

    <h2>关键类型与常量</h2>
    <table>
      <thead><tr><th>名称</th><th>作用</th></tr></thead>
      <tbody>
        <tr><td><code>CstNode</code></td><td>运行时 CST 节点；叶节点、内部节点、错误节点和缺失节点共用这一结构。</td></tr>
        <tr><td><code>Point</code></td><td>0-based 行列坐标。</td></tr>
        <tr><td><code>ParseError</code></td><td>运行时硬失败描述。</td></tr>
        <tr><td><code>ParseConfig</code></td><td>错误恢复和 GLR 版本裁剪配置。</td></tr>
        <tr><td><code>InputEdit</code></td><td>增量编辑描述。</td></tr>
        <tr><td><code>OldTree</code></td><td>旧树快照。</td></tr>
        <tr><td><code>sym_end</code></td><td>EOF 终结符。</td></tr>
        <tr><td><code>sym_error</code></td><td>错误节点使用的特殊符号。</td></tr>
      </tbody>
    </table>

    <h2>入口选择建议</h2>
    <ul>
      <li>已经有稳定的 <code>ParseTable</code> 时，优先调用 <code>parse()</code> 或它的配置 / 增量 / scanner 变体。</li>
      <li>只有在快速验证文法原型时才使用 <code>parse_from_dsl()</code>，不要把它放进热路径。</li>
      <li>需要判断“树是否可用”时看 <code>Result</code>；需要判断“树是否干净”时再看 <code>check_clean_root()</code>。</li>
    </ul>
  </article>
</template>