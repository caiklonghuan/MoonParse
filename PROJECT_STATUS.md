# MoonParse 项目状态

## 项目定位

MoonParse 是一个完全用 MoonBit 编写的解析器生成器 + GLR 运行时，
覆盖从 Grammar DSL → 解析表生成 → 容错解析 → 查询/高亮 → WASM 导出 → LSP 服务器的完整工具链。

## 一、核心引擎（MoonBit）

### 1. Grammar DSL 前端 (`grammar/`)

- 手写递归下降解析器，将 .grammar 文本解析为 Grammar AST
- 语义验证：未定义规则、左递归、不可达规则、正则合法性、优先级系统混合等
- Builder API：程序化构造 Grammar 对象
- 序列化/反序列化：Grammar ↔ DSL 文本 / JSON 往返

### 2. 解析表生成 (`tablegen/`)

- 语法规范化：展开高阶模式为扁平产生式
- NULLABLE / FIRST / FOLLOW 集合计算
- LR(0) 项目集族构建 + GOTO 转移
- LALR(1) 解析表生成
- Shift/Reduce 和 Reduce/Reduce 冲突解决（优先级/结合性/声明）
- 词法 DFA 构建（上下文敏感）
- 解析表序列化：JSON + 二进制格式

### 3. GLR 运行时 (`runtime/`)

- **GLR 引擎**：图结构化栈 (GSS)，并行处理歧义和冲突
- **错误恢复**：三层代价驱动策略
  - insert_missing（插入缺失节点）
  - recover_to_state（回溯 GSS 找可接受状态）
  - skip_token（跳过不可识别 token）
- **增量解析**：输入编辑后复用未受影响子树
- **外部扫描器**：无状态/有状态两种模式（Python 缩进等）
- **CST 不变性检查**：树结构验证
- **语法覆盖率统计**
- 7 个可调参数：错误恢复代价 + GLR 版本数限制

### 4. 查询引擎 (`query/`)

- Tree-sitter 兼容的 S-expression 查询语言
- 查询解析 + 执行引擎（回溯匹配）
- 高亮范围生成
- 局部变量作用域解析 (locals)

### 5. WASM 桥接 (`wasm/`)

- 78 个 wasm-gc 导出函数
- 句柄管理：parser / tree / cursor / query ID 注册表
- CST JSON 序列化
- JS/TS 胶水代码 (`moonparse.js` / `moonparse.d.ts`)
- Node.js + 浏览器双运行时支持

### 6. CLI (`cmd/main/`)


| 命令       | 功能                                |
| ---------- | ----------------------------------- |
| `check`    | 验证 .grammar 文件 + 冲突报告       |
| `fmt`      | 格式化 .grammar 文件                |
| `generate` | 生成 .parse_table（二进制/JSON）    |
| `build`    | 构建可分发的解析器                  |
| `wasm`     | 生成 JS 分发目录                    |
| `dump`     | 调试输出：IR / 表 / 自动机          |
| `parse`    | 解析输入（sexp/json/dot/tree 输出） |
| `query`    | 在 CST 上运行 S-expression 查询     |
| `test`     | 语料库回归测试                      |
| `clean`    | 清理构建目录                        |

## 二、内置语法 (`grammars/`)


| 语法       | 状态         | 规则数 |
| ---------- | ------------ | ------ |
| JSON       | stable       | 11     |
| JSON5      | stable       | 15     |
| C          | subset       | 77     |
| Python     | subset       | 82     |
| MoonBit    | experimental | 132    |
| Expression | demo         | 11     |

C 支持：typedef / struct / union / enum / 数组 / sizeof / cast / goto / label

Python 支持：缩进敏感解析（外部扫描器）、import/class/def/try/with/yield/推导式/装饰器/海象运算符

## 三、LSP 服务器 (`lsp/`)

TypeScript + Node.js，基于 vscode-languageserver v9 + MoonParse WASM。

### 已实现的 LSP 协议


| 能力                              | 状态 | 说明                                    |
| --------------------------------- | ---- | --------------------------------------- |
| textDocument/didOpen              | ✅   | 文档打开                                |
| textDocument/didChange            | ✅   | 增量同步                                |
| textDocument/didClose             | ✅   | 文档关闭                                |
| textDocument/publishDiagnostics   | ✅   | 诊断推送（ERROR/MISSING → Diagnostic） |
| textDocument/semanticTokens/full  | ✅   | 全量语义高亮                            |
| textDocument/semanticTokens/range | ✅   | 范围语义高亮                            |
| textDocument/documentSymbol       | ✅   | 文档大纲（函数/类/结构体/规则）         |
| textDocument/hover                | ✅   | 悬停提示（节点类型/字段名/range）       |
| textDocument/definition           | ✅   | 跳转定义（Grammar DSL）                 |
| textDocument/references           | ✅   | 查找引用（Grammar DSL）                 |
| textDocument/completion           | ✅   | 代码补全                                |
| textDocument/formatting           | ✅   | 格式化（Grammar DSL）                   |
| textDocument/rangeFormatting      | ✅   | 范围格式化                              |
| textDocument/codeAction           | ✅   | Quick Fix                               |
| workspace/didChangeConfiguration  | ✅   | 配置热更新                              |

### 内置语言高亮 query

- Grammar DSL（__dsl__）：关键字/字符串/regex/注释
- C：所有关键字/运算符/类型/字面量
- Python：关键字/运算符/函数/类
- JSON / JSON5：key/string/number/keyword

### 技术特性

- UTF-16 ↔ UTF-8 字节偏移双向精确转换（支持中文/emoji）
- 解析防抖（默认 100ms）
- parser / tree / cursor / query 全生命周期资源追踪
- 零宽诊断保护（MISSING 节点至少占 1 字符可见）
- VSCode 主题 scope 对照表

## 四、Website (`website/`)

- Vue 3 + Vite + CodeMirror 6 + Mermaid
- 交互式 Playground：4 面板分割，增量解析，语法高亮
- 10 个语言预设 + 自定义语法支持
- 语法树可视化（展开/折叠/左递归展平）
- 查询编辑器 + 结果导航
- URL 状态共享（base64 + deflate 压缩）
- 完整文档（7 个板块 ~40 页）
- GitHub Pages 自动部署

## 五、测试覆盖

- 24 个 vitest 测试（diagnostics + semantic-tokens）
- 160+ 个 WASM 白盒测试（wasm_wbtest.mbt）
- ~3100 行运行时测试（runtime_wbtest.mbt）
- JSON/JSON5 fuzz 测试 + 变异测试
- C/Python/MoonBit 各 40-60 个语法测试
- 快照测试 + 语料库回归测试

## 六、项目规模

```

grammar/        语法前端     ~2000 行 MoonBit
tablegen/       建表层       ~2500 行 MoonBit
runtime/        运行时       ~3500 行 MoonBit
query/          查询引擎     ~1000 行 MoonBit
wasm/           WASM 桥接    ~3500 行 MoonBit + JS/TS
cmd/main/       CLI          ~2000 行 MoonBit
grammars/       内置语法     ~3000 行 MoonBit + DSL
lsp/src/        LSP 服务器   ~3200 行 TypeScript (13 个模块)
website/        网站         Vue 3 SPA
```


的项目已经非常完整了。基于当前架构，以下是几个有深度的拓展方向：

一、从语法到语义：补上中间层
你现在做的是 CST/语法级别的工作。下一个自然台阶是语义分析层：

拓展	说明
符号解析/名称绑定	在 CST 之上做 scope resolution，建立引用→定义的图。非 MoonBit 特有，给任意语法写 scope rule 即可
类型检查器生成框架	允许在 .grammar 中声明类型规则，自动生成类型检查器（类似 tree-sitter 不做的、你的差异化能力）
语义高亮升级	目前语义高亮基于语法，加上"变量/函数/类型的实际含义"后会更准（Rust Analyzer 级别）
控制流图构造	从 CST 构建 CFG，支撑死代码检测、use-before-init 等静态检查
二、代码变换与重构
目前工具链偏"只读"，加上写入能力会有质的飞跃：

拓展	说明
结构化改写引擎	基于查询匹配 → 模板替换 → CST 就地修改。对标 ast-grep / Semgrep
代码格式化引擎	类似 prettier 的 pretty-printer，但基于 CST 节点+配置规则，而非正则替换
自动修复 (Quick Fix 扩展)	目前有 codeAction 框架，但规则太少。基于查询自动匹配错误模式并生成修复
源代码迁移工具	把一种语法描述的代码自动翻译为另一种（如 JSON → JSON5、C89 → C99），基于 CST diff
三、增量解析深水区
你已有增量解析，但还有大量可挖的深度：

拓展	说明
多维度失效分析	不仅按编辑位置找脏区域，还用 AST 节点指纹（哈希）做精确比对，处理"看起来位置变了但其实语义没变"的情况
跨文件增量	当前增量局限于单文件。如果 A.mbt import B.mbt，B 改了，A 的 import 区域也应失效
Lazy CST 节点	大文件中未被查询/高亮触碰的子树延迟构建，减少内存占用
增量解析性能分析器	可视化 "哪次编辑导致最大面积重解析"，帮助语法作者优化规则设计
四、解析能力增强
拓展	说明
GLR → GLL 可选后端	GLR 是栈共享，GLL 是解析森林共享。两者在不同类型歧义下有性能差，给用户选择
Adaptive 模式切换	无歧义代码用 LALR(1) 快路径，检测到冲突自动切 GLR。结合你的 LALR 建表能力，这是质的优化
错误消息定制 DSL	语法作者在 .grammar 中写错误消息模板，比如 "Expected ';' after expression but found '{token}'"
自动错误恢复启发式	基于机器学习或统计，从大量错误语料自动学习最优恢复策略
五、生态与集成
拓展	说明
Tree-sitter 互操作	导出/导入 tree-sitter 的 grammar.json，双向转换。这是社区影响力最大的动作——MoonParse 可以直接用 tree-sitter 生态的 200+ 语法
moon 插件系统	让 moon check --plugin moonparse 在 MoonBit 编译时跑自定义 lint，对标 ESLint 插件生态
GitHub Action	CI 中自动跑语法检查 + 高亮回归 + 冲突检测
更多内置语法	TypeScript、Rust、Go、Markdown——覆盖主流语言后，LSP 服务器可做"多语言轻量级诊断"
六、Website/Playground
拓展	说明
语法 diff 模式	改一行语法规则，实时看到对全量测试文件的解析差异（哪个 case 突然通过/失败）
冲突可视化	不只看冲突数量，在 LR 自动机图上标出冲突状态+冲突路径
协作功能	URL 分享里的 grammar + test cases 全部打包，方便提 issue
🎯 我的 Top 5 推荐
Tree-sitter grammar.json 互转 — 社区影响力最大的单项动作，立刻接入 200+ 现有语法
结构化改写/重构引擎 — 工具链从"只读"变成"可读写"，打开的场景是指数级的
Adaptive LALR/GLR 切换 — 硕士水平的算法工作 + 实际性能收益，可发论文
跨文件增量解析 — 工程深度 + 长尾收益，大型项目刚需
类型检查器生成框架 — 你和 tree-sitter 的终极差异化能力，别人不做你能做
你对哪个方向最感兴趣？可以深入讨论技术方案。