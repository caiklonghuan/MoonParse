// Grammar 序列化层
// DSL 文本序列化 + JSON 往返

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
  if !grammar.extras.is_empty() {
    let extras_str = grammar.extras.map(pattern_to_string).join(", ")
    parts.push("extras [" + extras_str + "]")
  }

  // externals 声明
  if !grammar.externals.is_empty() {
    let ext_str = grammar.externals.join(", ")
    parts.push("externals [" + ext_str + "]")
  }

  // word 声明
  match grammar.word {
    Some(w) => parts.push("word " + w)
    None => ()
  }

  // conflicts 声明
  if !grammar.conflicts.is_empty() {
    let groups_str = grammar.conflicts
      .map(fn(g) { "[" + g.join(", ") + "]" })
      .join(", ")
    parts.push("conflicts [" + groups_str + "]")
  }

  // supertypes 声明
  if !grammar.supertypes.is_empty() {
    parts.push("supertypes [" + grammar.supertypes.join(", ") + "]")
  }

  // rule 声明
  for name, rule in grammar.rules {
    ignore(name)
    // 属性前缀
    let attr_prefix = rule.attributes
      .map(fn(a) {
        match a {
          RuleAttribute::Inline => "@inline "
          RuleAttribute::Hide => "@hide "
          RuleAttribute::Deprecated => "@deprecated "
        }
      })
      .join("")
    // token 前缀
    let token_prefix = if rule.is_token { "token " } else { "" }
    // 模板参数
    let params_str = if rule.params.is_empty() {
      ""
    } else {
      "[" + rule.params.join(", ") + "]"
    }
    parts.push(
      attr_prefix +
      token_prefix +
      "rule " +
      rule.name +
      params_str +
      ": " +
      pattern_to_string(rule.pattern),
    )
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

  // "rules" — sort by name for deterministic output
  let rule_pairs : Array[(String, String)] = []
  for name, rule in grammar.rules {
    rule_pairs.push((name, rule_to_json(rule)))
  }
  rule_pairs.sort_by(fn(a, b) { a.0.compare(b.0) })
  let rule_parts = rule_pairs.map(fn(kv) { json_string(kv.0) + ": " + kv.1 })
  parts.push("\"rules\": {" + rule_parts.join(", ") + "}")

  // "precedences"
  let prec_parts = grammar.precedences.map(prec_decl_to_json)
  parts.push("\"precedences\": [" + prec_parts.join(", ") + "]")

  // "extras"
  let extras_parts = grammar.extras.map(pattern_to_json)
  parts.push("\"extras\": [" + extras_parts.join(", ") + "]")

  // "externals"
  let ext_parts = grammar.externals.map(json_string)
  parts.push("\"externals\": [" + ext_parts.join(", ") + "]")

  // "word"
  match grammar.word {
    Some(w) => parts.push("\"word\": " + json_string(w))
    None => parts.push("\"word\": null")
  }

  // "conflicts"
  let conflicts_parts = grammar.conflicts.map(fn(g) {
    "[" + g.map(json_string).join(", ") + "]"
  })
  parts.push("\"conflicts\": [" + conflicts_parts.join(", ") + "]")

  // "supertypes"
  let supertypes_parts = grammar.supertypes.map(json_string)
  parts.push("\"supertypes\": [" + supertypes_parts.join(", ") + "]")

  "{\n  " + parts.join(",\n  ") + "\n}"
}

///|
fn rule_to_json(rule : Rule) -> String {
  let is_named_str = if rule.is_named { "true" } else { "false" }
  let is_token_str = if rule.is_token { "true" } else { "false" }
  let params_str = "[" + rule.params.map(json_string).join(", ") + "]"
  let attrs_str = "[" +
    rule.attributes
    .map(fn(a) {
      match a {
        RuleAttribute::Inline => "\"Inline\""
        RuleAttribute::Hide => "\"Hide\""
        RuleAttribute::Deprecated => "\"Deprecated\""
      }
    })
    .join(", ") +
    "]"
  let parts = [
    "\"name\": " + json_string(rule.name),
    "\"is_named\": " + is_named_str,
    "\"is_token\": " + is_token_str,
    "\"params\": " + params_str,
    "\"attributes\": " + attrs_str,
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
    RuleApp(name, args) => {
      let args_str = args.map(pattern_to_json).join(", ")
      "{\"type\": \"RuleApp\", \"name\": " +
      json_string(name) +
      ", \"args\": [" +
      args_str +
      "]}"
    }
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

// JSON 反序列化
//
// 将 grammar_to_json 的输出还原为 Grammar（往返支持）。
// 使用 moonbitlang/core/json 标准库解析 JSON。

///|
/// 内部 JSON 解析错误（仅在 grammar_from_json 内传播）
priv suberror GrammarJsonError {
  GJBadField(String)
  GJBadType(String)
}

///|
fn gj_field(
  obj : Map[String, Json],
  key : String,
) -> Json raise GrammarJsonError {
  match obj.get(key) {
    Some(v) => v
    None => raise GJBadField("missing key: \{key}")
  }
}

///|
fn gj_str(j : Json) -> String raise GrammarJsonError {
  match j {
    String(s) => s
    _ => raise GJBadType("expected string")
  }
}

///|
fn gj_bool(j : Json) -> Bool raise GrammarJsonError {
  match j {
    True => true
    False => false
    _ => raise GJBadType("expected bool")
  }
}

///|
fn gj_int(j : Json) -> Int raise GrammarJsonError {
  match j {
    Number(n, ..) => n.to_int()
    _ => raise GJBadType("expected number")
  }
}

///|
fn gj_arr(j : Json) -> Array[Json] raise GrammarJsonError {
  match j {
    Array(a) => a
    _ => raise GJBadType("expected array")
  }
}

///|
fn gj_obj(j : Json) -> Map[String, Json] raise GrammarJsonError {
  match j {
    Object(o) => o
    _ => raise GJBadType("expected object")
  }
}

///|
fn gj_prec_kind(s : String) -> PrecKind raise GrammarJsonError {
  match s {
    "Left" => PrecKind::Left
    "Right" => PrecKind::Right
    "Nonassoc" => PrecKind::Nonassoc
    "Dynamic" => PrecKind::Dynamic
    _ => raise GJBadField("unknown PrecKind: \{s}")
  }
}

///|
fn gj_pattern(j : Json) -> Pattern raise GrammarJsonError {
  let o = gj_obj(j)
  let ty = gj_str(gj_field(o, "type"))
  match ty {
    "RuleRef" => RuleRef(gj_str(gj_field(o, "name")))
    "Literal" => Literal(gj_str(gj_field(o, "value")))
    "Regex" => Regex(gj_str(gj_field(o, "value")))
    "AnyChar" => AnyChar
    "Tagged" =>
      Tagged(gj_str(gj_field(o, "label")), gj_pattern(gj_field(o, "pattern")))
    "Not" => Not(gj_pattern(gj_field(o, "pattern")))
    "And" => And(gj_pattern(gj_field(o, "pattern")))
    "Repeat" => Repeat(gj_pattern(gj_field(o, "pattern")))
    "Plus" => Plus(gj_pattern(gj_field(o, "pattern")))
    "Optional" => Optional(gj_pattern(gj_field(o, "pattern")))
    "Field" =>
      Field(gj_str(gj_field(o, "field")), gj_pattern(gj_field(o, "pattern")))
    "RepeatRange" =>
      RepeatRange(
        gj_pattern(gj_field(o, "pattern")),
        gj_int(gj_field(o, "min")),
        gj_int(gj_field(o, "max")),
      )
    "Prec" =>
      Prec(
        gj_int(gj_field(o, "level")),
        gj_prec_kind(gj_str(gj_field(o, "kind"))),
        gj_pattern(gj_field(o, "pattern")),
      )
    "Choice" => {
      let pats = gj_arr(gj_field(o, "patterns")).map(gj_pattern)
      Choice(pats)
    }
    "Seq" => {
      let pats = gj_arr(gj_field(o, "patterns")).map(gj_pattern)
      Seq(pats)
    }
    "Alias" =>
      Alias(gj_str(gj_field(o, "name")), gj_pattern(gj_field(o, "pattern")))
    "RuleApp" => {
      let args = gj_arr(gj_field(o, "args")).map(gj_pattern)
      RuleApp(gj_str(gj_field(o, "name")), args)
    }
    _ => raise GJBadField("unknown pattern type: \{ty}")
  }
}

///|
fn gj_rule(j : Json) -> Rule raise GrammarJsonError {
  let o = gj_obj(j)
  let name = gj_str(gj_field(o, "name"))
  let is_named = gj_bool(gj_field(o, "is_named"))
  let is_token = gj_bool(gj_field(o, "is_token"))
  let params = gj_arr(gj_field(o, "params")).map(gj_str)
  let attributes = gj_arr(gj_field(o, "attributes")).map(fn(
    a,
  ) raise GrammarJsonError {
    match gj_str(a) {
      "Inline" => RuleAttribute::Inline
      "Hide" => RuleAttribute::Hide
      "Deprecated" => RuleAttribute::Deprecated
      s => raise GJBadField("unknown RuleAttribute: \{s}")
    }
  })
  let pattern = gj_pattern(gj_field(o, "pattern"))
  { name, is_named, is_token, params, attributes, pattern, location: None }
}

///|
fn gj_prec_decl(j : Json) -> PrecDecl raise GrammarJsonError {
  let o = gj_obj(j)
  let level = gj_int(gj_field(o, "level"))
  let kind = gj_prec_kind(gj_str(gj_field(o, "kind")))
  let rules = gj_arr(gj_field(o, "rules")).map(gj_str)
  { level, kind, rules }
}

///|
/// 将 grammar_to_json 的 JSON 输出还原为 Grammar 对象。
///
/// 成功返回 `Success(grammar)`，失败返回 `Error(ParseError)`（message 描述具体原因）。
/// 典型用途：从工具链 / tree-sitter JSON 格式加载预先构建好的 Grammar。
pub fn grammar_from_json(json_str : String) -> ParseResult[Grammar] {
  let dummy_loc : SourceLocation = { line: 0, column: 0 }
  let j = @json.parse(json_str) catch {
    err =>
      return Error({
        message: "grammar_from_json: JSON parse error: \{err}",
        location: dummy_loc,
      })
  }
  try {
    let o = gj_obj(j)

    // start
    let start : String? = match o.get("start") {
      Some(String(s)) => Some(s)
      _ => None
    }

    // rules
    let rules : Map[String, Rule] = Map::new()
    let rules_obj = gj_obj(gj_field(o, "rules"))
    for _name, rule_j in rules_obj {
      let rule = gj_rule(rule_j)
      rules.set(rule.name, rule)
    }

    // precedences
    let precedences = gj_arr(gj_field(o, "precedences")).map(gj_prec_decl)

    // extras
    let extras = gj_arr(gj_field(o, "extras")).map(gj_pattern)

    // externals
    let externals = gj_arr(gj_field(o, "externals")).map(gj_str)

    // word
    let word : String? = match o.get("word") {
      Some(String(s)) => Some(s)
      _ => None
    }

    // conflicts
    let conflicts = gj_arr(gj_field(o, "conflicts")).map(fn(
      g,
    ) raise GrammarJsonError {
      gj_arr(g).map(gj_str)
    })

    // supertypes
    let supertypes = gj_arr(gj_field(o, "supertypes")).map(gj_str)

    Success({
      start,
      rules,
      precedences,
      extras,
      externals,
      duplicate_rule_names: [],
      word,
      conflicts,
      supertypes,
    })
  } catch {
    GJBadField(msg) =>
      Error({ message: "grammar_from_json: \{msg}", location: dummy_loc })
    GJBadType(msg) =>
      Error({ message: "grammar_from_json: \{msg}", location: dummy_loc })
  }
}
