///|
/// This package is intentionally compile-only while M1 declarations have no
/// runtime implementation. It proves that the v1 public contract is visible
/// to an external MoonBit consumer.
pub fn root_v1_surface_is_visible(
  source : @moonparse.Source,
  language : @moonparse.Language,
  query : @moonparse.Query,
  snapshot : @moonparse.Snapshot,
  node : @moonparse.Node,
  field : @moonparse.FieldId,
) -> (@moonparse.Parser, @moonparse.Query?, @moonparse.ByteRange) raise @moonparse.QueryError {
  let parser = @moonparse.Parser::new_with_limits(
    language,
    @moonparse.ParseLimits::editor_default(),
  )
  let range : @moonparse.ByteRange = {
    start_byte: 0,
    end_byte: source.byte_length(),
  }
  ignore(snapshot.captures(query))
  ignore(node.child_by_field_id(field))
  ignore(@moonparse.Query::compile(language, "(root)"))
  (parser, language.query(@moonparse.QueryRole::Highlights), range)
}

///|
pub fn compiler_v1_surface_is_visible() -> @compiler.CompileOutput {
  let manifest = @compiler.PackManifest::new(
    name="example",
    version="1.0.0",
    license="Apache-2.0",
  )
  let source = @compiler.PackSource::new(
    manifest,
    grammar_name="grammar/main.moon",
    grammar="start document",
  ).with_highlights(source_name="queries/highlights.scm", query="(document)")
  let output = @compiler.compile_pack(source)
  ignore(output.artifact())
  ignore(output.diagnostics())
  output
}
