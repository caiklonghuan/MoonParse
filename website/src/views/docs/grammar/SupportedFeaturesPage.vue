<template>
  <article>
    <h1>支持特性</h1>
    <p>Grammar README 里没有把“支持特性”单独拆成一章，但核心概念和注意事项已经把常用声明、规则能力和使用边界说得很清楚。本页把这些能力按 website 入口重新整理。</p>

    <h2>顶层声明与扩展能力</h2>
    <table>
      <thead>
        <tr>
          <th>特性</th>
          <th>作用</th>
          <th>使用时要注意</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td><code>extras</code></td>
          <td>声明可在任意位置出现的附加 token，例如空白和注释。</td>
          <td>只能放终结符模式，不能塞非终结符引用或复杂语法组合。</td>
        </tr>
        <tr>
          <td><code>externals</code></td>
          <td>声明由外部词法器提供的 token 名称。</td>
          <td>它们会被视为合法 token 名，不应和普通规则职责混淆。</td>
        </tr>
        <tr>
          <td><code>word</code></td>
          <td>指定关键字提升使用的通用单词 token。</td>
          <td>必须指向一个合法的 <code>token rule</code>。</td>
        </tr>
        <tr>
          <td><code>conflicts</code></td>
          <td>显式声明预期的 GLR 冲突组。</td>
          <td>它不是关闭冲突检查，而是把这组歧义标记为预期行为。</td>
        </tr>
        <tr>
          <td><code>supertypes</code></td>
          <td>声明抽象超类型，便于查询和结构化消费。</td>
          <td>它是稳定元数据，不会直接改写解析树。</td>
        </tr>
      </tbody>
    </table>

    <h2>规则与 Pattern 能力</h2>
    <table>
      <thead>
        <tr>
          <th>能力</th>
          <th>典型写法</th>
          <th>作用</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td>字段命名</td>
          <td><code>lhs: expr</code></td>
          <td>为关键子结构命名，方便查询和下游消费。</td>
        </tr>
        <tr>
          <td>别名</td>
          <td><code>alias("number", value)</code></td>
          <td>不改底层结构，只改对外显示节点名。</td>
        </tr>
        <tr>
          <td>内联优先级</td>
          <td><code>prec.left(1, expr "+" expr)</code></td>
          <td>给表达式或局部结构附加优先级与结合性。</td>
        </tr>
        <tr>
          <td>模板规则</td>
          <td><code>comma_list[expr]</code></td>
          <td>复用一类可参数化模式。</td>
        </tr>
        <tr>
          <td>规则属性</td>
          <td><code>@inline</code>、<code>@hide</code>、<code>@deprecated</code></td>
          <td>控制节点暴露方式或迁移提示。</td>
        </tr>
        <tr>
          <td>前瞻断言</td>
          <td><code>!p</code>、<code>&amp;p</code></td>
          <td>表达局部前瞻约束。</td>
        </tr>
      </tbody>
    </table>

    <h2>一段带扩展特性的示例</h2>
    <pre><code>extras [/[ \t\n\r]+/, /#[^\n]*/]
externals [indent dedent newline]
word ident
conflicts [[call_expr, index_expr]]
supertypes [expr, stmt]

token rule ident: /[a-zA-Z_][a-zA-Z0-9_]*/
@deprecated rule legacy_assign: ident ":=" expr
rule block: indent stmt+ dedent</code></pre>

    <h2>使用边界</h2>
    <ul>
      <li><code>parse_grammar</code> 和顶层 <code>precedence</code> / 内联 <code>prec</code> 并不冲突，但两套优先级系统本身必须二选一，混用会得到 <code>MixedPrecSystems</code>。</li>
      <li><code>token rule</code> 属于词法层，不能随意引用普通语法规则。</li>
      <li>模板规则不能像普通规则那样直接引用，必须通过 <code>app(...)</code> 或 DSL 的 <code>name[...]</code> 实例化。</li>
      <li>前瞻断言当前只建议放在序列尾部，否则可能在后续阶段被忽略并触发警告。</li>
    </ul>

    <h2>最常见的错误</h2>
    <ul>
      <li><code>word</code> 指向了普通 <code>rule</code>，而不是 <code>token rule</code>。</li>
      <li>把非终结符引用放进 <code>extras</code>，导致 Grammar 级校验失败。</li>
      <li>在 token rule 中偷偷引用普通规则，破坏词法层纯度。</li>
      <li>在 <code>supertypes</code> 或 <code>conflicts</code> 中填了未定义规则名。</li>
      <li>普通规则继续引用已经标记 <code>@deprecated</code> 的规则，没有及时迁移。</li>
    </ul>
  </article>
</template>