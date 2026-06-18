# MoonParse 项目状态

## 项目定位

MoonParse 是一个完全用 MoonBit 编写的解析器生成器 + GLR 运行时，
覆盖从 Grammar DSL → 解析表生成 → 容错解析 → 查询/高亮 → WASM 导出 → LSP 服务器的完整工具链。

JSON、Python 和 MoonBit 已迁移到 schemaVersion 1 的标准 Language Pack，
并通过统一 LanguageBundle 构建 ParseTable、Query 与 Scanner 能力。

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

- wasm-gc 导出面已建立机器可检查的 API 快照
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

## 五、测试与状态口径

MoonBit 黑盒/白盒测试、WASM 宿主 smoke test、LSP Vitest、Website Corpus 与生产构建均纳入 CI。测试数、导出数和代码行由工具动态产生，不在本页手写容易漂移的精确数字。

- **已完成**：存在公开入口、自动测试和用户文档。
- **实验性**：能力可运行且有测试，但接口或行为仍可能变化。
- **计划中**：尚无可用公开入口，不计入当前能力。

当前项目版本读取根目录 `VERSION`。模块边界、API 稳定等级和生成物归属分别以 `docs/architecture.md`、`docs/api-stability.md` 与 `docs/generated-artifacts.md` 为准；生态扩张方向以 Roadmap 为准，不在状态页混写设想与现状。
