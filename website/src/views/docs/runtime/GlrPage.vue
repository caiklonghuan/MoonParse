<template>
  <article>
    <h1>GLR 与并行</h1>
    <p>默认的 <code>parse()</code> 最终会走 GLR 主路径。这不是“为了支持理论上的歧义文法”而做的额外选项，而是 runtime 适配真实语言工具场景的核心设计：当表格单元里存在多个合法动作时，运行时应该并行推进，再结合代价、优先级和路径合并策略选出最终保留的树。</p>

    <h2>什么时候会并行</h2>
    <ul>
      <li>某个 <code>(state, lookahead)</code> 对应到多个合法动作。</li>
      <li>文法本身允许 GLR 歧义，编译期无法静态裁掉全部冲突。</li>
      <li>错误恢复引入了新的候选路径，需要与正常路径一起比较总代价。</li>
    </ul>

    <h2>版本管理与 GSS</h2>
    <p>MoonParse 采用 Graph-Structured Stack 思路管理并行解析版本。每个活动版本都有自己的栈帧、累计错误代价、动态优先级和暂停状态；在合适的时候，runtime 会合并等价路径，并丢弃明显更差的候选。</p>

    <h2>版本上限</h2>
    <pre><code>max_version_count = 6
max_version_count_overflow = 4</code></pre>
    <p>当活动版本数超过上限时，运行时会先允许少量溢出，再按代价排序截尾。这样可以避免歧义文法在最坏情况下把版本数无限放大。</p>

    <h2>GLR 如何影响节点形状</h2>
    <p>多个版本在同一位置合并时，生成的节点可能被标记为 <code>fragile_left</code> 或 <code>fragile_right</code>。这并不表示节点不可用，而是表示它的边界来自多条路径的折中，因此后续增量编辑不能再把它当成稳定可复用子树。</p>

    <h2>GLR 和错误恢复是一起工作的</h2>
    <p>很多恢复路径本身就是额外的并行版本。运行时不会把“正常解析”和“恢复解析”硬拆成两个阶段，而是把它们统一放进版本管理和代价比较里。因此 <code>ParseConfig</code> 同时影响恢复行为和 GLR 路径裁剪。</p>

    <h2>和 <code>tablegen/</code> 的关系</h2>
    <p><code>tablegen/</code> 的 <code>ConflictReport</code> 只会告诉你哪些状态和 lookahead 位置可能发生多动作；真正把这些多动作跑起来、合并路径、保留最终树的是 <code>runtime/</code> 里的 GLR 引擎。</p>

    <h2>何时需要调节版本上限</h2>
    <ul>
      <li>你已经确认某类歧义会带来过多活动版本。</li>
      <li>你正在做恢复调优，需要比较不同分支规模下的结果质量。</li>
      <li>你有明确的性能证据，而不是凭感觉修改默认值。</li>
    </ul>
    <p>如果只是普通解析集成，先保持默认配置通常更稳妥。</p>
  </article>
</template>