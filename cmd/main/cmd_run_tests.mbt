///|
// 语料库测试运行器
///|
/// 单条测试用例
priv struct TestCase {
  name : String
  input : String
  expected : String
}

///|
/// 将字符串按换行符拆分为行数组
fn split_lines(s : String) -> Array[String] {
  let result : Array[String] = []
  let n = s.length()
  let mut line_start = 0
  for i in 0..<n {
    if s[i] == '\n' {
      result.push(s[line_start:i].to_string())
      line_start = i + 1
    }
  }
  // 最后一行（可能没有末尾 '\n'）
  if line_start <= n {
    result.push(s[line_start:n].to_string())
  }
  result
}

///|
/// 将行数组重新拼接为换行分隔的字符串
fn join_lines(lines : Array[String]) -> String {
  let buf = StringBuilder::new()
  let n = lines.length()
  for i in 0..<n {
    if i > 0 {
      buf.write_char('\n')
    }
    buf.write_string(lines[i])
  }
  buf.to_string()
}

///|
/// 判断一行是否是 tree-sitter corpus 分隔线（三个以上 '=' 字符）
fn is_separator_line(line : String) -> Bool {
  let n = line.length()
  if n < 3 {
    return false
  }
  for i in 0..<n {
    if line[i] != '=' {
      return false
    }
  }
  true
}

///|
/// 去掉字符串首尾空白行，保留内部内容（简易修剪）
fn trim_blank_lines(s : String) -> String {
  let lines = split_lines(s)
  let mut start = 0
  while start < lines.length() && lines[start].length() == 0 {
    start = start + 1
  }
  let mut end = lines.length()
  while end > start && lines[end - 1].length() == 0 {
    end = end - 1
  }
  join_lines(lines[start:end].to_array())
}

///|
/// 解析 corpus 文件内容，提取所有测试用例
fn parse_corpus(content : String) -> Array[TestCase] {
  let cases : Array[TestCase] = []
  let lines = split_lines(content)
  let n = lines.length()
  let mut i = 0
  while i < n {
    // 找到第一条分隔线
    if not(is_separator_line(lines[i])) {
      i = i + 1
      continue
    }
    i = i + 1
    // 名称行
    if i >= n {
      break
    }
    let name = lines[i]
    i = i + 1
    // 第二条分隔线
    if i >= n || not(is_separator_line(lines[i])) {
      continue
    }
    i = i + 1
    // 收集 input（直到遇到 "---" 行）
    let input_lines : Array[String] = []
    while i < n && lines[i] != "---" {
      input_lines.push(lines[i])
      i = i + 1
    }
    if i >= n {
      break
    }
    i = i + 1 // 跳过 "---"
    // 收集 expected（直到下一条分隔线或文件结尾）
    let expected_lines : Array[String] = []
    while i < n && not(is_separator_line(lines[i])) {
      expected_lines.push(lines[i])
      i = i + 1
    }
    let input_text = trim_blank_lines(join_lines(input_lines))
    let expected_text = trim_blank_lines(join_lines(expected_lines))
    cases.push({ name, input: input_text, expected: expected_text })
  }
  cases
}

///|
/// 运行单个 corpus 文件，返回 (passed, failed)
fn run_corpus_file(path : String, grammar_file : String) -> (Int, Int) {
  // 读取并解析 corpus 文件
  let content = match read_file(path) {
    Ok(s) => s
    Err(msg) => {
      print_err("error: cannot read corpus file '\{path}': " + msg)
      return (0, 0)
    }
  }
  // 加载 grammar 并编译解析表
  let table = match load_table_from_grammar(grammar_file) {
    Ok(t) => t
    Err(msg) => {
      print_err("error: cannot compile grammar: " + msg)
      return (0, 0)
    }
  }
  let cases = parse_corpus(content)
  if cases.is_empty() {
    print_warning("no test cases found in '\{path}'")
    return (0, 0)
  }
  let mut passed = 0
  let mut failed = 0
  for tc in cases {
    let actual = match @runtime.parse(table, tc.input) {
      Ok(root) => cst_to_sexp(root, tc.input, table)
      Err(e) => "(ERROR \{e.message})"
    }
    let expected = tc.expected
    if actual == expected {
      passed = passed + 1
    } else {
      failed = failed + 1
      print_err("\u2718 \{tc.name}")
      print_err("  expected: \{expected}")
      print_err("  actual:   \{actual}")
    }
  }
  (passed, failed)
}

///|
/// test 命令主体。
///
/// test_dir / 文件路径 解析规则：
///   - 若给定路径以 .grammar 结尾 → 扫描同目录下的 .txt 文件（简化：仅接受显式路径）
///   - 否则视为 corpus .txt 文件路径
pub fn cmd_run_tests(args : TestArgs) -> Int {
  let spec = match args.test_dir {
    None => {
      print_err("error: test directory or file required")
      return 2
    }
    Some(s) => s
  }

  // 支持 "<grammar>:<corpus>" 冒号分隔格式
  let (grammar_path, corpus_path) = parse_test_spec(spec)

  let (passed, failed) = run_corpus_file(corpus_path, grammar_path)
  let total = passed + failed
  if total == 0 {
    print_info("no tests found")
    return 0
  }
  if failed == 0 {
    print_info("\u2714 \{total} tests passed")
    0
  } else {
    print_err("\{failed} of \{total} tests FAILED")
    1
  }
}

///|
/// 解析测试目标规范字符串。
/// 支持 "grammar.grammar:tests.txt" 格式，或仅 "tests.txt"（同目录查找 .grammar）
fn parse_test_spec(spec : String) -> (String, String) {
  // 找冒号分隔符
  let n = spec.length()
  for i in 0..<n {
    if spec[i] == ':' {
      let grammar = spec[0:i].to_string()
      let corpus = spec[i + 1:n].to_string()
      return (grammar, corpus)
    }
  }
  // 无冒号：corpus 文件与 grammar 文件同名（仅后缀不同）
  let corpus = spec
  let grammar = derive_corpus_grammar_path(spec)
  (grammar, corpus)
}

///|
/// 从 corpus 文件路径推导 .grammar 文件路径（同目录、同基名、.grammar 后缀）
fn derive_corpus_grammar_path(corpus_path : String) -> String {
  let n = corpus_path.length()
  // 找最后一个 '.' 截断后缀
  let mut dot_pos = n
  for i in 0..<n {
    if corpus_path[i] == '.' {
      dot_pos = i
    }
  }
  if dot_pos < n {
    corpus_path[0:dot_pos].to_string() + ".grammar"
  } else {
    corpus_path + ".grammar"
  }
}
