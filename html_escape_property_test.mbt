///|
// A bounded alphabet includes all five escaping characters, entity-like text,
// whitespace, BMP and supplementary-plane Unicode. Byte arrays use core's
// generator and shrinker; shrinking is on bytes before this total mapping.
fn escape_input(bytes : Array[Byte]) -> String {
  let alphabet = [
    "a", "&", "<", ">", "\"", "'", " ", "\n", "\t", "é", "雲", "😀", ";", "#",
    "x", "2", "7", "p",
  ]
  let out = StringBuilder()
  for byte in bytes {
    out.write_string(alphabet[byte.to_int() % alphabet.length()])
  }
  out.to_string()
}

///|
// Independent, deliberately partial character-reference interpreter, not a
// copy of the encoder. Reject raw reserved characters and unknown/incomplete
// references. Decode once, so &amp;lt; must remain literal &lt;.
// WHATWG named-characters.html#named-character-references; &#x27; is U+0027.
fn decode_escaped_subset(wire : String) -> String? {
  let out = StringBuilder()
  let mut reference : String? = None
  for c in wire {
    match reference {
      Some(token) =>
        if c == ';' {
          match token {
            "amp" => out.write_char('&')
            "lt" => out.write_char('<')
            "gt" => out.write_char('>')
            "quot" => out.write_char('"')
            "#x27" => out.write_char('\'')
            _ => return None
          }
          reference = None
        } else {
          reference = Some(token + c.to_string())
        }
      None =>
        match c {
          '&' => reference = Some("")
          '<' | '>' | '"' | '\'' => return None
          _ => out.write_char(c)
        }
    }
  }
  match reference {
    Some(_) => None
    None => Some(out.to_string())
  }
}

///|
fn text_and_attribute_preserved(input : String) -> Bool {
  match @yami_kumo.render_html(@yami_kumo.text(input)) {
    Err(_) => false
    Ok(escaped) => {
      if decode_escaped_subset(escaped) != Some(input) {
        return false
      }
      match @yami_kumo.attr("title", input) {
        Err(_) => false
        Ok(attribute) =>
          match @yami_kumo.element("span", [attribute], []) {
            Err(_) => false
            Ok(node) =>
              match @yami_kumo.render_html(node) {
                Err(_) => false
                Ok(output) =>
                  output == "<span title=\"" + escaped + "\"></span>"
              }
          }
      }
    }
  }
}

///|
test "escaping interpreter independent reference vectors" {
  assert_eq(decode_escaped_subset(""), Some(""))
  assert_eq(decode_escaped_subset("&amp;&lt;&gt;&quot;&#x27;"), Some("&<>\"'"))
  assert_eq(decode_escaped_subset("&amp;lt;"), Some("&lt;"))
  assert_eq(decode_escaped_subset("雲😀\n\té"), Some("雲😀\n\té"))
  for
    invalid in [
      "&", "&amp", "&unknown;", "&#x28;", "<", ">", "\"", "'", "&&amp;",
    ] {
    assert_eq(decode_escaped_subset(invalid), None)
  }
}

///|
test "text and title escape preserve generated bounded Unicode" {
  @quickcheck.check(
    fn(bytes : Array[Byte]) {
      text_and_attribute_preserved(escape_input(bytes))
    },
    count=2000,
    max_size=64,
    max_shrinks=1000,
    seed=20261012,
  )
}

///|
test "HTML escaping exact boundaries and entity-looking input" {
  for
    (input, expected) in [
      ("", ""),
      ("&", "&amp;"),
      ("<", "&lt;"),
      (">", "&gt;"),
      ("\"", "&quot;"),
      ("'", "&#x27;"),
      ("&<>\"'", "&amp;&lt;&gt;&quot;&#x27;"),
      ("&amp;&lt;&#x27;", "&amp;amp;&amp;lt;&amp;#x27;"),
      ("&&<<>>\"\"''", "&amp;&amp;&lt;&lt;&gt;&gt;&quot;&quot;&#x27;&#x27;"),
      (" 雲😀é\n\t ", " 雲😀é\n\t "),
    ] {
    match @yami_kumo.render_html(@yami_kumo.text(input)) {
      Ok(actual) => assert_eq(actual, expected)
      Err(_) => fail("valid text failed to render")
    }
    assert_true(text_and_attribute_preserved(input))
  }
  let long = StringBuilder()
  for _ in 0..<1024 {
    long.write_string("&雲😀\"")
  }
  assert_true(text_and_attribute_preserved(long.to_string()))
}
