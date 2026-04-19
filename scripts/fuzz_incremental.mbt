///|
// scripts/fuzz_incremental.mbt — 单次编辑增量 fuzz runner

///|
struct FuzzIncrementalOptions {
  grammars : Array[ScriptGrammar]
  seed : Int
  count : Int
  depth : Int
  width : Int
} derive(Debug)

///|
fn parse_incremental_grammar_selector(text : String) -> Array[ScriptGrammar]? {
  match text {
    "json" => Some([Json])
    "expression" => Some([Expression])
    "both" => Some([Json, Expression])
    _ => None
  }
}

///|
fn fuzz_incremental_usage() -> String {
  (
    #|usage:
    #|  moon run scripts -- fuzz-incremental [--grammar json|expression|both] [--seed N] [--count N] [--depth N] [--width N]
    #|
    #|options:
    #|  --grammar  Grammar selection. Default: both.
    #|  --seed     RNG seed. Default: 78121.
    #|  --count    Guided base samples per grammar. Default: 1000.
    #|  --depth    Generator depth. Default: 3.
    #|  --width    Generator width. Default: 3.
  )
}

///|
fn parse_fuzz_incremental_options(
  args : Array[String],
) -> Result[FuzzIncrementalOptions, String] {
  let mut grammars = [Json, Expression]
  let mut seed = 78121
  let mut count = 1000
  let mut depth = 3
  let mut width = 3
  let mut i = 0
  while i < args.length() {
    match args[i] {
      "--grammar" => {
        if i + 1 >= args.length() {
          return Err(
            "missing value for --grammar\n\n" + fuzz_incremental_usage(),
          )
        }
        match parse_incremental_grammar_selector(args[i + 1]) {
          Some(value) => grammars = value
          None =>
            return Err(
              "unknown grammar selector '\{args[i + 1]}'\n\n" +
              fuzz_incremental_usage(),
            )
        }
        i = i + 2
      }
      "--seed" => {
        if i + 1 >= args.length() {
          return Err("missing value for --seed\n\n" + fuzz_incremental_usage())
        }
        match parse_nonnegative_int(args[i + 1]) {
          Some(value) => seed = value
          None =>
            return Err(
              "invalid non-negative integer for --seed: \{args[i + 1]}\n\n" +
              fuzz_incremental_usage(),
            )
        }
        i = i + 2
      }
      "--count" => {
        if i + 1 >= args.length() {
          return Err("missing value for --count\n\n" + fuzz_incremental_usage())
        }
        match parse_nonnegative_int(args[i + 1]) {
          Some(value) => count = value
          None =>
            return Err(
              "invalid non-negative integer for --count: \{args[i + 1]}\n\n" +
              fuzz_incremental_usage(),
            )
        }
        i = i + 2
      }
      "--depth" => {
        if i + 1 >= args.length() {
          return Err("missing value for --depth\n\n" + fuzz_incremental_usage())
        }
        match parse_nonnegative_int(args[i + 1]) {
          Some(value) => depth = value
          None =>
            return Err(
              "invalid non-negative integer for --depth: \{args[i + 1]}\n\n" +
              fuzz_incremental_usage(),
            )
        }
        i = i + 2
      }
      "--width" => {
        if i + 1 >= args.length() {
          return Err("missing value for --width\n\n" + fuzz_incremental_usage())
        }
        match parse_nonnegative_int(args[i + 1]) {
          Some(value) => width = value
          None =>
            return Err(
              "invalid non-negative integer for --width: \{args[i + 1]}\n\n" +
              fuzz_incremental_usage(),
            )
        }
        i = i + 2
      }
      other =>
        return Err("unknown option '\{other}'\n\n" + fuzz_incremental_usage())
    }
  }
  Ok({ grammars, seed, count, depth, width })
}

///|
fn run_fuzz_incremental(args : Array[String]) -> Int {
  if args.contains("--help") || args.contains("-h") {
    println(fuzz_incremental_usage())
    return 0
  }
  let options = match parse_fuzz_incremental_options(args) {
    Ok(options) => options
    Err(msg) => {
      println(msg)
      return 2
    }
  }

  let mut seed = options.seed
  for grammar in options.grammars {
    let table = compile_builtin_table(grammar)
    let mut clean_matches = 0
    let mut recovered_matches = 0
    let mut err_matches = 0
    let mut mutation_cases = 0

    for sample in 0..<options.count {
      let sample_seed = seed
      let (next, base) = generate_legal_input(
        grammar,
        seed,
        options.depth,
        options.width,
      )
      seed = next
      match
        validate_clean_sample(grammar, "fuzz-incremental base #\{sample}", base) {
        Some(msg) => {
          print_base_failure_context(
            "fuzz-incremental failed", grammar, sample, sample_seed, base, msg,
          )
          return 1
        }
        None => ()
      }

      for kind in all_mutation_kinds() {
        let mutation_seed = seed
        let (next, mutation) = mutate_input_for_grammar(
          grammar,
          seed,
          base,
          Some(kind),
        )
        seed = next
        let mutated = apply_mutation(base, mutation)
        if mutated == base {
          print_mutation_failure_context(
            "fuzz-incremental failed", grammar, sample, mutation_seed, base, mutation,
            mutated, "mutation did not change the input",
          )
          return 1
        }
        match
          check_incremental_mutation(
            grammar,
            table,
            base,
            mutation,
            "fuzz-incremental \{grammar_name(grammar)} #\{sample}/\{mutation.name}",
          ) {
          Ok(CleanMatch) => clean_matches = clean_matches + 1
          Ok(RecoveredMatch) => recovered_matches = recovered_matches + 1
          Ok(ErrMatch) => err_matches = err_matches + 1
          Err(msg) => {
            print_mutation_failure_context(
              "fuzz-incremental failed", grammar, sample, mutation_seed, base, mutation,
              mutated, msg,
            )
            return 1
          }
        }
        mutation_cases = mutation_cases + 1
      }
    }

    println(
      "fuzz-incremental \{grammar_name(grammar)} ok: seed=\{options.seed} samples=\{options.count} mutation_cases=\{mutation_cases} clean=\{clean_matches} recovered=\{recovered_matches} err=\{err_matches}",
    )
  }

  0
}
