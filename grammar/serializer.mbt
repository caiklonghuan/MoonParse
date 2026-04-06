// Grammar 序列化层
// 对应 DESIGN.md .6
// 提供两种序列化目标：
// grammar_to_string()  → DSL 文本（可被 parse_grammar 重新解析）
// grammar_to_json()    → JSON 字符串

// DSL 文本序列化

///|
/// 将 Grammar 序列化为 DSL 字符串，输出结果可被 parse_grammar 重新解析
pub fn grammar_to_string(grammar : Grammar) -> String {
  let parts : Array[String] = []

  // start 声明
  match grammar.start {
    Some(name) => parts.push("start " + name)
    None => ()
  }

  // precedence 声明（precedences 已按声明顺序排列，直接输出）
  for pd in grammar.precedences {
    let kind_str = match pd.kind {
      PrecKind::Left => "left"
      PrecKind::Right => "right"
      PrecKind::Nonassoc => "nonassoc"
      PrecKind::Dynamic => "dynamic"
    }
    let rules_str = pd.rules.join(", ")
    parts.push("precedence " + kind_str + " " + rules_str)
  }

  // extras 声明
  if not(grammar.extras.is_empty()) {
    let extras_str = grammar.extras.map(pattern_to_string).join(", ")
    parts.push("extras [" + extras_str + "]")
  }

  // rule 声明
  for name, rule in grammar.rules {
    ignore(name)
    // is_named=false 的匿名规则，rule.name 本身已含 "_" 前缀，无需再拼
    parts.push("rule " + rule.name + ": " + pattern_to_string(rule.pattern))
  }

  parts.join("\n")
}

// JSON 序列化

///|
/// 将 Grammar 序列化为 JSON 字符串
pub fn grammar_to_json(grammar : Grammar) -> String {
  let parts : Array[String] = []

  // "start"
  match grammar.start {
    Some(name) => parts.push("\"start\": " + json_string(name))
    None => parts.push("\"start\": null")
  }

  // "rules"
  let rule_parts : Array[String] = []
  for name, rule in grammar.rules {
    rule_parts.push(json_string(name) + ": " + rule_to_json(rule))
  }
  parts.push("\"rules\": {" + rule_parts.join(", ") + "}")

  // "precedences"
  let prec_parts = grammar.precedences.map(prec_decl_to_json)
  parts.push("\"precedences\": [" + prec_parts.join(", ") + "]")

  "{\n  " + parts.join(",\n  ") + "\n}"
}

///|
fn rule_to_json(rule : Rule) -> String {
  let is_named_str = if rule.is_named { "true" } else { "false" }
  let parts = [
    "\"name\": " + json_string(rule.name),
    "\"is_named\": " + is_named_str,
    "\"pattern\": " + pattern_to_json(rule.pattern),
  ]
  "{" + parts.join(", ") + "}"
}

///|
fn prec_decl_to_json(pd : PrecDecl) -> String {
  let kind_str = match pd.kind {
    PrecKind::Left => "\"Left\""
    PrecKind::Right => "\"Right\""
    PrecKind::Nonassoc => "\"Nonassoc\""
    PrecKind::Dynamic => "\"Dynamic\""
  }
  let rules_json = pd.rules.map(json_string).join(", ")
  let buf = StringBuilder::new()
  buf.write_string("{\"level\": ")
  buf.write_string(pd.level.to_string())
  buf.write_string(", \"kind\": ")
  buf.write_string(kind_str)
  buf.write_string(", \"rules\": [")
  buf.write_string(rules_json)
  buf.write_string("]}")
  buf.to_string()
}

///|
fn pattern_to_json(p : Pattern) -> String {
  match p {
    RuleRef(name) =>
      "{\"type\": \"RuleRef\", \"name\": " + json_string(name) + "}"
    Literal(s) => "{\"type\": \"Literal\", \"value\": " + json_string(s) + "}"
    Regex(re) => "{\"type\": \"Regex\", \"value\": " + json_string(re) + "}"
    AnyChar => "{\"type\": \"AnyChar\"}"
    Tagged(label, inner) =>
      "{\"type\": \"Tagged\", \"label\": " +
      json_string(label) +
      ", \"pattern\": " +
      pattern_to_json(inner) +
      "}"
    Not(inner) =>
      "{\"type\": \"Not\", \"pattern\": " + pattern_to_json(inner) + "}"
    And(inner) =>
      "{\"type\": \"And\", \"pattern\": " + pattern_to_json(inner) + "}"
    Repeat(inner) =>
      "{\"type\": \"Repeat\", \"pattern\": " + pattern_to_json(inner) + "}"
    Plus(inner) =>
      "{\"type\": \"Plus\", \"pattern\": " + pattern_to_json(inner) + "}"
    Optional(inner) =>
      "{\"type\": \"Optional\", \"pattern\": " + pattern_to_json(inner) + "}"
    Field(fname, inner) =>
      "{\"type\": \"Field\", \"field\": " +
      json_string(fname) +
      ", \"pattern\": " +
      pattern_to_json(inner) +
      "}"
    RepeatRange(inner, min, max) =>
      "{\"type\": \"RepeatRange\", \"min\": " +
      min.to_string() +
      ", \"max\": " +
      max.to_string() +
      ", \"pattern\": " +
      pattern_to_json(inner) +
      "}"
    Prec(level, kind, inner) => {
      let kind_str = match kind {
        PrecKind::Left => "\"Left\""
        PrecKind::Right => "\"Right\""
        PrecKind::Nonassoc => "\"Nonassoc\""
        PrecKind::Dynamic => "\"Dynamic\""
      }
      "{\"type\": \"Prec\", \"level\": " +
      level.to_string() +
      ", \"kind\": " +
      kind_str +
      ", \"pattern\": " +
      pattern_to_json(inner) +
      "}"
    }
    Choice(patterns) => {
      let arr = patterns.map(pattern_to_json).join(", ")
      "{\"type\": \"Choice\", \"patterns\": [" + arr + "]}"
    }
    Seq(patterns) => {
      let arr = patterns.map(pattern_to_json).join(", ")
      "{\"type\": \"Seq\", \"patterns\": [" + arr + "]}"
    }
    Alias(name, inner) =>
      "{\"type\": \"Alias\", \"name\": " +
      json_string(name) +
      ", \"pattern\": " +
      pattern_to_json(inner) +
      "}"
  }
}

// JSON 字符串转义

///|
/// 将字符串包裹为合法 JSON 字符串字面量（含转义处理）
fn json_string(s : String) -> String {
  let buf = StringBuilder::new()
  buf.write_char('"')
  for c in s {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ => buf.write_char(c)
    }
  }
  buf.write_char('"')
  buf.to_string()
}
