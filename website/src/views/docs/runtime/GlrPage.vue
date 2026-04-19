<template>
  <article>
    <h1>GLR 与并行</h1>
    <p>当某个表格单元里存在多个合法动作时，runtime 不会立刻拍板只走一条路，而是把这些候选变成并行解析版本继续推进。MoonParse 采用的是 Graph-Structured Stack 思路，并在实际实现里加入了代价排序和截尾机制。</p>

    <h2>什么时候会并行</h2>
    <p>当某个状态和 lookahead 对应到多条合法动作时，runtime 会保留多条版本继续推进。常见来源包括预期 GLR 歧义、动态优先级场景，以及编译期无法静态裁掉的多动作单元。</p>

    <h2>版本管理</h2>
    <p>GLR 运行时会维护多个活动版本。每个版本都有自己的栈帧、累计错误代价、动态优先级和暂停状态；在合适的时候，runtime 会对等价路径做合并，对代价过高或数量过多的路径做裁剪。</p>

    <h2>版本上限</h2>
    <pre><code>max_version_count = 6
max_version_count_overflow = 4</code></pre>
    <p>当活动版本数超过上限时，运行时会先允许少量溢出，再按代价排序截尾。这避免了歧义文法在最坏情况下把版本数无限放大。</p>

    <h2>Fragile 节点</h2>
    <p>多个版本在同一位置合并时，生成的节点会被标记为 <code>fragile_left</code> 或 <code>fragile_right</code>。这不是说节点不可用，而是说它的边界来源于多条路径，因此后续增量编辑不能再把它当成稳定可复用子树。</p>

    <h2>注意事项</h2>
    <p>Tablegen 的 <code>ConflictReport</code> 只告诉你“哪些位置可能发生多动作”。Runtime 里的 GLR 则是真正把这些多动作跑起来，并在恢复成本、动态优先级和路径合并策略的共同作用下选择最后保留的树。</p>
  </article>
</template>