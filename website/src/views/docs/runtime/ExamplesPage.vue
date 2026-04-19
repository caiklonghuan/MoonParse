<template>
  <article>
    <h1>示例</h1>
    <p>这一页给出 runtime 最常见的三种使用方式：全量解析、增量解析，以及带外部词法器的解析。</p>

    <h2>示例 1：普通解析</h2>
    <pre><code>let result = @runtime.parse(table, source)
match result {
  Ok(root) => println(root.to_string())
  Err(err) => println(err.to_string())
}</code></pre>

    <h2>示例 2：直接从 DSL 解析</h2>
    <pre><code>let result = @runtime.parse_from_dsl(
  "start s\nrule s: /[a-z]+/",
  "hello",
)</code></pre>
    <p>这个入口会先做 Grammar 解析和表生成，再执行 runtime 解析。适合快速实验，不适合反复高频调用。</p>

    <h2>示例 3：增量解析</h2>
    <pre><code>let old_tree : @runtime.OldTree = { root, old_input: "abc" }
let edit : @runtime.InputEdit = {
  start_byte: 1,
  old_end_byte: 2,
  new_end_byte: 3,
  start_point: { row: 0, column: 1 },
  old_end_point: { row: 0, column: 2 },
  new_end_point: { row: 0, column: 3 },
}

let next = @runtime.parse_with_old_tree(table, "axyc", Some(old_tree), Some(edit))</code></pre>

    <h2>示例 4：自定义恢复配置</h2>
    <pre><code>let config = {
  ..@runtime.ParseConfig::default(),
  error_cost_per_recovery: 800,
}

let result = @runtime.parse_with_config(table, source, config)</code></pre>

    <h2>示例 5：外部词法器</h2>
    <pre><code>fn scanner(input : String, pos : Int, valid : Array[Int]) -> (Int, Int)? {
  ignore(input)
  ignore(pos)
  ignore(valid)
  None
}

let result = @runtime.parse_with_external_scanner(table, source, scanner)</code></pre>
    <p>真正的回调一般会根据当前位置和当前允许的外部 token 集合返回一个 <code>(terminal_id, end_pos)</code>。这非常适合缩进敏感语言。</p>
  </article>
</template>