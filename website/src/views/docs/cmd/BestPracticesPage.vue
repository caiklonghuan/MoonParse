<template>
  <article>
    <h1>最佳实践</h1>
    <p><code>cmd/main</code> 的命令集不算多，但如果目标是稳定接入工程，仍然有几条值得提前固定下来的实践。</p>

    <h2>先区分“构建表”和“消费表”</h2>
    <p>本地调 grammar 时可以直接让 <code>parse</code> 或 <code>query</code> 从 <code>.grammar</code> 现编；一旦 grammar 稳定下来，就把 <code>generate</code> 变成单独步骤，后续统一使用 <code>--table</code>。这样可以让 parse/query 的延迟和失败模式都更可控。</p>

    <h2>在 CI 里分别利用退出码 1 和 2</h2>
    <p><code>check</code>、<code>generate</code>、<code>parse</code>、<code>fmt --check</code>、<code>test</code> 都会把“软失败”和“硬失败”分开编码。不要把所有非 0 都一概视为同一种问题，尤其是 <code>parse</code> 的 1 往往意味着已经有树，只是树里带了 ERROR 节点。</p>

    <h2>不要把 quiet 当作普通日志级别</h2>
    <p>当前 <code>--quiet</code> 会抑制全部 <code>print_info</code> 输出，包括命令的主结果。脚本里如果还需要 parse 树、query JSON 或 <code>fmt --stdout</code> 的正文，就不要加这个 flag。</p>

    <h2>让 corpus 文件名和 grammar 基名对齐</h2>
    <p><code>test</code> 在只接收 corpus 路径时，会自动推导同目录同基名的 <code>.grammar</code>。如果项目愿意遵循这个约定，就能少写一层 spec 绑定，也避开 Windows 绝对路径与冒号分隔的冲突。</p>

    <h2>把调试输出和结果输出分开消费</h2>
    <p><code>parse --tokens</code>、<code>generate --diagnostic</code> 和所有错误定位都走 stderr，而 parse/query/fmt 的正文通常走 stdout。这样做的好处是你可以只重定向 stdout，把 stderr 保留给终端观察；如果要做 IDE 或 web 调试面板，也更容易拆分展示。</p>

    <h2>把 check 放在 generate 之前</h2>
    <p>虽然 <code>generate --force</code> 可以顶着诊断继续输出表，但正常工程流程仍然应该先跑 <code>check</code> 看清楚 grammar 当前是 warning 还是 error，再决定是否允许强制生成。</p>
  </article>
</template>