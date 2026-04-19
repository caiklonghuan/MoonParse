<template>
  <article>
    <h1>示例</h1>
    <p>这一页不追求覆盖全部参数，而是给出几条最常用的工作流。示例统一使用仓库内入口 <code>moon run cmd/main --</code>；如果你已经有单独的 CLI 可执行文件，只需把前缀替换为 <code>moonparse</code>。</p>

    <h2>示例 1：本地迭代 grammar</h2>
    <pre><code>moon run cmd/main -- check grammars/json.grammar
moon run cmd/main -- fmt grammars/json.grammar --check
moon run cmd/main -- dump automaton grammars/json.grammar
moon run cmd/main -- parse grammars/json.grammar sample.json --format json</code></pre>
    <p>这一组命令适合写 grammar 时反复循环：先看诊断，再看格式，冲突或状态机异常时直接切到 <code>dump automaton</code>，最后用真实输入验证输出树。</p>

    <h2>示例 2：固定 parse table 后反复消费</h2>
    <pre><code>moon run cmd/main -- generate grammars/json.grammar -o out/json.parse_table
moon run cmd/main -- parse -t out/json.parse_table sample.json --format dot
moon run cmd/main -- query '(pair key: (string) @key)' sample.json -t out/json.parse_table --json</code></pre>
    <p>当 grammar 已经稳定时，优先把 <code>generate</code> 单独做成一步，后续统一走 <code>-t</code> / <code>--table</code>，这样可以避免每次执行都重新编译 grammar。</p>

    <h2>示例 3：构建产物目录</h2>
    <pre><code>moon run cmd/main -- build grammars/json.grammar -o out/build
moon run cmd/main -- build out/json.parse_table --wasm -o out/build
moon run cmd/main -- wasm -g grammars/json.grammar -o out/dist
moon run cmd/main -- wasm -t out/json.parse_table -o out/dist</code></pre>
    <p><code>build</code> 用于落地标准产物目录，<code>wasm</code> 用于生成 <code>parser.js</code> 胶水与配套 parse table。两者都能消费 grammar 或预编译表，但产物结构并不相同。</p>

    <h2>示例 4：从 stdin 读取输入</h2>
    <pre><code>Get-Content sample.json | moon run cmd/main -- parse -t out/json.parse_table --stdin --format sexp
Get-Content sample.json | moon run cmd/main -- query '(number) @n' -t out/json.parse_table --count</code></pre>
    <p>如果没有显式提供输入文件，<code>parse</code> 和 <code>query</code> 默认就会读 stdin；<code>--stdin</code> 只是把这个选择写得更明确。</p>

    <h2>示例 5：把 grammar 质量门禁接进 CI</h2>
    <pre><code>moon run cmd/main -- check grammars/json.grammar
moon run cmd/main -- fmt grammars/json.grammar --check
moon run cmd/main -- test corpus/json.txt</code></pre>
    <p>这里最重要的不是屏幕输出，而是退出码：<code>check</code> 会区分 warning 与 error，<code>fmt --check</code> 会区分已格式化与未格式化，<code>test</code> 会区分失败与加载错误。</p>

    <h2>示例 6：显式 grammar:corpus 绑定</h2>
    <pre><code>moon run cmd/main -- test grammars/json.grammar:corpus/json.txt
moon run cmd/main -- test C:\work\json.grammar:C:\work\corpus\json.txt</code></pre>
    <p><code>test</code> 的 spec 解析会跳过 Windows 盘符上的那个冒号，因此绝对路径形式仍然可用。</p>

    <h2>示例 7：清理与重新构建</h2>
    <pre><code>moon run cmd/main -- clean
moon run cmd/main -- generate grammars/json.grammar
moon run cmd/main -- build grammars/json.grammar --wasm</code></pre>
    <p>这适合在 CI 或重构建前把 <code>generated/</code>、<code>build/</code>、<code>dist/</code> 清空，再重新生成产物。</p>
  </article>
</template>