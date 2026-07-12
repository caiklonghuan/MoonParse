///|
test "mpack manifest accepts canonical deterministic JSON subset" {
  let manifest = b"{\"capabilities\":{\"nested\":true,\"scanner\":false},\"license\":\"Apache-2.0\",\"name\":\"Moon\\nParse\",\"source\":null,\"tags\":[\"parser\",1,-2],\"version\":\"1.0.0\"}"
  match encode_pack(semantic_sections(manifest_json=manifest)) {
    Ok(bytes) =>
      match validate_pack(bytes) {
        Ok(_) => ()
        Err(error) => fail("validation failed: \{to_repr(error)}")
      }
    Err(error) => fail("encode failed: \{to_repr(error)}")
  }
}

///|
test "mpack manifest rejects duplicate and unsorted object keys" {
  assert_true(
    encode_pack(semantic_sections(manifest_json=b"{\"name\":1,\"name\":2}"))
    is Err(DuplicateManifestKey),
  )
  assert_true(
    encode_pack(semantic_sections(manifest_json=b"{\"version\":1,\"name\":2}"))
    is Err(NonCanonicalManifestJson),
  )
  assert_true(
    encode_pack(semantic_sections(manifest_json=b"{\"a\":{\"z\":1,\"b\":2}}"))
    is Err(NonCanonicalManifestJson),
  )
}

///|
test "mpack manifest orders property names by UTF-16 code units" {
  let canonical = @utf8.encode("{\"😀\":1,\"\":2}")
  let reversed = @utf8.encode("{\"\":2,\"😀\":1}")
  assert_true(encode_pack(semantic_sections(manifest_json=canonical)) is Ok(_))
  assert_true(
    encode_pack(semantic_sections(manifest_json=reversed))
    is Err(NonCanonicalManifestJson),
  )
}

///|
test "mpack manifest rejects whitespace and non-minimal escapes" {
  assert_true(
    encode_pack(semantic_sections(manifest_json=b"{ \"name\":\"x\"}"))
    is Err(NonCanonicalManifestJson),
  )
  assert_true(
    encode_pack(semantic_sections(manifest_json=b"{\"name\":\"a\\/b\"}"))
    is Err(NonCanonicalManifestJson),
  )
  assert_true(
    encode_pack(semantic_sections(manifest_json=b"{\"name\":\"\\u0061\"}"))
    is Err(NonCanonicalManifestJson),
  )
  assert_true(
    encode_pack(semantic_sections(manifest_json=b"{\"name\":\"\\u000A\"}"))
    is Err(NonCanonicalManifestJson),
  )
}

///|
test "mpack manifest rejects invalid UTF-8 encodings" {
  let invalid : Array[Byte] = [
    b'{', b'"', b'n', b'a', b'm', b'e', b'"', b':', b'"', 0xC0, 0xAF, b'"', b'}',
  ]
  let invalid = Bytes::makei(invalid.length(), fn(index) { invalid[index] })
  assert_true(
    encode_pack(semantic_sections(manifest_json=invalid))
    is Err(InvalidManifestUtf8),
  )
  let surrogate : Array[Byte] = [
    b'{', b'"', b'n', b'a', b'm', b'e', b'"', b':', b'"', 0xED, 0xA0, 0x80, b'"',
    b'}',
  ]
  let surrogate = Bytes::makei(surrogate.length(), fn(index) {
    surrogate[index]
  })
  assert_true(
    encode_pack(semantic_sections(manifest_json=surrogate))
    is Err(InvalidManifestUtf8),
  )
}

///|
test "mpack manifest accepts RFC 8785 canonical number forms" {
  for
    number in [
      b"0", b"1", b"1.5", b"333333333.3333333", b"1e+30", b"4.5e-7", b"0.000001",
      b"1e-7", b"9007199254740992",
    ] {
    let json : Array[Byte] = [b'{', b'"', b'n', b'"', b':']
    for byte in number {
      json.push(byte)
    }
    json.push(b'}')
    let json = Bytes::makei(json.length(), fn(index) { json[index] })
    assert_true(encode_pack(semantic_sections(manifest_json=json)) is Ok(_))
  }
}

///|
test "mpack manifest rejects non-canonical or non-finite number forms" {
  for
    number in [
      b"-0", b"01", b"1.0", b"1e0", b"1E+30", b"1e30", b"0.0000001", b"333333333.33333329",
      b"1e+400",
    ] {
    let json : Array[Byte] = [b'{', b'"', b'n', b'"', b':']
    for byte in number {
      json.push(byte)
    }
    json.push(b'}')
    let json = Bytes::makei(json.length(), fn(index) { json[index] })
    assert_true(
      encode_pack(semantic_sections(manifest_json=json))
      is Err(InvalidManifestNumber),
    )
  }
}

///|
test "mpack manifest rejects trailing bytes and excessive nesting" {
  assert_true(
    encode_pack(semantic_sections(manifest_json=b"{}{}"))
    is Err(InvalidManifestJson),
  )
  let nested : Array[Byte] = [b'{', b'"', b'a', b'"', b':']
  for _ in 0..<65 {
    nested.push(b'[')
  }
  for _ in 0..<65 {
    nested.push(b']')
  }
  nested.push(b'}')
  let nested = Bytes::makei(nested.length(), fn(index) { nested[index] })
  assert_true(
    encode_pack(semantic_sections(manifest_json=nested))
    is Err(InvalidManifestJson),
  )
}
