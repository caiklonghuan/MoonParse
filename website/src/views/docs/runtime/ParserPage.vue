<template>
  <article>
    <h1>LR 解析器</h1>
    <p>runtime 的主循环负责把词法器返回的 token 转成节点栈变化。虽然对外入口统一走 GLR，但线性 LR 的 shift / reduce / accept 逻辑仍然是理解整个运行时的基础。</p>

    <h2>主循环关心什么</h2>
    <ul>
      <li>当前状态栈顶的 LR state。</li>
      <li>从词法器拿到的 lookahead token。</li>
      <li><code>action[(state, terminal)]</code> 给出的动作集合。</li>
      <li>规约后通过 <code>goto_table</code> 跳到的新状态。</li>
    </ul>

    <h2>三类动作</h2>
    <table>
      <thead><tr><th>动作</th><th>含义</th><th>结果</th></tr></thead>
      <tbody>
        <tr><td><code>Shift</code></td><td>消费一个 token</td><td>生成叶节点并推进输入位置；extras token 会保留节点但不改变 LR 状态。</td></tr>
        <tr><td><code>Reduce</code></td><td>按产生式归约多个子节点</td><td>弹出产生式体长度对应的节点，构造内部节点，再依据 goto 表压回新状态。</td></tr>
        <tr><td><code>Accept</code></td><td>完成解析</td><td>返回最终 CST 根节点。</td></tr>
      </tbody>
    </table>

    <h2>Trailing extras</h2>
    <p>归约时，栈顶末尾可能挂着空白或注释节点。它们不一定属于当前产生式体，因此 runtime 会先把 trailing extras 从规约候选中剥离，再在 reduce 完成后重新推回栈顶。这一行为和把 extras 直接丢弃完全不同。</p>

    <h2>增量相关字段</h2>
    <p>叶节点和内部节点都会记录创建时关联的 LR 状态，这主要服务于增量复用。旧树节点只有在其起始位置、状态和边界条件同时匹配时，才可能被安全复用到新解析中。</p>
  </article>
</template>