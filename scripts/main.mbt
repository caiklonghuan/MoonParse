///|
// scripts/main.mbt — fuzz 脚本入口

///|
fn global_usage() -> String {
  (
    #|usage:
    #|  moon run scripts -- fuzz-json [--seed N] [--count N] [--depth N] [--width N] [--guided-only]
    #|  moon run scripts -- mutate-input --grammar json|expression [--input TEXT] [--seed N] [--kind KIND] [--depth N] [--width N]
    #|  moon run scripts -- fuzz-incremental [--grammar json|expression|both] [--seed N] [--count N] [--depth N] [--width N]
    #|  moon run scripts -- bench-parse [--grammar json|expression|both] [--runs N]
    #|  moon run scripts -- bench-incremental [--grammar json|expression|both] [--runs N] [--size small|medium|large]
    #|  moon run scripts -- bench-serialize [--grammar json|expression|both] [--runs N]
    #|
    #|subcommands:
    #|  fuzz-json          Run deterministic JSON guided fuzz and optional mutation fuzz.
    #|  mutate-input       Generate or mutate one reproducible input and print edit details.
    #|  fuzz-incremental   Run deterministic single-edit incremental-vs-full fuzz.
    #|  bench-parse        Benchmark parse table generation and full/error parse timing + table size.
    #|  bench-incremental  Benchmark incremental vs full parse timing for various edit scenarios.
    #|  bench-serialize    Benchmark parse table serialize/deserialize timing and byte counts.
    #|
    #|examples:
    #|  moon run scripts -- fuzz-json --count 1000 --seed 61093
    #|  moon run scripts -- mutate-input --grammar json --seed 42 --kind replace-token
    #|  moon run scripts -- fuzz-incremental --grammar both --count 200 --seed 78121
    #|  moon run scripts -- bench-parse --grammar both --runs 10
    #|  moon run scripts -- bench-incremental --grammar json --size medium --runs 10
    #|  moon run scripts -- bench-serialize --grammar both --runs 5
  )
}

///|
fn help_for(subcommand : String?) -> String {
  match subcommand {
    None => global_usage()
    Some("fuzz-json") => fuzz_json_usage()
    Some("mutate-input") => mutate_input_usage()
    Some("fuzz-incremental") => fuzz_incremental_usage()
    Some("bench-parse") => bench_parse_usage()
    Some("bench-incremental") => bench_incremental_usage()
    Some("bench-serialize") => bench_serialize_usage()
    Some(other) => "unknown subcommand '\{other}'\n\n" + global_usage()
  }
}

///|
fn main {
  let all_args = @env.args()
  let argv = if all_args.is_empty() { [] } else { all_args[1:].to_array() }

  let code = if argv.is_empty() {
    println(global_usage())
    0
  } else {
    match argv[0] {
      "help" => {
        let sub = if argv.length() >= 2 { Some(argv[1]) } else { None }
        println(help_for(sub))
        0
      }
      "--help" => {
        println(global_usage())
        0
      }
      "-h" => {
        println(global_usage())
        0
      }
      "fuzz-json" => run_fuzz_json(argv[1:].to_array())
      "mutate-input" => run_mutate_input(argv[1:].to_array())
      "fuzz-incremental" => run_fuzz_incremental(argv[1:].to_array())
      "bench-parse" => run_bench_parse(argv[1:].to_array())
      "bench-incremental" => run_bench_incremental(argv[1:].to_array())
      "bench-serialize" => run_bench_serialize(argv[1:].to_array())
      other => {
        println("unknown subcommand '\{other}'")
        println("")
        println(global_usage())
        2
      }
    }
  }

  if code != 0 {
    script_exit(code)
  }
}
