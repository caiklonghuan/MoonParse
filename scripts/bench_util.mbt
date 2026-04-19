///|
// scripts/bench_util.mbt — micro-benchmark infrastructure shared by bench_* files

///|
struct BenchResult {
  name : String
  mean_us : Double
  median_us : Double
  p95_us : Double
  min_us : Double
  max_us : Double
  runs : Int
}

///|
// Calibrate: find how many calls fill ~10 ms, so each sample is stable.
fn bench_calibrate(f : () -> Unit) -> Int {
  f() // warmup
  let ts = @bench.monotonic_clock_start()
  f()
  let one_us = @bench.monotonic_clock_end(ts)
  if one_us >= 10000.0 {
    1
  } else {
    let divisor = if one_us < 0.001 { 0.001 } else { one_us }
    let n = (10000.0 / divisor).ceil().to_int()
    if n > 10000 {
      10000
    } else if n < 1 {
      1
    } else {
      n
    }
  }
}

///|
// Collect `runs` timing samples (µs per call) using `batch` calls per sample.
fn bench_collect(runs : Int, batch : Int, f : () -> Unit) -> Array[Double] {
  Array::makei(runs, _ => {
    let ts = @bench.monotonic_clock_start()
    for _ in 0..<batch {
      f()
    }
    @bench.monotonic_clock_end(ts) / batch.to_double()
  })
}

///|
// Compute summary statistics from timing samples (sorts in place).
fn bench_compute_stats(name : String, samples : Array[Double]) -> BenchResult {
  samples.sort()
  let n = samples.length()
  if n == 0 {
    return {
      name,
      mean_us: 0.0,
      median_us: 0.0,
      p95_us: 0.0,
      min_us: 0.0,
      max_us: 0.0,
      runs: 0,
    }
  }
  let mut sum = 0.0
  for s in samples {
    sum = sum + s
  }
  let mean_us = sum / n.to_double()
  let median_us = samples[n / 2]
  let min_us = samples[0]
  let max_us = samples[n - 1]
  let p95_raw = (n.to_double() * 0.95).ceil().to_int() - 1
  let p95_idx = if p95_raw < 0 {
    0
  } else if p95_raw >= n {
    n - 1
  } else {
    p95_raw
  }
  let p95_us = samples[p95_idx]
  { name, mean_us, median_us, p95_us, min_us, max_us, runs: n }
}

///|
// Run a benchmark: auto-calibrate batch size, collect samples, return stats.
fn bench_fn(name : String, runs : Int, f : () -> Unit) -> BenchResult {
  let batch = bench_calibrate(f)
  let samples = bench_collect(runs, batch, f)
  bench_compute_stats(name, samples)
}

///|
// Format a microsecond value as a human-readable time string.
fn fmt_us(us : Double) -> String {
  if us < 1000.0 {
    let t = (us * 10.0).to_int()
    "\{t / 10}.\{t % 10}µs"
  } else if us < 1000000.0 {
    let t = (us / 100.0).to_int()
    "\{t / 10}.\{t % 10}ms"
  } else {
    let t = (us / 100000.0).to_int()
    "\{t / 10}.\{t % 10}s"
  }
}

///|
// Print one bench result as a key=value line suitable for grep/awk parsing.
fn print_bench_result(r : BenchResult, extra : String) -> Unit {
  let e = if extra.is_empty() { "" } else { "  \{extra}" }
  println(
    "bench  name=\{r.name}  mean=\{fmt_us(r.mean_us)}  median=\{fmt_us(r.median_us)}  p95=\{fmt_us(r.p95_us)}  min=\{fmt_us(r.min_us)}  max=\{fmt_us(r.max_us)}  runs=\{r.runs}\{e}",
  )
}

///|
// Parse "json", "expression", or "both" to a list of ScriptGrammar values.
fn parse_bench_grammar_selector(text : String) -> Array[ScriptGrammar]? {
  match text {
    "json" => Some([Json])
    "expression" => Some([Expression])
    "both" => Some([Json, Expression])
    _ => None
  }
}

///|
// Generate a JSON array `[{"id":i,"v":v}…]` filling approximately `target` bytes.
fn json_of_target_size(target : Int) -> String {
  let buf = StringBuilder::new()
  buf.write_string("[")
  let mut written = 1
  let mut i = 0
  while written < target - 1 {
    let sep = if i == 0 { "" } else { "," }
    let item = sep +
      "{\"id\":" +
      i.to_string() +
      ",\"v\":" +
      (i * 3 + 1).to_string() +
      "}"
    if written + item.length() >= target {
      break
    }
    buf.write_string(item)
    written = written + item.length()
    i = i + 1
  }
  buf.write_string("]")
  buf.to_string()
}

///|
// Generate an expression `n+n+n+…` filling approximately `target` bytes.
fn expr_of_target_size(target : Int) -> String {
  let buf = StringBuilder::new()
  buf.write_string("n")
  let mut written = 1
  while written + 2 < target {
    buf.write_string("+n")
    written = written + 2
  }
  buf.to_string()
}

///|
// Build an input of a given size class for a grammar.
fn bench_input_for(grammar : ScriptGrammar, size_bytes : Int) -> String {
  match grammar {
    Json => json_of_target_size(size_bytes)
    Expression => expr_of_target_size(size_bytes)
  }
}
