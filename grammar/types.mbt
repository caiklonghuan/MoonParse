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
} derive(Eq, Debug)

///|
pub impl Show for PrecKind with output(self, logger) {
  match self {
    Left => logger.write_string("Left")
    Right => logger.write_string("Right")
    Nonassoc => logger.write_string("Nonassoc")
    Dynamic => logger.write_string("Dynamic")
  }
}

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
/// 规则属性，向 tablegen 传递优化/展示提示
pub(all) enum RuleAttribute {
  /// 内联规则：tablegen 可将此规则展开到父规则，减少 CST 节点层数
  Inline
  /// 隐藏规则：解析成功但不出现在命名 CST 节点中
  Hide
  /// 已废弃规则：标记该规则将在未来版本中移除，供迁移工具生成警告
  Deprecated
} derive(Debug, Eq)

///|
pub impl Show for RuleAttribute with output(self, logger) {
  match self {
    Inline => logger.write_string("Inline")
    Hide => logger.write_string("Hide")
    Deprecated => logger.write_string("Deprecated")
  }
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
  /// 节点类型别名 alias("name", p)：将产生式的显示名称覆盖为 alias_name
  Alias(String, Pattern)
  /// 模板规则实例化：name[arg1, arg2]，用具体 Pattern 替换模板参数
  RuleApp(String, Array[Pattern])
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
  /// 是否为词法规则（由 `token rule` 声明）；词法规则仅含终结符模式
  is_token : Bool
  /// 模板参数列表；非空时此规则为参数化模板，用 name[arg] 实例化
  params : Array[String]
  /// 规则属性（@inline / @hide）
  attributes : Array[RuleAttribute]
  /// 规则名在源码中的位置（行列，用于错误报告）
  location : SourceLocation?
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
  /// externals：由外部词法器处理的 token 名称列表
  /// 对应 DSL 中的 `externals [name1, name2, ...]` 声明
  externals : Array[String]
  /// 重复定义的规则名列表（解析阶段检测，校验阶段报告 DuplicateRule 错误）
  duplicate_rule_names : Array[String]
  /// word 关键字规则名：指定用于关键字提升的词法规则，防止关键字被识别为普通标识符
  mut word : String?
  /// conflicts：声明的 GLR 歧义规则组，每组列出可能产生 shift/reduce 歧义的规则对
  /// 对应 DSL 中的 `conflicts [[rule_a, rule_b], ...]` 声明
  conflicts : Array[Array[String]]
  /// supertypes：抽象超类型列表，供查询 API（如 tree-sitter query）使用
  /// 对应 DSL 中的 `supertypes [expr, stmt, ...]` 声明
  /// 列表中的规则名在 CST 查询中被视为抽象类别，而不是具体节点类型
  supertypes : Array[String]
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
    Literal(str) => {
      let buf = StringBuilder::new()
      buf.write_char('"')
      for c in str {
        match c {
          '"' => buf.write_string("\\\"")
          '\\' => buf.write_string("\\\\")
          _ => buf.write_char(c)
        }
      }
      buf.write_char('"')
      buf.to_string()
    }
    Regex(re) => {
      let buf = StringBuilder::new()
      buf.write_char('/')
      let chars = re.to_array()
      let mut k = 0
      while k < chars.length() {
        let c = chars[k]
        if c == '\\' && k + 1 < chars.length() {
          // 转义序列原样输出（含 \/ \n \\ 等）
          buf.write_char(c)
          buf.write_char(chars[k + 1])
          k = k + 2
        } else if c == '/' {
          // 裸 / 需转义，避免提前终止正则字面量
          buf.write_string("\\/")
          k = k + 1
        } else {
          buf.write_char(c)
          k = k + 1
        }
      }
      buf.write_char('/')
      buf.to_string()
    }
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
    Alias(name, p) => "alias(\"" + name + "\", " + pattern_to_string(p) + ")"
    RuleApp(name, args) =>
      name + "[" + args.map(pattern_to_string).join(", ") + "]"
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
