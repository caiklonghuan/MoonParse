<template>
  <article>
    <h1>示例</h1>
    <p>这里的示例直接取自 <code>grammar/README.md</code> 里最有代表性的几类使用方式：严格解析 DSL、宽松解析、Builder API 构造，以及 DSL / JSON 序列化往返。</p>

    <h2>从 DSL 读取并校验</h2>
    <pre><code>import {
  "caiklonghuan/MoonParse/grammar" @grammar,
}

fn load_grammar_from_dsl(dsl : String) -&gt; Unit {
  let grammar = match @grammar.parse_grammar(dsl) {
    @grammar.Success(g) =&gt; g
    @grammar.Error(err) =&gt; {
      println(
        "grammar parse error: " +
        err.message +
        " at " +
        err.location.line.to_string() +
        ":" +
        err.location.column.to_string(),
      )
      return
    }
  }

  let errors = @grammar.validate_grammar(grammar)
  if !errors.is_empty() {
    for err in errors {
      println(err.to_string())
    }
    return
  }

  println("grammar is valid")
}</code></pre>

    <h2>一个最小可工作的 DSL</h2>
    <pre><code>start list
extras [/[ \t\n\r]+/]
token rule ident: /[a-zA-Z_][a-zA-Z0-9_]*/
rule list: ident ("," ident)*</code></pre>

    <h2>编辑器场景：宽松解析</h2>
    <pre><code>let (partial_grammar, parse_errors) = @grammar.parse_grammar_lenient(dsl)
let validation_errors = @grammar.validate_grammar(partial_grammar)</code></pre>
    <p>这类入口适合“编辑中状态”：你可以一边收集语法层错误，一边继续对部分 <code>Grammar</code> 做语义校验，但不应把它直接当成最终可发布 grammar。</p>

    <h2>用 Builder API 生成标识符列表 grammar</h2>
    <pre><code>import {
  "caiklonghuan/MoonParse/grammar" @grammar,
}

fn make_identifier_list_grammar() -&gt; @grammar.Grammar {
  @grammar.Grammar::new()
    .set_start("list")
    .add_extra(@grammar.re("[ \\t\\n\\r]+"))
    .add_rule(
      @grammar.Rule::token(
        "ident",
        @grammar.re("[a-zA-Z_][a-zA-Z0-9_]*"),
      ),
    )
    .add_rule(
      @grammar.Rule::new(
        "list",
        @grammar.seq([
          @grammar.ref_("ident"),
          @grammar.repeat(
            @grammar.seq([
              @grammar.lit(","),
              @grammar.ref_("ident"),
            ]),
          ),
        ]),
      ),
    )
}</code></pre>

    <h2>回显为 DSL 与 JSON</h2>
    <pre><code>let text = @grammar.grammar_to_string(grammar)

let json = @grammar.grammar_to_json(grammar)
let restored = @grammar.grammar_from_json(json)</code></pre>
    <ul>
      <li><code>grammar_to_string</code> 适合调试打印、工具中展示语法，以及把 Builder API 构造结果重新输出为 DSL。</li>
      <li><code>grammar_to_json</code> / <code>grammar_from_json</code> 适合工具链传输、缓存中间产物和交换 Grammar 描述。</li>
    </ul>
  </article>
</template>