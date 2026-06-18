///|
enum LexerBenchGrammar {
  JsonLexer
  ExpressionLexer
  MoonBitLexer
}

///|
fn lexer_bench_usage() -> String {
  (
    #|usage:
    #|  moon run scripts -- bench-lexer [--grammar json|expression|moonbit|all] [--runs N]
    #|
    #|Runs at least 30 warmed samples and reports median latency together with
    #|input bytes, matched DFA bytes and cache hits. The raw lexer benchmark
    #|enables every DFA terminal so parser-state changes do not affect scanning.
  )
}

///|
fn lexer_bench_name(grammar : LexerBenchGrammar) -> String {
  match grammar {
    JsonLexer => "json"
    ExpressionLexer => "expression"
    MoonBitLexer => "moonbit"
  }
}

///|
fn lexer_bench_dsl(grammar : LexerBenchGrammar) -> String {
  match grammar {
    JsonLexer => @grammars.json_grammar
    ExpressionLexer => @grammars.expression_grammar
    MoonBitLexer => @grammars.moonbit_grammar
  }
}

///|
fn lexer_bench_input(grammar : LexerBenchGrammar) -> String {
  match grammar {
    JsonLexer => json_of_target_size(4096)
    ExpressionLexer => expr_of_target_size(4096)
    MoonBitLexer => {
      let unit = "pub fn add(a : Int, b : Int) -> Int { a + b }\n" +
        "test \"lexer\" { inspect(add(1, 2), content=\"3\") }\n"
      let builder = StringBuilder::new()
      let mut written = 0
      while written < 4096 {
        builder.write_string(unit)
        written = written + unit.length()
      }
      builder.to_string()
    }
  }
}

///|
fn lexer_bench_table(grammar : LexerBenchGrammar) -> @tablegen.ParseTable {
  let parsed = match @grammar.parse_grammar(lexer_bench_dsl(grammar)) {
    @grammar.Success(value) => value
    @grammar.Error(error) => abort(error.message)
  }
  let table = match @tablegen.generate_parse_table(parsed) {
    Ok((value, _)) => value
    Err(error) => abort(error)
  }
  let all : Array[Int] = []
  for terminal, _ in table.terminal_patterns {
    all.push(terminal)
  }
  table.lexer_dfa.valid_tokens[0] = all
  table
}

///|
fn scan_lexer_input(
  table : @tablegen.ParseTable,
  input : String,
  collect_stats : Bool,
) -> @runtime.LexerStats {
  let lexer = @runtime.LexerEngine::new(table.lexer_dfa)
  lexer.enable_stats(collect_stats)
  let mut position = 0
  while position < input.length() {
    let (_, next) = lexer.next_token(input, position, table, 0)
    let safe_next = if next > position { next } else { position + 1 }
    position = safe_next
  }
  lexer.stats()
}

///|
fn run_one_lexer_bench(grammar : LexerBenchGrammar, runs : Int) -> Unit {
  let table = lexer_bench_table(grammar)
  let input = lexer_bench_input(grammar)
  let stats = scan_lexer_input(table, input, true)
  let result = bench_fn("\{lexer_bench_name(grammar)}/lexer", runs, fn() {
    ignore(scan_lexer_input(table, input, false))
  })
  print_bench_result(
    result,
    "input_bytes=\{input.length()} scanned_characters=\{stats.scanned_characters} dfa_transitions=\{stats.dfa_transitions} cache_hits=\{stats.cache_hits}",
  )
}

///|
pub fn run_bench_lexer(args : Array[String]) -> Int {
  let mut grammars = [JsonLexer, ExpressionLexer, MoonBitLexer]
  let mut runs = 30
  let mut index = 0
  while index < args.length() {
    match args[index] {
      "--grammar" => {
        if index + 1 >= args.length() {
          println(lexer_bench_usage())
          return 2
        }
        grammars = match args[index + 1] {
          "json" => [JsonLexer]
          "expression" => [ExpressionLexer]
          "moonbit" => [MoonBitLexer]
          "all" => [JsonLexer, ExpressionLexer, MoonBitLexer]
          _ => {
            println(lexer_bench_usage())
            return 2
          }
        }
        index = index + 2
      }
      "--runs" => {
        if index + 1 >= args.length() {
          println(lexer_bench_usage())
          return 2
        }
        match parse_nonnegative_int(args[index + 1]) {
          Some(value) => runs = value
          None => {
            println("invalid --runs value")
            return 2
          }
        }
        if runs < 30 {
          println("--runs must be at least 30")
          return 2
        }
        index = index + 2
      }
      "--help" | "-h" => {
        println(lexer_bench_usage())
        return 0
      }
      _ => {
        println(lexer_bench_usage())
        return 2
      }
    }
  }
  for grammar in grammars {
    run_one_lexer_bench(grammar, runs)
  }
  0
}
