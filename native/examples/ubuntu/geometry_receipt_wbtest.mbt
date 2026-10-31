///|
test "geometry candidate comparison includes selection caret and preedit" {
  let document = @text.TextDocument::new("日本").unwrap()
  let caret = @primitives.Rect::new(1.0, 2.0, 1.0, 18.0).unwrap()
  let base = @text_host.TextInputState::new(document, caret)
  assert_true(same_geometry_state(base, base))
  let moved = document.with_selection(@text.TextSelection::new(1, 1).unwrap()).unwrap()
  assert_false(same_geometry_state(base, @text_host.TextInputState::new(moved, caret)))
  let other_caret = @primitives.Rect::new(2.0, 2.0, 1.0, 18.0).unwrap()
  assert_false(same_geometry_state(base, @text_host.TextInputState::new(document, other_caret)))
  let one = @text_host.TextPreedit::new("に", @text.TextSelection::new(1, 1).unwrap())
  let two = @text_host.TextPreedit::new("に", @text.TextSelection::new(0, 1).unwrap())
  assert_false(same_geometry_state(base, base.with_preedit(Some(one))))
  assert_false(same_geometry_state(base.with_preedit(Some(one)), base.with_preedit(Some(two))))
  assert_true(same_geometry_state(base.with_preedit(Some(one)), base.with_preedit(Some(one))))
}
