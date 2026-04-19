<template>
  <article>
    <h1>语法与模型</h1>
    <p><code>grammar/README.md</code> 里的核心概念主要围绕三层展开：整份语法的根对象 <code>Grammar</code>、单条规则 <code>Rule</code>，以及规则体里的统一表达 <code>Pattern</code>。本页把这三层压成 website 里最常用的一组索引。</p>

    <h2><code>Grammar</code> 由哪些部分组成</h2>
    <table>
      <thead>
        <tr>
          <th>字段</th>
          <th>作用</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td><code>start</code></td>
          <td>起始规则，决定整份语法从哪里开始。</td>
        </tr>
        <tr>
          <td><code>rules</code></td>
          <td>规则名到 <code>Rule</code> 的映射。</td>
        </tr>
        <tr>
          <td><code>precedences</code></td>
          <td>顶层优先级声明表。</td>
        </tr>
        <tr>
          <td><code>extras</code></td>
          <td>可在任意位置出现的附加 token，例如空白和注释。</td>
        </tr>
        <tr>
          <td><code>externals</code></td>
          <td>由外部词法器提供的 token 名称。</td>
        </tr>
        <tr>
          <td><code>word</code></td>
          <td>关键字提升所使用的通用单词 token。</td>
        </tr>
        <tr>
          <td><code>conflicts</code></td>
          <td>显式声明的冲突组。</td>
        </tr>
        <tr>
          <td><code>supertypes</code></td>
          <td>抽象超类型列表，便于查询和结构化使用。</td>
        </tr>
      </tbody>
    </table>

    <p>一个接近 README 的完整最小骨架如下：</p>
    <pre><code>start list
extras [/[ \t\n\r]+/]
word identifier
token rule identifier: /[a-zA-Z_][a-zA-Z0-9_]*/
rule item: identifier
rule list: head: item ("," tail: item)*
supertypes [item]</code></pre>

    <h2><code>Rule</code> 分哪几类</h2>
    <table>
      <thead>
        <tr>
          <th>规则类型</th>
          <th>适合场景</th>
          <th>典型 API</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td>普通规则</td>
          <td>描述语法层结构。</td>
          <td><code>Rule::new(name, pattern)</code></td>
        </tr>
        <tr>
          <td>token 规则</td>
          <td>描述词法层 token。</td>
          <td><code>Rule::token(name, pattern)</code></td>
        </tr>
        <tr>
          <td>模板规则</td>
          <td>抽象可复用模式，后续再实例化。</td>
          <td><code>Rule::template(name, params, pattern)</code></td>
        </tr>
      </tbody>
    </table>

    <pre><code>let identifier_rule = @grammar.Rule::token(
  "identifier",
  @grammar.re("[a-zA-Z_][a-zA-Z0-9_]*"),
)

let expr_rule = @grammar.Rule::new(
  "expr",
  @grammar.choice([
    @grammar.ref_("identifier"),
    @grammar.lit("null"),
  ]),
)

let comma_list_rule = @grammar.Rule::template(
  "comma_list",
  ["T"],
  @grammar.seq([
    @grammar.ref_("T"),
    @grammar.repeat(
      @grammar.seq([
        @grammar.lit(","),
        @grammar.ref_("T"),
      ]),
    ),
  ]),
)</code></pre>

    <p>如果规则名以下划线 <code>_</code> 开头，则默认视为匿名规则；另外还可以通过 <code>RuleAttribute::Inline</code>、<code>Hide</code>、<code>Deprecated</code> 给规则附加属性。</p>

    <h2><code>Pattern</code> 常见写法</h2>
    <table>
      <thead>
        <tr>
          <th>DSL 写法</th>
          <th>对应组合器</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td><code>identifier</code></td>
          <td><code>ref_("identifier")</code></td>
        </tr>
        <tr>
          <td><code>"+"</code></td>
          <td><code>lit("+")</code></td>
        </tr>
        <tr>
          <td><code>/\d+/</code></td>
          <td><code>re("\\d+")</code></td>
        </tr>
        <tr>
          <td><code>a b c</code></td>
          <td><code>seq([ref_("a"), ref_("b"), ref_("c")])</code></td>
        </tr>
        <tr>
          <td><code>a | b</code></td>
          <td><code>choice([ref_("a"), ref_("b")])</code></td>
        </tr>
        <tr>
          <td><code>item*</code></td>
          <td><code>repeat(ref_("item"))</code></td>
        </tr>
        <tr>
          <td><code>item+</code></td>
          <td><code>plus(ref_("item"))</code></td>
        </tr>
        <tr>
          <td><code>item?</code></td>
          <td><code>optional(ref_("item"))</code></td>
        </tr>
        <tr>
          <td><code>lhs: expr</code></td>
          <td><code>field("lhs", ref_("expr"))</code></td>
        </tr>
        <tr>
          <td><code>prec.left(1, expr "+" expr)</code></td>
          <td><code>prec(1, @grammar.PrecKind::Left, seq([...]))</code></td>
        </tr>
        <tr>
          <td><code>alias("number", value)</code></td>
          <td><code>alias_("number", ref_("value"))</code></td>
        </tr>
        <tr>
          <td><code>comma_list[expr]</code></td>
          <td><code>app("comma_list", [ref_("expr")])</code></td>
        </tr>
      </tbody>
    </table>

    <h2>Pattern 组合示例</h2>
    <pre><code>let call_pattern = @grammar.seq([
  @grammar.field("callee", @grammar.ref_("identifier")),
  @grammar.lit("("),
  @grammar.optional(
    @grammar.field(
      "arguments",
      @grammar.app("comma_list", [@grammar.ref_("expr")]),
    ),
  ),
  @grammar.lit(")"),
])

let unary_pattern = @grammar.prec(
  10,
  @grammar.PrecKind::Right,
  @grammar.seq([
    @grammar.choice([
      @grammar.lit("!"),
      @grammar.lit("-"),
    ]),
    @grammar.ref_("expr"),
  ]),
)</code></pre>
  </article>
</template>