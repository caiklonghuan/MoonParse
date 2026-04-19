<template>
  <article>
    <h1>公共接口</h1>
    <p>本页只对齐 <code>grammar/README.md</code> 里的模块公开面，不额外混入根包、WASM 或 JS 封装。重点是：DSL 解析、语义校验、序列化、Builder API，以及核心公开结构。</p>

    <h2>最常用 API</h2>
    <table>
      <thead>
        <tr>
          <th>类别</th>
          <th>主要 API</th>
          <th>说明</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td>DSL 解析</td>
          <td><code>parse_grammar</code>、<code>parse_grammar_lenient</code></td>
          <td>将 DSL 文本解析为 <code>Grammar</code>。</td>
        </tr>
        <tr>
          <td>语义校验</td>
          <td><code>validate_grammar</code></td>
          <td>检查未定义规则、左递归、优先级混用等问题。</td>
        </tr>
        <tr>
          <td>DSL / JSON 序列化</td>
          <td><code>grammar_to_string</code>、<code>grammar_to_json</code>、<code>grammar_from_json</code></td>
          <td>便于显示、持久化与工具链交换。</td>
        </tr>
        <tr>
          <td>数据结构</td>
          <td><code>Grammar</code>、<code>Rule</code>、<code>Pattern</code>、<code>PrecDecl</code></td>
          <td>整个模块的公开模型。</td>
        </tr>
        <tr>
          <td>Builder API</td>
          <td><code>Grammar::new</code>、<code>Rule::new</code>、<code>Rule::token</code>、<code>Rule::template</code></td>
          <td>用代码表达与 DSL 等价的 grammar。</td>
        </tr>
        <tr>
          <td>Pattern 组合器</td>
          <td><code>seq</code>、<code>choice</code>、<code>lit</code>、<code>re</code>、<code>ref_</code>、<code>repeat</code>、<code>plus</code>、<code>optional</code>、<code>field</code>、<code>alias_</code>、<code>prec</code>、<code>app</code></td>
          <td>用代码方式组合规则体。</td>
        </tr>
      </tbody>
    </table>

    <h2>Builder API 常用入口</h2>
    <pre><code>Grammar::new()
Grammar::set_start(name)
Grammar::add_rule(rule)
Grammar::add_extra(pattern)
Grammar::add_external(name)
Grammar::set_word(name)
Grammar::add_conflict(group)
Grammar::add_supertype(name)

Rule::new(name, pattern)
Rule::token(name, pattern)
Rule::template(name, params, pattern)</code></pre>

    <h2>公开结构</h2>
    <pre><code>pub(all) struct Grammar {
  mut start : String?
  rules : Map[String, Rule]
  precedences : Array[PrecDecl]
  extras : Array[Pattern]
  externals : Array[String]
  duplicate_rule_names : Array[String]
  mut word : String?
  conflicts : Array[Array[String]]
  supertypes : Array[String]
}

pub(all) enum RuleAttribute {
  Inline
  Hide
  Deprecated
}</code></pre>

    <h2>接口边界</h2>
    <ul>
      <li><code>parse_grammar</code> 只负责把 DSL 解析成对象，不保证这份 grammar 语义上可用；正式进入下游前仍必须调用 <code>validate_grammar</code>。</li>
      <li><code>grammar_from_json</code> 读取的是 MoonParse 自己的 Grammar JSON 往返格式，不应把它当成“任意外部 grammar schema”的通用导入器。</li>
      <li><code>grammar_to_json</code> / <code>grammar_from_json</code> 的结构往返不会保留源码位置信息。</li>
      <li><code>duplicate_rule_names</code> 和校验结果会报告重复定义，但最终 <code>Grammar.rules</code> 映射里只会保留后一次写入的结果。</li>
    </ul>
  </article>
</template>