# runtime/ 设计文档

## 概述

`runtime/` 是 MoonParse 的**运行时解析引擎**。它的定位与 tree-sitter 的 `lib/src/` 完全
对应：**只消费 `ParseTable` 数据**，不依赖 `tablegen/` 里的任何算法代码。

职责：

1. 用 `LexerDfa` 扫描输入字节流，产出 `Token` 序列（支持 context-aware 词法）
2. 用 `action / goto_table` 驱动 LR（兼 GLR）解析，构建 CST
3. 错误恢复：把语法错误降级为带代价的 `Error` 节点，始终产出完整 CST
4. 增量解析：输入有编辑时，复用未变动的旧树节点，避免全量重解析

---

## 架构总览

```
┌────────────────────────────────────────────────────────────────────────┐
│  调用方（cmd/ / wasm/ / 用户代码）                                       │
│                                                                        │
│  parse(table, input) -> CstNode                                        │
│  parse_incremental(table, input, old_tree, edit) -> CstNode            │
└─────────────────────────────┬──────────────────────────────────────────┘
                              │ runtime.mbt（公开 API 入口）
                              │
             ┌────────────────┴──────────────────┐
             │                                   │
             ▼                                   ▼
┌──────────────────────────┐       ┌──────────────────────────────────┐
│  lexer.mbt               │       │  parser.mbt                      │
│                          │       │                                  │
│  LexerEngine             │       │  主循环（单 version 线性 LR）     │
│  ──────────────────────  │◀──────│  ─────────────────────────────── │
│  · DFA 最长匹配           │ state │  · 每次 lex 前传 lr_state         │
│  · valid_tokens[state]   │       │  · action/goto 表驱动            │
│    context-aware 过滤     │       │  · 冲突时 GLR 分叉（glr.mbt）    │
│  · extras 保留进 CST      │       │  · 错误时 handle_error           │
│  · token 缓存（单槽）     │───────▶  消费 Token/LexError             │
└──────────────────────────┘       └──────────────────┬───────────────┘
                                                      │
                      ┌───────────────────────────────┤
                      │                               │
                      ▼                               ▼
     ┌────────────────────────┐       ┌───────────────────────────┐
     │  glr.mbt               │       │  recovery.mbt             │
     │                        │       │                           │
     │  GSS + Tomita GLR      │       │  三策略错误恢复            │
     │  ────────────────────  │       │  ─────────────────────    │
     │  · StackVersion 数组   │       │  · StackSummary 回退      │
     │  · 版本 merge + 剪枝   │       │  · missing token 插入     │
     │  · 代价比较消解歧义     │       │  · skip token 跳过        │
     └────────────────────────┘       └───────────────────────────┘
                                                      │
                                                      ▼
                                       ┌──────────────────────────┐
                                       │  incremental.mbt         │
                                       │                          │
                                       │  · InputEdit 标记        │
                                       │  · has_changes 传播      │
                                       │  · ReusableNode 游标     │
                                       │  · reuse 判断条件        │
                                       └──────────────────────────┘
```

### 子模块表

| 文件 | 职责 | 对应 tree-sitter |
|------|------|-----------------|
| `types.mbt` | 所有核心类型定义 | `subtree.h` / `length.h` |
| `lexer.mbt` | DFA 驱动词法，context-aware，单槽缓存 | `lexer.c` |
| `parser.mbt` | LR 主循环，调度 GLR/recovery | `parser.c` `ts_parser__advance` |
| `glr.mbt` | GSS，多版本并行，版本剪枝 | `stack.c` + 多版本路径 |
| `recovery.mbt` | 三策略错误恢复，代价函数 | `parser.c` `ts_parser__recover` |
| `incremental.mbt` | 增量复用旧节点 | `parser.c` `ts_parser__reuse_node` |
| `runtime.mbt` | 公开 API 入口 | `api.c` `ts_parser_parse` |

---

## 数据结构

### Point（行列坐标）

```moonbit
pub(all) struct Point {
  row    : Int   // 0-based 行
  column : Int   // 0-based 列（字节数，不是字符数）
}
```

### Length（位置描述符）

```moonbit
/// 描述 CST 节点的位置：字节偏移 + 行列坐标（用于增量解析的 O(1) 重新计算）
pub(all) struct Length {
  bytes  : Int    // 字节偏移（绝对或相对，由上下文决定）
  extent : Point  // 行列范围
}
```

tree-sitter 用 `padding + size` 而不是 `start + end`：
- `padding`：节点内容前的空白（不含在 size 里）
- `size`：节点内容本身的长度

这样 `total_bytes = padding.bytes + size.bytes`，增量偏移调整只需加减 Length，不用
重新扫描树。

**当前阶段**：Phase 2a/2b 用绝对 `start_byte/end_byte` 即可；增量解析（Phase 3a）时
换成 `padding+size` 表示。

### CstNode（CST 节点，统一类型）

CST 节点根据是否有子节点分两类，但用同一个结构体：

```moonbit
pub(all) struct CstNode {
  // ─── 标识 ──────────────────────────────────────────────────────
  symbol      : SymbolId   // TerminalId（叶）或 NonTerminalId（内部）
  is_named    : Bool       // true = 命名节点；false = 匿名/标点

  // ─── 位置 ──────────────────────────────────────────────────────
  start_byte  : Int
  end_byte    : Int
  start_point : Point
  end_point   : Point

  // ─── 叶节点字段（child_count == 0 时有效） ─────────────────────
  parse_state    : Int     // 创建时的 LR 状态（增量 reuse 用）
  lookahead_bytes: Int     // 词法器向前看的字节数（增量边界检查）
  is_keyword     : Bool    // 关键字 token（两阶段词法用）

  // ─── 内部节点字段（child_count > 0 时有效） ────────────────────
  children        : Array[CstNode]  // 包含 extras 子节点
  field_names     : Array[String?]  // 与 children 等长，对应字段名
  production_id   : Int             // 用于 alias 和字段名查表
  dynamic_precedence: Int           // 各级 Reduce 累积（GLR 消解用）

  // ─── 状态标记 ──────────────────────────────────────────────────
  extra         : Bool   // true = extras token，不改变 LR 状态
  is_missing    : Bool   // true = 错误恢复插入的虚拟缺失 token
  is_error      : Bool   // true = ERROR 节点（包含无法解析的内容）
  has_changes   : Bool   // true = 在增量编辑范围内，不可复用
  fragile_left  : Bool   // true = GLR 多路径合并产物，不可增量复用
  fragile_right : Bool   // 同上，右侧边界不稳
}
```

**与 tree-sitter 的对应**：tree-sitter 用内联小对象（`SubtreeInlineData`）和堆分配
（`SubtreeHeapData`）的 union 节省内存；MoonParse 在 WASM-GC 环境里用 GC 管理，
不需要引用计数，直接用结构体即可。

### SymbolId（统一符号 ID）

```moonbit
// 叶节点：SymbolId = TerminalId（正整数）
// 内部节点：SymbolId = NonTerminalId（正整数，与 terminal 空间分开）
// 特殊值：
pub let SYM_END          : SymbolId = 0    // EOF
pub let SYM_ERROR        : SymbolId = -1   // ERROR 节点
pub let SYM_ERROR_REPEAT : SymbolId = -2   // 错误恢复中间节点
```

### Token（词法单元，内部用）

```moonbit
/// 词法阶段的临时结构，不进入最终 CST
struct Token {
  terminal_id    : TerminalId
  start_byte     : Int
  end_byte       : Int
  lookahead_bytes: Int   // 词法器实际读到的末尾（>= end_byte）
  is_keyword     : Bool
}
```

### InputEdit（编辑描述）

```moonbit
pub(all) struct InputEdit {
  start_byte    : Int
  old_end_byte  : Int
  new_end_byte  : Int
  start_point   : Point
  old_end_point : Point
  new_end_point : Point
}
```

### ErrorStatus（版本代价，GLR + 错误恢复内部用）

```moonbit
struct ErrorStatus {
  cost               : Int
  node_count         : Int   // 自上次错误以来推入的节点数
  dynamic_precedence : Int
  is_in_error        : Bool
}
```

### ParseError（公开错误类型）

```moonbit
pub(all) struct ParseError {
  position : Int
  point    : Point
  message  : String  // 如 "unexpected '+', expected '(' or identifier"
}
// parse() 始终返回 CstNode（含 ERROR 节点），只有 table 损坏等极端情况才返回 ParseError
```

---

## 词法引擎（lexer.mbt）

### Context-aware 词法

LR 状态决定当前哪些 terminal 合法（`valid_tokens[lr_state]`）。词法器只尝试匹配有效的
terminal，避免歧义（例如 `do` 在某些状态是关键字，在其他状态是标识符）。

两阶段词法（对应 tree-sitter 的 keyword_capture_token，Phase 3b 实现）：
1. 先用**标识符 DFA** 匹配最长标识符
2. 检查结果是否命中**关键字表**（`keyword_map: Map[String, TerminalId]`）
3. 若命中关键字且当前状态下该关键字合法 → 返回关键字 token；否则返回标识符 token

### 单槽 Token 缓存

```moonbit
struct TokenCache {
  token      : Token?
  byte_index : Int
}
```

用途：GLR 模式下多个 stack version 处于同一 `position`，都需要下一个 token，避免
重复运行 DFA。命中条件：`cache.byte_index == pos && can_reuse_first_leaf(state, token)`。

### Extras 处理

Extras（空白、注释等）**保留在 CST 里**，标记 `extra=true`。shift extras token 时 LR
状态不变（`next_state = current_state`），不影响解析路径，但节点存在于 CST 里，格式
化工具和注释附着功能可以使用。

### LexerEngine 接口

```moonbit
struct LexerEngine {
  dfa   : LexerDfa
  cache : TokenCache
}

fn LexerEngine::new(dfa : LexerDfa) -> LexerEngine

/// 从 input[pos..] 扫描下一个 token
/// extras 也扫描，标记 is_extra=true（由 parser 决定如何 shift）
/// 返回 (token, new_pos)；token=None 表示 EOF；token.terminal_id=SYM_ERROR 表示词法错误
fn LexerEngine::next_token(
  self  : LexerEngine,
  input : String,
  pos   : Int,
  table : ParseTable,
  state : StateId,
) -> (Token?, Int)
```

### 词法算法

```
1. 检查 token 缓存：cache.byte_index == pos → 尝试 can_reuse → 命中则直接返回

2. valid = valid_tokens[state] ∪ table.extras

3. DFA 最长匹配：
   从 dfa.start 出发，走 transitions
   每到达 accept 状态时记录 (accept_symbol, current_pos) 为候选
   到无 transition 为止，取最后记录的候选

4. 候选不在 valid 里 → 进入错误模式（error_mode=true），
   用 ERROR_STATE 的 lex_mode 重新扫描，跳过单字节

5. is_extra = accept_symbol ∈ table.extras
   if is_extra: 产出 token 时标记 extra=true；parser shift 时 next_state=current_state

6. 更新 cache
```

---

## LR 主循环（parser.mbt）

### 栈结构

线性 LR（单 version）：

```moonbit
struct StackFrame {
  state : StateId
  node  : CstNode?   // None 只在 frame[0]（底部哨兵）
}
```

GLR 时每个 `StackVersion` 是独立的 `Array[StackFrame]`，由 `glr.mbt` 管理。

### 主循环伪代码

```
stack = [{state=1, node=None}]   // tree-sitter 初始 state=1（0=ERROR_STATE）
pos = 0

loop:
  state = stack.top.state
  (tok, new_pos) = lexer.next_token(input, pos, table, state)
  lookahead = tok ?? EOF_TOKEN

  actions = table.action.get((state, lookahead.terminal_id))

  if actions 为空:
    handle_error(stack, lookahead)
    continue

  // Phase 2a：取 actions[0]；Phase 2c：多 action → GLR 分叉
  for action in actions:
    match action:

      Shift(next_state):
        if lookahead.is_extra:
          // extra 不改变 LR 状态
          stack.push({state=state, node=make_leaf(lookahead, extra=true)})
        else:
          stack.push({state=next_state, node=make_leaf(lookahead)})
        pos = new_pos
        break  // shift 终止本轮，继续下轮 loop

      Reduce(prod_id):
        prod = table.productions[prod_id]
        if !check_lookahead_constraint(prod.lookahead, lookahead): continue
        children = stack.pop_n(prod.body.length)
        (children, trailing_extras) = remove_trailing_extras(children)
        goto_state = table.goto_table[(stack.top.state, prod.head)]
        is_fragile = (action_count > 1 || glr_merge_happened)
        node = make_inner_node(prod, children, goto_state, is_fragile)
        node.dynamic_precedence += prod.prec  // 累积
        stack.push({state=goto_state, node=node})
        for e in trailing_extras: stack.push({state=goto_state, node=e})

      Accept:
        return Ok(stack.top.node)
```

### Trailing Extras

Reduce 时，栈顶可能有 extra token（注释贴在行尾等情况）。这些 token **不属于**当前
规则，需要在 reduce 后重新推回栈顶（与 tree-sitter 的 `trailing_extras` 数组一致）。

### Fragile 标记

以下情况产生的内部节点标记 `fragile_left=true && fragile_right=true`：
- `action_count > 1`（存在冲突，取了其中一个 action）
- `initial_version_count > 1`（由 GLR 分叉路径 merge 产生）

Fragile 节点不能增量复用（词法上下文可能因另一路径而不同）。

---

## GLR 引擎（glr.mbt）

### Graph-Structured Stack（GSS）

tree-sitter 用 `StackVersion` (uint32) 作为并行路径的 index。MoonParse 等效地用：

```moonbit
struct GssState {
  versions      : Array[StackVersion]
  finished_tree : CstNode?
  accept_count  : Int
}

struct StackVersion {
  frames                 : Array[StackFrame]
  error_cost             : Int
  node_count_since_error : Int
  dynamic_precedence     : Int
  is_active              : Bool
  is_paused              : Bool
  paused_lookahead       : Token?
}
```

### 版本上限与 Condense

```
MAX_VERSION_COUNT          = 6
MAX_VERSION_COUNT_OVERFLOW = 4
MAX_COST_DIFFERENCE        = 18 × ERROR_COST_PER_SKIPPED_TREE
```

`condense_stack` 在每轮 advance 后执行：
1. 移除 `is_halted` 版本
2. 合并处于相同 `(state, position)` 的版本（`merge`）
3. 若某版本代价 > 最优 + `MAX_COST_DIFFERENCE` → 移除
4. 若 `finished_tree.error_cost <= min_active_cost` → 清栈，结束

### 版本推进主循环

```
do:
  for version in 0..version_count:
    allow_reuse = (version_count == 1)
    while version.is_active:
      advance(version, allow_reuse)

  min_error_cost = condense_stack()
  if finished_tree && finished_tree.error_cost < min_error_cost:
    clear_stack(); break

while version_count != 0

// 最终对重复节点链做树形平衡（repeat_depth 字段控制深度）
balance_subtree(finished_tree)
```

### 版本 Merge

两个 version 可以 merge 当且仅当它们到达相同的 `(state, parse_position)`。Merge
产生的节点标记 fragile。

---

## 错误恢复（recovery.mbt）

### 代价常量

```moonbit
let ERROR_COST_PER_SKIPPED_TREE  = 100
let ERROR_COST_PER_SKIPPED_CHAR  = 1
let ERROR_COST_PER_SKIPPED_LINE  = 30
let ERROR_COST_PER_MISSING_TREE  = 110
```

### StackSummary

进入 ERROR 状态时，记录最近历史状态快照：

```moonbit
struct StackSummaryEntry {
  state    : StateId
  position : Length
  depth    : Int
}

let MAX_SUMMARY_DEPTH = 16
type StackSummary = Array[StackSummaryEntry]
```

### 三策略顺序

#### 策略 1：回退到历史合法状态（`recover_to_state`）

```
for entry in stack_summary:
  if entry.state == ERROR_STATE: skip
  if entry.position == current_position: skip  // 避免零进展

  new_cost = current_error_cost
           + entry.depth × COST_PER_SKIPPED_TREE
           + (pos - entry.position.bytes) × COST_PER_CHAR
           + (row - entry.position.row) × COST_PER_LINE

  if better_version_exists(new_cost): break

  if lookahead 在 entry.state 里有合法 action:
    pop depth 帧，包装成 ERROR 节点
    push ERROR 节点，state = entry.state
    did_recover = true; break
```

#### 策略 2：插入缺失 token（`insert_missing_token`）

```
for missing_symbol in 1..token_count:
  state_after = table.goto_table[(current_state, missing_symbol)]
  if state_after == 0 || state_after == current_state: skip

  if lookahead 在 state_after 里能触发 reduce:
    创建 is_missing=true 虚拟节点
    push，state = state_after
    do_all_potential_reductions(state_after, lookahead)
    did_insert = true; break
```

#### 策略 3：跳过当前 token（`skip_token`）

```
if better_version_exists(cost_with_skip): 放弃此版本

创建 ERROR_REPEAT 节点包裹 lookahead
if node_count_since_error > 0:
  pop 一帧，把上一个 ERROR_REPEAT 合并进来
push ERROR_REPEAT，state = ERROR_STATE
继续消耗下一个 token
```

### `better_version_exists`

```
if finished_tree.error_cost <= new_cost: return true
for version in all_versions:
  if version.position.bytes < current.position.bytes: skip
  if version_status(version) dominates new_cost: return true
return false
```

### `do_all_potential_reductions`

在错误恢复或 lookahead 切换时，对当前状态强制尝试所有可能的 reduce（不管 lookahead
是什么）。这扩大了可能恢复的窗口，产生的新版本再进入 `condense_stack` 剪枝。

---

## 增量解析（incremental.mbt）

### InputEdit 应用

```moonbit
fn apply_edit(root : CstNode, edit : InputEdit) -> CstNode
```

从根节点向下遍历，对每个节点：
- `node.end_byte <= edit.start_byte` → 不受影响，`has_changes = false`
- `node.start_byte >= edit.old_end_byte` → 偏移调整（`+= delta`），`has_changes = false`
- 其他（与编辑区间有交叉）→ `has_changes = true`

### ReusableNode 游标

```moonbit
struct ReusableNode {
  stack              : Array[(CstNode, Int)]  // (node, child_index) 路径
  last_external_token: CstNode?
}
```

游标遍历旧树，按 `position` 顺序提供候选节点。主循环中，在调用词法器之前先尝试
`reuse_node`，再尝试 `get_cached_token`，最后才真正运行 DFA。

### 节点复用条件（`can_reuse_node`）

**不可复用的条件**（任意一条成立则重解析）：
- `node.has_changes`（在编辑区间内）
- `node.is_error`
- `node.is_missing`
- `node.fragile_left || node.fragile_right`
- 节点字节范围与 `included_range_differences` 有交叉
- 叶节点：`leaf.parse_state` 与当前 LR 状态下的 lex_mode 不匹配
- 叶节点：`leaf.lookahead_bytes` 超出当前 edit 范围

**Breakdown**：若整棵节点不可复用但其叶可能可复用，展开节点：把 children 依次推回
游标候选队列，逐一检查。

---

## 公开 API（runtime.mbt）

```moonbit
/// 全量解析，返回完整 CST（含 ERROR/MISSING 节点）
/// 始终成功（table 有效时）
pub fn parse(
  table : ParseTable,
  input : String,
) -> CstNode

/// 增量解析
pub fn parse_incremental(
  table    : ParseTable,
  input    : String,
  old_tree : CstNode,
  edit     : InputEdit,
) -> CstNode

/// GLR 模式，返回所有解析树（歧义文法有多棵）
pub fn parse_glr(
  table : ParseTable,
  input : String,
) -> Array[CstNode]

/// 从二进制字节反序列化 ParseTable
pub fn load_table(bytes : Bytes) -> Result[ParseTable, String]
```

**返回值语义**：`parse` / `parse_incremental` **始终返回 CstNode**，不返回 `Result`。
错误通过 CST 里的 `ERROR` / `MISSING` 节点传达（与 tree-sitter 一致）。

---

## 文件结构与估计行数

| 文件 | 职责 | 估计行数 |
|------|------|---------|
| `types.mbt` | `CstNode` / `Token` / `Length` / `Point` / `InputEdit` / `ErrorStatus` / `StackSummary` | ~150 |
| `lexer.mbt` | `LexerEngine`：DFA，extras，token 缓存，两阶段 keyword（Phase 3b） | ~200 |
| `parser.mbt` | 主循环，trailing extras，fragile，调度 GLR/recovery | ~250 |
| `glr.mbt` | `GssState`，StackVersion，condense，merge，版本上限 | ~300 |
| `recovery.mbt` | 三策略 + `StackSummary` + 代价函数 + `insert_missing` | ~250 |
| `incremental.mbt` | `apply_edit`，`ReusableNode`，`reuse_node`，`breakdown` | ~200 |
| `runtime.mbt` | 公开 API 入口，`load_table` | ~80 |
| `runtime_test.mbt` | 端到端测试 | ~400 |
| **合计** | | **~1830** |

---

## 实现阶段

### Phase 2a — 最小可用 LR 解析器

**目标**：`parse(table, input)` 输出完整 CST，extras 以 `extra=true` 节点保留。

- [ ] `types.mbt`：完整字段的 `CstNode`（未用字段置零/false）、`Token`、`Point`、`ParseError`
- [ ] `lexer.mbt`：DFA 最长匹配，extras 标记，单槽缓存（暂不做 keyword 两阶段）
- [ ] `parser.mbt`：线性 LR 主循环，trailing extras 分离，冲突取 `actions[0]`
- [ ] `runtime.mbt`：`parse()` 入口（单路径，无增量）
- [ ] `runtime_test.mbt`：算术表达式 + 空白 extras 端到端测试

`parse_state`、`lookahead_bytes`、`fragile_*`、`has_changes` 字段在 Phase 2a 留零，
后续阶段填充，不影响当前 API 形状。

### Phase 2b — 错误恢复

**目标**：任意输入都能产出完整 CST，错误区域用 ERROR/MISSING 节点表示。

- [ ] `recovery.mbt`：`StackSummary`，三策略，代价函数，`insert_missing_token`
- [ ] `parser.mbt`：接入 `handle_error`，`do_all_potential_reductions`
- [ ] `types.mbt`：补全 `is_missing`、`is_error`、`error_cost` 语义
- [ ] 测试：故意喂入错误语法，验证 ERROR 节点位置和代价

### Phase 2c — GLR

**目标**：歧义文法和 shift/reduce 冲突文法正确解析（不再盲目取 `actions[0]`）。

- [ ] `glr.mbt`：`GssState`，多版本推进，`condense_stack`，版本 merge
- [ ] `parser.mbt`：dispatch 多 action 到 GLR
- [ ] `types.mbt`：`fragile_*`、`dynamic_precedence` 实际填充
- [ ] `runtime.mbt`：`parse_glr()` 入口
- [ ] 测试：歧义文法，验证多棵树 / 动态优先级消解

### Phase 3a — 增量解析

**目标**：输入有小改动时，复用旧树节点，解析速度接近 O(edit_size)。

- [ ] `incremental.mbt`：`apply_edit`，`ReusableNode`，`reuse_node`，`breakdown`
- [ ] `types.mbt`：`parse_state`、`lookahead_bytes`、`has_changes`、`fragile_*` 实际填充
- [ ] `runtime.mbt`：`parse_incremental()` 入口
- [ ] 测试：大文件 + 小编辑，验证 reuse 率

### Phase 3b — 两阶段 keyword 词法

**目标**：支持上下文相关关键字（如 `async`/`await` 只在特定状态是关键字）。

- [ ] `lexer.mbt`：keyword DFA，两阶段检查
- [ ] `tablegen/`：生成 `keyword_capture_token` 和 `keyword_map`（需回头改 tablegen）
- [ ] 测试：含关键字冲突的语法
