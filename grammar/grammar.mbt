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
  /// 可选 (零或一次)
  Optional(Pattern)
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

// 3. 词法分析器
/// 将输入字符串转换为 Token 序列
/// 支持标识符、字符串字面量、正则表达式、符号和关键字的识别
/// 
/// 参数:
/// - input: 要进行词法分析的输入字符串
/// 
/// 返回值:
/// - Array[Token]: 词法分析后的标记序列
fn tokenize(input : String) -> Array[Token] {
  let tokens : Array[Token] = [] 
  let mut i = 0
  let len = input.length()
  
  while i < len {
    let c : Char = input[i].to_int().to_char().unwrap() 
    
    match c {
      ' ' | '\t' | '\n' | '\r' => i = i + 1
      
      '/' => {
        // 检查是否是注释
        if i + 1 < len {
          let next_c = input[i + 1].to_int().to_char().unwrap()
          if next_c == '/' {
            // 行注释：跳过到行尾
            i = i + 2  // 跳过 //
            while i < len && input[i].to_int().to_char().unwrap() != '\n' { i = i + 1 }
            if i < len { i = i + 1 }  // 跳过换行符
            continue
          } else if next_c == '*' {
            // 块注释：跳过到 */
            i = i + 2  // 跳过 /*
            while i + 1 < len {
              if input[i].to_int().to_char().unwrap() == '*' && input[i + 1].to_int().to_char().unwrap() == '/' {
                i = i + 2  // 跳过 */
                break
              }
              i = i + 1
            }
            continue
          }
        }
        // 正则表达式处理
        let mut j = i + 1
        while j < len && input[j].to_int().to_char().unwrap() != '/' { j = j + 1 }
        if j < len {
          let regex = input.substring(start=i + 1, end=j)
          tokens.push(Token::RegexLiteral(regex))
          i = j + 1
        } else { i = i + 1 }
      }
      
      '"' => {
        let mut j = i + 1
        while j < len && input[j].to_int().to_char().unwrap() != '"' { j = j + 1 }
        if j < len {
          let literal = input.substring(start=i + 1, end=j)
          tokens.push(Token::StringLiteral(literal))
          i = j + 1
        } else { i = i + 1 }
      }
      
      ':' | '|' | '*' | '+' | '?' | '(' | ')' | '@' => {
        tokens.push(Token::Symbol(c.to_string()))
        i = i + 1
      }
      
      _ => {
        if is_whitespace(c) { 
          i = i + 1
          continue 
        }
        let mut j = i
        while j < len {
          let c_j = input[j].to_int().to_char().unwrap()
          if is_whitespace(c_j) || is_symbol(c_j) { break }
          j = j + 1
        }
        if i == j {
          i = i + 1
          continue
        }
        let word = input.substring(start=i, end=j)
        if word == "rule" || word == "start" || word == "precedence" || word == "left" || word == "right" {
          tokens.push(Token::Keyword(word))
        } else {
          tokens.push(Token::Identifier(word))
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
  match c { ':' | '|' | '*' | '+' | '?' | '(' | ')' | '"' | '/' | '@' => true; _ => false }
}

// 4. 解析器状态
/// ParserState 表示解析过程中的状态信息
/// 包含 Token 序列和当前解析位置
struct ParserState {
  /// Token 序列
  tokens : Array[Token]
  /// 当前解析位置（可变）
  mut pos : Int
}

/// 解析 Grammar DSL 字符串，返回 Grammar 对象
/// 支持多行规则定义和起始规则声明
/// 
/// 参数:
/// - dsl: 包含语法规则的字符串
/// 
/// 返回值:
/// - Grammar: 解析后的语法定义对象
/// 
pub fn parse_grammar(dsl : String) -> Grammar {
  let tokens = tokenize(dsl)
  let state = { tokens, pos: 0 }
  let rules : Map[String, Rule] = Map::new()
  let grammar = { start: None, rules }
  
  /// 主解析循环：处理所有 Token
  while state.pos < state.tokens.length() {
    match state.tokens[state.pos] {
      /// 处理规则定义
      Keyword("rule") => {
        state.pos = state.pos + 1
        let rule = parse_rule(state)
        grammar.rules.set(rule.name, rule)
      }
      /// 处理起始规则声明
      Keyword("start") => {
        state.pos = state.pos + 1
        match state.tokens[state.pos] {
          Identifier(name) => {
            grammar.start = Some(name)
            state.pos = state.pos + 1
          }
          _ => ()
        }
      }
      /// 处理优先级声明（暂未实现，跳过）
      Keyword("precedence") => {
        state.pos = state.pos + 1
        // 跳过优先级声明的所有参数，直到下一个规则或声明
        while state.pos < state.tokens.length() {
          match state.tokens[state.pos] {
            Keyword("rule") | Keyword("start") | Keyword("precedence") => break
            _ => state.pos = state.pos + 1
          }
        }
      }
      /// 跳过其他 Token
      _ => state.pos = state.pos + 1
    }
  }
  grammar
}

/// 解析单个规则定义
/// 格式: rule name: pattern
/// 
/// 参数:
/// - state: 当前解析状态
/// 
/// 返回值:
/// - Rule: 解析后的规则对象
fn parse_rule(state : ParserState) -> Rule {
  match state.tokens[state.pos] {
    /// 解析规则名称
    Identifier(name) => {
      state.pos = state.pos + 1
      match state.tokens[state.pos] {
        /// 期望冒号分隔符
        Symbol(":") => {
          state.pos = state.pos + 1
          let pattern = parse_pattern(state)
          { name, pattern }
        }
        /// 错误处理：缺少冒号
        _ => { name, pattern: RuleRef("error") }
      }
    }
    /// 错误处理：无效规则名称
    _ => { name: "unknown", pattern: RuleRef("error") }
  }
}

/// 解析模式，支持选择操作 A | B | C
/// 处理优先级：选择 > 序列
/// 
/// 参数:
/// - state: 当前解析状态
/// 
/// 返回值:
/// - Pattern: 解析后的模式对象
fn parse_pattern(state : ParserState) -> Pattern {
  let first = parse_sequence(state)
  let choices = [first]
  
  /// 处理选择操作符 |
  while state.pos < state.tokens.length() {
    match state.tokens[state.pos] {
      Symbol("|") => {
        state.pos = state.pos + 1
        choices.push(parse_sequence(state))
      }
      _ => break
    }
  }
  
  /// 如果只有一个选择，返回单个模式；否则返回选择模式
  if choices.length() == 1 { choices[0] } else { Choice(choices) }
}

/// 解析序列模式，支持连续的模式 A B C
/// 处理优先级：序列 > 一元操作
/// 
/// 参数:
/// - state: 当前解析状态
/// 
/// 返回值:
/// - Pattern: 解析后的模式对象
fn parse_sequence(state : ParserState) -> Pattern {
  let seqs = []
  
  /// 收集连续的模式
  while state.pos < state.tokens.length() {
    match state.tokens[state.pos] {
      Identifier(_) | StringLiteral(_) | RegexLiteral(_) | Symbol("(") => {
        seqs.push(parse_unary(state))
      }
      _ => break
    }
  }
  
  /// 如果只有一个模式，返回单个模式；否则返回序列模式
  if seqs.length() == 1 { seqs[0] } else { Seq(seqs) }
}

/// 解析一元操作，支持重复 * + 和可选 ?
/// 处理优先级：一元操作 > 原子模式
/// 
/// 参数:
/// - state: 当前解析状态
/// 
/// 返回值:
/// - Pattern: 解析后的模式对象
fn parse_unary(state : ParserState) -> Pattern {
  let pattern = parse_primary(state)
  if state.pos < state.tokens.length() {
    match state.tokens[state.pos] {
      /// 零或多次重复
      Symbol("*") => { state.pos = state.pos + 1; Repeat(pattern) }
      /// 一或多次重复（转换为 pattern + pattern*）
      Symbol("+") => { 
        state.pos = state.pos + 1; 
        // + 等价于 Pattern 后面跟着一个 *
        Seq([pattern, Repeat(pattern)]) 
      }
      /// 可选（零或一次）
      Symbol("?") => { state.pos = state.pos + 1; Optional(pattern) }
      /// 无一元操作符
      _ => pattern
    }
  } else { pattern }
}

/// 解析基本模式（原子模式）
/// 包括：规则引用、字面量、正则、分组、语义动作（暂未实现）
/// 
/// 参数:
/// - state: 当前解析状态
/// 
/// 返回值:
/// - Pattern: 解析后的原子模式对象
fn parse_primary(state : ParserState) -> Pattern {
  if state.pos >= state.tokens.length() { return RuleRef("EOF") }
  
  match state.tokens[state.pos] {
    /// 规则引用
    Identifier(name) => { state.pos = state.pos + 1; RuleRef(name) }
    /// 字符串字面量
    StringLiteral(lit) => { state.pos = state.pos + 1; Literal(lit) }
    /// 正则表达式
    RegexLiteral(re) => { state.pos = state.pos + 1; Regex(re) }
    /// 分组表达式
    Symbol("(") => {
      state.pos = state.pos + 1
      let inner = parse_pattern(state)
      if state.pos < state.tokens.length() {
        match state.tokens[state.pos] {
          Symbol(")") => state.pos = state.pos + 1
          _ => () // 这里实际应处理缺少括号的错误
        }
      }
      inner
    }
    /// 语义动作（暂未实现，跳过@符号）
    Symbol("@") => {
      state.pos = state.pos + 1
      // 跳过语义动作名称，继续解析实际模式
      if state.pos < state.tokens.length() {
        match state.tokens[state.pos] {
          Identifier(_) => state.pos = state.pos + 1
          _ => ()
        }
      }
      // 递归解析实际的模式
      parse_primary(state)
    }
    /// 错误处理
    _ => { 
      state.pos = state.pos + 1
      RuleRef("error") 
    }
  }
}

