///|
/// 解析错误，包含可读的消息和源码位置
pub(all) struct ParseError {
  message : String
  location : SourceLocation
}

///|
/// 解析结果：成功携带值，失败携带错误
pub(all) enum ParseResult[T] {
  Success(T)
  Error(ParseError)
}

///|
/// 解析器内部状态（包内私有）
priv struct ParserState {
  tokens : Array[TokenWithLocation]
  mut pos : Int
}

///|
/// 解析 Grammar DSL 字符串，返回完整的 Grammar 对象
pub fn parse_grammar(dsl : String) -> ParseResult[Grammar] {
  let (grammar, errors) = parse_grammar_lenient(dsl)
  if errors.is_empty() {
    Success(grammar)
  } else {
    Error(errors[0])
  }
}

///|
/// 解析 Grammar DSL 字符串，支持 panic-mode 错误恢复。
/// 遇到顶层语句的解析错误时，跳到下一个顶层关键字继续解析，
/// 返回部分构建的 Grammar 以及收集到的所有解析错误。
pub fn parse_grammar_lenient(dsl : String) -> (Grammar, Array[ParseError]) {
  let tokens = tokenize(dsl)
  let state = { tokens, pos: 0 }
  let grammar : Grammar = {
    start: None,
    rules: Map::new(),
    precedences: [],
    extras: [],
    externals: [],
    duplicate_rule_names: [],
    word: None,
    conflicts: [],
    supertypes: [],
  }
  let errors : Array[ParseError] = []

  while state.pos < state.tokens.length() {
    match state.tokens[state.pos].token {
      Keyword("rule") => {
        state.pos = state.pos + 1
        match parse_rule(state, false, []) {
          Success(rule) => {
            if grammar.rules.contains(rule.name) {
              grammar.duplicate_rule_names.push(rule.name)
            }
            grammar.rules.set(rule.name, rule)
          }
          Error(err) => {
            errors.push(err)
            skip_to_next_toplevel(state)
          }
        }
      }
      // token rule name: pattern — 声明词法规则（仅含终结符）
      Identifier("token") => {
        state.pos = state.pos + 1
        if state.pos < state.tokens.length() &&
          state.tokens[state.pos].token is Keyword("rule") {
          state.pos = state.pos + 1
          match parse_rule(state, true, []) {
            Success(rule) => {
              if grammar.rules.contains(rule.name) {
                grammar.duplicate_rule_names.push(rule.name)
              }
              grammar.rules.set(rule.name, rule)
            }
            Error(err) => {
              errors.push(err)
              skip_to_next_toplevel(state)
            }
          }
        } else {
          let loc = if state.pos < state.tokens.length() {
            state.tokens[state.pos].location
          } else {
            state.tokens[state.tokens.length() - 1].location
          }
          errors.push({
            message: "Expected 'rule' after 'token'",
            location: loc,
          })
          skip_to_next_toplevel(state)
        }
      }
      // word name — 指定关键字提升规则（类 Tree-sitter word 属性）
      Identifier("word") => {
        state.pos = state.pos + 1
        if state.pos < state.tokens.length() {
          match state.tokens[state.pos].token {
            Identifier(name) => {
              grammar.word = Some(name)
              state.pos = state.pos + 1
            }
            _ => {
              errors.push({
                message: "Expected identifier after 'word'",
                location: state.tokens[state.pos].location,
              })
              skip_to_next_toplevel(state)
            }
          }
        } else {
          errors.push({
            message: "Unexpected end of input after 'word'",
            location: state.tokens[state.tokens.length() - 1].location,
          })
        }
      }
      // @inline rule / @hide rule — 规则属性标注
      Symbol("@") => {
        let attrs = collect_rule_attributes(state)
        // 属性之后必须跟 rule 或 token rule
        if state.pos < state.tokens.length() {
          match state.tokens[state.pos].token {
            Keyword("rule") => {
              state.pos = state.pos + 1
              match parse_rule(state, false, attrs) {
                Success(rule) => {
                  if grammar.rules.contains(rule.name) {
                    grammar.duplicate_rule_names.push(rule.name)
                  }
                  grammar.rules.set(rule.name, rule)
                }
                Error(err) => {
                  errors.push(err)
                  skip_to_next_toplevel(state)
                }
              }
            }
            Identifier("token") => {
              state.pos = state.pos + 1
              if state.pos < state.tokens.length() &&
                state.tokens[state.pos].token is Keyword("rule") {
                state.pos = state.pos + 1
                match parse_rule(state, true, attrs) {
                  Success(rule) => {
                    if grammar.rules.contains(rule.name) {
                      grammar.duplicate_rule_names.push(rule.name)
                    }
                    grammar.rules.set(rule.name, rule)
                  }
                  Error(err) => {
                    errors.push(err)
                    skip_to_next_toplevel(state)
                  }
                }
              } else {
                let loc = if state.pos < state.tokens.length() {
                  state.tokens[state.pos].location
                } else {
                  state.tokens[state.tokens.length() - 1].location
                }
                errors.push({
                  message: "Expected 'rule' after '@... token'",
                  location: loc,
                })
                skip_to_next_toplevel(state)
              }
            }
            _ => {
              errors.push({
                message: "Expected 'rule' or 'token rule' after rule attributes",
                location: state.tokens[state.pos].location,
              })
              skip_to_next_toplevel(state)
            }
          }
        } else {
          errors.push({
            message: "Unexpected end of input after rule attributes",
            location: state.tokens[state.tokens.length() - 1].location,
          })
        }
      }
      Keyword("start") => {
        state.pos = state.pos + 1
        if state.pos < state.tokens.length() {
          match state.tokens[state.pos].token {
            Identifier(name) => {
              grammar.start = Some(name)
              state.pos = state.pos + 1
            }
            _ => {
              errors.push({
                message: "Expected identifier after 'start'",
                location: state.tokens[state.pos].location,
              })
              skip_to_next_toplevel(state)
            }
          }
        } else {
          errors.push({
            message: "Unexpected end of input after 'start'",
            location: state.tokens[state.tokens.length() - 1].location,
          })
        }
      }
      Keyword("precedence") => {
        state.pos = state.pos + 1
        let level = grammar.precedences.length() + 1
        match parse_prec_decl(state, level) {
          Success(decl) => grammar.precedences.push(decl)
          Error(err) => {
            errors.push(err)
            skip_to_next_toplevel(state)
          }
        }
      }
      Keyword("extras") => {
        state.pos = state.pos + 1
        match parse_extras(state) {
          Success(patterns) =>
            for p in patterns {
              grammar.extras.push(p)
            }
          Error(err) => {
            errors.push(err)
            skip_to_next_toplevel(state)
          }
        }
      }
      Keyword("externals") => {
        state.pos = state.pos + 1
        match parse_externals(state) {
          Success(names) =>
            for n in names {
              grammar.externals.push(n)
            }
          Error(err) => {
            errors.push(err)
            skip_to_next_toplevel(state)
          }
        }
      }
      // conflicts [[rule_a, rule_b], [rule_c, rule_d]] — 声明 GLR 歧义规则组
      Identifier("conflicts") => {
        state.pos = state.pos + 1
        match parse_conflicts(state) {
          Success(groups) =>
            for g in groups {
              grammar.conflicts.push(g)
            }
          Error(err) => {
            errors.push(err)
            skip_to_next_toplevel(state)
          }
        }
      }
      // supertypes [expr, stmt, ...] — 声明抽象超类型列表，供查询 API 使用
      Identifier("supertypes") => {
        state.pos = state.pos + 1
        match parse_name_list(state, "supertypes") {
          Success(names) =>
            for n in names {
              grammar.supertypes.push(n)
            }
          Error(err) => {
            errors.push(err)
            skip_to_next_toplevel(state)
          }
        }
      }
      _ => state.pos = state.pos + 1
    }
  }
  (grammar, errors)
}

///|
/// 收集 `@inline` / `@hide` 序列，返回属性列表（同时消耗 token）
fn collect_rule_attributes(state : ParserState) -> Array[RuleAttribute] {
  let attrs : Array[RuleAttribute] = []
  while state.pos < state.tokens.length() {
    match state.tokens[state.pos].token {
      Symbol("@") => {
        state.pos = state.pos + 1
        if state.pos < state.tokens.length() {
          match state.tokens[state.pos].token {
            Identifier("inline") => {
              attrs.push(RuleAttribute::Inline)
              state.pos = state.pos + 1
            }
            Identifier("hide") => {
              attrs.push(RuleAttribute::Hide)
              state.pos = state.pos + 1
            }
            Identifier("deprecated") => {
              attrs.push(RuleAttribute::Deprecated)
              state.pos = state.pos + 1
            }
            _ => break
          }
        }
      }
      _ => break
    }
  }
  attrs
}

///|
/// panic-mode 恢复辅助：跳过 token 直到遇到下一个顶层关键字（不消耗该关键字）
fn skip_to_next_toplevel(state : ParserState) -> Unit {
  while state.pos < state.tokens.length() {
    match state.tokens[state.pos].token {
      Keyword("rule")
      | Keyword("start")
      | Keyword("precedence")
      | Keyword("extras")
      | Keyword("externals")
      | Symbol("@") => break
      // 上下文关键字：只有当前一个 token 不是 pattern 内部操作符时才视为顶层声明起始
      Identifier("token")
      | Identifier("word")
      | Identifier("conflicts")
      | Identifier("supertypes") => {
        let prev_is_pattern_ctx = if state.pos > 0 {
          match state.tokens[state.pos - 1].token {
            Symbol(":")
            | Symbol("|")
            | Symbol("(")
            | Symbol("[")
            | Symbol("*")
            | Symbol("+")
            | Symbol("?")
            | Symbol(",")
            | Symbol(".")
            | Symbol("@")
            | Symbol("!")
            | Symbol("&") => true
            Identifier(_) | StringLiteral(_) | RegexLiteral(_) => true
            _ => false
          }
        } else {
          false
        }
        if prev_is_pattern_ctx {
          state.pos = state.pos + 1
        } else {
          break
        }
      }
      _ => state.pos = state.pos + 1
    }
  }
}

// 规则层

///|
/// 解析顶层 precedence 声明：precedence [left|right|dynamic] name1, name2, ...
fn parse_prec_decl(state : ParserState, level : Int) -> ParseResult[PrecDecl] {
  // 可选结合性修饰词
  let kind = if state.pos < state.tokens.length() {
    match state.tokens[state.pos].token {
      Keyword("left") => {
        state.pos = state.pos + 1
        PrecKind::Left
      }
      Keyword("right") => {
        state.pos = state.pos + 1
        PrecKind::Right
      }
      Keyword("nonassoc") => {
        state.pos = state.pos + 1
        PrecKind::Nonassoc
      }
      Keyword("dynamic") => {
        state.pos = state.pos + 1
        PrecKind::Dynamic
      }
      _ => PrecKind::Nonassoc
    }
  } else {
    PrecKind::Nonassoc
  }
  // 逗号分隔的规则名列表（必须以字母或下划线开头，不得为纯数字）
  let rules : Array[String] = []
  while state.pos < state.tokens.length() {
    match state.tokens[state.pos].token {
      Identifier(name) => {
        if name.length() > 0 &&
          name[0].to_int() >= '0'.to_int() &&
          name[0].to_int() <= '9'.to_int() {
          return Error({
            message: "Expected rule name in precedence declaration, got numeric literal '\{name}'",
            location: state.tokens[state.pos].location,
          })
        }
        rules.push(name)
        state.pos = state.pos + 1
      }
      Symbol(",") => state.pos = state.pos + 1
      _ => break
    }
  }
  if rules.is_empty() {
    let loc = if state.pos < state.tokens.length() {
      state.tokens[state.pos].location
    } else {
      state.tokens[state.tokens.length() - 1].location
    }
    return Error({
      message: "precedence declaration requires at least one rule name",
      location: loc,
    })
  }
  Success({ level, kind, rules })
}

///|
/// 解析单条规则：`[token] rule name[params]: pattern`
/// is_token: 由 `token rule` 语法触发；attributes: 由 `@inline`/`@hide` 语法触发
fn parse_rule(
  state : ParserState,
  is_token : Bool,
  attributes : Array[RuleAttribute],
) -> ParseResult[Rule] {
  if state.pos >= state.tokens.length() {
    return Error({
      message: "Unexpected end of input, expected rule name",
      location: state.tokens[state.tokens.length() - 1].location,
    })
  }
  match state.tokens[state.pos].token {
    Identifier(name) => {
      let name_loc = state.tokens[state.pos].location
      state.pos = state.pos + 1
      if state.pos >= state.tokens.length() {
        return Error({
          message: "Unexpected end of input, expected ':' after rule name",
          location: name_loc,
        })
      }
      // 检查是否有模板参数 [T, U, ...]
      let params : Array[String] = []
      if state.tokens[state.pos].token is Symbol("[") {
        state.pos = state.pos + 1
        while state.pos < state.tokens.length() {
          match state.tokens[state.pos].token {
            Identifier(param) => {
              params.push(param)
              state.pos = state.pos + 1
              if state.pos < state.tokens.length() &&
                state.tokens[state.pos].token is Symbol(",") {
                state.pos = state.pos + 1
              }
            }
            Symbol("]") => {
              state.pos = state.pos + 1
              break
            }
            _ =>
              return Error({
                message: "Expected template parameter name or ']'",
                location: state.tokens[state.pos].location,
              })
          }
        }
      }
      match state.tokens[state.pos].token {
        Symbol(":") => {
          state.pos = state.pos + 1
          let is_named = !name.has_prefix("_")
          match parse_pattern(state) {
            Success(pattern) =>
              Success({
                name,
                pattern,
                is_named,
                is_token,
                params,
                attributes,
                location: Some(name_loc),
              })
            Error(err) => Error(err)
          }
        }
        _ =>
          Error({
            message: "Expected ':' after rule name",
            location: state.tokens[state.pos].location,
          })
      }
    }
    _ =>
      Error({
        message: "Expected identifier for rule name",
        location: state.tokens[state.pos].location,
      })
  }
}

// 表达式层（优先级从低到高：选择 > 序列 > 一元 > 原子）

///|
/// 解析选择表达式：`A | B | C`
fn parse_pattern(state : ParserState) -> ParseResult[Pattern] {
  match parse_sequence(state) {
    Error(err) => Error(err)
    Success(first) => {
      let choices = [first]
      while state.pos < state.tokens.length() {
        match state.tokens[state.pos].token {
          Symbol("|") => {
            state.pos = state.pos + 1
            match parse_sequence(state) {
              Success(seq) => choices.push(seq)
              Error(err) => return Error(err)
            }
          }
          _ => break
        }
      }
      if choices.length() == 1 {
        Success(choices[0])
      } else {
        Success(Choice(choices))
      }
    }
  }
}

///|
/// 解析序列表达式：`A B C`（连续的一元表达式）
fn parse_sequence(state : ParserState) -> ParseResult[Pattern] {
  let seqs = []
  let mut has_error = false
  let mut error = { message: "", location: { line: 0, column: 0 } }

  while state.pos < state.tokens.length() {
    match state.tokens[state.pos].token {
      // `token rule` starts a new top-level declaration; stop the sequence here.
      Identifier("token") => {
        let is_token_rule = state.pos + 1 < state.tokens.length() &&
          state.tokens[state.pos + 1].token is Keyword("rule")
        if is_token_rule {
          break
        } else {
          match parse_unary(state) {
            Success(p) => seqs.push(p)
            Error(err) => {
              has_error = true
              error = err
              break
            }
          }
        }
      }
      Identifier(_)
      | StringLiteral(_)
      | RegexLiteral(_)
      | Symbol("(")
      | Symbol("@")
      | Symbol("!")
      | Symbol("&")
      | Symbol(".")
      | Keyword("prec")
      | Keyword("alias") =>
        match parse_unary(state) {
          Success(p) => seqs.push(p)
          Error(err) => {
            has_error = true
            error = err
            break
          }
        }
      _ => break
    }
  }

  if has_error {
    Error(error)
  } else if seqs.length() == 0 {
    let loc = if state.pos < state.tokens.length() {
      state.tokens[state.pos].location
    } else if state.tokens.length() > 0 {
      state.tokens[state.tokens.length() - 1].location
    } else {
      { line: 1, column: 1 }
    }
    Error({ message: "Expected pattern", location: loc })
  } else if seqs.length() == 1 {
    Success(seqs[0])
  } else {
    Success(Seq(seqs))
  }
}

///|
/// 解析一元后缀表达式：`A*`、`A+`、`A?`、`A{n}`、`A{n,m}`
fn parse_unary(state : ParserState) -> ParseResult[Pattern] {
  match parse_primary(state) {
    Error(err) => Error(err)
    Success(pattern) => {
      if state.pos >= state.tokens.length() {
        return Success(pattern)
      }
      match state.tokens[state.pos].token {
        Symbol("*") => {
          state.pos = state.pos + 1
          Success(Repeat(pattern))
        }
        Symbol("+") => {
          state.pos = state.pos + 1
          Success(Plus(pattern))
        }
        Symbol("?") => {
          state.pos = state.pos + 1
          Success(Optional(pattern))
        }
        Symbol("{") => parse_repeat_range(state, pattern)
        _ => Success(pattern)
      }
    }
  }
}

///|
/// 解析 `{n}` 或 `{n,m}` 重复区间（调用前 `{` 尚未消耗）
fn parse_repeat_range(
  state : ParserState,
  pattern : Pattern,
) -> ParseResult[Pattern] {
  state.pos = state.pos + 1 // 消耗 {
  if state.pos >= state.tokens.length() {
    return Error({
      message: "Expected number after '{'",
      location: state.tokens[state.tokens.length() - 1].location,
    })
  }
  match state.tokens[state.pos].token {
    Identifier(min_str) =>
      match parse_int_str(min_str) {
        None =>
          Error({
            message: "Expected integer in repeat range",
            location: state.tokens[state.pos].location,
          })
        Some(min) => {
          state.pos = state.pos + 1
          if state.pos >= state.tokens.length() {
            return Error({
              message: "Expected ',' or '}' in repeat range",
              location: state.tokens[state.tokens.length() - 1].location,
            })
          }
          match state.tokens[state.pos].token {
            Symbol("}") => {
              state.pos = state.pos + 1
              Success(RepeatRange(pattern, min, min))
            }
            Symbol(",") => {
              state.pos = state.pos + 1
              if state.pos >= state.tokens.length() {
                return Error({
                  message: "Expected number after ','",
                  location: state.tokens[state.tokens.length() - 1].location,
                })
              }
              match state.tokens[state.pos].token {
                Identifier(max_str) =>
                  match parse_int_str(max_str) {
                    None =>
                      Error({
                        message: "Expected integer after ','",
                        location: state.tokens[state.pos].location,
                      })
                    Some(max) => {
                      state.pos = state.pos + 1
                      if state.pos >= state.tokens.length() {
                        return Error({
                          message: "Expected '}' to close repeat range",
                          location: state.tokens[state.tokens.length() - 1].location,
                        })
                      }
                      match state.tokens[state.pos].token {
                        Symbol("}") => {
                          state.pos = state.pos + 1
                          if min > max {
                            return Error({
                              message: "Invalid repeat range: minimum \{min} is greater than maximum \{max}",
                              location: state.tokens[state.pos - 1].location,
                            })
                          }
                          Success(RepeatRange(pattern, min, max))
                        }
                        _ =>
                          Error({
                            message: "Expected '}' to close repeat range",
                            location: state.tokens[state.pos].location,
                          })
                      }
                    }
                  }
                _ =>
                  Error({
                    message: "Expected integer after ','",
                    location: state.tokens[state.pos].location,
                  })
              }
            }
            _ =>
              Error({
                message: "Expected ',' or '}' in repeat range",
                location: state.tokens[state.pos].location,
              })
          }
        }
      }
    _ =>
      Error({
        message: "Expected integer after '{'",
        location: state.tokens[state.pos].location,
      })
  }
}

///|
/// 解析原子表达式：标识符、字面量、正则、分组、前缀操作符
fn parse_primary(state : ParserState) -> ParseResult[Pattern] {
  if state.pos >= state.tokens.length() {
    return Error({
      message: "Unexpected end of input",
      location: state.tokens[state.tokens.length() - 1].location,
    })
  }
  match state.tokens[state.pos].token {
    // 标识符：下一个 token 为 `:` 则是命名字段，`[` 则是模板实例化，否则是规则引用
    // 注意：Field 只绑定紧邻的 primary（不包含后续序列元素）。
    // 即 `name: A B C` 解析为 `Seq([Field(name, A), B, C])`。
    // 若需 field 覆盖整个序列，请用分组：`name: (A B C)`。
    Identifier(name) => {
      state.pos = state.pos + 1
      if state.pos < state.tokens.length() {
        match state.tokens[state.pos].token {
          Symbol(":") => {
            state.pos = state.pos + 1
            match parse_primary(state) {
              Success(inner) => Success(Field(name, inner))
              Error(err) => Error(err)
            }
          }
          Symbol("[") => {
            // 模板实例化：name[arg1, arg2, ...]
            state.pos = state.pos + 1
            let args : Array[Pattern] = []
            while state.pos < state.tokens.length() {
              match state.tokens[state.pos].token {
                Symbol("]") => {
                  state.pos = state.pos + 1
                  break
                }
                Symbol(",") => state.pos = state.pos + 1
                _ =>
                  match parse_pattern(state) {
                    Success(p) => args.push(p)
                    Error(err) => return Error(err)
                  }
              }
            }
            Success(RuleApp(name, args))
          }
          _ => Success(RuleRef(name))
        }
      } else {
        Success(RuleRef(name))
      }
    }
    StringLiteral(lit) => {
      state.pos = state.pos + 1
      Success(Literal(lit))
    }
    RegexLiteral(re) => {
      state.pos = state.pos + 1
      Success(Regex(re))
    }
    // 分组 (pattern)
    Symbol("(") => {
      state.pos = state.pos + 1
      match parse_pattern(state) {
        Error(err) => Error(err)
        Success(inner) =>
          if state.pos < state.tokens.length() {
            match state.tokens[state.pos].token {
              Symbol(")") => {
                state.pos = state.pos + 1
                Success(inner)
              }
              _ =>
                Error({
                  message: "Expected ')' to close group",
                  location: state.tokens[state.pos].location,
                })
            }
          } else {
            Error({
              message: "Unexpected end of input, expected ')'",
              location: state.tokens[state.tokens.length() - 1].location,
            })
          }
      }
    }
    // 语义标签 @label primary
    Symbol("@") => {
      state.pos = state.pos + 1
      if state.pos >= state.tokens.length() {
        return Error({
          message: "Expected label name after '@'",
          location: state.tokens[state.tokens.length() - 1].location,
        })
      }
      match state.tokens[state.pos].token {
        Identifier(label) => {
          state.pos = state.pos + 1
          match parse_primary(state) {
            Success(inner) => Success(Tagged(label, inner))
            Error(err) => Error(err)
          }
        }
        _ =>
          Error({
            message: "Expected identifier as label after '@'",
            location: state.tokens[state.pos].location,
          })
      }
    }
    // 负向前瞻 !primary
    Symbol("!") => {
      state.pos = state.pos + 1
      match parse_primary(state) {
        Success(inner) => Success(Not(inner))
        Error(err) => Error(err)
      }
    }
    // 正向前瞻 &primary
    Symbol("&") => {
      state.pos = state.pos + 1
      match parse_primary(state) {
        Success(inner) => Success(And(inner))
        Error(err) => Error(err)
      }
    }
    // 任意字符 .
    Symbol(".") => {
      state.pos = state.pos + 1
      Success(AnyChar)
    }
    Keyword("prec") => {
      state.pos = state.pos + 1
      // 检查是否有 .kind 修饰
      let kind = if state.pos < state.tokens.length() {
        match state.tokens[state.pos].token {
          Symbol(".") => {
            state.pos = state.pos + 1
            if state.pos >= state.tokens.length() {
              return Error({
                message: "Expected 'left', 'right', or 'dynamic' after 'prec.'",
                location: state.tokens[state.tokens.length() - 1].location,
              })
            }
            match state.tokens[state.pos].token {
              Keyword("left") => {
                state.pos = state.pos + 1
                PrecKind::Left
              }
              Keyword("right") => {
                state.pos = state.pos + 1
                PrecKind::Right
              }
              Keyword("dynamic") => {
                state.pos = state.pos + 1
                PrecKind::Dynamic
              }
              _ =>
                return Error({
                  message: "Expected 'left', 'right', or 'dynamic' after 'prec.'",
                  location: state.tokens[state.pos].location,
                })
            }
          }
          _ => PrecKind::Nonassoc
        }
      } else {
        PrecKind::Nonassoc
      }
      // 消耗 (
      if state.pos >= state.tokens.length() {
        return Error({
          message: "Expected '(' after prec specifier",
          location: state.tokens[state.tokens.length() - 1].location,
        })
      }
      match state.tokens[state.pos].token {
        Symbol("(") => state.pos = state.pos + 1
        _ =>
          return Error({
            message: "Expected '(' after prec specifier",
            location: state.tokens[state.pos].location,
          })
      }
      // 读优先级数字
      if state.pos >= state.tokens.length() {
        return Error({
          message: "Expected precedence level number",
          location: state.tokens[state.tokens.length() - 1].location,
        })
      }
      let level = match state.tokens[state.pos].token {
        Identifier(n) =>
          match parse_int_str(n) {
            Some(v) => {
              state.pos = state.pos + 1
              v
            }
            None =>
              return Error({
                message: "Expected integer as precedence level",
                location: state.tokens[state.pos].location,
              })
          }
        _ =>
          return Error({
            message: "Expected precedence level number",
            location: state.tokens[state.pos].location,
          })
      }
      // 消耗 ,
      if state.pos >= state.tokens.length() {
        return Error({
          message: "Expected ',' after precedence level",
          location: state.tokens[state.tokens.length() - 1].location,
        })
      }
      match state.tokens[state.pos].token {
        Symbol(",") => state.pos = state.pos + 1
        _ =>
          return Error({
            message: "Expected ',' after precedence level",
            location: state.tokens[state.pos].location,
          })
      }
      // 解析内部模式
      match parse_pattern(state) {
        Error(err) => Error(err)
        Success(inner) => {
          if state.pos >= state.tokens.length() {
            return Error({
              message: "Expected ')' to close prec()",
              location: state.tokens[state.tokens.length() - 1].location,
            })
          }
          match state.tokens[state.pos].token {
            Symbol(")") => {
              state.pos = state.pos + 1
              Success(Prec(level, kind, inner))
            }
            _ =>
              Error({
                message: "Expected ')' to close prec()",
                location: state.tokens[state.pos].location,
              })
          }
        }
      }
    }
    // alias("name", pattern)
    Keyword("alias") => {
      state.pos = state.pos + 1
      if state.pos >= state.tokens.length() {
        return Error({
          message: "Expected '(' after 'alias'",
          location: state.tokens[state.tokens.length() - 1].location,
        })
      }
      match state.tokens[state.pos].token {
        Symbol("(") => {
          state.pos = state.pos + 1
          // Read alias name (string literal or identifier)
          if state.pos >= state.tokens.length() {
            return Error({
              message: "Expected alias name after 'alias('",
              location: state.tokens[state.tokens.length() - 1].location,
            })
          }
          let alias_name = match state.tokens[state.pos].token {
            StringLiteral(s) => s
            Identifier(name) => name
            _ =>
              return Error({
                message: "Expected string or identifier as alias name",
                location: state.tokens[state.pos].location,
              })
          }
          state.pos = state.pos + 1
          // Read ','
          if state.pos >= state.tokens.length() {
            return Error({
              message: "Expected ',' after alias name",
              location: state.tokens[state.tokens.length() - 1].location,
            })
          }
          match state.tokens[state.pos].token {
            Symbol(",") => state.pos = state.pos + 1
            _ =>
              return Error({
                message: "Expected ',' after alias name",
                location: state.tokens[state.pos].location,
              })
          }
          // Read inner pattern
          match parse_pattern(state) {
            Error(err) => Error(err)
            Success(inner) => {
              // Read ')'
              if state.pos >= state.tokens.length() {
                return Error({
                  message: "Expected ')' to close alias()",
                  location: state.tokens[state.tokens.length() - 1].location,
                })
              }
              match state.tokens[state.pos].token {
                Symbol(")") => {
                  state.pos = state.pos + 1
                  Success(Alias(alias_name, inner))
                }
                _ =>
                  Error({
                    message: "Expected ')' to close alias()",
                    location: state.tokens[state.pos].location,
                  })
              }
            }
          }
        }
        _ =>
          Error({
            message: "Expected '(' after 'alias'",
            location: state.tokens[state.pos].location,
          })
      }
    }
    _ =>
      Error({
        message: "Unexpected token in pattern",
        location: state.tokens[state.pos].location,
      })
  }
}

///|
/// 解析 `extras [pattern, pattern, ...]` 声明
/// 'extras' 关键字已被调用方消费，当前 token 应为 '['
fn parse_extras(state : ParserState) -> ParseResult[Array[Pattern]] {
  // 消耗 '['
  if state.pos >= state.tokens.length() {
    return Error({
      message: "Expected '[' after 'extras'",
      location: state.tokens[state.tokens.length() - 1].location,
    })
  }
  match state.tokens[state.pos].token {
    Symbol("[") => state.pos = state.pos + 1
    _ =>
      return Error({
        message: "Expected '[' after 'extras'",
        location: state.tokens[state.pos].location,
      })
  }
  let patterns : Array[Pattern] = []
  // 解析逗号分隔的 pattern 列表直到 ']'
  while state.pos < state.tokens.length() {
    match state.tokens[state.pos].token {
      Symbol("]") => {
        state.pos = state.pos + 1
        return Success(patterns)
      }
      Symbol(",") => state.pos = state.pos + 1
      _ =>
        match parse_pattern(state) {
          Success(p) => patterns.push(p)
          Error(err) => return Error(err)
        }
    }
  }
  Error({
    message: "Unexpected end of input, expected ']' to close 'extras'",
    location: state.tokens[state.tokens.length() - 1].location,
  })
}

///|
/// 解析 `externals [name1, name2, ...]` 声明
/// 'externals' 关键字已被调用方消费，当前 token 应为 '['
fn parse_externals(state : ParserState) -> ParseResult[Array[String]] {
  // 消耗 '['
  if state.pos >= state.tokens.length() {
    return Error({
      message: "Expected '[' after 'externals'",
      location: state.tokens[state.tokens.length() - 1].location,
    })
  }
  match state.tokens[state.pos].token {
    Symbol("[") => state.pos = state.pos + 1
    _ =>
      return Error({
        message: "Expected '[' after 'externals'",
        location: state.tokens[state.pos].location,
      })
  }
  let names : Array[String] = []
  // 解析逗号分隔的标识符列表直到 ']'
  while state.pos < state.tokens.length() {
    match state.tokens[state.pos].token {
      Symbol("]") => {
        state.pos = state.pos + 1
        return Success(names)
      }
      Symbol(",") => state.pos = state.pos + 1
      Identifier(name) => {
        names.push(name)
        state.pos = state.pos + 1
      }
      _ =>
        return Error({
          message: "Expected identifier or ']' in externals declaration",
          location: state.tokens[state.pos].location,
        })
    }
  }
  Error({
    message: "Unexpected end of input, expected ']' to close 'externals'",
    location: state.tokens[state.tokens.length() - 1].location,
  })
}

///|
/// 解析 conflicts 声明：`conflicts [[rule_a, rule_b], [rule_c, rule_d]]`
/// 返回规则名组的列表（每组对应一个嵌套列表）
fn parse_conflicts(state : ParserState) -> ParseResult[Array[Array[String]]] {
  if state.pos >= state.tokens.length() {
    return Error({
      message: "Expected '[' after 'conflicts'",
      location: state.tokens[state.tokens.length() - 1].location,
    })
  }
  // 消耗外层 '['
  match state.tokens[state.pos].token {
    Symbol("[") => state.pos = state.pos + 1
    _ =>
      return Error({
        message: "Expected '[' after 'conflicts'",
        location: state.tokens[state.pos].location,
      })
  }
  let groups : Array[Array[String]] = []
  while state.pos < state.tokens.length() {
    match state.tokens[state.pos].token {
      Symbol("]") => {
        state.pos = state.pos + 1
        return Success(groups)
      }
      Symbol(",") => state.pos = state.pos + 1
      // 内层 '[' — 解析一个规则名组
      Symbol("[") => {
        state.pos = state.pos + 1
        let group : Array[String] = []
        while state.pos < state.tokens.length() {
          match state.tokens[state.pos].token {
            Symbol("]") => {
              state.pos = state.pos + 1
              break
            }
            Symbol(",") => state.pos = state.pos + 1
            Identifier(name) => {
              group.push(name)
              state.pos = state.pos + 1
            }
            _ =>
              return Error({
                message: "Expected rule name or ']' in conflicts group",
                location: state.tokens[state.pos].location,
              })
          }
        }
        groups.push(group)
      }
      _ =>
        return Error({
          message: "Expected '[' or ']' in conflicts declaration",
          location: state.tokens[state.pos].location,
        })
    }
  }
  Error({
    message: "Unexpected end of input, expected ']' to close 'conflicts'",
    location: state.tokens[state.tokens.length() - 1].location,
  })
}

///|
/// 解析简单标识符列表：`keyword [name1, name2, ...]`
/// 用于 supertypes 等声明（重用，避免重复代码）
fn parse_name_list(
  state : ParserState,
  keyword : String,
) -> ParseResult[Array[String]] {
  if state.pos >= state.tokens.length() {
    return Error({
      message: "Expected '[' after '\{keyword}'",
      location: state.tokens[state.tokens.length() - 1].location,
    })
  }
  match state.tokens[state.pos].token {
    Symbol("[") => state.pos = state.pos + 1
    _ =>
      return Error({
        message: "Expected '[' after '\{keyword}'",
        location: state.tokens[state.pos].location,
      })
  }
  let names : Array[String] = []
  while state.pos < state.tokens.length() {
    match state.tokens[state.pos].token {
      Symbol("]") => {
        state.pos = state.pos + 1
        return Success(names)
      }
      Symbol(",") => state.pos = state.pos + 1
      Identifier(name) => {
        names.push(name)
        state.pos = state.pos + 1
      }
      _ =>
        return Error({
          message: "Expected identifier or ']' in '\{keyword}' declaration",
          location: state.tokens[state.pos].location,
        })
    }
  }
  Error({
    message: "Unexpected end of input, expected ']' to close '\{keyword}'",
    location: state.tokens[state.tokens.length() - 1].location,
  })
}
