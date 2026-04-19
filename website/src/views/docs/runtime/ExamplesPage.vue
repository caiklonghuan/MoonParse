<template>
  <article>
    <h1>示例</h1>
    <p>这一页给出 <code>runtime/</code> 最常见的五种使用方式：正式解析、DSL 快速验证、增量解析、外部 scanner，以及运行后检查。所有示例都围绕 README 中推荐的调用路径组织。</p>

    <h2>示例 1：解析并判断结果是否干净</h2>
    <pre><code>match @runtime.parse(table, input) {
  Ok(root) =>
    match @runtime.check_clean_root(root, input) {
      None => println("clean parse")
      Some(msg) => println("recovered parse: " + msg)
    }
  Err(err) => println("runtime error: " + err.message)
}</code></pre>
    <p>这段代码体现了最重要的使用习惯：<code>Ok(root)</code> 只表示 runtime 给出了树，不表示输入没有语法问题。</p>

    <h2>示例 2：直接从 DSL 快速验证</h2>
    <pre><code>match @runtime.parse_from_dsl(
  "start list\nextras [/[ \\t\\n\\r]+/]\nrule list: /[A-Za-z_][A-Za-z0-9_]*/ (\",\" /[A-Za-z_][A-Za-z0-9_]*/) *",
  "foo,bar,baz",
) {
  Ok(root) => println(root.to_string())
  Err(err) => println(err.message)
}</code></pre>
    <p><code>parse_from_dsl()</code> 会在内部完成 Grammar 解析、校验、建表和运行时解析。它适合文档示例和调试原型，但不适合高频调用。</p>

    <h2>示例 3：基于旧树做增量解析</h2>
    <pre><code>let old_root = match @runtime.parse(table, old_input) {
  Ok(root) => root
  Err(err) => {
    println(err.message)
    return
  }
}

let old_tree : @runtime.OldTree = {
  root: old_root,
  old_input: old_input,
}

let edit : @runtime.InputEdit = {
  start_byte: 2,
  old_end_byte: 2,
  new_end_byte: 3,
  start_point: @runtime.bytes_to_point(old_input, 0, { row: 0, column: 0 }, 2),
  old_end_point: @runtime.bytes_to_point(old_input, 0, { row: 0, column: 0 }, 2),
  new_end_point: @runtime.bytes_to_point(new_input, 0, { row: 0, column: 0 }, 3),
}

match @runtime.parse_with_old_tree(table, new_input, Some(old_tree), Some(edit)) {
  Ok(root) => println(root.end_byte.to_string())
  Err(err) => println(err.message)
}</code></pre>
    <p>增量解析是否真正复用旧节点，首先取决于 <code>OldTree</code> 是否来自对应的旧文本，其次取决于 <code>InputEdit</code> 的 byte 和 point 是否一致。</p>

    <h2>示例 4：接入外部 scanner</h2>
    <pre><code>fn scanner(
  input : String,
  pos : Int,
  valid_external_tids : Array[Int],
) -> (Int, Int)? {
  let custom_tid = 7
  let mut allowed = false
  for tid in valid_external_tids {
    if tid == custom_tid {
      allowed = true
      break
    }
  }

  if allowed && pos &lt; input.length() &&
    input[pos].to_int().to_char().unwrap() == '@' {
    Some((custom_tid, pos + 1))
  } else {
    None
  }
}

match @runtime.parse_with_external_scanner(table, input, scanner) {
  Ok(root) => println(root.end_byte.to_string())
  Err(err) => println(err.message)
}</code></pre>
    <p>如果 scanner 需要维护缩进栈或模式切换等分支相关状态，应改用 <code>StatefulScanner</code>，让 GLR 分叉时每条路径都能持有独立状态。</p>

    <h2>示例 5：做结构检查和覆盖率统计</h2>
    <pre><code>match @runtime.check_cst_invariants(root, input) {
  None => println("tree structure is valid")
  Some(msg) => println("tree invariant broken: " + msg)
}

let report = @runtime.grammar_coverage_report(
  table,
  ["a,b", "x,y,z"],
  1,
)
println(report)</code></pre>
    <p>这两组接口非常适合测试、回归和语法样例集评估。前者回答“树是不是结构正确”，后者回答“样例有没有覆盖到规则”。</p>
  </article>
</template>