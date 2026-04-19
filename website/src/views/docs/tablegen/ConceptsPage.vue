<template>
  <article>
    <h1>核心概念</h1>
    <p><code>tablegen/README.md</code> 的核心概念主要围绕 5 个结构：<code>AugmentedGrammar</code>、<code>ParseTable</code>、<code>Production</code>、<code>ConflictReport</code>、<code>LexerDfa</code>。本页把这几个结构压成 website 里的快速索引。</p>

    <h2>关键数据结构</h2>
    <table>
      <thead>
        <tr>
          <th>类型</th>
          <th>定位</th>
          <th>最重要的信息</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td><code>AugmentedGrammar</code></td>
          <td>标准化 CFG</td>
          <td>持有终结符 / 非终结符映射、扁平产生式、terminal patterns、extras、优先级表、word token、declared conflicts。</td>
        </tr>
        <tr>
          <td><code>ParseTable</code></td>
          <td>最终编译产物</td>
          <td>包含 action、goto、productions、lexer_dfa、symbol_metadata、terminal names / patterns、extras、external tokens、keyword map 等运行时字段。</td>
        </tr>
        <tr>
          <td><code>Production</code></td>
          <td>扁平产生式</td>
          <td>包含 head、body、prec、assoc、rule_name、lookahead、alias_name 等信息。</td>
        </tr>
        <tr>
          <td><code>ConflictReport</code></td>
          <td>编译诊断</td>
          <td>记录冲突出现在哪个 LR 状态、哪个 lookahead 终结符以及属于哪种严重级别。</td>
        </tr>
        <tr>
          <td><code>LexerDfa</code></td>
          <td>上下文敏感词法器</td>
          <td>持有 DFA 状态集合、起始状态，以及每个 LR 状态当前允许的 <code>valid_tokens</code>。</td>
        </tr>
      </tbody>
    </table>

    <h2>怎么快速判断“现在拿到的是不是最终产物”</h2>
    <ul>
      <li><code>AugmentedGrammar</code> 是进入算法前的标准化中间表示。</li>
      <li>项目集、goto 图和原始 LALR 表都属于中间态，适合调试，不适合直接交给 runtime。</li>
      <li><code>ParseTable</code> 才是最终可执行解析器的只读数据镜像。</li>
      <li><code>ConflictReport</code> 是编译诊断，不属于 runtime 数据本体。</li>
    </ul>
  </article>
</template>