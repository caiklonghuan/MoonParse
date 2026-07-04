///|
// Incremental trace JSON serializer.

///|
fn write_trace_range(
  buf : StringBuilder,
  range : @runtime.IncrementalTraceRange,
) -> Unit {
  buf.write_char('{')
  write_kvi(buf, "startByte", range.start_byte)
  buf.write_char(',')
  write_kvi(buf, "endByte", range.end_byte)
  buf.write_char(',')
  write_kvi(buf, "startRow", range.start_point.row)
  buf.write_char(',')
  write_kvi(buf, "startCol", range.start_point.column)
  buf.write_char(',')
  write_kvi(buf, "endRow", range.end_point.row)
  buf.write_char(',')
  write_kvi(buf, "endCol", range.end_point.column)
  buf.write_char('}')
}

///|
fn write_reuse_range(
  buf : StringBuilder,
  range : @runtime.IncrementalReuseRange,
) -> Unit {
  buf.write_char('{')
  write_kvs(buf, "kind", range.kind)
  buf.write_char(',')
  write_kvi(buf, "startByte", range.start_byte)
  buf.write_char(',')
  write_kvi(buf, "endByte", range.end_byte)
  buf.write_char(',')
  write_kvi(buf, "startRow", range.start_point.row)
  buf.write_char(',')
  write_kvi(buf, "startCol", range.start_point.column)
  buf.write_char(',')
  write_kvi(buf, "endRow", range.end_point.row)
  buf.write_char(',')
  write_kvi(buf, "endCol", range.end_point.column)
  buf.write_char('}')
}

///|
fn incremental_trace_to_json(trace : @runtime.IncrementalTrace) -> String {
  let buf = StringBuilder::new()
  buf.write_char('{')
  write_jstr(buf, "edit")
  buf.write_char(':')
  buf.write_char('{')
  write_jstr(buf, "oldRange")
  buf.write_char(':')
  write_trace_range(buf, trace.edit_old_range)
  buf.write_char(',')
  write_jstr(buf, "newRange")
  buf.write_char(':')
  write_trace_range(buf, trace.edit_new_range)
  buf.write_char('}')
  buf.write_char(',')
  write_jstr(buf, "reparseRange")
  buf.write_char(':')
  write_trace_range(buf, trace.reparse_range)
  buf.write_char(',')
  write_jstr(buf, "reusedRanges")
  buf.write_char(':')
  buf.write_char('[')
  for i in 0..<trace.reused_ranges.length() {
    if i > 0 {
      buf.write_char(',')
    }
    write_reuse_range(buf, trace.reused_ranges[i])
  }
  buf.write_char(']')
  buf.write_char(',')
  write_kvi(buf, "reusedNodeCount", trace.reused_node_count)
  buf.write_char(',')
  write_kvi(buf, "reusedByteCount", trace.reused_byte_count)
  buf.write_char(',')
  write_kvi(buf, "sourceByteLength", trace.source_byte_length)
  buf.write_char('}')
  buf.to_string()
}

///|
fn incremental_trace_success_json(
  tree_id : Int,
  trace : @runtime.IncrementalTrace,
) -> String {
  let buf = StringBuilder::new()
  buf.write_char('{')
  write_kvb(buf, "ok", true)
  buf.write_char(',')
  write_kvi(buf, "treeId", tree_id)
  buf.write_char(',')
  write_jstr(buf, "trace")
  buf.write_char(':')
  buf.write_string(incremental_trace_to_json(trace))
  buf.write_char('}')
  buf.to_string()
}

///|
fn incremental_trace_error_json(message : String) -> String {
  let buf = StringBuilder::new()
  buf.write_char('{')
  write_kvb(buf, "ok", false)
  buf.write_char(',')
  write_kvi(buf, "treeId", -1)
  buf.write_char(',')
  write_kvs(buf, "error", message)
  buf.write_char(',')
  write_jstr(buf, "trace")
  buf.write_string(":null")
  buf.write_char('}')
  buf.to_string()
}
