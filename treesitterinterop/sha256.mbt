///|
let sha256_initial : Array[UInt] = [
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
  0x5be0cd19,
]

///|
let sha256_rounds : Array[UInt] = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
  0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
  0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
  0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
  0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
  0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
  0xc67178f2,
]

///|
fn rotr32(value : UInt, bits : Int) -> UInt {
  (value >> bits) | (value << (32 - bits))
}

///|
fn sha256_ch(x : UInt, y : UInt, z : UInt) -> UInt {
  (x & y) ^ (x.lnot() & z)
}

///|
fn sha256_maj(x : UInt, y : UInt, z : UInt) -> UInt {
  (x & y) ^ (x & z) ^ (y & z)
}

///|
fn sha256_big0(x : UInt) -> UInt {
  rotr32(x, 2) ^ rotr32(x, 13) ^ rotr32(x, 22)
}

///|
fn sha256_big1(x : UInt) -> UInt {
  rotr32(x, 6) ^ rotr32(x, 11) ^ rotr32(x, 25)
}

///|
fn sha256_small0(x : UInt) -> UInt {
  rotr32(x, 7) ^ rotr32(x, 18) ^ (x >> 3)
}

///|
fn sha256_small1(x : UInt) -> UInt {
  rotr32(x, 17) ^ rotr32(x, 19) ^ (x >> 10)
}

///|
fn sha256_hex8(value : UInt) -> String {
  let raw = value.to_string(radix=16)
  let out = StringBuilder::new()
  for _ in 0..<(8 - raw.length()) {
    out.write_char('0')
  }
  out.write_string(raw)
  out.to_string()
}

///|
pub fn sha256_bytes_hex(data : Bytes) -> String {
  let msg = data.to_array()
  msg.push((0x80).to_byte())
  while msg.length() % 64 != 56 {
    msg.push((0).to_byte())
  }
  let bit_len = data.length() * 8
  msg.push((0).to_byte())
  msg.push((0).to_byte())
  msg.push((0).to_byte())
  msg.push((0).to_byte())
  msg.push(((bit_len >> 24) & 0xff).to_byte())
  msg.push(((bit_len >> 16) & 0xff).to_byte())
  msg.push(((bit_len >> 8) & 0xff).to_byte())
  msg.push((bit_len & 0xff).to_byte())
  let h = sha256_initial.copy()
  let mut offset = 0
  while offset < msg.length() {
    let w : Array[UInt] = Array::make(64, 0)
    for i in 0..<16 {
      let j = offset + i * 4
      w[i] = (msg[j].to_uint() << 24) |
        (msg[j + 1].to_uint() << 16) |
        (msg[j + 2].to_uint() << 8) |
        msg[j + 3].to_uint()
    }
    for i in 16..<64 {
      w[i] = sha256_small1(w[i - 2]) +
        w[i - 7] +
        sha256_small0(w[i - 15]) +
        w[i - 16]
    }
    let mut a = h[0]
    let mut b = h[1]
    let mut c = h[2]
    let mut d = h[3]
    let mut e = h[4]
    let mut f = h[5]
    let mut g = h[6]
    let mut hh = h[7]
    for i in 0..<64 {
      let t1 = hh +
        sha256_big1(e) +
        sha256_ch(e, f, g) +
        sha256_rounds[i] +
        w[i]
      let t2 = sha256_big0(a) + sha256_maj(a, b, c)
      hh = g
      g = f
      f = e
      e = d + t1
      d = c
      c = b
      b = a
      a = t1 + t2
    }
    h[0] = h[0] + a
    h[1] = h[1] + b
    h[2] = h[2] + c
    h[3] = h[3] + d
    h[4] = h[4] + e
    h[5] = h[5] + f
    h[6] = h[6] + g
    h[7] = h[7] + hh
    offset = offset + 64
  }
  h.map(sha256_hex8).join("")
}
