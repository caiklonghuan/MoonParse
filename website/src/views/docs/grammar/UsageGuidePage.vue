<template>
  <article>
    <h1>使用指南</h1>
    <p>对绝大多数调用方，推荐把 <code>grammar/</code> 当成一个固定流程来用：先得到 <code>Grammar</code>，再做语义校验，最后把它交给下游 <code>tablegen/</code>。本页按 README 的实际使用顺序整理常见入口。</p>

    <h2>入口怎么选</h2>
    <table>
      <thead>
        <tr>
          <th>入口</th>
          <th>适合场景</th>
          <th>说明</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td><code>parse_grammar</code></td>
          <td>命令行编译、CI、正式构建</td>
          <td>遇到首个语法错误就失败，适合拿最终结果。</td>
        </tr>
        <tr>
          <td><code>parse_grammar_lenient</code></td>
          <td>编辑器、IDE、在线 grammar 编辑</td>
          <td>尽量恢复后继续解析，便于持续给用户反馈。</td>
        </tr>
        <tr>
          <td><code>Grammar::new()</code> + Builder API</td>
          <td>MoonBit 内按条件拼装规则、批量生成语法</td>
          <td>避免字符串拼接，直接构造类型化 grammar。</td>
        </tr>
        <tr>
          <td><code>grammar_to_json</code> / <code>grammar_from_json</code></td>
          <td>缓存、跨进程传输、工具链中转</td>
          <td>适合把 grammar 当结构化协议使用。</td>
        </tr>
      </tbody>
    </table>

    <h2>基于 DSL 文本使用</h2>
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

    <p>一个最小可工作的 DSL 例子如下：</p>
    <pre><code>start list
extras [/[ \t\n\r]+/]
token rule ident: /[a-zA-Z_][a-zA-Z0-9_]*/
rule list: ident ("," ident)*</code></pre>

    <h2>需要错误恢复时</h2>
    <p>如果场景是编辑器或在线语法编辑器，不希望在遇到第一处 DSL 错误时就立刻中止，应使用宽松解析：</p>
    <pre><code>let (partial_grammar, parse_errors) = @grammar.parse_grammar_lenient(dsl)
let validation_errors = @grammar.validate_grammar(partial_grammar)</code></pre>
    <ul>
      <li><code>parse_grammar_lenient</code> 会尽量跳到下一条顶层声明继续分析。</li>
      <li>它会返回“尽力恢复后的部分 <code>Grammar</code>”以及全部已收集的 <code>ParseError</code>。</li>
      <li>推荐把语法层错误和语义校验错误分开展示给用户。</li>
      <li>这种结果适合编辑中状态，不应直接视为可发布 grammar。</li>
    </ul>

    <h2>以 Builder API 编程构造 Grammar</h2>
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
}

let grammar = make_identifier_list_grammar()
let errors = @grammar.validate_grammar(grammar)</code></pre>

    <h2>如何与下游模块衔接</h2>
    <pre><code>let grammar = ...
let errors = @grammar.validate_grammar(grammar)
if errors.is_empty() {
  // 交由 tablegen 继续生成 ParseTable
}</code></pre>
    <p>只有 <code>grammar/</code> 这里已经通过解析与校验，后续 <code>tablegen/</code> 和 <code>runtime/</code> 的行为才更稳定、更容易解释。</p>
  </article>
</template>