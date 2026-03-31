# tablegen/ 设计文档

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
- **优先级与结合性绑定**：将 DSL 中的 prec / precedence 标记精确映射到每条产生式，供冲突解决使用

### 子模块 3：LR 自动机生成器（LR Automaton Builder）→ items.mbt + lalr.mbt

**职责**：工程量最大的部分，构建解析 DFA。

- **项目集闭包（Closure）**：给定一个带 • 的解析位置，推导出所有后续可能路径
- **GOTO 转移函数**：计算在状态 A 见到符号 X 后切换到哪个状态 B
- **LALR(1) 状态压缩**：合并具有相同核心（Kernel）的项目集，减小解析表体积，避免状态爆炸

### 子模块 4：词法器编译器（Lexer Compiler）→ lexer.mbt

**职责**：Tree-Sitter 的词法分析是"受控"的（上下文感知），而非独立扫描。

- **Regex → DFA**：Thompson 构造法（Regex → NFA）+ 子集构造法（NFA → DFA）+ Hopcroft 最小化
- **上下文感知**：为每个 LR 状态生成"当前合法 Token 列表"（alid_tokens 映射）——解析 if 语句时词法器自动忽略不可能出现的符号，消除词法歧义

### 子模块 5：冲突解决与发射器（Conflict Resolver & Emitter）→ conflicts.mbt + serialize.mbt

**职责**：处理逻辑矛盾并产出最终产物。

- **移进/规约冲突处理（S/R Conflict）**：按优先级/结合性自动选择路径；无法解决时标记为 `Ambiguous`，为 GLR 并行解析保留空间
- **表压缩（Table Compression）**：原始解析表极大且稀疏，采用偏移量压缩（offset encoding）让生成的 .parse_table 控制在几十 KB
- **二进制序列化**：将内存中的 Map / Set 按照 §7 定义的格式写入二进制流

## 端到端数据流

```
Grammar AST
  │
  ▼ normalize()                  §1 增广文法构建
AugmentedGrammar
  │
  ├─ first_set() / follow_set()  §2 FIRST/FOLLOW
  │
  ▼ build_item_sets()            §3 LR(0) 项目集族
Array[Set[LRItem]]
  │
  ▼ build_lalr_table()           §4 LALR(1) 表
ParseTable (带冲突)
  │
  ├─ resolve_conflicts()         §5 优先级过滤 / 冲突报告
  │
  ├─ build_lexer_dfa()           §6 词法器 DFA
  │
  ▼ serialize_table()            §7 序列化
Bytes (.parse_table)
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
| `Not(p)` / `And(p)` | 生成前瞻约束（注解到后续产生式） |
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

/// DFA 状态（子集构造 + Hopcroft 最小化）
pub(all) struct DfaState {
  id          : DfaStateId
  transitions : Map[Char, DfaStateId]
  accept      : TerminalId?    // 接受的 terminal（优先级最高者）
}

pub(all) struct LexerDfa {
  states      : Array[DfaState]
  start       : DfaStateId
  /// valid_tokens[s] = { t | action[(s,t)] ≠ ∅ } ∪ extras_set
  valid_tokens : Map[StateId, Set[TerminalId]]
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
// 主流程（三步）
pub fn augment_grammar(grammar : Grammar) -> AugmentedGrammar
pub fn build_item_sets(grammar : AugmentedGrammar)
  -> (Array[Set[LRItem]], Map[(StateId, Symbol), StateId])
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

| 文件 | 职责 | 估算行数 |
|------|------|---------|
| `types.mbt` | 所有公开类型定义（Symbol、Production、ParseTable 等） | ~200 |
| `normalize.mbt` | `augment_grammar()`：Grammar → AugmentedGrammar | ~300 |
| `sets.mbt` | `first_set()` / `follow_set()` / `nullable()` | ~250 |
| `items.mbt` | `closure()` / `goto_set()` / `build_item_sets()` | ~350 |
| `lalr.mbt` | `build_lalr_table()` | ~300 |
| `conflicts.mbt` | `resolve_conflicts()` | ~200 |
| `lexer.mbt` | Regex → NFA → DFA 最小化 | ~500 |
| `serialize.mbt` | 二进制 / JSON 序列化反序列化 | ~300 |
| `tablegen.mbt` | `generate_parse_table()` 一键入口 | ~100 |
| `tablegen_test.mbt` | 集成测试（JSON 语法 → 表 → 验证） | ~200 |
| **合计** | | **~2700** |

---

## 实现阶段

### Phase 1（核心路径，无词法器）
目标：能为无 Regex 的纯 Literal 语法生成正确 LALR 表

- [x] `types.mbt` — 完整类型定义
- [x] `normalize.mbt` — Grammar → AugmentedGrammar（不含 Regex）
- [x] `sets.mbt` — FIRST / FOLLOW / nullable
- [x] `items.mbt` — LR(0) 项目集构建
- [x] `lalr.mbt` — LALR(1) 表
- [x] `conflicts.mbt` — 优先级过滤 + 冲突报告
- [x] `serialize.mbt` — JSON 序列化（调试用）
- [x] `tablegen.mbt` — `generate_parse_table()` 一键入口
- [ ] `tablegen_test.mbt` — 用算术表达式文法（`E → E + T | T`）端到端验证
- [ ] `serialize_test.mbt` — `table_to_json()` 输出格式验证

### Phase 2（词法器集成）
- [ ] `lexer.mbt` — NFA 构造（Thompson）
- [ ] `lexer.mbt` — DFA 子集构造 + Hopcroft 最小化
- [ ] 上下文敏感词法（`valid_tokens` 映射）
- [ ] `serialize.mbt` — 二进制格式 + 词法 DFA 序列化

### Phase 3（完整 Grammar 支持）
- [ ] `normalize.mbt` — `Not` / `And` 前瞻处理
- [ ] `normalize.mbt` — `Field` / `Tagged` 元数据保留
- [ ] `normalize.mbt` — 外部词法器 `externals` 声明
- [ ] 大型语法测试（JSON、MoonBit 子集）

---

## 已知局限（Phase 1）

- LALR(1) 而非 LR(1)：极少数文法在 LALR(1) 下产生伪冲突，LR(1) 无此问题（Phase 3 后考虑）
- 词法优先：Regex 冲突按 DFA 最长匹配 + 声明顺序决定，暂不支持动态优先词法
- SPPF：歧义时当前取优先级最高路径，不保留完整歧义森林（后续 runtime/ 阶段决策）
- 增量编译：每次全量重新生成表。表缓存（基于语法哈希）可在 CLI 层实现

types.mbt — 所有公开类型定义（Symbol、BodySymbol、Production、ParseTable 等，~200 行）
normalize.mbt — augment_grammar()：Grammar → AugmentedGrammar（~300 行）
sets.mbt — first_set() / follow_set() / nullable()（~250 行）
items.mbt — closure() / goto_set() / build_item_sets()（~350 行）
lalr.mbt — build_lalr_table()（~300 行）
conflicts.mbt — 优先级过滤 + 冲突报告（~200 行）
serialize.mbt — JSON 序列化（Phase 1 只需 JSON）（~150 行）

---

## Phase 1 代码审查报告

> 审查时间：代码提交至 `37da446` 后。96/96 单元测试通过，`moon build` 干净。

### 缺失文件（硬性阻塞）

| 文件 | 状态 | 说明 |
|------|------|------|
| `tablegen.mbt` | ❌ 未创建 | `generate_parse_table()` 一键入口，Phase 1 最终对外 API 无法调用 |
| `tablegen_test.mbt` | ❌ 未创建 | design.md Phase 1 目标"用算术表达式文法端到端验证"尚未完成 |
| `serialize_test.mbt` | ❌ 未创建 | `table_to_json()` 零测试覆盖；输出格式是否正确无法验证 |

### 功能缺陷（影响正确性）

#### 1. 顶层 `grammar.precedences` 未被 normalize.mbt 消费

`grammar/types.mbt` 中 `Grammar.precedences : Array[PrecDecl]` 存储用户写的顶层优先级声明（如 `precedence left "+", "-"`）。`normalize.mbt` 的 `augment_grammar()` **完全不读取** `grammar.precedences`——只有内联 `Prec(level, kind, inner)` 模式产生式才携带 prec/assoc。

**后果**：用顶层声明定义优先级的语法，冲突解决时所有优先级均为 `None`，退化为 `Ambiguous`。

**修复方向**：在 `augment_grammar()` 步骤 4 展开规则时，将 `grammar.precedences` 转换为 `(Terminal, Int, PrecKind)` 的查找表，并在 `add_production()` 时主动附加 prec/assoc（若产生式 body 含对应终结符）。或者修改 `augment_grammar` 返回 `AugmentedGrammar` 时额外携带 `prec_table : Map[TerminalId, (Int, PrecKind)]`，由 `resolve_conflicts` 在查找 `shift_prec_for` 时优先使用。

#### 2. `AugmentedGrammar.extras` 始终为空

`normalize.mbt` 第 5 步硬编码 `extras: []`，注释写明"grammar/ 层目前未建模 extras"。但 `Grammar` 类型**实际上没有** `extras` 字段——grammar DSL 层确实未暴露此概念。

**后果**：目前无 extras 机制，空白符必须在每条产生式中手写可选空白，无法生成支持跳过空白的解析器。

**修复方向（Phase 2 前置）**：在 `Grammar` 中添加 `extras : Array[Pattern]`，parser.mbt 解析 `extras [...]` 声明；`augment_grammar()` 将 extras Pattern 注册为终结符后填入 `AugmentedGrammar.extras`。

#### 3. `is_named` 使用名称启发式而非来源信息

`lalr.mbt` step 3（`symbol_metadata` 构建）用以下启发式判断：

```moonbit
let is_named = name != "$accept" && not(name.has_prefix("_"))
```

但 `NormCtx.nt_metas : Array[SymbolMeta]` 在 `normalize.mbt` 中已按 `rule.is_named` 准确填充，该信息在返回 `AugmentedGrammar` 时**被丢弃**——`AugmentedGrammar` 结构体没有 `nt_metas` 字段。

**后果**：以 `_` 开头但实际是命名节点的规则、以及不以 `_` 开头但应匿名的辅助规则，`is_named` 都会错误。这直接影响运行时 AST 节点类型的可见性。

**修复方向**：在 `AugmentedGrammar` 中增加 `nt_metas : Array[SymbolMeta]`（indexed by NonTerminalId），由 `normalize.mbt` 从 `ctx.nt_metas` 填入；`lalr.mbt` step 3 改为直接从 `grammar.nt_metas` 读取。

### 接口不一致

#### 4. design.md 公开 API 与实现签名不符

design.md "公开 API 汇总"中写：

```moonbit
pub fn build_item_sets(grammar : AugmentedGrammar)
  -> (Array[Set[LRItem]], Map[(StateId, Symbol), StateId])
```

实际实现将 item_sets 和 goto_map 拆分为两个独立函数：

```moonbit
pub fn build_item_sets(grammar : AugmentedGrammar) -> Array[Set[LRItem]]
pub fn build_goto_map(grammar : AugmentedGrammar, item_sets : Array[Set[LRItem]]) -> Map[(StateId, Symbol), StateId]
```

这是合理的设计拆分，但 `generate_parse_table()` 需调用两步，design.md API 汇总需更新。

#### 5. Phase 1 实现阶段 checklist 全部未勾选

design.md "Phase 1"下 7 个 `[ ]` 均未更新为 `[x]`，但代码已全部实现并测试通过。

### serialize.mbt 输出缺失字段

#### 6. `table_to_json()` 缺少 `terminal_patterns`

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

1. **必做**：创建 `tablegen.mbt`，实现 `generate_parse_table()`（约 20 行流水线胶水代码）
2. **必做**：创建 `tablegen_test.mbt`，编写算术表达式文法端到端测试（验证状态数、shift/reduce 动作、冲突解决）
3. **必做**：创建 `serialize_test.mbt`，验证 `table_to_json()` 输出的关键字段
4. **建议**：将 `AugmentedGrammar` 增加 `nt_metas` 字段修复 `is_named` bug（5 行改动）
5. **建议**：`table_to_json()` 补充 `terminal_patterns` 输出
6. **推迟至 Phase 2**：顶层 `grammar.precedences`、extras 机制、二进制序列化