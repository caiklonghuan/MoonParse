///|
// Highlight Query 引擎

///|
/// 标准高亮名称集合（对应 LSP SemanticTokenType + Neovim/Helix + VS Code 惯例）
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
/// 执行高亮查询，返回按 start_byte 排序的 `Array[HighlightRange]`
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
/// 执行高亮查询 + 局部变量解析，返回语义感知的 HighlightRange 列表
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
