///|
/// 优先级结合性
pub(all) enum PrecKind {
  /// 左结合（同级遇冲突取左侧规约）
  Left
  /// 右结合（同级遇冲突取右侧规约）
  Right
  /// 无结合性
  Nonassoc
  /// 运行时动态优先级
  Dynamic
} derive(Eq, Show)

///|
/// 顶层 `precedence` 声明（一条声明对应一个优先级层级）
pub(all) struct PrecDecl {
  /// 优先级层级（按声明顺序从 1 起，越大越高）
  level : Int
  /// 结合性
  kind : PrecKind
  /// 该层级包含的规则名列表
  rules : Array[String]
}

///|
/// Pattern 表示语法规则中的模式类型
pub(all) enum Pattern {
  /// 规则引用
  RuleRef(String)
  /// 字面量字符串
  Literal(String)
  /// 正则表达式
  Regex(String)
  /// 选择分支 A | B | C
  Choice(Array[Pattern])
  /// 顺序序列 A B C
  Seq(Array[Pattern])
  /// 零或多次重复 A*
  Repeat(Pattern)
  /// 一或多次重复 A+
  Plus(Pattern)
  /// 零或一次可选 A?
  Optional(Pattern)
  /// 语义标签 @label p
  Tagged(String, Pattern)
  /// 负向前瞻 !p
  Not(Pattern)
  /// 正向前瞻 &p
  And(Pattern)
  /// 任意单个字符 .
  AnyChar
  /// 命名字段 fieldname: pattern
  Field(String, Pattern)
  /// 精确或区间重复 p{n} / p{n,m}
  RepeatRange(Pattern, Int, Int)
  /// 内联优先级标注 prec(n,p) / prec.left(n,p) / prec.right(n,p) / prec.dynamic(n,p)
  Prec(Int, PrecKind, Pattern)
}

///|
/// Rule 表示一条语法规则
pub(all) struct Rule {
  /// 规则名称
  name : String
  /// 规则的模式体
  pattern : Pattern
  /// 是否为命名节点（名称以 _ 开头则为匿名节点）
  is_named : Bool
}

///|
/// Grammar 表示整个语法，包含起始规则和全部规则映射
pub(all) struct Grammar {
  /// 起始规则名称
  mut start : String?
  /// 规则名称 → Rule 的映射
  rules : Map[String, Rule]
  /// 顶层优先级声明列表（按声明顺序排列，越靠后层级越高）
  precedences : Array[PrecDecl]
  /// extras：可出现在任意位置的 token 模式（空白、注释等）
  /// 对应 DSL 中的 `extras [pattern, ...]` 声明
  extras : Array[Pattern]
}

///|
/// 将需要括号的子模式包裹起来
fn wrap_if_complex(p : Pattern) -> String {
  match p {
    Seq(_) | Choice(_) => "(" + pattern_to_string(p) + ")"
    _ => pattern_to_string(p)
  }
}

///|
/// 将 Pattern 渲染为 DSL 字符串，自动处理括号优先级
pub fn pattern_to_string(pattern : Pattern) -> String {
  match pattern {
    RuleRef(name) => name
    Literal(str) => "\"" + str + "\""
    Regex(re) => "/" + re + "/"
    AnyChar => "."
    Tagged(label, p) => "@" + label + " " + wrap_if_complex(p)
    Not(p) => "!" + wrap_if_complex(p)
    And(p) => "&" + wrap_if_complex(p)
    Repeat(p) => wrap_if_complex(p) + "*"
    Plus(p) => wrap_if_complex(p) + "+"
    Optional(p) => wrap_if_complex(p) + "?"
    Field(fname, p) => fname + ": " + wrap_if_complex(p)
    RepeatRange(p, min, max) =>
      if min == max {
        wrap_if_complex(p) + "{" + min.to_string() + "}"
      } else {
        wrap_if_complex(p) + "{" + min.to_string() + "," + max.to_string() + "}"
      }
    Prec(level, kind, p) => {
      let prefix = match kind {
        PrecKind::Left => "prec.left"
        PrecKind::Right => "prec.right"
        PrecKind::Dynamic => "prec.dynamic"
        PrecKind::Nonassoc => "prec"
      }
      prefix + "(" + level.to_string() + ", " + pattern_to_string(p) + ")"
    }
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
    Seq(patterns) => {
      let mut result = ""
      for i in 0..<patterns.length() {
        if i > 0 {
          result = result + " "
        }
        // 序列中嵌套 Choice 必须加括号，否则 A (B|C) 会被误读为 A B | C
        let p_str = match patterns[i] {
          Choice(_) => "(" + pattern_to_string(patterns[i]) + ")"
          _ => pattern_to_string(patterns[i])
        }
        result = result + p_str
      }
      result
    }
  }
}

///|
pub fn Pattern::to_string(self : Pattern) -> String {
  pattern_to_string(self)
}
