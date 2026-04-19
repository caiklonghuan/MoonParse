<template>
  <article>
    <h1>解析器</h1>
    <p><code>runtime/</code> 对外提供的是一组 parse 入口，但内部其实有两条执行路线：默认的 GLR 主路径，以及作为对照和测试基线存在的线性 LR 路径。理解 parser 页的关键，不是死记一个循环，而是知道每条入口最终会落到哪类执行模型。</p>

    <h2>入口与执行模型</h2>
    <table>
      <thead><tr><th>入口</th><th>实际执行模型</th><th>适合什么场景</th></tr></thead>
      <tbody>
        <tr><td><code>parse()</code></td><td>GLR</td><td>正式运行时入口；允许冲突、歧义和错误恢复。</td></tr>
        <tr><td><code>parse_with_config()</code></td><td>GLR + 自定义配置</td><td>需要调优恢复代价或版本上限。</td></tr>
        <tr><td><code>parse_linear()</code></td><td>单路径 LR</td><td>非歧义文法、白盒测试和性能对照。</td></tr>
        <tr><td><code>parse_with_old_tree*</code></td><td>增量解析</td><td>在新一轮运行时中尝试复用旧节点。</td></tr>
      </tbody>
    </table>

    <h2>主循环关心什么</h2>
    <ul>
      <li>当前状态栈顶的 LR state。</li>
      <li>词法器返回的 lookahead token。</li>
      <li><code>action[(state, terminal)]</code> 给出的动作集合。</li>
      <li>规约完成后通过 <code>goto_table</code> 转到的新状态。</li>
    </ul>
    <p>在线性 LR 路径里，这些步骤按单条栈顺序推进；在 GLR 路径里，同样的动作会在多个活跃版本上并行发生。</p>

    <h2>三类核心动作</h2>
    <table>
      <thead><tr><th>动作</th><th>含义</th><th>结果</th></tr></thead>
      <tbody>
        <tr><td><code>Shift</code></td><td>消费一个 token</td><td>生成叶节点并推进输入位置；extras token 会保留为节点，但不驱动 LR 状态前进。</td></tr>
        <tr><td><code>Reduce</code></td><td>按产生式归约多个子节点</td><td>弹出产生式体长度对应的节点，构造内部节点，再根据 goto 表压回新状态。</td></tr>
        <tr><td><code>Accept</code></td><td>完成解析</td><td>返回最终 CST 根节点。</td></tr>
      </tbody>
    </table>

    <h2>为什么 extras 不能直接丢弃</h2>
    <p>空白和注释通常来自 extras 规则。它们不会像普通 token 一样改变 LR 状态，但仍然要以 <code>extra=true</code> 的叶节点留在 CST 中。归约时，runtime 会先把栈顶 trailing extras 从规约候选里剥离，再在 reduce 完成后挂回去，这样才能保留源码还原和注释附着所需的信息。</p>

    <h2>解析状态会写进节点</h2>
    <p><code>CstNode</code> 不只记录 span 和 children，还会记录 <code>parse_state</code>、<code>lookahead_bytes</code> 等与解析上下文相关的信息。这样做的目的不是展示给最终用户，而是为了后续增量复用时判断一个旧节点是否还能在新上下文中安全复用。</p>

    <h2>何时使用 <code>parse_linear()</code></h2>
    <ul>
      <li>你确定文法是非歧义的，不依赖 GLR 分叉。</li>
      <li>你正在写白盒测试，想观察更直接的 LR 行为。</li>
      <li>你要做基准对照，比较单路径和 GLR 路径的差异。</li>
    </ul>
    <p><code>parse_linear()</code> 不是 <code>parse()</code> 的通用替代品。只要语言工具需要在真实输入上承受歧义、冲突和恢复，默认仍应回到 GLR 主路径。</p>
  </article>
</template>