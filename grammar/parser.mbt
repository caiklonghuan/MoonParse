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

// 公开入口

///|
/// 解析 Grammar DSL 字符串，返回完整的 Grammar 对象
pub fn parse_grammar(dsl : String) -> ParseResult[Grammar] {
  let tokens = tokenize(dsl)
  let state = { tokens, pos: 0 }
  let grammar : Grammar = {
    start: None,
    rules: Map::new(),
    precedences: [],
    extras: [],
  }

  while state.pos < state.tokens.length() {
    match state.tokens[state.pos].token {
      Keyword("rule") => {
        state.pos = state.pos + 1
        match parse_rule(state) {
          Success(rule) => grammar.rules.set(rule.name, rule)
          Error(err) => return Error(err)
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
            _ =>
              return Error({
                message: "Expected identifier after 'start'",
                location: state.tokens[state.pos].location,
              })
          }
        } else {
          return Error({
            message: "Unexpected end of input after 'start'",
            location: state.tokens[state.tokens.length() - 1].location,
          })
        }
      }
      // 优先级声明：记录到 grammar.precedences
      Keyword("precedence") => {
        state.pos = state.pos + 1
        let level = grammar.precedences.length() + 1
        match parse_prec_decl(state, level) {
          Success(decl) => grammar.precedences.push(decl)
          Error(err) => return Error(err)
        }
      }
      // extras 声明：extras [pattern, ...]
      Keyword("extras") => {
        state.pos = state.pos + 1
        match parse_extras(state) {
          Success(patterns) =>
            for p in patterns {
              grammar.extras.push(p)
            }
          Error(err) => return Error(err)
        }
      }
      _ => state.pos = state.pos + 1
    }
  }
  Success(grammar)
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
      Identifier("dynamic") => {
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
/// 解析单条规则：`rule name: pattern`
fn parse_rule(state : ParserState) -> ParseResult[Rule] {
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
      match state.tokens[state.pos].token {
        Symbol(":") => {
          state.pos = state.pos + 1
          let is_named = name.length() == 0 || name[0] != '_'
          match parse_pattern(state) {
            Success(pattern) =>
              Success({ name, pattern, is_named, location: Some(name_loc) })
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
    // 标识符：下一个 token 为 `:` 则是命名字段，否则是规则引用
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
    // 内联优先级标注 prec(...) / prec.left(...) / prec.right(...) / prec.dynamic(...)
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
              Identifier("dynamic") => {
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

// extras 解析

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
