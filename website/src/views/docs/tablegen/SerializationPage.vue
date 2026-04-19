<template>
  <article>
    <h1>序列化</h1>
    <p><code>tablegen/README.md</code> 明确区分了两条持久化路径：JSON 更适合调试和展示，二进制更适合真正落盘、缓存和运行时加载。两条路径都围绕最终的 <code>ParseTable</code> 工作。</p>

    <h2>公开入口</h2>
    <pre><code>table_to_json(table)          -> String
table_from_json(json)         -> Result[ParseTable, String]
serialize_table(table)        -> Bytes
deserialize_table(bytes)      -> Result[ParseTable, String]</code></pre>

    <h2>JSON 适合什么</h2>
    <ul>
      <li>调试、可视化和诊断输出。</li>
      <li>快照测试。</li>
      <li>想直接检查表里长什么样时的人类可读中间格式。</li>
    </ul>

    <h2>二进制适合什么</h2>
    <ul>
      <li>真正落盘和运行时加载。</li>
      <li>减少体积和字符串解析成本。</li>
      <li>做实际分发产物缓存。</li>
    </ul>

    <h2>序列化往返示例</h2>
    <pre><code>fn roundtrip_table(table : @tablegen.ParseTable) -> Unit {
  let json = @tablegen.table_to_json(table)
  let bytes = @tablegen.serialize_table(table)

  let from_json = match @tablegen.table_from_json(json) {
    Ok(t) => t
    Err(msg) => {
      println("table_from_json failed: " + msg)
      return
    }
  }

  let from_bytes = match @tablegen.deserialize_table(bytes) {
    Ok(t) => t
    Err(msg) => {
      println("deserialize_table failed: " + msg)
      return
    }
  }

  println("json states = " + from_json.states.to_string())
  println("bytes states = " + from_bytes.states.to_string())
}</code></pre>

    <h2>为什么最终产物必须是 ParseTable</h2>
    <p><code>ParseTable</code> 不只是 action / goto 的“教科书最小表”，它还包含运行时需要的 <code>lexer_dfa</code>、<code>terminal_names</code>、<code>extras</code>、<code>external_token_ids</code>、<code>word_token</code>、<code>keyword_map</code> 等辅助字段。真正面向运行时协议的是完整成品表，而不是中间的 <code>AugmentedGrammar</code> 或项目集。</p>

    <h2>注意事项</h2>
    <ul>
      <li><code>table_to_json()</code> 和 <code>serialize_table()</code> 只处理 <code>ParseTable</code>，不包含单独返回的 <code>ConflictReport[]</code>。</li>
      <li>如果只是想“看懂表长什么样”，优先用 JSON；如果目标是做实际编译产物分发，优先用二进制。</li>
      <li>一旦已经拿到稳定的 JSON 或 Bytes，后续恢复时应优先走反序列化入口，而不是重复做一遍 Grammar 到 ParseTable 的全量编译。</li>
    </ul>
  </article>
</template>