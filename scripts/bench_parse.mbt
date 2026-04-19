///|
// scripts/bench_parse.mbt — parse table generation + full/error parse benchmarks

///|
struct BenchParseOptions {
  grammars : Array[ScriptGrammar]
  runs : Int
} derive(Debug)

///|
fn bench_parse_usage() -> String {
  (
    #|usage:
    #|  moon run scripts -- bench-parse [--grammar json|expression|both] [--runs N]
    #|
    #|options:
    #|  --grammar  Grammar(s) to benchmark. Default: both.
    #|  --runs     Timing samples per scenario. Default: 10.
    #|
    #|output: key=value lines, one per scenario, prefixed with "bench" or "size".
    #|  bench  name=<grammar>/<scenario>  mean=…  median=…  p95=…  min=…  max=…  runs=…
    #|  size   name=<grammar>/table_size  json_bytes=…  bin_bytes=…  compression=…
    #|
    #|measured scenarios per grammar:
    #|  <g>/table_gen          — parse + generate_parse_table from DSL
    #|  <g>/full_parse/small   — parse ~256 B input
    #|  <g>/full_parse/medium  — parse ~10 KB input
    #|  <g>/full_parse/large   — parse ~100 KB input
    #|  <g>/error_parse/…      — parse truncated / prefix-garbage / mid-garbage input
    #|  <g>/table_size         — table JSON bytes vs binary bytes (compression ratio)
  )
}

///|
fn parse_bench_parse_options(
  args : Array[String],
) -> Result[BenchParseOptions, String] {
  let mut grammars : Array[ScriptGrammar] = [Json, Expression]
  let mut runs = 10
  let mut i = 0
  while i < args.length() {
    match args[i] {
      "--grammar" => {
        if i + 1 >= args.length() {
          return Err("missing value for --grammar\n\n" + bench_parse_usage())
        }
        match parse_bench_grammar_selector(args[i + 1]) {
          Some(gs) => grammars = gs
          None =>
            return Err(
              "unknown grammar '\{args[i + 1]}'\n\n" + bench_parse_usage(),
            )
        }
        i = i + 2
      }
      "--runs" => {
        if i + 1 >= args.length() {
          return Err("missing value for --runs\n\n" + bench_parse_usage())
        }
        match parse_nonnegative_int(args[i + 1]) {
          Some(v) => runs = if v < 1 { 1 } else { v }
          None =>
            return Err(
              "invalid --runs value: '\{args[i + 1]}'\n\n" + bench_parse_usage(),
            )
        }
        i = i + 2
      }
      "--help" | "-h" => {
        println(bench_parse_usage())
        return Err("")
      }
      flag => return Err("unknown flag '\{flag}'\n\n" + bench_parse_usage())
    }
  }
  Ok({ grammars, runs })
}

///|
fn run_grammar_bench_parse(grammar : ScriptGrammar, runs : Int) -> Unit {
  let gname = grammar_name(grammar)
  println("=== bench-parse [\{gname}, runs=\{runs}] ===")

  // 1. Parse table generation time
  let dsl = builtin_grammar_dsl(grammar)
  let r_tablegen = bench_fn("\{gname}/table_gen", runs, fn() {
    let parsed_g = match @grammar.parse_grammar(dsl) {
      @grammar.Success(p) => p
      @grammar.Error(_) => abort("parse_grammar failed in bench")
    }
    match @tablegen.generate_parse_table(parsed_g) {
      Ok(_) => ()
      Err(_) => abort("generate_parse_table failed in bench")
    }
  })
  print_bench_result(r_tablegen, "")

  // Pre-compile table once for parse benchmarks
  let table = compile_builtin_table(grammar)

  // 2. Full parse timing across size classes
  let size_classes : Array[(String, Int)] = [
    ("small", 256),
    ("medium", 10240),
    ("large", 102400),
  ]
  for sc in size_classes {
    let (label, sz) = sc
    let input = bench_input_for(grammar, sz)
    let actual = input.length()
    let r = bench_fn("\{gname}/full_parse/\{label}", runs, fn() {
      ignore(@runtime.parse(table, input))
    })
    print_bench_result(r, "input_bytes=\{actual}")
  }

  // 3. Error input parse timing
  let error_cases : Array[(String, String)] = match grammar {
    Json =>
      [
        ("truncated", "{\"a\": [1, 2,"),
        ("prefix_garbage", "!!! {\"a\": 1}"),
        ("middle_garbage", "{\"a\": !, \"b\": 2}"),
      ]
    Expression =>
      [
        ("truncated", "n + n *"),
        ("prefix_garbage", "!!! n + n"),
        ("middle_garbage", "n + ! + n"),
      ]
  }
  for ec in error_cases {
    let (label, input) = ec
    let r = bench_fn("\{gname}/error_parse/\{label}", runs, fn() {
      ignore(@runtime.parse(table, input))
    })
    print_bench_result(r, "input_bytes=\{input.length()}")
  }

  // 4. Table size metrics (JSON bytes vs binary bytes)
  let json_str = @tablegen.table_to_json(table)
  let bin_bytes = @tablegen.serialize_table(table)
  let json_bytes = json_str.length()
  let bin_size = bin_bytes.length()
  let ratio_t = if bin_size == 0 {
    0
  } else {
    (json_bytes.to_double() / bin_size.to_double() * 10.0).to_int()
  }
  println(
    "size   name=\{gname}/table_size  json_bytes=\{json_bytes}  bin_bytes=\{bin_size}  compression=\{ratio_t / 10}.\{ratio_t % 10}x",
  )
}

///|
pub fn run_bench_parse(args : Array[String]) -> Int {
  match parse_bench_parse_options(args) {
    Err(msg) => {
      if msg.is_empty() {
        return 0
      }
      println("error: \{msg}")
      1
    }
    Ok(opts) => {
      for g in opts.grammars {
        run_grammar_bench_parse(g, opts.runs)
      }
      0
    }
  }
}
