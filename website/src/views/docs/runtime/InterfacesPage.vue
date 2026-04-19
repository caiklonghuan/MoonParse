<template>
  <article>
    <h1>公共接口</h1>
    <p>这一页汇总 <code>runtime/</code> 包对外暴露的稳定入口和关键类型。对于大多数调用方，最重要的是几条 parse 入口、增量结构和错误配置。</p>

    <h2>解析入口</h2>
    <pre><code>parse(table, input) -> Result[CstNode, ParseError]
parse_with_config(table, input, config) -> Result[CstNode, ParseError]
parse_from_dsl(dsl, input) -> Result[CstNode, ParseError]

parse_with_old_tree(table, input, old_tree, edit)
parse_with_old_tree_and_config(table, input, old_tree, edit, config)

parse_with_external_scanner(table, input, scanner)
parse_with_old_tree_and_external_scanner(table, input, old_tree, edit, scanner)</code></pre>

    <h2>辅助入口</h2>
    <pre><code>apply_edit(old_tree, edit) -> OldTree
find_reusable_node(old_tree, new_pos, lr_state, edit_start, old_end_byte)
  -> CstNode?

byte_offset_to_char_col(source, line, col_bytes) -> Int
bytes_to_point(source, byte_offset, origin, start_byte) -> Point</code></pre>

    <h2>核心类型</h2>
    <table>
      <thead><tr><th>类型</th><th>说明</th></tr></thead>
      <tbody>
        <tr><td><code>CstNode</code></td><td>运行时语法树节点，叶节点和内部节点共享一套结构。</td></tr>
        <tr><td><code>Point</code></td><td>0-based 行列坐标。</td></tr>
        <tr><td><code>ParseError</code></td><td>解析硬失败时返回的位置和消息。</td></tr>
        <tr><td><code>ParseConfig</code></td><td>错误恢复和 GLR 版本裁剪配置。</td></tr>
        <tr><td><code>InputEdit</code></td><td>增量编辑描述。</td></tr>
        <tr><td><code>OldTree</code></td><td>旧树快照，供增量复用。</td></tr>
        <tr><td><code>ExternalScanner</code></td><td>外部词法器回调类型。</td></tr>
      </tbody>
    </table>

    <h2>特殊符号常量</h2>
    <pre><code>sym_end          // EOF
sym_error        // ERROR 节点
sym_error_repeat // 错误恢复中间节点</code></pre>

    <h2>入口选择</h2>
    <p>如果你已经有稳定的 <code>ParseTable</code>，优先调用 <code>parse()</code> 或其增量/配置变体；如果只是想快速试一段 DSL，才使用 <code>parse_from_dsl()</code>。后者每次都会重复经过 Grammar 和 Tablegen。</p>
  </article>
</template>