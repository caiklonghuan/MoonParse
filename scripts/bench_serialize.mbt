///|
// scripts/bench_serialize.mbt — parse table serialization timing + table size regression

///|
struct BenchSerializeOptions {
  grammars : Array[ScriptGrammar]
  runs : Int
} derive(Debug)

///|
fn bench_serialize_usage() -> String {
  (
    #|usage:
    #|  moon run scripts -- bench-serialize [--grammar json|expression|both] [--runs N]
    #|
    #|options:
    #|  --grammar  Grammar(s) to benchmark. Default: both.
    #|  --runs     Timing samples per scenario. Default: 10.
    #|
    #|output: key=value lines prefixed with "bench" or "size".
    #|  bench  name=<g>/serialize        — serialize_table()   → Bytes
    #|  bench  name=<g>/deserialize      — deserialize_table() ← Bytes
    #|  bench  name=<g>/table_to_json    — table_to_json()     → String
    #|  bench  name=<g>/table_from_json  — table_from_json()   ← String
    #|  size   name=<g>/table_size  json_bytes=… bin_bytes=… compression=…
    #|
    #|use --runs 1 to get a single-shot regression for table size tracking.
  )
}

///|
fn parse_bench_serialize_options(
  args : Array[String],
) -> Result[BenchSerializeOptions, String] {
  let mut grammars : Array[ScriptGrammar] = [Json, Expression]
  let mut runs = 10
  let mut i = 0
  while i < args.length() {
    match args[i] {
      "--grammar" => {
        if i + 1 >= args.length() {
          return Err(
            "missing value for --grammar\n\n" + bench_serialize_usage(),
          )
        }
        match parse_bench_grammar_selector(args[i + 1]) {
          Some(gs) => grammars = gs
          None =>
            return Err(
              "unknown grammar '\{args[i + 1]}'\n\n" + bench_serialize_usage(),
            )
        }
        i = i + 2
      }
      "--runs" => {
        if i + 1 >= args.length() {
          return Err("missing value for --runs\n\n" + bench_serialize_usage())
        }
        match parse_nonnegative_int(args[i + 1]) {
          Some(v) => runs = if v < 1 { 1 } else { v }
          None =>
            return Err(
              "invalid --runs value: '\{args[i + 1]}'\n\n" +
              bench_serialize_usage(),
            )
        }
        i = i + 2
      }
      "--help" | "-h" => {
        println(bench_serialize_usage())
        return Err("")
      }
      flag => return Err("unknown flag '\{flag}'\n\n" + bench_serialize_usage())
    }
  }
  Ok({ grammars, runs })
}

///|
fn run_grammar_bench_serialize(grammar : ScriptGrammar, runs : Int) -> Unit {
  let gname = grammar_name(grammar)
  println("=== bench-serialize [\{gname}, runs=\{runs}] ===")

  let table = compile_builtin_table(grammar)

  // Pre-compute outputs so the bench closures are stable
  let bin_bytes = @tablegen.serialize_table(table)
  let json_str = @tablegen.table_to_json(table)
  let bin_size = bin_bytes.length()
  let json_bytes = json_str.length()

  // 1. serialize_table timing
  let r_ser = bench_fn("\{gname}/serialize", runs, fn() {
    ignore(@tablegen.serialize_table(table))
  })
  print_bench_result(r_ser, "output_bytes=\{bin_size}")

  // 2. deserialize_table timing
  let r_deser = bench_fn("\{gname}/deserialize", runs, fn() {
    ignore(@tablegen.deserialize_table(bin_bytes))
  })
  print_bench_result(r_deser, "input_bytes=\{bin_size}")

  // 3. table_to_json timing
  let r_to_json = bench_fn("\{gname}/table_to_json", runs, fn() {
    ignore(@tablegen.table_to_json(table))
  })
  print_bench_result(r_to_json, "output_bytes=\{json_bytes}")

  // 4. table_from_json timing
  let r_from_json = bench_fn("\{gname}/table_from_json", runs, fn() {
    ignore(@tablegen.table_from_json(json_str))
  })
  print_bench_result(r_from_json, "input_bytes=\{json_bytes}")

  // 5. Size regression line: uncompressed (JSON) vs compressed (binary)
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
pub fn run_bench_serialize(args : Array[String]) -> Int {
  match parse_bench_serialize_options(args) {
    Err(msg) => {
      if msg.is_empty() {
        return 0
      }
      println("error: \{msg}")
      1
    }
    Ok(opts) => {
      for g in opts.grammars {
        run_grammar_bench_serialize(g, opts.runs)
      }
      0
    }
  }
}
