<template>
  <article>
    <h1>示例</h1>
    <p>这一页给出几段最常见的 CLI 组合用法，重点不是列出全部 flag，而是展示一条完整工作流通常怎么串起来。</p>

    <h2>示例 1：先检查，再生成</h2>
    <pre><code>moonparse check grammars/json.grammar
moonparse generate grammars/json.grammar -o build/json.parse_table</code></pre>
    <p>适合在 CI 里先把 warning / error 分开处理，再决定是否允许把表产物写入构建目录。</p>

    <h2>示例 2：本地调 grammar 时直接 parse</h2>
    <pre><code>moonparse parse grammars/json.grammar sample.json
moonparse parse grammars/json.grammar sample.json --format json
moonparse parse grammars/json.grammar sample.json --tokens</code></pre>

    <h2>示例 3：稳定场景下复用预编译表</h2>
    <pre><code>moonparse generate grammars/json.grammar -o build/json.parse_table
moonparse parse --table build/json.parse_table sample.json --format dot
moonparse query '(pair key: (string) @key)' sample.json --table build/json.parse_table</code></pre>

    <h2>示例 4：把 fmt 接进脚本</h2>
    <pre><code>moonparse fmt grammars/json.grammar --check
moonparse fmt grammars/json.grammar --stdout &gt; /tmp/json.formatted.grammar</code></pre>
    <p>如果只想检测格式漂移，用 <code>--check</code>；如果要把结果交给别的工具消费，用 <code>--stdout</code>。</p>

    <h2>示例 5：查询结构节点</h2>
    <pre><code>moonparse query '(pair key: (string) @key value: (number) @value)' \
  sample.json \
  --grammar grammars/json.grammar

moonparse query '(number) @num' sample.json \
  --table build/json.parse_table \
  --json</code></pre>

    <h2>示例 6：跑 corpus 回归</h2>
    <pre><code>moonparse test tests/json.txt
moonparse test grammars/json.grammar:tests/json.txt</code></pre>
    <p>前一种形式适合 grammar 与 corpus 同目录同基名的项目结构；后一种适合想显式把 grammar 和 corpus 绑定在一起的场景。</p>
  </article>
</template>