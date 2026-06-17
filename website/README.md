# MoonParse Website

MoonParse 的 Vue 3 + Vite 文档站和浏览器 Playground，负责展示 Grammar、CST、Query、高亮与增量解析能力。

## 开发

要求 Node.js 22。运行时资源与预编译表都是构建产物，不在 Website 内维护第二份权威副本。

```bash
npm ci
npm run dev
```

生产验证：

```bash
npm run precompile
npm run corpus
npm run build
```

`npm run build` 会先从 `../wasm/` 同步 JS/WASM，再生成 `src/data/precompiledTables.js`。完整仓库门禁请在根目录执行 `npm test`，生成物策略见 [generated-artifacts.md](../docs/generated-artifacts.md)。
