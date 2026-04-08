///|
// Highlight Query 引擎
//
// 将 CompiledQuery 的执行结果转换为 HighlightRange 列表；
// 按 start_byte 稳定排序输出，便于编辑器直接使用。
//
// Tree-Sitter 高亮约定：
//   - 捕获名即高亮类型，如 "keyword"  "string"  "comment" 等
//   - 同一字节范围若有多个捕获，DFS 先出现（模式编号较小）者优先级更高
//   - 注入语言和局部变量解析见 locals.mbt（独立 phase）

///|
/// 标准高亮名称集合（对应 LSP SemanticTokenType + Neovim/Helix + VS Code 惯例）。
///
/// 用途：
///   1. 向用户展示可用的捕获名列表
///   2. WASM 层过滤非标准捕获（如 @local.* 捕获名）
pub let highlight_names : Array[String] = [
  "attribute", "comment", "constant", "constant.builtin", "constructor", "embedded",
  "escape", "function", "function.builtin", "function.macro", "function.method",
  "keyword", "keyword.control", "keyword.directive", "keyword.function", "keyword.operator",
  "keyword.return", "label", "module", "number", "operator", "parameter", "property",
  "punctuation", "punctuation.bracket", "punctuation.delimiter", "string", "string.escape",
  "string.special", "tag", "tag.attribute", "type", "type.builtin", "type.definition",
  "variable", "variable.builtin", "variable.member", "variable.parameter",
  // locals 解析后追加的派生名称
   "variable.local", "variable.parameter.local",
]

///|
/// 单个高亮区间（语义 token），供编辑器渲染使用。
pub(all) struct HighlightRange {
  start_byte : Int
  end_byte : Int
  start_point : @runtime.Point
  end_point : @runtime.Point
  /// 高亮类型，即查询中 @capture_name 去掉 @ 后的字符串。
  /// 例："keyword"  "string.escape"  "variable.local"
  highlight_name : String
} derive(Show)

///|
// 内部辅助：稳定插入排序（按 start_byte 升序，相同则按 end_byte 降序保持最宽在前）

///|
fn sort_ranges(ranges : Array[HighlightRange]) -> Unit {
  let n = ranges.length()
  for i in 1..<n {
    let key = ranges[i]
    let mut j = i - 1
    while j >= 0 {
      let r = ranges[j]
      let should_swap = r.start_byte > key.start_byte ||
        (r.start_byte == key.start_byte && r.end_byte < key.end_byte)
      if should_swap {
        ranges[j + 1] = ranges[j]
        j = j - 1
      } else {
        break
      }
    }
    ranges[j + 1] = key
  }
}

///|
/// 执行高亮查询，返回按 start_byte 排序的 `Array[HighlightRange]`。
///
/// # 参数
/// - root            : CST 根节点（由 `@runtime.parse` 返回）
/// - input           : 被解析的原始 UTF-8 字符串
/// - table           : 对应语言的 ParseTable
/// - highlight_query : 已编译的高亮查询（包含 `@keyword`、`@string` 等捕获）
///
/// # 返回值
/// 所有命中的 HighlightRange，按 start_byte 升序排序。
/// 若同一字节范围有多个捕获命中，保留所有（调用方按需去重）。
pub fn apply_highlights(
  root : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
  highlight_query : CompiledQuery,
) -> Array[HighlightRange] {
  let captures = exec(highlight_query, root, input, table)
  let ranges : Array[HighlightRange] = []
  for c in captures {
    let node = c.node
    // 跳过零宽节点（MISSING 等特殊节点，除非是 ERROR）
    if node.start_byte >= node.end_byte && not(node.is_error) {
      continue
    }
    // 跳过 local.* 系列捕获名（供 locals 引擎使用，不直接映射为高亮色）
    if str_starts_with(c.capture_name, "local.") {
      continue
    }
    ranges.push({
      start_byte: node.start_byte,
      end_byte: node.end_byte,
      start_point: node.start_point,
      end_point: node.end_point,
      highlight_name: c.capture_name,
    })
  }
  sort_ranges(ranges)
  ranges
}

///|
/// 执行高亮查询 + 局部变量解析，返回语义感知的 HighlightRange 列表。
///
/// locals_query 应包含特殊捕获名：
///   - `@local.scope`      : 作用域边界（如函数体、块）
///   - `@local.definition` : 局部变量定义（绑定到最近的 scope）
///   - `@local.reference`  : 局部变量引用
///
/// 处理逻辑：
///   对每个 `@local.reference` 节点，在祖先 scope 中查找同名 `@local.definition`；
///   找到时，将对应 HighlightRange 的 `highlight_name` 追加 `.local` 后缀；
///   未找到时保持不变（视为全局变量）。
pub fn apply_highlights_with_locals(
  root : @runtime.CstNode,
  input : String,
  table : @tablegen.ParseTable,
  highlight_query : CompiledQuery,
  locals_query : CompiledQuery,
) -> Array[HighlightRange] {
  let highlights = apply_highlights(root, input, table, highlight_query)
  let local_res = resolve_locals(root, input, table, locals_query)
  let result : Array[HighlightRange] = []
  for h in highlights {
    if local_res.is_local_ref(h.start_byte) {
      result.push({
        start_byte: h.start_byte,
        end_byte: h.end_byte,
        start_point: h.start_point,
        end_point: h.end_point,
        highlight_name: h.highlight_name + ".local",
      })
    } else {
      result.push(h)
    }
  }
  result
}

///|
// 字符串工具（仅在 query 包内使用）

///|
fn str_starts_with(s : String, prefix : String) -> Bool {
  let slen = s.length()
  let plen = prefix.length()
  if slen < plen {
    return false
  }
  let mut i = 0
  while i < plen {
    if s[i] != prefix[i] {
      return false
    }
    i = i + 1
  }
  true
}
