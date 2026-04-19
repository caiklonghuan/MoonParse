///|
// dump 命令处理器
// 将语法的内部结构输出到 stdout，用于调试。
//
// 子命令：
//   dump ir        — 打印语法 IR（规则、终结符、优先级）
//   dump table     — 打印 LALR 解析表 JSON
//   dump automaton — 打印 LR(0) 项目集和 GOTO 跳转

///|
/// dump 命令主体。
pub fn cmd_dump(args : DumpArgs) -> Int {
  match args.target {
    DumpTarget::Ir => dump_ir(args.input)
    DumpTarget::Table => dump_table(args.input)
    DumpTarget::Automaton => dump_automaton(args.input)
  }
}

///|
/// dump ir：将 grammar IR 以人类可读格式输出到 stdout。
fn dump_ir(input : String) -> Int {
  let src = match read_file(input) {
    Ok(s) => s
    Err(msg) => {
      print_err("error: " + msg)
      return 2
    }
  }
  let grammar = match @grammar.parse_grammar(src) {
    Success(g) => g
    Error(err) => {
      report_grammar_parse_error(err, Some(input), Some(src))
      return 2
    }
  }
  print_info(@grammar.grammar_to_string(grammar))
  0
}

///|
/// dump table：将 LALR 解析表以 JSON 格式输出到 stdout。
/// 接受 .grammar 文件（生成解析表）或已有 .parse_table 文件（直接输出）。
fn dump_table(input : String) -> Int {
  // 若输入已经是 JSON 格式的 .parse_table，直接打印
  if dump_ends_with(input, ".json") {
    return dump_print_file(input)
  }

  // 若输入是二进制 .parse_table，反序列化后转 JSON 输出
  if dump_ends_with(input, ".parse_table") {
    let bytes = match read_bytes(input) {
      Ok(b) => b
      Err(msg) => {
        print_err("error: " + msg)
        return 2
      }
    }
    let table = match @tablegen.deserialize_table(bytes) {
      Ok(t) => t
      Err(msg) => {
        print_err("error: failed to deserialize parse table: " + msg)
        return 2
      }
    }
    print_info(@tablegen.table_to_json(table))
    return 0
  }

  // 默认：从 .grammar 文件生成解析表
  let src = match read_file(input) {
    Ok(s) => s
    Err(msg) => {
      print_err("error: " + msg)
      return 2
    }
  }
  let grammar = match @grammar.parse_grammar(src) {
    Success(g) => g
    Error(err) => {
      report_grammar_parse_error(err, Some(input), Some(src))
      return 2
    }
  }
  let (table, _) = match @tablegen.generate_parse_table(grammar) {
    Ok(r) => r
    Err(msg) => {
      print_err("error: " + msg)
      return 2
    }
  }
  print_info(@tablegen.table_to_json(table))
  0
}

///|
fn dump_print_file(path : String) -> Int {
  match read_file(path) {
    Ok(s) => {
      print_info(s)
      0
    }
    Err(msg) => {
      print_err("error: " + msg)
      2
    }
  }
}

///|
/// dump automaton：打印 LR(0) 项目集和 GOTO 跳转关系。
fn dump_automaton(input : String) -> Int {
  let src = match read_file(input) {
    Ok(s) => s
    Err(msg) => {
      print_err("error: " + msg)
      return 2
    }
  }
  let grammar = match @grammar.parse_grammar(src) {
    Success(g) => g
    Error(err) => {
      report_grammar_parse_error(err, Some(input), Some(src))
      return 2
    }
  }

  let aug = @tablegen.augment_grammar(grammar)
  let item_sets = @tablegen.build_item_sets(aug)
  let goto_map = @tablegen.build_goto_map(aug, item_sets)

  // 构建 id → name 反向映射
  let nt_id_to_name : Map[Int, String] = Map::new()
  for name, id in aug.nonterminals {
    nt_id_to_name.set(id, name)
  }
  let term_id_to_name : Map[Int, String] = Map::new()
  for name, id in aug.terminals {
    term_id_to_name.set(id, name)
  }

  // 按 state id 预先整理 goto 表
  let state_gotos : Map[Int, Array[(String, Int)]] = Map::new()
  for key, next_state in goto_map {
    let (state_id, sym) = key
    let sym_name = dump_sym_name(sym, nt_id_to_name, term_id_to_name)
    match state_gotos.get(state_id) {
      None => state_gotos.set(state_id, [(sym_name, next_state)])
      Some(arr) => arr.push((sym_name, next_state))
    }
  }

  let buf = StringBuilder::new()
  for i in 0..<item_sets.length() {
    let item_set = item_sets[i]
    buf.write_string("State \{i}:\n")

    // 对项目排序以保证输出确定性
    let items_arr = item_set.to_array()
    items_arr.sort_by(fn(a, b) { a.compare(b) })

    for item in items_arr {
      let prod = aug.productions[item.prod]
      let head_name = match nt_id_to_name.get(prod.head) {
        Some(n) => n
        None => "NT\{prod.head}"
      }
      buf.write_string("  \{head_name} \u2192")
      for j in 0..<prod.body.length() {
        let bs = prod.body[j]
        if j == item.dot {
          buf.write_string(" \u2022")
        }
        let sym_name = dump_sym_name(bs.symbol, nt_id_to_name, term_id_to_name)
        buf.write_string(" \{sym_name}")
      }
      if item.dot == prod.body.length() {
        buf.write_string(" \u2022")
      }
      buf.write_char('\n')
    }

    // GOTO 跳转
    match state_gotos.get(i) {
      Some(entries) => {
        entries.sort_by(fn(a, b) {
          if a.0 < b.0 {
            -1
          } else if a.0 > b.0 {
            1
          } else {
            0
          }
        })
        buf.write_string("  \u2500\u2500\u2500 goto \u2500\u2500\u2500\n")
        for entry in entries {
          buf.write_string("  \{entry.0} \u2192 State \{entry.1}\n")
        }
      }
      None => ()
    }
    buf.write_char('\n')
  }

  print_info(buf.to_string())
  0
}

///|
fn dump_sym_name(
  sym : @tablegen.Symbol,
  nt_map : Map[Int, String],
  term_map : Map[Int, String],
) -> String {
  match sym {
    @tablegen.Symbol::Terminal(id) =>
      match term_map.get(id) {
        Some(n) => n
        None => "T\{id}"
      }
    @tablegen.Symbol::NonTerminal(id) =>
      match nt_map.get(id) {
        Some(n) => n
        None => "NT\{id}"
      }
    @tablegen.Symbol::EndOfInput => "$"
  }
}

///|
fn dump_ends_with(s : String, suffix : String) -> Bool {
  let n = s.length()
  let sl = suffix.length()
  if n < sl {
    return false
  }
  for i in 0..<sl {
    if s[n - sl + i] != suffix[i] {
      return false
    }
  }
  true
}
