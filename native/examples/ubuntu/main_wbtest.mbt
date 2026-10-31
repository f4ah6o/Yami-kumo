///|
test "Ubuntu text state rounds fractional logical caret outward" {
  let selection = @text.TextSelection::new(2, 0).unwrap()
  let document = @text.TextDocument::new("日本")
    .unwrap()
    .with_selection(selection)
    .unwrap()
  let marked = @text_host.TextPreedit::new("にほん", selection)
  let caret = @primitives.Rect::new(-3.2, 10.3, 1.0, 17.2).unwrap()
  let state = @text_host.TextInputState::new(document, caret).with_preedit(
    Some(marked),
  )
  let actual = ubuntu_text_state(state).unwrap()
  assert_true(
    actual.caret() == @primitives.Rect::new(-4.0, 10.0, 2.0, 18.0).unwrap(),
  )
  assert_eq(actual.document().text(), "日本")
  assert_true(actual.document().selection() == selection)
  assert_eq(actual.preedit().unwrap().text(), "にほん")
  assert_true(actual.preedit().unwrap().selection() == selection)
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

///|
test "all Ubuntu Settings entry selectors retain the original owner" {
  assert_true(use_retained_settings_entry(["ubuntu", "--settings-e2e"], None))
  assert_true(use_retained_settings_entry(["ubuntu", "--settings-retained-control"], None))
  assert_true(use_retained_settings_entry(["ubuntu"], Some("1")))
  assert_false(use_retained_settings_entry(["ubuntu"], None))
  assert_false(use_retained_settings_entry(["ubuntu", "--text-e2e"], Some("0")))
}
