///|
/// Token 为词法单元类型（包内私有）
enum Token {
  /// 标识符（含数字串，如 {3} 中的 "3"）
  Identifier(String)
  /// 双引号字符串字面量
  StringLiteral(String)
  /// 正斜杠正则表达式字面量
  RegexLiteral(String)
  /// 单字符符号（: | * + ? ( ) @ ! & . { } ,）
  Symbol(String)
  /// 保留关键字（rule / start / precedence / left / right）
  Keyword(String)
}

///|
/// 源码位置（行列号均从 1 开始）
pub(all) struct SourceLocation {
  line : Int
  column : Int
}

///|
/// 携带位置信息的词法单元
pub(all) struct TokenWithLocation {
  token : Token
  location : SourceLocation
}

///|
/// 将源码字符串转换为带位置信息的 Token 序列
/// 自动跳过空白、行注释（//）和块注释（/* */）
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
      '\r' => i = i + 1
      '/' => {
        if i + 1 < len {
          let next_c = input[i + 1].to_int().to_char().unwrap()
          if next_c == '/' {
            // 行注释：跳到行尾
            i = i + 2
            column = column + 2
            while i < len && input[i].to_int().to_char().unwrap() != '\n' {
              i = i + 1
              column = column + 1
            }
            if i < len {
              i = i + 1
              line = line + 1
              column = 1
            }
            continue
          } else if next_c == '*' {
            // 块注释：跳到 */
            let block_start_line = line
            let block_start_col = column
            i = i + 2
            column = column + 2
            let mut closed = false
            while i + 1 < len {
              if input[i].to_int().to_char().unwrap() == '*' &&
                input[i + 1].to_int().to_char().unwrap() == '/' {
                i = i + 2
                column = column + 2
                closed = true
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
            if !closed {
              // 未关闭的块注释：产生错误 token
              tokens.push({
                token: Token::Identifier("<unclosed block comment>"),
                location: { line: block_start_line, column: block_start_col },
              })
              i = len
            }
            continue
          }
        }
        // 正则表达式 /…/
        let start_line = line
        let start_col = column
        let mut j = i + 1
        column = column + 1
        // 支持 \/ 转义：跳过 \\ 后紧跟的字符（不视为结束 /）
        while j < len {
          let ch = input[j].to_int().to_char().unwrap()
          if ch == '/' {
            break
          } else if ch == '\\' && j + 1 < len {
            // 转义序列：跳过 \\ 和紧跟的字符
            j = j + 2
            column = column + 2
          } else if ch == '\n' {
            line = line + 1
            column = 1
            j = j + 1
          } else {
            column = column + 1
            j = j + 1
          }
        }
        if j < len {
          let regex = input[i + 1:j].to_string()
          tokens.push({
            token: Token::RegexLiteral(regex),
            location: { line: start_line, column: start_col },
          })
          i = j + 1
          column = column + 1
        } else {
          // 未关闭的正则：产生错误 token 而非静默丢弃
          let partial = input[i + 1:len].to_string()
          tokens.push({
            token: Token::RegexLiteral(partial),
            location: { line: start_line, column: start_col },
          })
          i = len
        }
      }
      '"' => {
        let start_line = line
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
          let literal = input[i + 1:j].to_string()
          tokens.push({
            token: Token::StringLiteral(literal),
            location: { line: start_line, column: start_col },
          })
          i = j + 1
          column = column + 1
        } else {
          // 未关闭的字符串：产生错误 token 而非静默丢弃
          let partial = input[i + 1:len].to_string()
          tokens.push({
            token: Token::StringLiteral(partial),
            location: { line: start_line, column: start_col },
          })
          i = len
        }
      }
      ':'
      | '|'
      | '*'
      | '+'
      | '?'
      | '('
      | ')'
      | '@'
      | '!'
      | '&'
      | '.'
      | '{'
      | '}'
      | ','
      | '['
      | ']' => {
        tokens.push({
          token: Token::Symbol(c.to_string()),
          location: { line, column },
        })
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
          if is_whitespace(c_j) || is_symbol(c_j) {
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
        if i == j {
          i = i + 1
          column = column + 1
          continue
        }
        let word = input[i:j].to_string()
        if word == "rule" ||
          word == "start" ||
          word == "precedence" ||
          word == "left" ||
          word == "right" ||
          word == "nonassoc" ||
          word == "dynamic" ||
          word == "prec" ||
          word == "extras" ||
          word == "externals" ||
          word == "alias" {
          tokens.push({
            token: Token::Keyword(word),
            location: { line, column: start_col },
          })
        } else {
          tokens.push({
            token: Token::Identifier(word),
            location: { line, column: start_col },
          })
        }
        i = j
      }
    }
  }
  tokens
}

///|
fn is_whitespace(c : Char) -> Bool {
  match c {
    ' ' | '\t' | '\n' | '\r' => true
    _ => false
  }
}

///|
fn is_symbol(c : Char) -> Bool {
  match c {
    ':'
    | '|'
    | '*'
    | '+'
    | '?'
    | '('
    | ')'
    | '"'
    | '/'
    | '@'
    | '\\'
    | '!'
    | '&'
    | '.'
    | '{'
    | '}'
    | ','
    | '['
    | ']' => true
    _ => false
  }
}

///|
/// 将字符串解析为非负整数；包含非数字字符时返回 None
fn parse_int_str(s : String) -> Int? {
  if s.length() == 0 {
    return None
  }
  let max_val = 2147483647
  let mut result = 0
  for i in 0..<s.length() {
    let d = s[i].to_int() - '0'.to_int()
    if d < 0 || d > 9 {
      return None
    }
    // 溢出检测：若继续乘 10 加 d 会超出 Int 最大值则返回 None
    if result > (max_val - d) / 10 {
      return None
    }
    result = result * 10 + d
  }
  Some(result)
}
