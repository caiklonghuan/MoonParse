<template>
  <article>
    <h1>Grammar 概览</h1>
    <p><code>grammar/</code> 是 MoonParse 的语法前端模块，负责把 Grammar DSL 或 Builder API 构造出的规则整理成统一的 <code>Grammar</code> 模型，并为下游 <code>tablegen/</code> 提供稳定、可检查、可序列化的输入。</p>

    <h2>模块定位</h2>
    <ul>
      <li>将 DSL 文本解析为 <code>Grammar</code> 对象。</li>
      <li>对 <code>Grammar</code> 做语义校验。</li>
      <li>将 <code>Grammar</code> 序列化为 DSL 文本或 JSON，并支持从 JSON 还原。</li>
      <li>为下游建表链路提供标准化输入。</li>
    </ul>
    <p>它不负责生成 LR/LALR 解析表、不执行运行时源码解析、不构造 CST / AST，也不处理增量编辑。</p>

    <h2>在整体系统中的位置</h2>
    <pre><code>Grammar DSL / Builder API
          |
          v
      grammar/
          |
          v
     Grammar 对象
          |
          v
      tablegen/
          |
          v
      ParseTable
          |
          v
      runtime/</code></pre>
    <p>可以把它理解为“定义和检查语法”的一层：<code>grammar/</code> 解决“语法如何表示”，<code>tablegen/</code> 解决“语法如何编译为解析表”，<code>runtime/</code> 解决“解析表如何驱动真实解析”。</p>

    <h2>内部处理链路</h2>
    <pre><code>Grammar DSL / Builder API
       |
       v
   lexer.mbt / api.mbt
       |
       v
  TokenWithLocation[] / Grammar
       |
       v
     parser.mbt
       |
       v
      Grammar
       |
       v
    validator.mbt
       |
       +------------------&gt; serializer.mbt
       |
       v
     tablegen/</code></pre>

    <table>
      <thead>
        <tr>
          <th>文件</th>
          <th>主要职责</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td><code>types.mbt</code></td>
          <td>定义 <code>Grammar</code>、<code>Rule</code>、<code>Pattern</code>、<code>ValidationError</code> 等核心类型。</td>
        </tr>
        <tr>
          <td><code>api.mbt</code></td>
          <td>提供 <code>Grammar::new</code>、<code>Rule::new</code>、<code>seq</code>、<code>choice</code> 等 Builder API。</td>
        </tr>
        <tr>
          <td><code>lexer.mbt</code> / <code>parser.mbt</code></td>
          <td>把 DSL 文本切成 token，并还原为 <code>Grammar</code> 对象。</td>
        </tr>
        <tr>
          <td><code>validator.mbt</code></td>
          <td>检查规则引用、左递归、优先级系统、模板、<code>word</code>、<code>extras</code> 等语义约束。</td>
        </tr>
        <tr>
          <td><code>serializer.mbt</code></td>
          <td>负责 DSL 回显以及 JSON 往返。</td>
        </tr>
      </tbody>
    </table>

    <h2>公开能力一览</h2>
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
          <td>便于显示、持久化和工具链交换。</td>
        </tr>
        <tr>
          <td>数据结构</td>
          <td><code>Grammar</code>、<code>Rule</code>、<code>Pattern</code>、<code>PrecDecl</code></td>
          <td>整个模块的核心模型。</td>
        </tr>
        <tr>
          <td>Builder API</td>
          <td><code>Grammar::new</code>、<code>Rule::new</code>、<code>Rule::token</code>、<code>Rule::template</code></td>
          <td>用代码构造 grammar，而不是手写 DSL。</td>
        </tr>
      </tbody>
    </table>

    <h2>推荐使用流程</h2>
    <ol>
      <li>准备 DSL 文本，或通过 Builder API 构造 <code>Grammar</code>。</li>
      <li>调用 <code>parse_grammar</code> 或 <code>parse_grammar_lenient</code> 得到 <code>Grammar</code>。</li>
      <li>必须再调用 <code>validate_grammar</code> 做语义校验。</li>
      <li>确认校验结果可接受后，再交给 <code>tablegen/</code> 继续生成 <code>ParseTable</code>。</li>
      <li>如需展示、持久化或缓存，可调用 <code>grammar_to_string</code> 或 <code>grammar_to_json</code>。</li>
    </ol>
    <p><code>grammar/</code> 可以看成“下游编译链路的输入守门员”。只有它这里已经通过解析与校验，后面的建表结果和运行时行为才有可解释性。</p>
  </article>
</template>