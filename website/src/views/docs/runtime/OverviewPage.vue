<template>
  <article>
    <h1>概览</h1>
    <p>Runtime 页先只保留最常用入口、最小示例、常见任务和使用前自检。目标是让你尽快把一份已经编译好的 <code>ParseTable</code> 跑起来，并拿到可继续查询和遍历的 CST。</p>

    <h2>用途</h2>
    <ul>
      <li>消费已经编译好的 <code>ParseTable</code>，对源码做正式解析并产出 CST。</li>
      <li>在编辑器或在线场景里利用错误恢复和增量复用继续返回可用树。</li>
      <li>在布局敏感或特殊词法场景里接入外部词法器回调。</li>
    </ul>

    <h2>最小示例</h2>
    <p>如果你已经有一份稳定的 <code>ParseTable</code>，最短路径通常就是直接调用 <code>parse()</code>。</p>
    <pre><code>let result = @runtime.parse(table, source)
match result {
  Ok(root) => println(root.to_string())
  Err(err) => println(err.to_string())
}</code></pre>
    <table>
      <thead><tr><th>结果</th><th>含义</th></tr></thead>
      <tbody>
        <tr><td><code>Ok(root)</code></td><td>返回一棵 CST；其中仍可能包含恢复产生的错误节点或缺失节点。</td></tr>
        <tr><td><code>Err(err)</code></td><td>运行时无法继续返回可用树时的硬失败。</td></tr>
      </tbody>
    </table>

    <h2>常见任务从哪里进入</h2>
    <table>
      <thead><tr><th>现在要做什么</th><th>建议先看</th><th>原因</th></tr></thead>
      <tbody>
        <tr><td>先把一份表跑起来</td><td>示例</td><td>这里直接给出普通解析、增量解析和外部词法器调用代码。</td></tr>
        <tr><td>想查 parse 入口和关键类型</td><td>公共接口</td><td>集中列出 parse 变体、增量辅助入口和公开类型。</td></tr>
        <tr><td>想排查词法或外部 scanner 问题</td><td>词法引擎</td><td>这里集中看 lexer 接口、缓存和外部词法器回调。</td></tr>
        <tr><td>想做恢复或编辑器增量</td><td>错误恢复 / 增量解析</td><td>分别看恢复代价配置和 <code>InputEdit</code> / <code>OldTree</code> 的要求。</td></tr>
      </tbody>
    </table>

    <h2>使用前先自检</h2>
    <ul>
      <li>优先使用已经编译好的 <code>ParseTable</code>；<code>parse_from_dsl()</code> 只适合快速实验，不适合热路径。</li>
      <li>不要把 <code>Ok(root)</code> 直接理解成“源码无错”；恢复后的树里仍可能包含 <code>is_error</code> 或 <code>is_missing</code> 节点。</li>
      <li>如果要做增量解析，确保 <code>InputEdit</code> 的 byte offset 和 point 坐标准确一致。</li>
    </ul>
  </article>
</template>