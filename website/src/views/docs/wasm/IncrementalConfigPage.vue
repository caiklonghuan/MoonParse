<template>
  <article>
    <h1>增量与配置</h1>
    <p><code>wasm/</code> 不只暴露一次性全量解析，还暴露了增量解析和全局 GLR 错误恢复参数。这两者组合起来，才是编辑器和 IDE 集成真正高频使用的路径。</p>

    <h2>低层增量解析</h2>
    <pre><code>parse_incremental(
  parserId,
  oldTreeId,
  newSource,
  start_byte,
  old_end_byte,
  new_end_byte,
  start_row,
  start_col,
  old_end_row,
  old_end_col,
  new_end_row,
  new_end_col,
)</code></pre>
    <p>这个接口返回新的 <code>tree_id</code>。如果调用成功，宿主需要自己决定何时释放旧树和新树；如果调用失败，则返回 <code>-1</code>，并通过 <code>parse_error_last()</code> 提供最近一次运行时错误说明。</p>

    <h2>便捷增量接口</h2>
    <pre><code>wasm_parse_incremental(parserId, source, oldTreeId, changesJson)</code></pre>
    <p>这是一层更接近浏览器或编辑器宿主的数据形态的薄封装。它接收 JSON 形式的编辑信息，返回新的树 JSON 字符串，而不是新的句柄。</p>

    <h3>它和低层接口的关键差别</h3>
    <ul>
      <li>低层 <code>parse_incremental()</code> 返回新树句柄，更适合长期复用。</li>
      <li><code>wasm_parse_incremental()</code> 返回 JSON 字符串，适合一次性消费。</li>
      <li>按 README 的约定，<code>wasm_parse_incremental()</code> 会在内部消费旧树句柄与新树句柄，不把新树继续留给宿主复用。</li>
    </ul>
    <p>因此，如果你的目标是反复复用最新树，应优先选低层接口，而不是这层便捷封装。</p>

    <h2>GLR 错误恢复参数</h2>
    <pre><code>parse_config_set(
  error_cost_per_skipped_tree,
  error_cost_per_skipped_char,
  error_cost_per_skipped_line,
  error_cost_per_missing_tree,
  error_cost_per_recovery,
  max_version_count,
  max_version_count_overflow,
)

parse_config_reset()</code></pre>
    <p><code>parse_config_set()</code> 的 7 个参数都属于模块级全局配置。某个位置传 <code>-1</code> 表示“保留当前值不修改”。这些设置会影响后续的全量和增量解析，但不会回溯性地改变已经生成的树。</p>

    <h2>高层 JS wrapper 对应接口</h2>
    <pre><code>mp.setParseConfig({ ... })
mp.resetParseConfig()
mp.parseErrorLast()</code></pre>
    <p><code>moonparse.js</code> 把位置参数 API 包装成了对象式接口，更适合 JS/TS 侧直接调用。</p>

    <h2>调用上的一个关键限制</h2>
    <p>这些配置不是某个 <code>parser_id</code> 私有的，而是整个 wasm 模块共享的全局状态。如果一个宿主里同时存在多种不同的解析需求，配置切换就需要调用方自己协调。</p>
  </article>
</template>