# MoonParse 项目设计文档

## 项目目标

基于 MoonBit 实现的 **Tree-Sitter 风格的 GLR 解析器生成器工具链**：

- 用户写 `.grammar` 语法描述文件，工具链**编译时**生成紧凑的 LALR(1) 解析表
- **运行时**使用 GLR 引擎（Tomita 算法）驱动解析表，天然支持歧义和左递归
- 支持**增量解析**：基于 LR 状态栈精确定位受编辑影响的区域，局部重新解析
- 编译为 WASM，可在浏览器/Node/LSP 中运行
- 约 **1.5 万行**代码，六大模块

### 与 Tree-Sitter 的对应关系

| Tree-Sitter 概念 | MoonParse 对应 |
|---|---|
| `grammar.js`（JS DSL） | `.grammar` 文件（MoonParse DSL） |
| `tree-sitter generate` | `tablegen/` 模块（编译时） |
| `libtree-sitter` C 运行时 | `runtime/` 模块（GLR 引擎） |
| `parser.c` 生成的解析表 | 序列化的 `.parse_table` 数据 |
| `TSNode` / `TSTree` | `ParseNode` / `ParseTree` |
| `ts_parser_parse_with_options` | `parse_incremental()` |

---

## 模块划分与代码量估算

| 模块 | 目录 | 估算行数 | 状态 | 说明 |
|------|------|---------|------|------|
| Grammar DSL Parser | `grammar/` | ~2000 | 基本完成 | 语法定义解析 |
| Parse Table Generator | `tablegen/` | ~3500 | 未开始 | LALR(1) 表编译 |
| GLR Runtime | `runtime/` | ~4000 | 骨架 | GLR 引擎 + 增量解析 |
| WASM 接口 | `wasm/` | ~1500 | 骨架 | 浏览器/Node 集成 |
| 标准语法包 | `grammars/` | ~2500 | 未开始 | 内建语法示例 |
| CLI 工具 | `cmd/` | ~1000 | 骨架 | 命令行工具 |
| 公共 API | 根目录 | ~500 | 骨架 | 对外接口聚合 |
| **合计** | | **~15000** | | |

---

## 模块依赖关系

```
grammars/ ─────────────────────────────────────────┐
                                                     │
grammar/ ──► tablegen/ ──► (parse tables)           │
                               │                     │
                               ▼                     │
                           runtime/ ──► wasm/       │
                               ▲                     │
                               └─────────────────────┘
                        cmd/ (顶层调用 grammar + tablegen + runtime)
                    根包 MoonParse.mbt (公共 API 聚合)
```

**数据流**：
```
.grammar 文件
    │ grammar/ (解析)
    ▼
Grammar AST
    │ tablegen/ (编译)
    ▼
ParseTable (.parse_table 文件)
    │ runtime/ (解释执行)
    ▼
ParseTree (CST)
```

---

## 模块 1：Grammar DSL Parser（`grammar/`）

**现状**：核心功能已完成，约 600 行

**已有**：
- `Pattern` / `Rule` / `Grammar` 数据结构
- `SourceLocation` / `ParseResult` / `ParseError`
- `tokenize()` 带行列追踪
- `parse_grammar()` 完整语法解析

**待完善**（~1400 行）：

### 1.1 Pattern 扩展（对齐 Tree-Sitter 表达力）
- `Plus(Pattern)` — 一或多次（`+`）
- `RepeatRange(Pattern, Int, Int)` — `{n,m}`
- `Not(Pattern)` — 负向前瞻 `!p`（Tree-Sitter 的 `token.immediate`）
- `And(Pattern)` — 正向前瞻 `&p`
- `AnyChar` — 任意字符 `.`
- `Field(String, Pattern)` — 命名字段（Tree-Sitter 的 `field("name", rule)`）

### 1.2 节点可见性（Tree-Sitter 的 named vs anonymous）
- **命名节点**（Named）：出现在 CST 中，可被查询
- **匿名节点**（Anonymous）：标点、关键字等，默认隐藏
- DSL 区分：`rule name = ...`（命名）vs `rule _name = ...`（匿名，下划线前缀）
- 或用 `@hidden` 注解

### 1.3 Grammar 校验器
- 规则引用完整性检查（引用了未定义规则报错）
- 直接/间接左递归检测（GLR 天然支持，无需消除，但需标记以优化）
- 可达性分析（从 start 不可达的规则警告）
- 优先级冲突检查（`prec` 声明完整性）

### 1.4 优先级和结合性（Tree-Sitter 的 `prec`）
- `prec(n, rule)` — 声明优先级
- `prec.left(n, rule)` — 左结合
- `prec.right(n, rule)` — 右结合
- `prec.dynamic(n, rule)` — 运行时动态优先级
- 用于指导 GLR 在 shift-reduce 冲突时的选择

### 1.5 外部词法器声明（Tree-Sitter 的 `externals`）
- `externals: [token1, token2, ...]` — 声明由外部扫描器理的 token
- 用于缩进敏感语言（如 Python、Haskell）

### 1.6 Grammar 序列化/反序列化
- `grammar_to_string()` — Grammar → DSL 文本（格式化输出）
- Grammar AST → JSON（传给 tablegen）
- 支持 `.grammar` 文件读写

---

---

## 模块 2：Parse Table Generator（`tablegen/`）

**现状**：不存在（原 `generator/` 仅为 PEG 代码生成骨架，需重写）

**目标**（~3500 行）：
这是整个系统的**编译时核心**，对应 Tree-Sitter 的 `tree-sitter generate` 命令。

### 2.1 增广文法构建
- `augment_grammar(grammar)` — 添加 `S' → S $` 起始规则
- 枚举所有终结符（Terminals）和非终结符（NonTerminals）
- 产生式（Production）规范化表示

### 2.2 FIRST / FOLLOW 集合计算
```moonbit
fn first_set(grammar, symbol) -> Set[Terminal]
fn follow_set(grammar, nonterminal) -> Set[Terminal]
fn nullable(grammar, symbol) -> Bool
```

### 2.3 LR(0) 项目集构建（Item Sets）
```moonbit
/// LR(0) Item: [A → α • β, ...] (dot position in production)
struct LRItem {
  production : ProductionId
  dot        : Int          // dot 位置
}
/// 项目集闭包 closure(I)
fn closure(grammar, items) -> Set[LRItem]
/// GOTO 函数
fn goto(grammar, items, symbol) -> Set[LRItem]
/// 构建规范 LR(0) 项目集族
fn build_item_sets(grammar) -> Array[Set[LRItem]]
```

### 2.4 LALR(1) 解析表构建
```moonbit
/// 解析表动作
enum Action {
  Shift(StateId)
  Reduce(ProductionId)
  Accept
  Error
}
/// 解析表
struct ParseTable {
  states  : Int
  action  : Map[(StateId, Terminal), Array[Action]]  // Array[Action] 支持 GLR 冲突
  goto    : Map[(StateId, NonTerminal), StateId]
  prods   : Array[Production]
}
fn build_lalr_table(grammar, item_sets) -> ParseTable
```

### 2.5 GLR 冲突处理（不消解，记录所有路径）
- Shift-Reduce 冲突 → `action[(s, t)]` 包含多个动作（GLR 并行探索）
- Reduce-Reduce 冲突 → 同上
- **优先级/结合性**用于过滤冲突中的次优路径（借鉴 Tree-Sitter 的 `prec`）
- 冲突报告：`warn` 级别（有 `prec` 解决）vs `error` 级别（无法解决的歧义）

### 2.6 词法器集成
- 从 Grammar 中提取所有 Literal / Regex terminal
- 构建 DFA 词法器（正则 → NFA → DFA 最小化）
- **上下文敏感词法**：基于当前 LR 状态过滤合法 token（Tree-Sitter 关键特性）

### 2.7 解析表序列化
- `serialize_table(table) → Bytes` — 紧凑二进制格式
- `deserialize_table(bytes) → ParseTable` — 运行时加载
- 可选：JSON 格式（调试用）

---

## 模块 3：GLR Runtime（`runtime/`）

**现状**：骨架，约 40 行，需重写

**目标**（~4000 行）：
这是**运行时核心**，对应 `libtree-sitter` 的 C 实现。

### 3.1 核心数据结构

```moonbit
/// CST 节点（不可变，持久化数据结构）
struct ParseNode {
  symbol   : Symbol       // 对应的文法符号
  start    : Int          // 字节偏移（起始）
  end      : Int          // 字节偏移（结束）
  children : Array[ParseNode]
  is_named : Bool         // named vs anonymous
  field    : String?      // 字段名（如有）
  is_error : Bool         // 错误恢复节点
}
/// 图结构栈（GSS - Graph Structured Stack）节点
struct GSSNode {
  state    : StateId
  node     : ParseNode?   // 对应的树节点
  prev     : Array[GSSNode]  // 前驱（GLR 分叉时有多个）
}
```

### 3.2 GLR 解析引擎（Tomita 算法）
- `Parser { table, input, positions, stack_tops : Array[GSSNode] }`
- **核心循环**：
  1. 对所有活跃栈顶，查 action 表
  2. Shift：创建新 GSSNode，推入标记
  3. Reduce：沿栈弹出 `len(prod)` 个节点，GOTO 得新状态，合并到 GSS
  4. Accept：完成
- **GSS 合并**：相同 state 的节点合并（避免指数爆炸）
- **Earley 风格局部歧义打包**（SPPF 节点）

### 3.3 增量解析引擎（Tree-Sitter 核心特性）
```moonbit
struct ChangeSet {
  start_byte : Int
  old_end    : Int
  new_end    : Int
  new_text   : String
}
fn parse_incremental(
  parser  : Parser,
  old_tree : ParseTree,
  changes  : Array[ChangeSet],
  new_input : String
) -> ParseTree
```
- **算法**：
  1. 计算受影响区域（变更范围 + 上下文扩展）
  2. 从旧树中找到最大可复用的子树集合
  3. 重新 lex/parse 受影响区域，缝合新旧子树
  4. 返回新树（结构共享旧树的不变部分）

### 3.4 错误恢复（Tree-Sitter 风格）
- **Error 节点**：无法解析的区域包裹为 `ERROR` 节点，不停止解析
- **Token 跳过**：遇到意外 token 时跳过，找到下一个合法同步点
- **Token 插入**：缺少 token 时虚拟插入（`MISSING` 节点）
- 多错误收集，整棵树始终完整

### 3.5 ParseTree 查询接口（对应 Tree-Sitter Query API）
```moonbit
fn node_type(node) -> String             // 节点类型名称
fn node_text(node, input) -> String      // 对应原文本
fn node_range(node) -> Range             // 字节范围
fn node_location(node) -> (line, col)    // 行列号
fn named_children(node) -> Array[ParseNode]
fn child_by_field(node, field) -> ParseNode?
fn walk(tree, visitor)                   // 访问者遍历
fn to_sexp(tree) -> String               // S-表达式（Tree-Sitter 格式兼容）
/// 基于 pattern 的查询（简化版 Tree-Sitter Query）
fn query(tree, pattern : String) -> Array[Match]
```

### 3.6 词法器运行时
- 从序列化的 DFA 表驱动
- **上下文敏感**：当前 LR 状态决定哪些 token 合法
- Unicode 支持（UTF-8，对应 Tree-Sitter 的编码支持）

---

## 模块 4：WASM 接口（`wasm/`）

**现状**：骨架，约 30 行

**目标**（~1500 行）：

### 4.1 WASM 导出函数（供 JS/TS 调用，对应 Tree-Sitter Web 绑定）
```typescript
// 对应 web-tree-sitter 的 API
wasm_create_parser(table_bytes: Uint8Array): parser_id
wasm_parse(parser_id, source: string): tree_json
wasm_parse_incremental(parser_id, source, old_tree_id, changes_json): tree_json
wasm_node_sexp(tree_id, node_id): string
wasm_query(tree_id, pattern): matches_json
wasm_free_tree(tree_id)
wasm_free_parser(parser_id)
```

### 4.2 内存管理
- 线性内存中的字符串传递（JS → WASM）
- `parser_id / tree_id` 句柄映射表（整数 → 指针）
- MoonBit GC 与 WASM 线性内存协作

### 4.3 序列化层
- `ParseNode → JSON`（输出给 JS，含位置、类型、字段名）
- 解析表字节 → 内部 ParseTable（从 JS 传入 `.wasm` 内嵌或动态加载）
- 变更集 JSON → `Array[ChangeSet]`
- 错误信息序列化（行列号、类型、消息）

### 4.4 TypeScript 绑定
- 自动生成 `.d.ts` 类型声明
- 封装异步 WASM 加载逻辑
- 兼容 Tree-Sitter Web API 的接口形状（便于工具生态复用）

### 4.5 Node.js / 浏览器双适配
- 检测运行环境（`typeof window`）
- 同步 vs 异步初始化路径

---

## 模块 5：标准语法包（`grammars/`）

**现状**：不存在

**目标**（~2500 行）：
用于验证整个工具链，同时作为用户参考示例。

### 5.1 JSON 语法（~200 行）
- 完整 JSON 规格，测试歧义-free 文法

### 5.2 CSV 语法（~100 行）
- 基础格式，测试分隔符处理

### 5.3 TOML 语法（~300 行）
- 测试多行字符串、嵌套表

### 5.4 MoonBit 语法子集（~800 行）
- 表达式、声明、类型、模式匹配
- **自举验证**：用 MoonParse 解析 MoonParse 的 `.grammar` 文件

### 5.5 Grammar DSL 自身的语法（~200 行）
- 元语法：MoonParse 用自身定义自身的语法格式
- 可替换掉手写的 `grammar/grammar.mbt` 词法器

### 5.6 通用语法辅助片段（~300 行）
- 空白/注释（行注释/块注释）
- Unicode 标识符
- 数字字面量（整数、浮点、hex）
- 字符串字面量（转义序列）

---

## 模块 6：CLI 工具（`cmd/main/`）

**现状**：骨架

**目标**（~1000 行）：

### 6.1 命令结构（对应 `tree-sitter` CLI）
```
moonparse generate <file.grammar>         # 编译语法 → .parse_table 文件
moonparse parse <file.grammar> <input>    # 解析并输出 S-表达式树
moonparse check <file.grammar>            # 校验语法，报告冲突
moonparse fmt <file.grammar>              # 格式化 .grammar 文件
moonparse query <file.grammar> <pattern> <input>  # 执行 Query
moonparse test                            # 运行 grammars/ 测试用例
```

### 6.2 generate 命令
1. 读取 `.grammar` → `grammar/` 解析为 Grammar AST
2. `tablegen/` 构建 LALR 表 + 检测冲突
3. 序列化 → `.parse_table` 文件
4. 可选：`--diagnostic` 输出项目集、冲突报告

### 6.3 parse 命令
1. 加载 `.parse_table`
2. `runtime/` GLR 解析输入
3. 输出 S-表达式（兼容 Tree-Sitter 格式）

### 6.4 调试输出
- `--tokens`：输出词法分析结果
- `--states`：输出 LR 状态转移过程
- `--ambiguities`：输出 GLR 并行路径（歧义可视化）

### 6.5 错误友好输出
- 精确行列号高亮
- 语法冲突时给出冲突的产生式和状态

---

## 实现路线图

| 阶段 | 模块重点 | 里程碑 |
|------|---------|--------|
| **P1** grammar 完整 | grammar/ 扩展 Pattern、校验器、`prec` 支持 | grammar/ 能解析完整语法含优先级 |
| **P2** 表生成 | tablegen/ FIRST/FOLLOW + LR 项目集 + LALR 表 | 能生成 JSON 语法的解析表 |
| **P3** GLR 引擎 | runtime/ GSS + GLR 核心循环 + 词法器 | 能解析 JSON，输出正确 CST |
| **P4** 增量解析 | runtime/ 增量引擎 + 子树复用 | 编辑器场景下增量更新 |
| **P5** 错误恢复 | runtime/ ERROR 节点 + token 跳过/插入 | 语法错误时树仍完整 |
| **P6** WASM + CLI | wasm/ 完整 + cmd/ 完整 | 可发布，浏览器可用 |
| **P7** 标准语法包 | grammars/ + 自举验证 | MoonBit 子集能解析 |

---

## 关键设计决策

### 决策 1：GLR 而非 PEG（已定）
GLR 是 Tree-Sitter 架构的核心，支持天然左递归、歧义处理和精确增量解析。PEG 的有序选择虽然简单，但无法精确支持增量解析，也不能表达自然歧义文法。

### 决策 2：编译时 vs 运行时
- **编译时**（`tablegen/`）：一次性计算 LALR 表，结果序列化
- **运行时**（`runtime/`）：只需表驱动，无需 `tablegen/` 依赖
- 这使得发布的语言包只需携带 `.parse_table` 文件，不需要分发 `tablegen/`

### 决策 3：SPPF vs 普通 CST
- 暂时生成普通 CST（`Array[ParseNode]` 子节点）
- 歧义时取优先级最高路径，丢弃次优路径
- P4 后考虑引入 SPPF（共享打包解析森林）保留所有歧义解释

### 决策 4：词法器架构
- **内置词法器**：从 Grammar 的 Literal/Regex 自动构建 DFA
- **外部词法器接口**：预留 `externals` 接口，支持缩进敏感语言（Python 风格）

---

## 待确认的设计决策

1. **`generator/` 目录是否重命名为 `tablegen/`**？目前骨架文件在 `generator/`，改名需同步更新 `moon.pkg` 等配置。
2. **增量解析的优先级** — 是 P3 还是 P6 之后再做？
3. **SPPF 支持** — 是否需要保留所有歧义解释，还是取最高优先级路径即可？
4. **外部词法器接口** — 缩进敏感语言（Python 风格）是否在 1.0 范围内？


