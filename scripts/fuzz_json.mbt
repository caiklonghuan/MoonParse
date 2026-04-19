///|
// scripts/fuzz_json.mbt — JSON fuzz runner

///|
struct FuzzJsonOptions {
  seed : Int
  count : Int
  depth : Int
  width : Int
  guided_only : Bool
} derive(Debug)

///|
fn fuzz_json_usage() -> String {
  (
    #|usage:
    #|  moon run scripts -- fuzz-json [--seed N] [--count N] [--depth N] [--width N] [--guided-only]
    #|
    #|options:
    #|  --seed         RNG seed. Default: 61093.
    #|  --count        Number of guided base samples. Default: 1000.
    #|  --depth        Generator depth. Default: 3.
    #|  --width        Generator width. Default: 3.
    #|  --guided-only  Skip mutation fuzz and only validate clean guided JSON.
  )
}

///|
fn parse_fuzz_json_options(
  args : Array[String],
) -> Result[FuzzJsonOptions, String] {
  let mut seed = 61093
  let mut count = 1000
  let mut depth = 3
  let mut width = 3
  let mut guided_only = false
  let mut i = 0
  while i < args.length() {
    match args[i] {
      "--seed" => {
        if i + 1 >= args.length() {
          return Err("missing value for --seed\n\n" + fuzz_json_usage())
        }
        match parse_nonnegative_int(args[i + 1]) {
          Some(value) => seed = value
          None =>
            return Err(
              "invalid non-negative integer for --seed: \{args[i + 1]}\n\n" +
              fuzz_json_usage(),
            )
        }
        i = i + 2
      }
      "--count" => {
        if i + 1 >= args.length() {
          return Err("missing value for --count\n\n" + fuzz_json_usage())
        }
        match parse_nonnegative_int(args[i + 1]) {
          Some(value) => count = value
          None =>
            return Err(
              "invalid non-negative integer for --count: \{args[i + 1]}\n\n" +
              fuzz_json_usage(),
            )
        }
        i = i + 2
      }
      "--depth" => {
        if i + 1 >= args.length() {
          return Err("missing value for --depth\n\n" + fuzz_json_usage())
        }
        match parse_nonnegative_int(args[i + 1]) {
          Some(value) => depth = value
          None =>
            return Err(
              "invalid non-negative integer for --depth: \{args[i + 1]}\n\n" +
              fuzz_json_usage(),
            )
        }
        i = i + 2
      }
      "--width" => {
        if i + 1 >= args.length() {
          return Err("missing value for --width\n\n" + fuzz_json_usage())
        }
        match parse_nonnegative_int(args[i + 1]) {
          Some(value) => width = value
          None =>
            return Err(
              "invalid non-negative integer for --width: \{args[i + 1]}\n\n" +
              fuzz_json_usage(),
            )
        }
        i = i + 2
      }
      "--guided-only" => {
        guided_only = true
        i = i + 1
      }
      other => return Err("unknown option '\{other}'\n\n" + fuzz_json_usage())
    }
  }
  Ok({ seed, count, depth, width, guided_only })
}

///|
fn run_fuzz_json(args : Array[String]) -> Int {
  if args.contains("--help") || args.contains("-h") {
    println(fuzz_json_usage())
    return 0
  }
  let options = match parse_fuzz_json_options(args) {
    Ok(options) => options
    Err(msg) => {
      println(msg)
      return 2
    }
  }

  let mut seed = options.seed
  let mut clean_samples = 0
  let mut mutation_cases = 0
  let mut recovered_mutations = 0
  let mut err_mutations = 0

  for sample in 0..<options.count {
    let sample_seed = seed
    let (next, base) = json_guided_value(seed, options.depth, options.width)
    seed = next
    match validate_clean_sample(Json, "fuzz-json base #\{sample}", base) {
      Some(msg) => {
        print_base_failure_context(
          "fuzz-json failed",
          Json,
          sample,
          sample_seed,
          base,
          msg,
        )
        return 1
      }
      None => clean_samples = clean_samples + 1
    }

    if !options.guided_only {
      for kind in all_mutation_kinds() {
        let mutation_seed = seed
        let (next, mutation) = json_mutation(seed, base, Some(kind))
        seed = next
        let mutated = apply_mutation(base, mutation)
        if mutated == base {
          print_mutation_failure_context(
            "fuzz-json failed",
            Json,
            sample,
            mutation_seed,
            base,
            mutation,
            mutated,
            "mutation did not change the input",
          )
          return 1
        }
        match
          check_any_input_stable(
            Json,
            "fuzz-json mutation #\{sample}/\{mutation.name}",
            mutated,
          ) {
          Ok(CleanParse) => ()
          Ok(RecoveredParse) => recovered_mutations = recovered_mutations + 1
          Ok(ParseReturnedErr) => err_mutations = err_mutations + 1
          Err(msg) => {
            print_mutation_failure_context(
              "fuzz-json failed",
              Json,
              sample,
              mutation_seed,
              base,
              mutation,
              mutated,
              msg,
            )
            return 1
          }
        }
        mutation_cases = mutation_cases + 1
      }
    }
  }

  println(
    "fuzz-json ok: seed=\{options.seed} samples=\{clean_samples} mutation_cases=\{mutation_cases} recovered=\{recovered_mutations} err=\{err_mutations}",
  )
  0
}
