# tablegen/ 设计文档

## 整体架构

### 包之间的依赖关系

```
用户 DSL 字符串
      │
      ▼
┌──────────────────────────────────────────────────────────┐
│  grammar/  —— DSL 前端                                    │
│                                                          │
│  lexer.mbt ──▶ parser.mbt ──▶ validator.mbt              │
│  String→Token   Token→AST     AST→[Error]                │
│                                                          │
│  types.mbt：Grammar / Rule / Pattern / PrecDecl          │
│  serializer.mbt：grammar_to_string / grammar_to_json     │
└───────────────────────────┬──────────────────────────────┘
                            │ Grammar
                            ▼
┌──────────────────────────────────────────────────────────┐
│  tablegen/  —— 离线解析表编译器（依赖 grammar/）           │
│                                                          │
│  ① normalize.mbt                                        │
│     augment_grammar(Grammar) → AugmentedGrammar         │
│     · Choice/Repeat/Plus/Optional 展开为基础产生式        │
│     · 引入增广起始符 $accept → start $                   │
│     · 注册所有 Literal/Regex → TerminalId                │
│          │                                               │
│          │ AugmentedGrammar                              │
│     ┌────┴─────────────────────────────┐                 │
│     │                                  │                 │
│     ▼                                  ▼                 │
│  ② sets.mbt                    ③ items.mbt              │
│     nullable / FIRST / FOLLOW     LR(0) 项目集族         │
│     (内部计算，不进入 ParseTable)   build_item_sets()     │
│                                   build_goto_map()       │
│                │                       │                 │
│                └───────────┬───────────┘                 │
│                            ▼                             │
│                    ④ lalr.mbt                            │
│                       build_lalr_table(                  │
│                         aug, item_sets, goto_map)        │
│                       → ParseTable (含冲突)              │
│                            │                             │
│                            ▼                             │
│                    ⑤ conflicts.mbt                       │
│                       resolve_conflicts(table, grammar)  │
│                       → (ParseTable resolved, [Report])  │
│                            │                             │
│          ┌─────────────────┘                             │
│          │ ParseTable resolved                           │
│          │                                               │
│          │         AugmentedGrammar（来自步骤①）──────┐  │
│          ▼                     ▼                      │  │
│       ⑥ lexer.mbt ◀───────────┘                      │  │
│          build_lexer_dfa(aug, table)                  │  │
│          → LexerDfa                                   │  │
│          (Phase 2：注入 ParseTable.lexer_dfa)          │  │
│          │                                            │  │
│          └──────────────────────────────────────────┐  │  │
│                                                     │  │  │
│  tablegen.mbt  ←─────── 一键入口（调用 ①~⑦）  ◀───┘  ◀┘  │
│  generate_parse_table(Grammar)                           │
│  → Result[(ParseTable, [Report])]                        │
│       │                                                  │
│       ▼                                                  │
│  ⑦ serialize.mbt                                        │
│                       table_to_json()  → String  ✅      │
│                       serialize_table() → Bytes  ✅      │
│                       deserialize_table() → …   ✅       │
└───────────────────────────┬──────────────────────────────┘
                            │ JSON / .parse_table 文件
                            ▼
┌──────────────────────────────────────────────────────────┐
│  runtime/  —— 运行时解析引擎（Phase 2，尚未实现）          │
│                                                          │
│  · deserialize_table() 加载 ParseTable                   │
│  · LexerDfa 扫描输入字节流 → Token                       │
│  · action / goto_table 驱动 shift / reduce               │
│  · extras token（空白、注释）直接跳过，不推栈             │
│  · GLR：action 含多个动作时并行分叉保留全部路径           │
│  · 输出：CST（具体语法树）/ AST（抽象语法树）             │
└──────────────────────────────────────────────────────────┘
```

### 数据类型流转

```
String
  └─[grammar/parser]──▶ Grammar
                          ├─ rules        : Map[String, Rule]
                          ├─ precedences  : Array[PrecDecl]
                          └─ start        : String?

Grammar
  └─[normalize]──▶ AugmentedGrammar
                     ├─ terminals         : Map[String, TerminalId]
                     ├─ nonterminals      : Map[String, NonTerminalId]
                     ├─ productions       : Array[Production]
                     ├─ terminal_patterns : Map[TerminalId, TerminalDef]
                     ├─ extras            : Array[TerminalId]
                     └─ nt_metas         : Array[SymbolMeta]   ← ⚠️ 当前未透传（见已知缺陷）

AugmentedGrammar
  ├─[sets]──────▶ nullable / FIRST / FOLLOW  (内部，不序列化)
  ├─[items]─────▶ Array[Set[LRItem]]
  │               Map[(StateId, Symbol), StateId]
  ├─[lalr]──────▶ ParseTable
  │                 ├─ action       : Map[(StateId, TerminalId), Array[Action]]
  │                 ├─ goto_table   : Map[(StateId, NonTerminalId), StateId]
  │                 ├─ productions  : Array[Production]
  │                 ├─ lexer_dfa    : LexerDfa   ← Phase 2 由 lexer.mbt 填充
  │                 └─ symbol_metadata : Array[SymbolMeta]
  └─[lexer]─────▶ LexerDfa
                    ├─ states       : Array[DfaState]
                    ├─ start        : DfaStateId
                    └─ valid_tokens : Map[StateId, Array[TerminalId]]

(ParseTable + AugmentedGrammar)
  └─[conflicts]──▶ (ParseTable resolved, Array[ConflictReport])

ParseTable
  └─[serialize]──▶ JSON String  (Phase 1 ✅)
                   Bytes         (Phase 2)
```

### lexer.mbt 与其他模块的关系

`lexer.mbt` 是唯一**同时读取 `AugmentedGrammar` 和 `ParseTable`** 的模块：

- 从 `grammar.terminal_patterns` 取词法规则（Literal/Regex/AnyChar）→ Thompson NFA → 子集构造 → DFA
- 从 `table.action` 取每个解析状态的合法 token → 填入 `LexerDfa.valid_tokens`

**Phase 1 现状**：`build_lexer_dfa()` 已实现，但 `generate_parse_table()` 尚未调用它，`ParseTable.lexer_dfa` 仍是空桩。接通只需在 `tablegen.mbt` 末尾加：

```moonbit
let real_dfa = build_lexer_dfa(aug, resolved_table)
let final_table = { ..resolved_table, lexer_dfa: real_dfa }
Ok((final_table, reports))
```

---

## 模块定位

`tablegen/` 是 MoonParse 的**编译时核心**。

- **输入**：`grammar/` 包产出的 `Grammar` AST
- **输出**：序列化的 `ParseTable`（`.parse_table` 文件 / 内存字节）
- **依赖**：`grammar/`
- **被依赖**：`cmd/`（CLI generate 命令）；`runtime/` 在运行时直接加载序列化表，不依赖本包

**设计原则**：表生成是一次性离线操作，允许较高时间复杂度；生成后的表为只读数据，运行时零计算开销。

---

## 模块设计

tablegen/ 内部拆分为 5 个职责单一的子模块，与后文 §1~§7 章节一一对应：

### 子模块 1：文法规范化（Grammar Normalizer）→ `normalize.mbt`

**职责**：将用户编写的 DSL Grammar 转换为计算机易于处理的标准型（Canonical Form）。

- **产生式提取**：将 Choice、Repeat、Optional、Plus 等高阶 Pattern 展开为基础递归产生式（见 §1 展开规则表）
- **左递归统一**：Repeat(p) 展开为 A → ε | A p（左递归），GLR 天然支持，无需消除
- **增广文法构建**：自动添加 S' → StartSymbol $

### 子模块 2：符号属性计算（Symbol Property Calculator）→ sets.mbt

**职责**：这是整个解析表的数学基础，负责三项核心集合计算。

- **Nullable 探测**：不动点迭代识别哪些非终结符可推导出 ε
- **FIRST & FOLLOW 集合**：计算每个非终结符可能出现在最左侧（FIRST）和紧随其后（FOLLOW）的终结符集合

> 注：优先级与结合性信息由 `normalize.mbt` 在展开产生式时注入（内联 `Prec`），并由 `conflicts.mbt` 的 `resolve_conflicts()` 在消解冲突时查询产生式 `.prec/.assoc`。`sets.mbt` 本身只做 nullable/FIRST/FOLLOW，不涉及优先级。

### 子模块 3：LR 自动机生成器（LR Automaton Builder）→ items.mbt + lalr.mbt

**职责**：工程量最大的部分，构建解析 DFA。

- **项目集闭包（Closure）**：给定一个带 • 的解析位置，推导出所有后续可能路径
- **GOTO 转移函数**：计算在状态 A 见到符号 X 后切换到哪个状态 B
- **LALR(1) 状态压缩**：合并具有相同核心（Kernel）的项目集，减小解析表体积，避免状态爆炸

### 子模块 4：词法器编译器（Lexer Compiler）→ lexer.mbt

**职责**：Tree-Sitter 的词法分析是"受控"的（上下文感知），而非独立扫描。

- **Regex → DFA**：Thompson 构造法（Regex → NFA）+ 子集构造法（NFA → DFA）+ Hopcroft 最小化
- **上下文感知**：为每个 LR 状态生成"当前合法 Token 列表"（`valid_tokens` 映射）——解析 if 语句时词法器自动忽略不可能出现的符号，消除词法歧义

### 子模块 5：冲突解决与发射器（Conflict Resolver & Emitter）→ conflicts.mbt + serialize.mbt

**职责**：处理逻辑矛盾并产出最终产物。

- **移进/规约冲突处理（S/R Conflict）**：按优先级/结合性自动选择路径；无法解决时标记为 `Ambiguous`，为 GLR 并行解析保留空间
- **表压缩（Table Compression）**：原始解析表极大且稀疏，采用偏移量压缩（offset encoding）让生成的 .parse_table 控制在几十 KB
- **二进制序列化**：将内存中的 Map / Set 按照 §7 定义的格式写入二进制流

## 端到端数据流

```
Grammar AST
  │
  ▼ augment_grammar()            §1 增广文法构建
AugmentedGrammar
  │
  ├─ first_set() / follow_set()  §2 FIRST/FOLLOW（内部用，不输出）
  │
  ▼ build_item_sets()            §3 LR(0) 项目集族
Array[Set[LRItem]]
  │
  ▼ build_goto_map()             §3 GOTO 转移表
Map[(StateId, Symbol), StateId]
  │
  ▼ build_lalr_table()           §4 LALR(1) 表（含冲突）
ParseTable
  │
  ▼ resolve_conflicts()          §5 优先级过滤
  │
  ├──────────────────────────────────────────────────────────┐
  │ ParseTable resolved                    AugmentedGrammar  │
  │                                                          │
  ▼                             ◀───────────────────────────-┘
build_lexer_dfa(aug, table)     §6 词法器 DFA（Phase 2）
  │
  ▼
LexerDfa → 注入 ParseTable.lexer_dfa
  │
  ▼ table_to_json() / serialize_table()  §7 序列化
JSON String / Bytes (.parse_table)
```

---

## §1 增广文法构建

将用户 Grammar 扁平化为 `(非终结符, 产生式序列)` 的 CFG 标准形式。

```moonbit
/// 扁平化后的符号
pub(all) enum Symbol {
  Terminal(TerminalId)
  NonTerminal(NonTerminalId)
  EndOfInput
}

/// 产生式体中携带字段元数据的符号包装
/// field_name 来自 Pattern::Field("name", p) 或 Pattern::Tagged("tag", p)
pub(all) struct BodySymbol {
  symbol     : Symbol
  field_name : String?   // Some("left") for Field/Tagged; None otherwise
}

/// 产生式：A → β
pub(all) struct Production {
  id       : ProductionId
  head     : NonTerminalId
  body     : Array[BodySymbol]
  prec     : Int?             // 继承自 Pattern::Prec 或优先级声明
  assoc    : PrecKind?        // Left | Right | Nonassoc
  rule_name : String          // 来源规则名（调试用）
}

/// 增广后的文法
pub(all) struct AugmentedGrammar {
  start       : NonTerminalId            // S'
  terminals   : Map[String, TerminalId]
  nonterminals: Map[String, NonTerminalId]
  productions : Array[Production]
  terminal_patterns : Map[TerminalId, TerminalDef]
  /// 总是合法的 token（对应 Grammar.extras），可出现在任意位置（空白、注释等）
  extras      : Array[TerminalId]
  /// 非终结符元数据，indexed by NonTerminalId（由 normalize.mbt 从 Rule.is_named 准确填充）
  nt_metas    : Array[SymbolMeta]
  /// 顶层优先级声明（来自 Grammar.precedences），供 conflicts.mbt 查找 shift 优先级
  prec_table  : Map[TerminalId, (Int, @grammar.PrecKind)]
}

pub(all) enum TerminalDef {
  Literal(String)
  Regex(String)
  AnyChar
}

/// 主入口：Grammar → AugmentedGrammar
pub fn augment_grammar(grammar : Grammar) -> AugmentedGrammar
```

**Pattern → 产生式展开规则**：

| Pattern 变体 | 展开方式 |
|-------------|---------|
| `Literal(s)` / `Regex(re)` / `AnyChar` | 注册为终结符 |
| `RuleRef(name)` | 引用同名非终结符 |
| `Seq([a,b,c])` | `A → a b c` |
| `Choice([a,b])` | `A → a`，`A → b`（两条产生式） |
| `Repeat(p)` | `A → ε`，`A → A p`（左递归，GLR 天然支持） |
| `Plus(p)` | `A → p`，`A → A p` |
| `Optional(p)` | `A → ε`，`A → p` |
| `RepeatRange(p,n,m)` | 展开为 n 次必须 + (m-n) 次 Optional |
| `Tagged(tag, p)` / `Field(name, p)` | 透传 p；对应 BodySymbol.field_name = Some(tag/name) |
| `Not(p)` / `And(p)` | 提取终结符 ID 生成 `LookaheadConstraint`（零宽断言），注入 `Production.lookahead`；复杂嵌套 pattern 回退透传（Phase 3） |
| `Prec(level, kind, p)` | 透传 p，level/kind 注解到产生式 |

---

## §2 FIRST / FOLLOW 集合计算

```moonbit
/// 计算 FIRST(α)：α 序列最左可能出现的终结符集合
pub fn first_seq(grammar : AugmentedGrammar, seq : Array[Symbol]) -> Set[TerminalId]

/// 计算单个符号的 FIRST
pub fn first_set(grammar : AugmentedGrammar, sym : Symbol) -> Set[TerminalId]

/// 计算非终结符的 FOLLOW 集合
pub fn follow_set(grammar : AugmentedGrammar, nt : NonTerminalId) -> Set[TerminalId]

/// 判断符号序列是否可推导出 ε
pub fn nullable(grammar : AugmentedGrammar, seq : Array[Symbol]) -> Bool
```

**算法**：标准不动点迭代，直到集合不再变化。记忆化每个非终结符的 nullable / FIRST / FOLLOW。

---

## §3 LR(0) 项目集构建

```moonbit
/// LR(0) 项目：[A → α • β]
pub(all) struct LRItem {
  prod : ProductionId
  dot  : Int              // • 的位置（0..=body.len）
}

/// 项目集闭包：closure(I)
///   对 I 中所有 [A → α • B β]，将 B 的所有产生式 [B → • γ] 加入
pub fn closure(grammar : AugmentedGrammar, items : Set[LRItem]) -> Set[LRItem]

/// GOTO(I, X)：把 • 越过 X 后的项目集的闭包
pub fn goto_set(grammar : AugmentedGrammar, items : Set[LRItem], sym : Symbol) -> Set[LRItem]

/// 构建规范 LR(0) 项目集族（DFA 状态集合）
pub fn build_item_sets(grammar : AugmentedGrammar) -> Array[Set[LRItem]]

/// 每个状态的 GOTO 转移
pub fn build_goto_map(
  grammar   : AugmentedGrammar,
  item_sets : Array[Set[LRItem]]
) -> Map[(StateId, Symbol), StateId]
```

**实现要点**：
- 用规范集合（排序后的 `LRItem` 数组）作 Map key，实现项目集去重
- BFS 遍历新状态，直到无新状态产生

---

## §4 LALR(1) 解析表构建

LALR(1) = LR(0) 项目集 + 向前看符号（lookahead）合并自 FOLLOW 集合。

```moonbit
/// 解析动作
pub(all) enum Action {
  Shift(StateId)
  Reduce(ProductionId)
  Accept
}

/// 非终结符的符号元数据（对应 Rule.is_named）
pub(all) struct SymbolMeta {
  name     : String   // 规则名
  is_named : Bool     // false = 匿名节点，不暴露给用户 AST
}

/// 解析表
pub(all) struct ParseTable {
  states      : Int
  /// action[(state, terminal)] 可能含多个动作（GLR 冲突）
  action      : Map[(StateId, TerminalId), Array[Action]]
  /// goto[(state, nonterminal)] → 目标状态
  goto_table  : Map[(StateId, NonTerminalId), StateId]
  productions : Array[Production]
  /// 词法器 DFA（与解析表打包）
  lexer_dfa   : LexerDfa
  /// 非终结符元数据，indexed by NonTerminalId（用于生成 AST 节点类型）
  symbol_metadata : Array[SymbolMeta]
  /// 终结符 pattern 定义，供词法器重建和 runtime 使用
  terminal_patterns : Map[TerminalId, TerminalDef]
  /// TerminalId → 可读名称（从 AugmentedGrammar.terminals 反转），供 runtime 错误信息使用
  terminal_names : Map[TerminalId, String]
}

/// 主接口
pub fn build_lalr_table(
  grammar   : AugmentedGrammar,
  item_sets : Array[Set[LRItem]],
  goto_map  : Map[(StateId, Symbol), StateId]
) -> ParseTable
```

**向前看符号计算（LALR 合并）**：
1. 对 LR(0) 项目集中每个 reduce 项 `[A → α •]`
2. 其 lookahead = `FOLLOW(A)`（经典 LALR 近似，比 LR(1) 状态少）
3. 合并同一 LR(0) 状态下的所有同名非终结符的 lookahead

**`is_named` 来源**：`build_lalr_table()` 从 `grammar.nt_metas` 直接读取（由 `normalize.mbt` 按 `Rule.is_named` 准确填充），不再使用名称前缀启发式。

---

## §5 冲突处理

**冲突类型**：

| 类型 | 来源 | 默认策略 |
|------|------|---------|
| Shift-Reduce | 文法歧义 / 需要 `prec` | 保留所有动作（GLR） |
| Reduce-Reduce | 文法歧义 | 保留所有动作（GLR） |

```moonbit
pub(all) enum ConflictSeverity {
  /// 有 prec/assoc 信息可过滤次优路径（编译期消解）
  Warn(String)
  /// 无优先级信息，GLR 并行保留
  Ambiguous(String)
  /// prec.dynamic 冲突：编译期无法消解，运行时由 runtime/ 比较动态整数值
  DynamicConflict(Int)   // 携带 dynamic prec id，便于 runtime/ 查找
}

pub(all) struct ConflictReport {
  state     : StateId
  terminal  : TerminalId
  actions   : Array[Action]
  severity  : ConflictSeverity
}

/// 用优先级/结合性过滤冲突，无法过滤的报告为 Ambiguous
pub fn resolve_conflicts(
  table    : ParseTable,
  grammar  : AugmentedGrammar
) -> (ParseTable, Array[ConflictReport])
```

**优先级过滤规则**（借鉴 Tree-Sitter）：
- Shift 的优先级 = 下一个终结符对应的最高 `prec` 级别
- Reduce 的优先级 = 被规约产生式的 `prec` 级别
- 若 Shift > Reduce：删除 Reduce（或按结合性决定）
- 若相等且 Left 结合：删除 Shift；Right 结合：删除 Reduce

---

## §6 词法器集成

词法器在**上下文敏感**模式下工作：当前 LR 状态决定哪些 token 合法，减少误匹配。

```moonbit
/// NFA 状态（Thompson 构造）
priv struct NfaState { ... }

/// DFA 状态（子集构造；Hopcroft 最小化留 Phase 3）
pub(all) struct DfaState {
  id          : DfaStateId
  transitions : Map[Char, DfaStateId]
  accept      : TerminalId?    // 接受的 terminal（优先级最高者）
}

pub(all) struct LexerDfa {
  states      : Array[DfaState]
  start       : DfaStateId
  /// valid_tokens[s] = { t | action[(s,t)] ≠ ∅ } ∪ extras_set
  valid_tokens : Map[StateId, Array[TerminalId]]  // 实现用 Array，非 Set
}

/// Literal / Regex → NFA → DFA 最小化
pub fn build_lexer_dfa(
  grammar   : AugmentedGrammar,
  table     : ParseTable
) -> LexerDfa
```

**Regex → NFA**：Thompson 构造，支持：`.` `*` `+` `?` `|` `[...]` `\d` `\w` `\s`。MoonBit 标准库无内置 NFA，需自实现（~400 行）。

**词法器 Token 优先级**（歧义消解顺序）：
1. `Literal` 优先于 `Regex`（精确字符串 > 正则表达式）
2. 同类型中，**声明顺序靠前者优先**
3. 最终依赖最长匹配（DFA 天然满足）

**valid_tokens 公式**：`valid_tokens[s] = { t | action[(s,t)] ≠ ∅ } ∪ extras_set`，  
其中 `extras_set = Set{ t | t ∈ AugmentedGrammar.extras }`。

### §6.5 Extras 机制

Extras（对应 `Grammar.extras`）是**可出现在任意位置**的 token，典型示例：空白符 `\s+`、行注释 `//…`。

- `AugmentedGrammar.extras : Array[TerminalId]` 收集所有 extras terminal
- 每个 LR 状态的 `valid_tokens[s]` 均自动包含此集合，因此词法器始终尝试匹配 extras
- Extras token 被识别后**不推入 LR 栈**，运行时引擎直接忽略（或挂到 CST 叶节点作为 trivia）

---

## §7 解析表序列化

```moonbit
/// 序列化为紧凑二进制（小端字节序）
pub fn serialize_table(table : ParseTable) -> Bytes

/// 从字节反序列化（运行时加载，无需依赖 tablegen/）
pub fn deserialize_table(bytes : Bytes) -> Result[ParseTable, String]

/// JSON 格式（调试 / 工具集成用）
pub fn table_to_json(table : ParseTable) -> String
```

**二进制格式**（版本 1）：
```
magic    : [0x4D, 0x50, 0x54, 0x01]   // "MPT\x01"
states   : u32
prods    : u32
act_count: u32
...action entries (state_id u16, term_id u16, action_tag u8, target u16)...
...goto entries  (state_id u16, nt_id u16, target u16)...
...productions   (head u16, body_len u8, body[symbol_tag u8, id u16, field_name_idx u8]...)...
...lexer dfa     (states, transitions, accept)...
...field_names   (count u16, entries: [nt_id u16, sym_pos u8, name_len u8, name: bytes]...)...
...sym_metadata  (count u16, entries: [nt_id u16, is_named u8, name_len u8, name: bytes]...)...
```

---

## 公开 API 汇总

```moonbit
// 主流程（四步）
pub fn augment_grammar(grammar : Grammar) -> AugmentedGrammar
pub fn build_item_sets(grammar : AugmentedGrammar) -> Array[Set[LRItem]]
pub fn build_goto_map(
  grammar   : AugmentedGrammar,
  item_sets : Array[Set[LRItem]]
) -> Map[(StateId, Symbol), StateId]
pub fn build_lalr_table(
  grammar   : AugmentedGrammar,
  item_sets : Array[Set[LRItem]],
  goto_map  : Map[(StateId, Symbol), StateId]
) -> ParseTable

// 词法器
pub fn build_lexer_dfa(grammar : AugmentedGrammar, table : ParseTable) -> LexerDfa

// 冲突处理
pub fn resolve_conflicts(
  table   : ParseTable,
  grammar : AugmentedGrammar
) -> (ParseTable, Array[ConflictReport])

// 序列化
pub fn serialize_table(table : ParseTable) -> Bytes
pub fn deserialize_table(bytes : Bytes) -> Result[ParseTable, String]
pub fn table_to_json(table : ParseTable) -> String

// 一键生成（封装上述步骤）：Grammar → (ParseTable, Array[ConflictReport])
pub fn generate_parse_table(
  grammar : Grammar
) -> Result[(ParseTable, Array[ConflictReport]), String]
```

---

## 文件结构

| 文件 | 职责 | 行数 |
|------|------|------|
| `types.mbt` | 所有公开类型定义（Symbol、Production、ParseTable、LookaheadConstraint 等） | 148 |
| `normalize.mbt` | `augment_grammar()`：Grammar → AugmentedGrammar，含 Not/And 前瞻、extras 展开 | 535 |
| `sets.mbt` | `first_set()` / `follow_set()` / `nullable()` | 305 |
| `items.mbt` | `closure()` / `goto_set()` / `build_item_sets()`，预构建 head→prods 索引 | 240 |
| `lalr.mbt` | `build_lalr_table()`，FOLLOW 缓存，lookahead 过滤 | 143 |
| `conflicts.mbt` | `resolve_conflicts()`，预构建 shift_prec_map | 215 |
| `lexer.mbt` | Thompson NFA + 子集构造 DFA，Unicode 字符区间支持 | 690 |
| `serialize.mbt` | JSON + 二进制序列化（含 terminal_names、lexer_dfa、确定性排序） | 846 |
| `tablegen.mbt` | `generate_parse_table()` 一键入口 | 48 |
| **合计（实现代码）** | | **3,170** |
| `conflicts_test.mbt` | 冲突处理测试 | 302 |
| `items_test.mbt` | LR 项目集测试 | 272 |
| `lalr_test.mbt` | LALR 表构建测试 | 298 |
| `lexer_test.mbt` | DFA 构建、Unicode、valid_tokens 测试 | 205 |
| `normalize_test.mbt` | 文法规范化、extras、Not/And 测试 | 424 |
| `serialize_test.mbt` | JSON/二进制序列化、往返一致性、确定性测试 | 243 |
| `sets_test.mbt` | FIRST/FOLLOW/nullable 测试 | 231 |
| `tablegen_test.mbt` | 端到端集成测试（算术表达式） | 189 |
| **合计（含测试）** | | **5,334** |

---

## 实现阶段

### Phase 1（核心路径，无词法器）✅ 已完成
目标：能为无 Regex 的纯 Literal 语法生成正确 LALR 表

- [x] `types.mbt` — 完整类型定义
- [x] `normalize.mbt` — Grammar → AugmentedGrammar
- [x] `sets.mbt` — FIRST / FOLLOW / nullable
- [x] `items.mbt` — LR(0) 项目集构建
- [x] `lalr.mbt` — LALR(1) 表
- [x] `conflicts.mbt` — 优先级过滤 + 冲突报告
- [x] `serialize.mbt` — JSON 序列化
- [x] `tablegen.mbt` — `generate_parse_table()` 一键入口
- [x] `tablegen_test.mbt` — 算术表达式文法端到端验证
- [x] `serialize_test.mbt` — `table_to_json()` 输出格式验证

### Phase 2（词法器集成）✅ 已完成
- [x] `lexer.mbt` — Thompson NFA 构造
- [x] `lexer.mbt` — DFA 子集构造
- [x] 上下文敏感词法（`valid_tokens` 映射）
- [x] `tablegen.mbt` — 接通 `build_lexer_dfa()`
- [x] `AugmentedGrammar` 增加 `nt_metas` 字段，修复 `is_named` 启发式
- [x] `AugmentedGrammar` 增加 `prec_table` 字段，修复顶层优先级声明
- [x] `serialize.mbt` — 二进制格式（BinWriter/BinReader + 9 对 write_*/read_* 辅助函数）
- [x] `serialize.mbt` — lexer DFA 序列化（含 valid_tokens、transitions 确定性排序）
- [x] `serialize.mbt` — `terminal_names` 反向查找序列化（runtime 错误信息支持）
- [x] `grammar/` — `extras` 声明支持（`Grammar.extras` 字段 + DSL 解析）
- [x] `normalize.mbt` — `Not` / `And` 前瞻约束（`LookaheadConstraint` 类型 + LALR 过滤）

### Phase 2 性能优化 ✅ 已完成
- [x] `items.mbt` — 预构建 `head→prods` 索引，closure 从 O(P) 降为 O(1)
- [x] `lalr.mbt` — 预计算全部 FOLLOW 集合缓存，从 O(N×不动点迭代) 降为 O(1)/次
- [x] `conflicts.mbt` — 预构建 `shift_prec_map`，从 O(P×B)/次 降为 O(1)/次
- [x] `items.mbt` — `item_set_key` 改用 StringBuilder，从 O(n²) 降为 O(n)
- [x] `serialize.mbt` — Map 迭代前排序，确保二进制输出确定性
- [x] `lexer.mbt` — `add_range_chars` 直接按码点迭代，支持 Unicode BMP 字符区间

### Phase 3（完整 Grammar 支持）
- [ ] `lexer.mbt` — Hopcroft DFA 最小化（减小词法器状态数）
- [ ] `normalize.mbt` — `Field` / `Tagged` 元数据完整保留到 BodySymbol
- [ ] `normalize.mbt` — 外部词法器 `externals` 声明
- [ ] `cmd/main/main.mbt` — Grammar hash 增量缓存（`serialize_table` 已确定性，可直接实现）
- [ ] `tablegen/` — Error recovery 预留 `ErrorToken` variant
- [ ] 大型语法测试（JSON、MoonBit 子集）

---

## 已知局限

- **LALR(1) 伪冲突**：LALR 比 LR(1) 状态少，代价是极少数文法产生伪冲突。GLR 多路并行可以容错，Phase 3 后考虑升级
- **Hopcroft 最小化未做**：子集构造产生的 DFA 状态数可能是最小 DFA 的数倍，Phase 3 实现
- **`AnyChar`/`.` 仅覆盖 ASCII**：避免 65536 条转移边导致 DFA 爆炸；字符区间 `[lo, hi]` 已支持完整 BMP

---

## 未完成设计清单（对标 tree-sitter）

逐层列出与 tree-sitter 的 gap，按优先级排序。

### P1 — runtime Phase 2c（GLR）前必须完成

#### 1.1 `Action::Reduce` 缺少 `dynamic_precedence` 字段

tree-sitter 的 `TSParseAction::reduce.dynamic_precedence` 在 Reduce 时累积到 CST 节点，runtime GLR 用它在 `condense_stack` 里比较并行路径优劣。

**现状**：`Action` 枚举中 `Reduce(ProductionId)` 只携带产生式 ID；`Production.assoc = Dynamic` 有标记，但数值没传进 action。

**需要**：
```moonbit
// types.mbt
pub(all) enum Action {
  Shift(StateId)
  Reduce(ProductionId, Int)  // 第二个参数：dynamic_precedence（0 = 无）
  Accept
}
```
同时 `lalr.mbt` 的 reduce action 构造处、`conflicts.mbt` 的冲突消解处、`serialize.mbt` 的 binary 格式都需要相应更新。

#### 1.2 `Grammar` / `ParseTable` 缺少 `conflicts` 白名单

tree-sitter DSL 中可以声明 `conflicts: $ => [[$.a, $.b]]`，表示这些规则之间的冲突是**用户期望的歧义**，直接保留为 GLR 路径而不报 `Ambiguous` 警告。

**现状**：`Grammar` 没有 `conflicts` 字段，所有多 action 格都被当作意外冲突报告。

**需要**：
- `grammar/types.mbt`：`Grammar` 增加 `conflicts : Array[Array[String]]`（规则名对）
- `grammar/parser.mbt`：解析 `conflicts [...]` DSL 语法
- `tablegen/conflicts.mbt`：`resolve_conflicts` 接收白名单，白名单内的 S/R 或 R/R 不报警告，直接标记为 `GLR_Parallel`

---

### P2 — runtime CST API 完整性（字段访问等）

#### 2.1 `field_names_by_production_id` 缺失

tree-sitter 的 `language->field_map` 按 `production_id` 存储该产生式每个 body 位置的字段名，runtime 调用 `ts_node_child_by_field_name()` 时用此表做 O(1) 查找。

**现状**：`BodySymbol.field_name` 在 AugmentedGrammar 阶段有值，但 `ParseTable` / `serialize_table` 没有把它聚合为 `production_id → [(body_pos, field_name)]` 的索引，runtime 无法高效查找。

**需要**：
```moonbit
// types.mbt — ParseTable 新增
pub(all) struct ParseTable {
  // ... 现有字段 ...
  /// production_id → Array[(body_pos, field_name)]（只含有名字段）
  field_names_by_production : Map[ProductionId, Array[(Int, String)]]
}
```
`tablegen.mbt` 的 `generate_parse_table` 末尾从 `aug.productions` 聚合此 Map；`serialize.mbt` 增加对应序列化节。

#### 2.2 `Not` / `And` 前瞻约束逻辑实现为 no-op

`LookaheadConstraint` 数据结构存在（`NotFollowedBy / FollowedBy`），但 `normalize.mbt` 的 `to_symbol` 对 `Not(inner)` / `And(inner)` 直接透传，没有计算 `inner` 模式对应的终结符集合。

**现状代码**：
```moonbit
Not(inner) =>
  // Phase 1：忽略负向前瞻，直接透传
  to_symbol(ctx, inner, rule_name, field_name, prec, assoc)
And(inner) =>
  // Phase 1：忽略正向前瞻，直接透传
  to_symbol(ctx, inner, rule_name, field_name, prec, assoc)
```

**需要**：
- `inner` 必须是 terminal pattern（Literal/Regex/RuleRef 展开后是终结符）
- 调用 `collect_terminals(ctx, inner)` 把 inner 展开为 `Array[TerminalId]`
- 用 `add_production_with_lookahead` 将约束注入产生式
- 复杂嵌套（inner 含 Seq/Choice）暂继续透传，记录 TODO

---

### P3 — 两阶段 keyword 词法（Phase 3b runtime 需要）

#### 3.1 `Grammar.word` 字段缺失

tree-sitter DSL 的 `word: $ => $.identifier` 声明用于 keyword 提取：词法器先匹配 `word` token（通常是标识符正则），再在候选集里查关键字表。

**需要**：
- `grammar/types.mbt`：`Grammar` 增加 `word : String?`（规则名引用）
- `grammar/parser.mbt`：解析 `word identifier` DSL 语法
- `tablegen/normalize.mbt`：把 `word` 对应的 `TerminalId` 传入 `AugmentedGrammar`
- `tablegen/lexer.mbt`：识别哪些 terminal 的 `Literal` 能被 `word` 正则匹配，生成独立的 keyword DFA
- `tablegen/types.mbt`：`ParseTable` 增加 `keyword_capture_token : TerminalId?`
- `tablegen/serialize.mbt`：序列化 `keyword_capture_token`

---

### P4 — CST 形状灵活性（非核心正确性）

#### 4.1 `alias` 支持缺失

DSL `alias($.rule, "name")` / `alias($.rule, $.other)` 允许在特定产生式里把某个 NT 节点改名显示。

**需要**：
- `grammar/types.mbt`：`Pattern` 增加 `Alias(Pattern, String)` 变体
- `tablegen/types.mbt`：`ParseTable` 增加 `alias_sequences : Map[(NonTerminalId, ProductionId), Array[String?]]`（每个 body 位置的别名，None = 不改名）
- `tablegen/normalize.mbt`：处理 `Alias` 并记录到序列化表
- `tablegen/serialize.mbt`：序列化 `alias_sequences`

#### 4.2 `supertypes` 声明缺失

`supertypes: $ => [$.expr]` 让某些 NT 在 CST 里隐藏自身，只透出子类型节点。

**需要**：
- `grammar/types.mbt`：`Grammar` 增加 `supertypes : Array[String]`
- `grammar/parser.mbt`：解析 `supertypes [...]` DSL 语法
- `tablegen/types.mbt`：`SymbolMeta` 增加 `is_supertype : Bool` 字段
- `tablegen/serialize.mbt`：序列化 `is_supertype`

#### 4.3 `inline` 规则内联（性能优化）

`inline: $ => [$._helper]` 把某些辅助 NT inline 展开，减少 LR 状态数。这是纯优化，不影响正确性。

**需要**：
- `grammar/types.mbt`：`Grammar` 增加 `inline_rules : Array[String]`
- `tablegen/normalize.mbt`：在 `augment_grammar` 阶段把被 inline NT 的产生式直接展开到引用处

---

### P5 — 词法器优化（低优先级）

#### 5.1 Hopcroft DFA 最小化

子集构造产生的 DFA 状态数可能是最小 DFA 的数倍（已在"已知局限"中记录）。

**需要**：`tablegen/lexer.mbt` 在子集构造后增加 Hopcroft 最小化（Hopcroft 1971）传递，合并等价状态。

#### 5.2 lex_mode 压缩（多对一映射）

tree-sitter 把多个共享相同 `valid_tokens` 的 LR 状态映射到同一个 `lex_state`，减小词法表体积。

**需要**：`tablegen/lexer.mbt` 在构建 `valid_tokens` 时做等价类合并，生成 `lex_modes : Map[StateId, LexStateId]` + `lex_states : Map[LexStateId, Array[TerminalId]]`。

---

### 实现依赖关系

```
grammar/conflicts 白名单   ──▶  P1.2
grammar/word               ──▶  P3.1
grammar/supertypes         ──▶  P4.2
grammar/alias              ──▶  P4.1
grammar/inline_rules       ──▶  P4.3
                                   │
                                   ▼
tablegen P1.1 Action dynamic_prec  ──────────▶  runtime Phase 2c GLR
tablegen P2.1 field_names_by_prod  ──────────▶  runtime CstNode.childByField
tablegen P2.2 Not/And 逻辑实现     ──────────▶  runtime lookahead constraint 有效
tablegen P3.1 keyword_capture_token ─────────▶  runtime Phase 3b
```
- **`Not`/`And` 只支持 Literal/Regex/AnyChar/Choice 的简单组合**：复杂嵌套 pattern 回退透传
- **无 Error recovery**：解析失败时直接返回错误，不做 token 插入/删除修复（runtime 层决策）
- **无增量缓存**：每次调用 `generate_parse_table()` 都全量重建；`serialize_table` 已确定性，CLI 层可加 hash 缓存

---

## 已解决的历史缺陷

| 缺陷 | 状态 |
|------|------|
| `grammar.precedences` 顶层声明未被消费，冲突退化为 Ambiguous | ✅ 已修（`prec_table` 字段 + `build_shift_prec_map`） |
| `AugmentedGrammar.extras` 始终为空，无法跳过空白 | ✅ 已修（`Grammar.extras` DSL + parser 解析 + normalize 透传） |
| `is_named` 用名称前缀启发式，以 `_` 开头的命名节点判断错误 | ✅ 已修（`nt_metas` 字段，`normalize.mbt` 准确透传） |
| `Not`/`And` 直接透传内层 pattern，前瞻约束被忽略 | ✅ 已修（`LookaheadConstraint` + LALR reduce 过滤） |
| `shift_prec_for` O(P×B) 全量扫描 | ✅ 已修（预构建 `shift_prec_map`，O(1) 查表） |
| `closure` O(P) 线性扫描产生式 | ✅ 已修（预构建 `head_to_prods` 索引） |
| FOLLOW 集合每次 reduce 项重新计算 | ✅ 已修（Step 2 前一次性缓存全部非终结符 FOLLOW） |
| `item_set_key` O(n²) 字符串拼接 | ✅ 已修（改用 StringBuilder） |
| `add_range_chars` 只覆盖 ASCII，Unicode 字符区间无转移 | ✅ 已修（直接按码点迭代） |
| Map 迭代顺序不确定，同一语法两次序列化字节不同 | ✅ 已修（序列化前按 key 排序） |
| `write_str` 截断非 ASCII（只写低 8 位） | ✅ 已修（改为 UTF-16 LE） |
| `ParseTable` 无 `terminal_names`，runtime 无法生成可读错误信息 | ✅ 已修（从 `aug.terminals` 反转填充） |
| `tablegen.mbt` 未接通 `build_lexer_dfa()` | ✅ 已修 |

---

## 已解决的历史缺陷（Phase 1 代码审查）

> 原审查基于 commit `37da446`。当前 HEAD `b556f13`，107/107 测试通过。

### 已修复

| 文件 | 状态 | 说明 |
|------|------|------|
| `tablegen.mbt` | ✅ 已创建 | `generate_parse_table()` 一键入口 |
| `tablegen_test.mbt` | ✅ 已创建 | 算术表达式文法端到端验证，5 个表驱动测试块 |
| `serialize_test.mbt` | ✅ 已创建 | `table_to_json()` 输出格式验证，6 个测试块 |
| `lexer.mbt` | ✅ 已实现 | Thompson NFA + 子集构造 DFA，`build_lexer_dfa()` 完整实现 |

### 功能缺陷（已全部修复）

#### 1. ✅ 顶层 `grammar.precedences` 透传至 `prec_table`

**已修复**。`normalize.mbt` 步骤 5 将 `grammar.precedences` 转换为
`prec_table : Map[TerminalId, (Int, PrecKind)]` 并作为 `AugmentedGrammar` 的字段输出；
`conflicts.mbt` 的 `build_shift_prec_map()` 以 `prec_table` 为回落优先级来源。
用顶层 `precedence left "+", "-"` 声明的语法现在可以正确消解 S/R 冲突。

#### 2. ✅ `AugmentedGrammar.extras` 已接通 DSL

**已修复**。`Grammar` 加了 `extras : Array[Pattern]` 字段，`grammar/parser.mbt`
解析 `extras [...]` 声明；`augment_grammar()` 将 extras Pattern 注册为终结符后
填入 `AugmentedGrammar.extras`；`build_lexer_dfa()` 自动把 extras 并入每个
LR 状态的 `valid_tokens`。

#### 3. ✅ `is_named` 改用 `nt_metas` 精确来源

**已修复**。`AugmentedGrammar` 增加了 `nt_metas : Array[SymbolMeta]`，
由 `normalize.mbt` 从 `ctx.nt_metas` 填入（按 `rule.is_named` 准确设置）；
`lalr.mbt` step 3 直接读取 `grammar.nt_metas`，不再用名称前缀启发式。

### 接口不一致

#### 4. ✅ `build_item_sets` 签名已修正

原错误：设计文档写合并返回值 `(Array[Set[LRItem]], Map[...])`。  
实际实现拆分为两个独立函数 `build_item_sets` + `build_goto_map`，API 汇总已同步更新。

#### 5. ✅ Phase 1 checklist 已全部勾选

### serialize.mbt 输出缺失字段

#### 6. `table_to_json()` 缺少 `terminal_patterns`

**性质：不是 bug（Phase 2 待实现功能）**。现有代码行为正确，只是 `table_to_json()` 输出不完整——`ParseTable` 尚未携带 `terminal_patterns` 字段，JSON 中缺少终结符元数据是已知的阶段性限制，不影响 Phase 1 功能。

JSON 输出有 `symbol_metadata`（非终结符名称）但无终结符元数据。工具链读取 JSON 后无法得知 `TerminalId 3` 对应哪个字面量或正则，无法重建词法器。

**修复方向**：在 `table_to_json()` 输出增加 `"terminal_patterns"` 数组：

```json
"terminal_patterns": [
  { "id": 0, "type": "literal", "value": "+" },
  { "id": 1, "type": "regex",   "value": "[0-9]+" }
]
```

需为 `ParseTable` 增加 `terminal_patterns : Map[TerminalId, TerminalDef]` 字段（或由 `generate_parse_table()` 从 `AugmentedGrammar.terminal_patterns` 传入）。

#### 7. `table_to_json()` 缺少 `ConflictReport` 输出

`resolve_conflicts()` 返回 `(ParseTable, Array[ConflictReport])`，但 `table_to_json()` 只接受 `ParseTable`，冲突报告无法序列化到 JSON。

**修复方向**：新增 `table_and_conflicts_to_json(table, reports)` 或在 JSON 顶层加 `"conflicts"` 字段（可选参数）。

### 次要问题（不阻塞 MVP）

| # | 位置 | 描述 |
|---|------|------|
| 8 | `conflicts.mbt: shift_prec_for()` | O(P×B) 全产生式扫描；大型语法下为二次方复杂度，可改为预构建 `Map[TerminalId, Int]` |
| 9 | `normalize.mbt: Not/And` | 注释标明"Phase 1 忽略"，但 design.md §1 展开规则表中写了"生成前瞻约束"，文档与实现不符，需修正文档 |
| 10 | `items.mbt: item_set_key()` | 用字符串拼接作 Map key（`"\{prod},\{dot};..."`），性能差且有 ID 碰撞理论风险；建议改为 `Array[LRItem]` Hash |

### 小结：完成 Phase 1 MVP 的最小工作量



四、设计完全空白的区域
空白 A：lexer.mbt 零测试（✅ 已补充）

`lexer_test.mbt` 已创建，覆盖 Thompson NFA 构造、子集构造、量词、字符类、转义、Unicode 区间、接受优先级、`build_valid_tokens` 全部主路径。136/136 测试通过。

空白 B：错误处理策略（✅ 已设计）

#### `generate_parse_table()` 的 `Result` 语义

**现状**：函数签名为 `Result[(ParseTable, Array[ConflictReport]), String]`，当前实现永远返回 `Ok`，即使传入空文法也如此。`Err` 分支预留给 Phase 2/3 的前置校验。

**设计决策**：

| 条件 | 当前行为 | Phase 2 目标行为 |
|------|---------|----------------|
| 空文法（`grammar.rules` 为空） | 返回 `Ok`（退化解析表） | 返回 `Err("empty grammar")` |
| `grammar.start` 指向不存在的规则 | 返回 `Ok`（以 ID 0 为起始，无意义） | 返回 `Err("start rule not found: ...")` |
| 合法文法（含冲突） | 返回 `Ok((table, reports))` | 同左，冲突由 `reports` 而非 `Err` 传递 |

**关键原则**：**冲突不是错误**。`Err` 只表示"无法生成有意义的解析表"（结构性问题）；冲突属于语法属性，通过 `Array[ConflictReport]` 表达，由调用者决策。

#### `ConflictReport` 严重性与调用者决策

```
ConflictSeverity
├── Warn(msg)            — S/R 冲突已通过 prec/assoc 消解
│                          调用者：可忽略，或可选展示给语法作者
│
├── Ambiguous(msg)       — S/R 或 R/R 冲突，无 prec 信息，GLR 保留全部分支
│                          调用者：必须关注，语法存在语义歧义
│                            · 工具链（CLI）：打印警告，继续生成表
│                            · 解析器运行时（runtime/）：多路并行，需上层仲裁
│
└── DynamicConflict(id)  — prec.dynamic 冲突，编译期无法消解
                           调用者：不视为错误，但必须确保 runtime/ 注册了对应的
                           动态优先级比较器（否则运行时退化为 Ambiguous 语义）
```

**调用方参考模式**：

```moonbit
match generate_parse_table(grammar) {
  Err(msg) => { /* 结构性问题，无法继续 */ fail(msg) }
  Ok((table, reports)) => {
    let has_ambiguous = reports.iter().any(fn(r) {
      match r.severity { Ambiguous(_) => true; _ => false }
    })
    // Warn 和 DynamicConflict 可选展示；Ambiguous 须警告用户
    if has_ambiguous { warn("grammar has unresolved ambiguities") }
    // 无论如何，table 可用于后续序列化和 runtime 构建
    use(table)
  }
}
```

空白 D：main.mbt 与 generate_parse_table() 的交互（✅ 已实现）

`cmd/main/main.mbt` 已重写为完整 5 步流程：DSL 解析 → 校验（警告不阻断）→ 生成解析表 → 冲突报告按 `[warn]/[ambiguous]/[dynamic]` 分类打印 → `table_to_json()` 输出到 stdout。`moon.pkg` 已添加 `@tablegen` 依赖。

**Phase 2 已全部完成**：
- [x] `AugmentedGrammar` 加 `nt_metas` 字段，修复 `is_named` 启发式
- [x] `grammar/` 加 `extras` 声明支持
- [x] `tablegen.mbt` 接通 `build_lexer_dfa()`
- [x] `serialize.mbt` 二进制格式 + 词法 DFA 序列化 + `terminal_names` + 确定性排序
- [x] `Not`/`And` 前瞻约束实现
- [x] 性能优化（head→prods 索引、FOLLOW 缓存、shift_prec_map、StringBuiler key）