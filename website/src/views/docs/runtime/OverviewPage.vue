<template>
  <article>
    <h1>概览</h1>
    <p><code>runtime/</code> 是 MoonParse 的运行时执行层。它消费 <code>tablegen/</code> 生成的 <code>ParseTable</code>，把真实输入文本解析成带位置信息、错误恢复标记和增量复用信息的 <code>CstNode</code> 语法树。</p>

    <h2>模块职责</h2>
    <ul>
      <li>基于 <code>ParseTable</code> 执行完整解析，并返回 CST。</li>
      <li>在冲突或歧义存在时，以 GLR 方式并行推进多条解析路径。</li>
      <li>在输入不完整或包含错误时尽量恢复，保留 <code>ERROR</code> / <code>MISSING</code> 节点。</li>
      <li>在编辑器场景中基于旧树和编辑描述做增量解析。</li>
      <li>结合 DFA 与外部词法器回调做上下文敏感扫描。</li>
      <li>提供不变量检查、干净树判定和文法覆盖率统计。</li>
    </ul>

    <h2>在整条链路中的位置</h2>
    <pre><code>Grammar DSL / Builder API
        -&gt; grammar/
        -&gt; Grammar
        -&gt; tablegen/
        -&gt; ParseTable
        -&gt; runtime/
        -&gt; CST</code></pre>
    <p>和 <code>grammar/</code>、<code>tablegen/</code> 相比，<code>runtime/</code> 不再关心规则如何声明或解析表如何生成，而是关心“这张表怎样在真实源码上运行”。它是最靠近最终输入文本的一层。</p>

    <h2>内部结构</h2>
    <table>
      <thead><tr><th>文件</th><th>主要职责</th></tr></thead>
      <tbody>
        <tr><td><code>runtime.mbt</code></td><td>对外公开入口，聚合默认解析、增量解析和外部扫描器变体。</td></tr>
        <tr><td><code>glr.mbt</code></td><td>GLR 主引擎，负责 GSS、活跃路径、恢复代价和路径截尾。</td></tr>
        <tr><td><code>parser.mbt</code></td><td>线性 LR 解析路径，适合非歧义文法、白盒测试和基准对照。</td></tr>
        <tr><td><code>incremental.mbt</code></td><td>旧树标记、可复用节点查找和增量解析入口。</td></tr>
        <tr><td><code>lexer.mbt</code></td><td>上下文敏感词法引擎，支持 DFA、外部 scanner 和状态克隆。</td></tr>
        <tr><td><code>invariants.mbt</code></td><td>CST 结构不变量和增量标记检查。</td></tr>
        <tr><td><code>coverage.mbt</code></td><td>解析后覆盖率统计与报告输出。</td></tr>
        <tr><td><code>types.mbt</code></td><td><code>CstNode</code>、<code>InputEdit</code>、<code>ParseConfig</code>、<code>ParseError</code> 等基础类型。</td></tr>
      </tbody>
    </table>

    <h2>推荐入口</h2>
    <table>
      <thead><tr><th>现在要做什么</th><th>优先入口</th><th>说明</th></tr></thead>
      <tbody>
        <tr><td>正常运行时解析</td><td><code>parse()</code></td><td>默认 GLR 入口，最适合正式集成场景。</td></tr>
        <tr><td>调节恢复代价或版本上限</td><td><code>parse_with_config()</code></td><td>在默认 GLR 路径上附加 <code>ParseConfig</code>。</td></tr>
        <tr><td>复用旧树做增量解析</td><td><code>parse_with_old_tree()</code></td><td>最常用的增量入口，要求旧树和编辑描述准确一致。</td></tr>
        <tr><td>接入外部 token 识别</td><td><code>parse_with_external_scanner()</code></td><td>适合缩进、布局敏感或特殊词法规则。</td></tr>
        <tr><td>需要每条分支持有独立 scanner 状态</td><td><code>parse_with_stateful_scanner()</code></td><td>GLR 分叉时会 clone scanner 状态。</td></tr>
        <tr><td>快速验证 DSL</td><td><code>parse_from_dsl()</code></td><td>内部会重新做 Grammar 解析和建表，不适合热路径。</td></tr>
        <tr><td>做白盒测试或线性基准</td><td><code>parse_linear()</code></td><td>只维护单路径 LR，不替代正式运行时入口。</td></tr>
      </tbody>
    </table>

    <h2>开始使用前先记住</h2>
    <ul>
      <li><code>parse()</code> 默认走 GLR 解析，不是线性 LR 的快捷入口。</li>
      <li><code>Ok(root)</code> 不等于输入无错；是否为干净树要继续看 <code>check_clean_root()</code>。</li>
      <li>增量复用依赖旧树、旧文本和 <code>InputEdit</code> 坐标完全一致，坐标错了就不要期待可复用。</li>
    </ul>
  </article>
</template>