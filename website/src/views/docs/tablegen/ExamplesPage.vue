<template>
  <article>
    <h1>示例</h1>
    <p>这里直接对齐 <code>tablegen/README.md</code> 里的几类典型用法：一键建表、Grammar 级预校验、冲突报告处理、分阶段观察流水线，以及序列化往返。</p>

    <h2>一键生成 ParseTable</h2>
    <pre><code>import {
  "caiklonghuan/MoonParse/grammar" @grammar,
  "caiklonghuan/MoonParse/tablegen" @tablegen,
}

fn compile_list_grammar(dsl : String) -&gt; Unit {
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

  let (table, reports) = match @tablegen.generate_parse_table(grammar) {
    Ok(result) =&gt; result
    Err(msg) =&gt; {
      println("tablegen error: " + msg)
      return
    }
  }

  println("states = " + table.states.to_string())
  println("productions = " + table.productions.length().to_string())
  println("conflict reports = " + reports.length().to_string())
}</code></pre>

    <p>README 中对应的最小 DSL 例子如下：</p>
    <pre><code>start list
extras [/[ \t\n\r]+/]
rule list: item ("," item)*
rule item: /[A-Za-z_][A-Za-z0-9_]*/</code></pre>

    <h2>先做 Grammar 级校验再建表</h2>
    <pre><code>import {
  "caiklonghuan/MoonParse/grammar" @grammar,
  "caiklonghuan/MoonParse/tablegen" @tablegen,
}

fn compile_with_validation(grammar : @grammar.Grammar) -&gt; Unit {
  let validation = @grammar.validate_grammar(grammar)
  let fatal_errors : Array[@grammar.ValidationError] = []
  let warnings : Array[@grammar.ValidationError] = []

  for err in validation {
    match err.kind {
      @grammar.ValidationErrorKind::DirectLeftRecursion(_)
      | @grammar.ValidationErrorKind::IndirectLeftRecursion(_) =&gt;
        warnings.push(err)
      _ =&gt; fatal_errors.push(err)
    }
  }

  if !fatal_errors.is_empty() {
    for err in fatal_errors {
      println(err.to_string())
    }
    return
  }

  let (_table, reports) = match @tablegen.generate_parse_table(grammar) {
    Ok(result) =&gt; result
    Err(msg) =&gt; {
      println("tablegen error: " + msg)
      return
    }
  }

  println("warnings = " + warnings.length().to_string())
  println("conflicts = " + reports.length().to_string())
}</code></pre>

    <h2>按严重级别处理冲突报告</h2>
    <pre><code>import {
  "caiklonghuan/MoonParse/tablegen" @tablegen,
}

fn print_conflict_reports(reports : Array[@tablegen.ConflictReport]) -&gt; Unit {
  for report in reports {
    let level = match report.severity {
      @tablegen.ConflictSeverity::Warn(_) =&gt; "warn"
      @tablegen.ConflictSeverity::Ambiguous(_) =&gt; "ambiguous"
      @tablegen.ConflictSeverity::DynamicConflict(_) =&gt; "dynamic"
      @tablegen.ConflictSeverity::Declared(_) =&gt; "declared"
    }
    println(
      level +
      " conflict at state=" +
      report.state.to_string() +
      " terminal=" +
      report.terminal.to_string(),
    )
  }
}</code></pre>

    <h2>分阶段观察编译流水线</h2>
    <pre><code>let aug = @tablegen.augment_grammar(grammar)
let item_sets = @tablegen.build_item_sets(aug)
let goto_map = @tablegen.build_goto_map(aug, item_sets)
let raw_table = @tablegen.build_lalr_table(aug, item_sets, goto_map)
let (resolved_table, reports) = @tablegen.resolve_conflicts(raw_table, aug)
let dfa = @tablegen.build_lexer_dfa(aug, resolved_table)</code></pre>
    <p>这类阶段性 API 适合调试和研究。如果目标是交付最终可运行的 <code>ParseTable</code>，默认仍应优先用 <code>generate_parse_table()</code>。</p>

    <h2>JSON / 二进制往返</h2>
    <pre><code>let json = @tablegen.table_to_json(table)
let bytes = @tablegen.serialize_table(table)

let from_json = match @tablegen.table_from_json(json) {
  Ok(t) =&gt; t
  Err(msg) =&gt; {
    println("table_from_json failed: " + msg)
    return
  }
}

let from_bytes = match @tablegen.deserialize_table(bytes) {
  Ok(t) =&gt; t
  Err(msg) =&gt; {
    println("deserialize_table failed: " + msg)
    return
  }
}</code></pre>
  </article>
</template>