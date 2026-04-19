<template>
  <article>
    <h1>示例</h1>
    <p>这一页给出几段最常用的查询工作流：编译并执行查询、按 <code>match_id</code> 分组理解结果、做高亮，以及做 locals 解析。</p>

    <h2>示例 1：最基础的结构查询</h2>
    <pre><code>import {
  "caiklonghuan/MoonParse/query" @query,
  "caiklonghuan/MoonParse/runtime" @runtime,
  "caiklonghuan/MoonParse/tablegen" @tablegen,
}

fn run_identifier_query(
  root : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
) -> Unit {
  let compiled = match @query.compile("(identifier) @name") {
    Ok(q) => q
    Err(err) => {
      println(err.to_string())
      return
    }
  }

  let captures = @query.exec(compiled, root, input, table)
  for capture in captures {
    println(capture.capture_name + ": " + @query.node_text(capture.node, input))
  }
}</code></pre>

    <h2>示例 2：用 <code>match_id</code> 理解多捕获结果</h2>
    <pre><code>let captures = @query.exec(compiled, root, input, table)
for capture in captures {
  println(
    "match=" + capture.match_id.to_string() +
    ", capture=" + capture.capture_name +
    ", text=" + @query.node_text(capture.node, input),
  )
}</code></pre>
    <p>如果一条顶层模式里既有顶层捕获又有子捕获，它们会共享同一个 <code>match_id</code>。</p>

    <h2>示例 3：用谓词过滤结果</h2>
    <pre><code>(identifier) @name
#match? @name "^[a-z]+$"
#not-eq? @name "self"</code></pre>
    <p>这个查询会保留全小写且文本不等于 <code>self</code> 的标识符。</p>

    <h2>示例 4：生成高亮区间</h2>
    <pre><code>let highlight_query = match @query.compile(
  #|(number_literal) @number
  #|(string_literal) @string
) {
  Ok(q) => q
  Err(err) => {
    println(err.to_string())
    return
  }
}

let ranges = @query.apply_highlights(root, input, table, highlight_query)
for range in ranges {
  println(
    range.highlight_name +
    " [" + range.start_byte.to_string() + ", " + range.end_byte.to_string() + ")",
  )
}</code></pre>

    <h2>示例 5：locals 解析</h2>
    <pre><code>let locals_query = match @query.compile(
  #|(block) @local.scope
  #|(identifier) @local.definition
  #|(identifier) @local.reference
) {
  Ok(q) => q
  Err(err) => {
    println(err.to_string())
    return
  }
}

let resolution = @query.resolve_locals(root, input, table, locals_query)
if resolution.is_local_ref(42) {
  println("node at start_byte=42 is a local reference")
}</code></pre>

    <h2>示例 6：带 locals 的高亮</h2>
    <pre><code>let ranges = @query.apply_highlights_with_locals(
  root,
  input,
  table,
  highlight_query,
  locals_query,
)

for range in ranges {
  println(range.highlight_name)
}</code></pre>
    <p>如果某个高亮区间对应的是已绑定的本地引用，名字会自动追加 <code>.local</code> 后缀。</p>
  </article>
</template>