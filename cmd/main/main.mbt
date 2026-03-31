///|
/// 将冲突严重级别转为可读前缀
fn severity_label(s : @tablegen.ConflictSeverity) -> String {
  match s {
    @tablegen.ConflictSeverity::Warn(_) => "[warn]"
    @tablegen.ConflictSeverity::Ambiguous(_) => "[ambiguous]"
    @tablegen.ConflictSeverity::DynamicConflict(_) => "[dynamic]"
  }
}

///|
/// 将冲突报告打印到 stderr（用 println 近似，MoonBit WASM 目标暂无独立 stderr）
fn print_conflicts(reports : Array[@tablegen.ConflictReport]) -> Unit {
  if reports.length() == 0 {
    return
  }
  println("── 冲突报告（\{reports.length()} 条）────────────────────")
  for r in reports {
    let label = severity_label(r.severity)
    let msg = match r.severity {
      @tablegen.ConflictSeverity::Warn(m) => m
      @tablegen.ConflictSeverity::Ambiguous(m) => m
      @tablegen.ConflictSeverity::DynamicConflict(id) =>
        "dynamic prec id=\{id} in state \{r.state} on terminal \{r.terminal}"
    }
    println("  \{label} \{msg}")
    println(
      "    state=\{r.state}  terminal=\{r.terminal}  actions=\{r.actions.length()}",
    )
  }
  println("")
}

///|
/// Entry point.  Run with `moon run cmd/main` from the project root.
///
/// 流程：
///   1. 解析内嵌示例 DSL（实际 CLI 可改为读 stdin/文件）
///   2. validate_grammar 校验（警告，不阻断）
///   3. generate_parse_table 生成 LALR(1) 解析表
///   4. 冲突报告打印到 stdout
///   5. table_to_json 序列化后打印到 stdout
fn main {
  let dsl =
    #|start expr
    #|precedence left plus, minus
    #|precedence left star, slash
    #|rule expr: expr plus term | expr minus term | term
    #|rule term: term star factor | term slash factor | factor
    #|rule factor: /\d+/ | "(" expr ")"
    #|rule plus:  "+"
    #|rule minus: "-"
    #|rule star:  "*"
    #|rule slash: "/"

  // ── 1. 解析 DSL ──────────────────────────────────────────────────────────
  let grammar = match @grammar.parse_grammar(dsl) {
    Success(g) => g
    Error(err) => {
      println(
        "解析失败: \{err.message} at \{err.location.line}:\{err.location.column}",
      )
      return
    }
  }

  // ── 2. 语义校验（警告性，不阻断）────────────────────────────────────────
  let errors = @grammar.validate_grammar(grammar)
  if errors.length() > 0 {
    println("── 校验警告（\{errors.length()} 条）────────────────────")
    for e in errors {
      println("  [warn] \{e.to_string()}")
    }
    println("")
  }

  // ── 3. 生成解析表 ────────────────────────────────────────────────────────
  let (table, reports) = match @tablegen.generate_parse_table(grammar) {
    Ok(r) => r
    Err(msg) => {
      println("生成解析表失败: \{msg}")
      return
    }
  }

  // ── 4. 冲突报告 ──────────────────────────────────────────────────────────
  print_conflicts(reports)

  // ── 5. 输出 JSON 解析表 ──────────────────────────────────────────────────
  println("── 解析表 JSON ─────────────────────────────────────────")
  println(@tablegen.table_to_json(table))
}
