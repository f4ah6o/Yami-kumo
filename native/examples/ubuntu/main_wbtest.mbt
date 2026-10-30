///|
test "Ubuntu text state rounds fractional logical caret outward" {
  let document = @text.TextDocument::new("日本").unwrap()
  let caret = @primitives.Rect::new(-3.2, 10.3, 1.0, 17.2).unwrap()
  let actual = ubuntu_text_caret(caret).unwrap()
  assert_true(actual == @primitives.Rect::new(-4.0, 10.0, 2.0, 18.0).unwrap())
  assert_eq(document.text(), "日本")
}

///|
test "Ubuntu text caret rejects overflow and empty bounds" {
  for
    caret in [
      @primitives.Rect::new(2147483647.0, 0.0, 1.0, 1.0).unwrap(),
      @primitives.Rect::new(-2147483649.0, 0.0, 1.0, 1.0).unwrap(),
      @primitives.Rect::new(0.0, 0.0, 0.0, 1.0).unwrap(),
    ] {
    assert_true(ubuntu_text_caret(caret) is Err(_))
  }
}
