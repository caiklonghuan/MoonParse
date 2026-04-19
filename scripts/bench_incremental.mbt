///|
// scripts/bench_incremental.mbt — incremental vs full parse timing benchmarks

///|
struct BenchIncrementalOptions {
  grammars : Array[ScriptGrammar]
  runs : Int
  size_bytes : Int
} derive(Debug)

///|
fn bench_incremental_usage() -> String {
  (
    #|usage:
    #|  moon run scripts -- bench-incremental [--grammar json|expression|both] [--runs N] [--size small|medium|large]
    #|
    #|options:
    #|  --grammar  Grammar(s) to benchmark. Default: both.
    #|  --runs     Timing samples per scenario. Default: 10.
    #|  --size     Base input size class. Default: medium.
    #|             small=256B  medium=10KB  large=100KB
    #|
    #|output: key=value lines, one per scenario, prefixed with "bench" or "ratio".
    #|  bench  name=<g>/incremental/<edit>  …
    #|  bench  name=<g>/full_parse/<edit>   …
    #|  ratio  name=<g>/ratio/<edit>        inc_pct_of_full=…%
    #|
    #|measured edit scenarios:
    #|  insert_begin   — insert one char at byte 0
    #|  insert_middle  — insert one char at byte len/2
    #|  insert_end     — insert one char at the end
    #|  replace_one    — replace one char at byte len/2
    #|  large_replace  — replace 20% of input (bytes [len/4, len/2))
  )
}

///|
fn parse_bench_incremental_options(
  args : Array[String],
) -> Result[BenchIncrementalOptions, String] {
  let mut grammars : Array[ScriptGrammar] = [Json, Expression]
  let mut runs = 10
  let mut size_bytes = 10240
  let mut i = 0
  while i < args.length() {
    match args[i] {
      "--grammar" => {
        if i + 1 >= args.length() {
          return Err(
            "missing value for --grammar\n\n" + bench_incremental_usage(),
          )
        }
        match parse_bench_grammar_selector(args[i + 1]) {
          Some(gs) => grammars = gs
          None =>
            return Err(
              "unknown grammar '\{args[i + 1]}'\n\n" + bench_incremental_usage(),
            )
        }
        i = i + 2
      }
      "--runs" => {
        if i + 1 >= args.length() {
          return Err("missing value for --runs\n\n" + bench_incremental_usage())
        }
        match parse_nonnegative_int(args[i + 1]) {
          Some(v) => runs = if v < 1 { 1 } else { v }
          None =>
            return Err(
              "invalid --runs value: '\{args[i + 1]}'\n\n" +
              bench_incremental_usage(),
            )
        }
        i = i + 2
      }
      "--size" => {
        if i + 1 >= args.length() {
          return Err("missing value for --size\n\n" + bench_incremental_usage())
        }
        match args[i + 1] {
          "small" => size_bytes = 256
          "medium" => size_bytes = 10240
          "large" => size_bytes = 102400
          s =>
            return Err(
              "unknown size '\{s}' (use small|medium|large)\n\n" +
              bench_incremental_usage(),
            )
        }
        i = i + 2
      }
      "--help" | "-h" => {
        println(bench_incremental_usage())
        return Err("")
      }
      flag =>
        return Err("unknown flag '\{flag}'\n\n" + bench_incremental_usage())
    }
  }
  Ok({ grammars, runs, size_bytes })
}

///|
// Run one edit scenario: bench incremental parse, bench full parse, print ratio.
fn run_one_incremental_scenario(
  gname : String,
  table : @tablegen.ParseTable,
  base_input : String,
  edit_label : String,
  edit_start : Int,
  edit_old_end : Int,
  replacement : String,
  runs : Int,
) -> Unit {
  // Parse base input once to get old_root
  let old_root = match @runtime.parse(table, base_input) {
    Ok(r) => r
    Err(e) => {
      println("skip \{gname}/\{edit_label}: old parse failed: \{e.message}")
      return
    }
  }
  let (new_input, edit) = make_edit_from_replacement(
    base_input, edit_start, edit_old_end, replacement,
  )
  let new_len = new_input.length()

  // Capture old_root and old_input for use in the closure
  let old_tree_arg : @runtime.OldTree = {
    root: old_root,
    old_input: base_input,
  }

  // Bench incremental parse
  let r_inc = bench_fn("\{gname}/incremental/\{edit_label}", runs, fn() {
    ignore(
      @runtime.parse_with_old_tree(
        table,
        new_input,
        Some(old_tree_arg),
        Some(edit),
      ),
    )
  })
  print_bench_result(r_inc, "input_bytes=\{new_len}")

  // Bench full re-parse of new input
  let r_full = bench_fn("\{gname}/full_parse/\{edit_label}", runs, fn() {
    ignore(@runtime.parse(table, new_input))
  })
  print_bench_result(r_full, "input_bytes=\{new_len}")

  // Print ratio: incremental time as % of full re-parse
  let pct = if r_full.mean_us < 0.001 {
    0
  } else {
    (r_inc.mean_us / r_full.mean_us * 100.0).to_int()
  }
  println("ratio  name=\{gname}/ratio/\{edit_label}  inc_pct_of_full=\{pct}%")
}

///|
fn run_grammar_bench_incremental(
  grammar : ScriptGrammar,
  runs : Int,
  size_bytes : Int,
) -> Unit {
  let gname = grammar_name(grammar)
  println(
    "=== bench-incremental [\{gname}, runs=\{runs}, size=\{size_bytes}B] ===",
  )

  let table = compile_builtin_table(grammar)
  let base = bench_input_for(grammar, size_bytes)
  let len = base.length()

  // Edit scenario definitions: (label, start, old_end, replacement)
  let mid = len / 2
  let q1 = len / 4
  let q2 = len / 2

  // insert_begin: insert one "x" at byte 0
  run_one_incremental_scenario(
    gname, table, base, "insert_begin", 0, 0, "x", runs,
  )

  // insert_middle: insert one "x" at byte len/2
  run_one_incremental_scenario(
    gname, table, base, "insert_middle", mid, mid, "x", runs,
  )

  // insert_end: insert one "x" at byte len (append)
  run_one_incremental_scenario(
    gname, table, base, "insert_end", len, len, "x", runs,
  )

  // replace_one: replace one char at byte len/2
  let ro_end = if mid + 1 <= len { mid + 1 } else { len }
  run_one_incremental_scenario(
    gname, table, base, "replace_one", mid, ro_end, "x", runs,
  )

  // large_replace: replace bytes [len/4, len/2) with a single "x"
  // This is a large destructive edit; incremental may not be faster here.
  run_one_incremental_scenario(
    gname, table, base, "large_replace", q1, q2, "x", runs,
  )
}

///|
pub fn run_bench_incremental(args : Array[String]) -> Int {
  match parse_bench_incremental_options(args) {
    Err(msg) => {
      if msg.is_empty() {
        return 0
      }
      println("error: \{msg}")
      1
    }
    Ok(opts) => {
      for g in opts.grammars {
        run_grammar_bench_incremental(g, opts.runs, opts.size_bytes)
      }
      0
    }
  }
}
