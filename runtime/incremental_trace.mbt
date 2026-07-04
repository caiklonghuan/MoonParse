///|
// 增量解析 trace 聚合工具。

///|
fn clamp_int(value : Int, low : Int, high : Int) -> Int {
  if value < low {
    low
  } else if value > high {
    high
  } else {
    value
  }
}

///|
fn make_trace_range(
  start_byte : Int,
  end_byte : Int,
  start_point : Point,
  end_point : Point,
) -> IncrementalTraceRange {
  { start_byte, end_byte, start_point, end_point }
}

///|
fn trace_range_from_bytes(
  input : String,
  start_byte : Int,
  end_byte : Int,
) -> IncrementalTraceRange {
  let source_len = input.length()
  let start = clamp_int(start_byte, 0, source_len)
  let end = clamp_int(end_byte, start, source_len)
  let start_point = bytes_to_point(input, 0, { row: 0, column: 0 }, start)
  let end_point = bytes_to_point(input, start, start_point, end)
  make_trace_range(start, end, start_point, end_point)
}

///|
fn compare_reuse_range(
  left : IncrementalReuseRange,
  right : IncrementalReuseRange,
) -> Int {
  let by_start = left.start_byte.compare(right.start_byte)
  if by_start != 0 {
    return by_start
  }
  let by_end = left.end_byte.compare(right.end_byte)
  if by_end != 0 {
    return by_end
  }
  left.kind.compare(right.kind)
}

///|
fn same_reuse_range(
  left : IncrementalReuseRange,
  right : IncrementalReuseRange,
) -> Bool {
  left.start_byte == right.start_byte &&
  left.end_byte == right.end_byte &&
  left.kind == right.kind
}

///|
fn stable_unique_reuse_ranges(
  raw_ranges : Array[IncrementalReuseRange],
  source_len : Int,
) -> Array[IncrementalReuseRange] {
  let sorted = raw_ranges.copy()
  sorted.sort_by(compare_reuse_range)
  let result : Array[IncrementalReuseRange] = []
  for range in sorted {
    let start = clamp_int(range.start_byte, 0, source_len)
    let end = clamp_int(range.end_byte, start, source_len)
    if start >= end {
      continue
    }
    let normalized : IncrementalReuseRange = {
      ..range,
      start_byte: start,
      end_byte: end,
    }
    if result.is_empty() ||
      !same_reuse_range(result[result.length() - 1], normalized) {
      result.push(normalized)
    }
  }
  result
}

///|
fn reused_union_byte_count(ranges : Array[IncrementalReuseRange]) -> Int {
  if ranges.is_empty() {
    return 0
  }
  let mut total = 0
  let mut cur_start = ranges[0].start_byte
  let mut cur_end = ranges[0].end_byte
  let mut i = 1
  while i < ranges.length() {
    let r = ranges[i]
    if r.start_byte <= cur_end {
      if r.end_byte > cur_end {
        cur_end = r.end_byte
      }
    } else {
      total = total + (cur_end - cur_start)
      cur_start = r.start_byte
      cur_end = r.end_byte
    }
    i = i + 1
  }
  total + (cur_end - cur_start)
}

///|
fn reparse_range_from_reuse(
  input : String,
  edit : InputEdit,
  ranges : Array[IncrementalReuseRange],
) -> IncrementalTraceRange {
  let source_len = input.length()
  if ranges.is_empty() {
    return trace_range_from_bytes(input, 0, source_len)
  }
  let anchor_start = clamp_int(edit.start_byte, 0, source_len)
  let anchor_end = clamp_int(edit.new_end_byte, anchor_start, source_len)
  let mut gap_start = 0
  for r in ranges {
    if r.end_byte <= anchor_start {
      if r.end_byte > gap_start {
        gap_start = r.end_byte
      }
      continue
    }
    if r.start_byte >= anchor_end {
      return trace_range_from_bytes(input, gap_start, r.start_byte)
    }
    if r.end_byte > gap_start {
      gap_start = r.end_byte
    }
  }
  trace_range_from_bytes(input, gap_start, source_len)
}

///|
fn build_incremental_trace(
  input : String,
  edit : InputEdit,
  raw_reused_ranges : Array[IncrementalReuseRange],
) -> IncrementalTrace {
  let source_len = input.length()
  let reused_ranges = stable_unique_reuse_ranges(raw_reused_ranges, source_len)
  {
    edit_old_range: make_trace_range(
      edit.start_byte,
      edit.old_end_byte,
      edit.start_point,
      edit.old_end_point,
    ),
    edit_new_range: make_trace_range(
      edit.start_byte,
      edit.new_end_byte,
      edit.start_point,
      edit.new_end_point,
    ),
    reparse_range: reparse_range_from_reuse(input, edit, reused_ranges),
    reused_ranges,
    reused_node_count: reused_ranges.length(),
    reused_byte_count: reused_union_byte_count(reused_ranges),
    source_byte_length: source_len,
  }
}
