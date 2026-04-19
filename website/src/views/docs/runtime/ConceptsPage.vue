<template>
  <article>
    <h1>核心概念</h1>
    <p><code>runtime/</code> 对外暴露的结构并不多，但每个类型都承载了运行时语义。理解这些类型之后，你就能判断当前拿到的是“树本身”“恢复配置”还是“增量复用所需的上下文”。</p>

    <h2>关键类型</h2>
    <table>
      <thead><tr><th>类型</th><th>角色</th><th>最值得关注的字段</th></tr></thead>
      <tbody>
        <tr><td><code>CstNode</code></td><td>运行时返回的 CST 节点</td><td><code>symbol</code>、<code>children</code>、<code>field_names</code>、<code>extra</code>、<code>is_missing</code>、<code>is_error</code>、<code>has_changes</code>、<code>fragile_left</code>、<code>fragile_right</code></td></tr>
        <tr><td><code>Point</code></td><td>0-based 行列坐标</td><td><code>row</code>、<code>column</code>；列是 Unicode codepoint 偏移，不是 UTF-8 byte offset</td></tr>
        <tr><td><code>ParseError</code></td><td>运行时硬失败描述</td><td><code>position</code>、<code>point</code>、<code>message</code></td></tr>
        <tr><td><code>ParseConfig</code></td><td>恢复代价和 GLR 截尾配置</td><td>跳过、缺失、恢复代价，以及 <code>max_version_count</code></td></tr>
        <tr><td><code>InputEdit</code></td><td>一次编辑的字节与坐标变化</td><td><code>start_byte</code>、<code>old_end_byte</code>、<code>new_end_byte</code> 以及对应的三个 <code>Point</code></td></tr>
        <tr><td><code>OldTree</code></td><td>旧树快照</td><td>旧根节点与旧输入文本，供增量复用查找</td></tr>
        <tr><td><code>ExternalScanner</code></td><td>无状态外部词法器</td><td>签名为 <code>(String, Int, Array[Int]) -&gt; (Int, Int)?</code></td></tr>
        <tr><td><code>StatefulScanner</code></td><td>有状态外部词法器 trait</td><td>需要实现 <code>scan()</code> 和 <code>clone_scanner()</code>，供 GLR 分支独立持有状态</td></tr>
      </tbody>
    </table>

    <h2>节点上的运行时标记</h2>
    <ul>
      <li><code>extra=true</code> 表示 extras 节点，例如空白和注释；它们保留在 CST 中，但不会像普通 token 那样驱动 LR 状态转移。</li>
      <li><code>is_missing=true</code> 表示恢复阶段插入的零宽缺失节点。</li>
      <li><code>is_error=true</code> 或 <code>symbol = sym_error</code> 表示错误节点。</li>
      <li><code>has_changes=true</code> 表示该节点落在编辑影响区间内，通常不能直接复用。</li>
      <li><code>fragile_left=true</code> 或 <code>fragile_right=true</code> 表示它来自 GLR 多路径合并边界，后续增量复用必须更保守。</li>
      <li><code>parse_state</code> 和 <code>lookahead_bytes</code> 记录节点创建时的解析上下文，供增量复用判定使用。</li>
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
    <p>这些参数控制的是运行时策略，不是文法本身。多数场景先用默认值即可，只有在确实需要调优恢复行为或控制 GLR 分支规模时才应修改。</p>

    <h2>两种“成功”的区别</h2>
    <table>
      <thead><tr><th>结果</th><th>含义</th></tr></thead>
      <tbody>
        <tr><td><code>Ok(root)</code></td><td>运行时给出了一棵可用树，但其中仍可能含有 <code>ERROR</code> / <code>MISSING</code> 节点。</td></tr>
        <tr><td><code>check_clean_root(root, input) = None</code></td><td>这棵树完整覆盖输入，并且没有恢复留下的错误或缺失节点。</td></tr>
      </tbody>
    </table>

    <h2>位置与偏移</h2>
    <ul>
      <li><code>start_byte</code> / <code>end_byte</code> 适合底层切片、编辑计算和 scanner 回调。</li>
      <li><code>Point</code> 更适合展示、定位和与编辑器集成。</li>
      <li><code>Point.column</code> 是 Unicode codepoint 列，不要把它直接当成 UTF-8 字节列。</li>
    </ul>

    <h2>常见误区</h2>
    <ul>
      <li>把 <code>Ok(root)</code> 当成“源码没有语法错误”；实际错误经常以内嵌节点形式保留在树里。</li>
      <li>只根据编辑区间判断节点是否可复用；复用还依赖状态、错误标记、前瞻边界和 fragile 标记。</li>
      <li>认为外部 scanner 只在单路径下工作；实际上 GLR 分支下更要注意 scanner 状态隔离。</li>
    </ul>
  </article>
</template>