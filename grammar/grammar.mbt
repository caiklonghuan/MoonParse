// 1. 数据结构
/// Pattern 表示语法规则中的模式类型
/// 支持规则引用、字面量、正则表达式、选择、序列、重复、可选等
pub(all) enum Pattern {
  /// 规则引用
  RuleRef(String)
  /// 字面量字符串
  Literal(String)
  /// 正则表达式
  Regex(String)
  /// 选择分支
  Choice(Array[Pattern])
  /// 序列
  Seq(Array[Pattern])
  /// 重复 (零或多次)
  Repeat(Pattern)
  /// 重复 (一或多次)
  Plus(Pattern)
  /// 可选 (零或一次)
  Optional(Pattern)
  /// 新增：语义动作标签，例如 @name pattern
  Tagged(String, Pattern)
}

/// Rule 表示一个语法规则，包含名称和对应的模式
pub(all) struct Rule {
  /// 规则名称
  name : String
  /// 规则的模式定义
  pattern : Pattern
}

/// Grammar 表示整个语法定义，包含起始规则和规则映射
pub(all) struct Grammar {
  /// 起始规则名称
  mut start : String?
  /// 规则名称到规则的映射
  rules : Map[String, Rule]
}

// 2.1 Pattern 的字符串转换方法
/// 为 Pattern 实现字符串转换，处理优先级并自动添加必要的括号
pub fn pattern_to_string(pattern : Pattern) -> String {
  match pattern {
    /// 规则引用直接返回名称
    RuleRef(name) => name
    
    /// 字面量带引号
    Literal(str) => "\"" + str + "\""
    
    /// 正则表达式带斜杠
    Regex(re) => "/" + re + "/"
    
    /// 语义动作/标签模式：显示为 @label pattern
    /// 如果子模式是复杂模式（Seq 或 Choice），建议加括号以清晰表达范围
    Tagged(label, p) => {
      let inner = match p {
        Seq(_) | Choice(_) => "(" + pattern_to_string(p) + ")"
        _ => pattern_to_string(p)
      }
      "@" + label + " " + inner
    }
    
    /// 选择分支：A | B | C
    Choice(patterns) => {
      let mut result = ""
      for i in 0..<patterns.length() {
        if i > 0 {
          result = result + " | "
        }
        result = result + pattern_to_string(patterns[i])
      }
      result
    }
    
    /// 序列模式：A B C
    Seq(patterns) => {
      let mut result = ""
      for i in 0..<patterns.length() {
        if i > 0 {
          result = result + " "
        }
        /// 关键逻辑：如果序列中嵌套了 Choice，必须加括号
        /// 否则 A (B | C) 会变成 A B | C，语义发生变化
        let p_str = match patterns[i] {
          Choice(_) => "(" + pattern_to_string(patterns[i]) + ")"
          _ => pattern_to_string(patterns[i])
        }
        result = result + p_str
      }
      result
    }
    
    /// 重复模式：A*
    /// 如果内部是 Seq 或 Choice，加括号确保后缀操作符作用于整体
    Repeat(p) => {
      let inner = match p {
        Seq(_) | Choice(_) => "(" + pattern_to_string(p) + ")"
        _ => pattern_to_string(p)
      }
      inner + "*"
    }
    
    /// 一或多次：A+
    Plus(p) => {
      let inner = match p {
        Seq(_) | Choice(_) => "(" + pattern_to_string(p) + ")"
        _ => pattern_to_string(p)
      }
      inner + "+"
    }
    
    /// 可选模式：A?
    Optional(p) => {
      let inner = match p {
        Seq(_) | Choice(_) => "(" + pattern_to_string(p) + ")"
        _ => pattern_to_string(p)
      }
      inner + "?"
    }
  }
}

/// 绑定到 Pattern 类型上，方便调用 pattern.to_string()
pub fn Pattern::to_string(self : Pattern) -> String {
  pattern_to_string(self)
}
// 2. Token 类型
/// Token 表示词法分析后的标记类型
enum Token {
  /// 标识符
  Identifier(String)
  /// 字符串字面量
  StringLiteral(String)
  /// 正则表达式字面量
  RegexLiteral(String)
  /// 符号
  Symbol(String)
  /// 关键字
  Keyword(String)
}

// 2.5 位置信息
/// SourceLocation 表示源代码中的位置信息
pub(all) struct SourceLocation {
  /// 行号（从1开始）
  line : Int
  /// 列号（从1开始）
  column : Int
}

/// TokenWithLocation 表示带有位置信息的 Token
pub(all) struct TokenWithLocation {
  /// Token 内容
  token : Token
  /// 位置信息
  location : SourceLocation
}

// 3. 词法分析器
/// 将输入字符串转换为 Token 序列
/// 支持标识符、字符串字面量、正则表达式、符号和关键字的识别
/// 
/// 参数:
/// - input: 要进行词法分析的输入字符串
/// 
/// 返回值:
/// - Array[TokenWithLocation]: 带有位置信息的词法分析标记序列
fn tokenize(input : String) -> Array[TokenWithLocation] {
  let tokens : Array[TokenWithLocation] = [] 
  let mut i = 0
  let len = input.length()
  let mut line = 1
  let mut column = 1
  
  while i < len {
    let c : Char = input[i].to_int().to_char().unwrap() 
    
    match c {
      ' ' | '\t' => { 
        column = column + 1
        i = i + 1
      }
      '\n' => {
        line = line + 1
        column = 1
        i = i + 1
      }
      '\r' => i = i + 1  // 跳过 \r
      
      '/' => {
        // 检查是否是注释
        if i + 1 < len {
          let next_c = input[i + 1].to_int().to_char().unwrap()
          if next_c == '/' {
            // 行注释：跳过到行尾
            i = i + 2  // 跳过 //
            column = column + 2
            while i < len && input[i].to_int().to_char().unwrap() != '\n' { 
              i = i + 1
              column = column + 1
            }
            if i < len { 
              i = i + 1  // 跳过换行符
              line = line + 1
              column = 1
            }
            continue
          } else if next_c == '*' {
            // 块注释：跳过到 */
            i = i + 2  // 跳过 /*
            column = column + 2
            while i + 1 < len {
              if input[i].to_int().to_char().unwrap() == '*' && input[i + 1].to_int().to_char().unwrap() == '/' {
                i = i + 2  // 跳过 */
                column = column + 2
                break
              }
              if input[i].to_int().to_char().unwrap() == '\n' {
                line = line + 1
                column = 1
              } else {
                column = column + 1
              }
              i = i + 1
            }
            continue
          }
        }
        // 正则表达式处理
        let start_col = column
        let mut j = i + 1
        column = column + 1
        while j < len && input[j].to_int().to_char().unwrap() != '/' { 
          if input[j].to_int().to_char().unwrap() == '\n' {
            line = line + 1
            column = 1
          } else {
            column = column + 1
          }
          j = j + 1
        }
        if j < len {
          let regex = input.substring(start=i + 1, end=j)
          tokens.push({ token: Token::RegexLiteral(regex), location: { line, column: start_col } })
          i = j + 1
          column = column + 1
        } else { 
          i = i + 1
          column = column + 1
        }
      }
      
      '"' => {
        let start_col = column
        let mut j = i + 1
        column = column + 1
        let mut escaped = false
        while j < len {
          let c_j = input[j].to_int().to_char().unwrap()
          if escaped {
            escaped = false
          } else if c_j == '\\' {
            escaped = true
          } else if c_j == '"' {
            break
          }
          if c_j == '\n' {
            line = line + 1
            column = 1
          } else {
            column = column + 1
          }
          j = j + 1
        }
        if j < len {
          let literal = input.substring(start=i + 1, end=j)
          tokens.push({ token: Token::StringLiteral(literal), location: { line, column: start_col } })
          i = j + 1
          column = column + 1
        } else { 
          i = i + 1
          column = column + 1
        }
      }
      
      ':' | '|' | '*' | '+' | '?' | '(' | ')' | '@' => {
        tokens.push({ token: Token::Symbol(c.to_string()), location: { line, column } })
        i = i + 1
        column = column + 1
      }
      
      _ => {
        if is_whitespace(c) { 
          i = i + 1
          column = column + 1
          continue 
        }
        let start_col = column
        let mut j = i
        while j < len {
          let c_j = input[j].to_int().to_char().unwrap()
          if is_whitespace(c_j) || is_symbol(c_j) { break }
          if c_j == '\n' {
            line = line + 1
            column = 1
          } else {
            column = column + 1
          }
          j = j + 1
        }
        if i == j {
          i = i + 1
          column = column + 1
          continue
        }
        let word = input.substring(start=i, end=j)
        if word == "rule" || word == "start" || word == "precedence" || word == "left" || word == "right" {
          tokens.push({ token: Token::Keyword(word), location: { line, column: start_col } })
        } else {
          tokens.push({ token: Token::Identifier(word), location: { line, column: start_col } })
        }
        i = j
      }
    }
  }
  tokens
}
/// 判断字符是否为空白字符
/// 
/// 参数:
/// - c: 要判断的字符
/// 
/// 返回值:
/// - Bool: 如果是空白字符返回 true，否则 false
fn is_whitespace(c : Char) -> Bool {
  match c { ' ' | '\t' | '\n' | '\r' => true; _ => false }
}

/// 判断字符是否为语法符号
/// 
/// 参数:
/// - c: 要判断的字符
/// 
/// 返回值:
/// - Bool: 如果是语法符号返回 true，否则 false
fn is_symbol(c : Char) -> Bool {
  match c { ':' | '|' | '*' | '+' | '?' | '(' | ')' | '"' | '/' | '@' | '\\' => true; _ => false }
}

// 4. 解析器状态
/// ParserState 表示解析过程中的状态信息
/// 包含 Token 序列和当前解析位置
struct ParserState {
  /// Token 序列
  tokens : Array[TokenWithLocation]
  /// 当前解析位置（可变）
  mut pos : Int
}

/// 解析错误信息
pub(all) struct ParseError {
  /// 错误消息
  message : String
  /// 错误位置
  location : SourceLocation
}

/// 解析结果类型
pub(all) enum ParseResult[T] {
  /// 成功
  Success(T)
  /// 错误
  Error(ParseError)
}

/// 解析 Grammar DSL 字符串，返回 Grammar 对象
/// 支持多行规则定义和起始规则声明
/// 
/// 参数:
/// - dsl: 包含语法规则的字符串
/// 
/// 返回值:
/// - ParseResult[Grammar]: 解析结果，成功返回 Grammar，失败返回错误信息
/// 
pub fn parse_grammar(dsl : String) -> ParseResult[Grammar] {
  let tokens = tokenize(dsl)
  let state = { tokens, pos: 0 }
  let rules : Map[String, Rule] = Map::new()
  let grammar = { start: None, rules }
  
  /// 主解析循环：处理所有 Token
  while state.pos < state.tokens.length() {
    match state.tokens[state.pos].token {
      /// 处理规则定义
      Keyword("rule") => {
        state.pos = state.pos + 1
        match parse_rule(state) {
          Success(rule) => {
            grammar.rules.set(rule.name, rule)
          }
          Error(err) => return Error(err)
        }
      }
      /// 处理起始规则声明
      Keyword("start") => {
        state.pos = state.pos + 1
        if state.pos < state.tokens.length() {
          match state.tokens[state.pos].token {
            Identifier(name) => {
              grammar.start = Some(name)
              state.pos = state.pos + 1
            }
            _ => return Error({
              message: "Expected identifier after 'start'",
              location: state.tokens[state.pos].location
            })
          }
        } else {
          return Error({
            message: "Unexpected end of input after 'start'",
            location: state.tokens[state.tokens.length() - 1].location
          })
        }
      }
      /// 处理优先级声明（暂未实现，跳过）
      Keyword("precedence") => {
        state.pos = state.pos + 1
        // 跳过优先级声明的所有参数，直到下一个规则或声明
        while state.pos < state.tokens.length() {
          match state.tokens[state.pos].token {
            Keyword("rule") | Keyword("start") | Keyword("precedence") => break
            _ => state.pos = state.pos + 1
          }
        }
      }
      /// 跳过其他 Token
      _ => state.pos = state.pos + 1
    }
  }
  Success(grammar)
}

/// 解析单个规则定义
/// 格式: rule name: pattern
/// 
/// 参数:
/// - state: 当前解析状态
/// 
/// 返回值:
/// - ParseResult[Rule]: 解析结果，成功返回规则，失败返回错误信息
fn parse_rule(state : ParserState) -> ParseResult[Rule] {
  if state.pos >= state.tokens.length() {
    return Error({
      message: "Unexpected end of input, expected rule name",
      location: state.tokens[state.tokens.length() - 1].location
    })
  }
  
  match state.tokens[state.pos].token {
    /// 解析规则名称
    Identifier(name) => {
      let name_location = state.tokens[state.pos].location
      state.pos = state.pos + 1
      if state.pos >= state.tokens.length() {
        return Error({
          message: "Unexpected end of input, expected ':' after rule name",
          location: name_location
        })
      }
      match state.tokens[state.pos].token {
        /// 期望冒号分隔符
        Symbol(":") => {
          state.pos = state.pos + 1
          match parse_pattern(state) {
            Success(pattern) => Success({ name, pattern })
            Error(err) => Error(err)
          }
        }
        /// 错误处理：缺少冒号
        _ => Error({
          message: "Expected ':' after rule name",
          location: state.tokens[state.pos].location
        })
      }
    }
    /// 错误处理：无效规则名称
    _ => Error({
      message: "Expected identifier for rule name",
      location: state.tokens[state.pos].location
    })
  }
}

/// 解析模式，支持选择操作 A | B | C
/// 处理优先级：选择 > 序列
/// 
/// 参数:
/// - state: 当前解析状态
/// 
/// 返回值:
/// - ParseResult[Pattern]: 解析结果，成功返回模式，失败返回错误信息
fn parse_pattern(state : ParserState) -> ParseResult[Pattern] {
  match parse_sequence(state) {
    Success(first) => {
      let choices = [first]
      
      /// 处理选择操作符 |
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
      
      /// 如果只有一个选择，返回单个模式；否则返回选择模式
      if choices.length() == 1 { Success(choices[0]) } else { Success(Choice(choices)) }
    }
    Error(err) => Error(err)
  }
}

/// 解析序列模式，支持连续的模式 A B C
/// 处理优先级：序列 > 一元操作
/// 
/// 参数:
/// - state: 当前解析状态
/// 
/// 返回值:
/// - ParseResult[Pattern]: 解析结果，成功返回模式，失败返回错误信息
fn parse_sequence(state : ParserState) -> ParseResult[Pattern] {
  let seqs = []
  let mut has_error = false
  let mut error = { message: "", location: { line: 0, column: 0 } }
  
  /// 收集连续的模式
  while state.pos < state.tokens.length() {
    match state.tokens[state.pos].token {
      Identifier(_) | StringLiteral(_) | RegexLiteral(_) | Symbol("(") | Symbol("@") => {
        match parse_unary(state) {
          Success(pattern) => seqs.push(pattern)
          Error(err) => {
            has_error = true
            error = err
            break
          }
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

/// 解析一元操作，支持重复 * + 和可选 ?
/// 处理优先级：一元操作 > 原子模式
/// 
/// 参数:
/// - state: 当前解析状态
/// 
/// 返回值:
/// - ParseResult[Pattern]: 解析结果，成功返回模式，失败返回错误信息
fn parse_unary(state : ParserState) -> ParseResult[Pattern] {
  match parse_primary(state) {
    Success(pattern) => {
      if state.pos < state.tokens.length() {
        match state.tokens[state.pos].token {
          /// 零或多次重复
          Symbol("*") => { 
            state.pos = state.pos + 1
            Success(Repeat(pattern))
          }
          /// 一或多次重复
          Symbol("+") => { 
            state.pos = state.pos + 1
            Success(Plus(pattern))
          }
          /// 可选（零或一次）
          Symbol("?") => { 
            state.pos = state.pos + 1
            Success(Optional(pattern))
          }
          /// 无一元操作符
          _ => Success(pattern)
        }
      } else { 
        Success(pattern)
      }
    }
    Error(err) => Error(err)
  }
}

/// 解析基本模式（原子模式）
/// 包括：规则引用、字面量、正则、分组、语义动作
/// 
/// 参数:
/// - state: 当前解析状态
/// 
/// 返回值:
/// - ParseResult[Pattern]: 解析结果，成功返回原子模式，失败返回错误信息
fn parse_primary(state : ParserState) -> ParseResult[Pattern] {
  if state.pos >= state.tokens.length() { 
    return Error({
      message: "Unexpected end of input",
      location: state.tokens[state.tokens.length() - 1].location
    })
  }
  
  match state.tokens[state.pos].token {
    /// 规则引用
    Identifier(name) => { 
      state.pos = state.pos + 1
      Success(RuleRef(name))
    }
    /// 字符串字面量
    StringLiteral(lit) => { 
      state.pos = state.pos + 1
      Success(Literal(lit))
    }
    /// 正则表达式
    RegexLiteral(re) => { 
      state.pos = state.pos + 1
      Success(Regex(re))
    }
    /// 分组表达式
    Symbol("(") => {
      state.pos = state.pos + 1
      match parse_pattern(state) {
        Success(inner) => {
          if state.pos < state.tokens.length() {
            match state.tokens[state.pos].token {
              Symbol(")") => {
                state.pos = state.pos + 1
                Success(inner)
              }
              _ => Error({
                message: "Expected ')' to close group",
                location: state.tokens[state.pos].location
              })
            }
          } else {
            Error({
              message: "Unexpected end of input, expected ')'",
              location: state.tokens[state.tokens.length() - 1].location
            })
          }
        }
        Error(err) => Error(err)
      }
    }
    /// 语义动作：@label pattern
    Symbol("@") => {
      state.pos = state.pos + 1
      if state.pos >= state.tokens.length() {
        return Error({
          message: "Expected label name after '@'",
          location: state.tokens[state.tokens.length() - 1].location
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
        _ => Error({
          message: "Expected identifier as label after '@'",
          location: state.tokens[state.pos].location
        })
      }
    }
    /// 错误处理
    _ => Error({
      message: "Unexpected token in pattern",
      location: state.tokens[state.pos].location
    })
  }
}

