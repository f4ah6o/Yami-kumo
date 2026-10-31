///|
fn owner_focus_measure(
  value : String,
  size : Double,
) -> Result[@text_layout.TextMeasurement, @diagnostics.FrameworkError] {
  let document = @text.TextDocument::new(value).unwrap()
  let bounds = @primitives.Rect::new(
    0.0,
    0.0,
    (value.length() + 1).to_double() * size,
    size,
  ).unwrap()
  let carets = []
  let mut offset = 0
  let caret = @primitives.Rect::new(0.0, 0.0, 1.0, size).unwrap()
  carets.push(@text_layout.CaretGeometry::new(0, true, caret, caret).unwrap())
  for scalar in value.iter() {
    offset += if scalar.to_int() > 0xFFFF { 2 } else { 1 }
    let caret = @primitives.Rect::new(offset.to_double() * size, 0.0, 1.0, size).unwrap()
    carets.push(
      @text_layout.CaretGeometry::new(offset, true, caret, caret).unwrap(),
    )
  }
  Ok(
    @text_layout.TextMeasurement::new(
      document,
      bounds,
      bounds,
      size * 0.8,
      1,
      0,
      carets,
    ).unwrap(),
  )
}

///|
test "owned geometry stage holds resized focus proposal without publication" {
  let mounted = Mounted::new(@platform.WindowId::new(1L))
  let key = @view.NodeKey::new("name")
  let view = @view.column(@view.NodeKey::new("root"), [
    @view.text_field(key, @view.TextFieldProps::new("", "Name")),
  ])
  ignore(mounted.commit(view, 640.0, 480.0, 1.0, owner_focus_measure).unwrap())
  assert_true(mounted.focus(key))
  let owner = mounted.capture_terminal_text_owner(7UL).unwrap()
  let scope = mounted.scope.unwrap()
  let old_target = scope.target()
  let old_focus = scope.snapshot().focus_owner()
  let old_root = scope.snapshot().node(1UL).unwrap().bounds()
  let candidate = mounted
    .stage_owned_text_geometry(
      owner, view, 800.0, 480.0, 1.5, owner_focus_measure,
    )
    .unwrap()
  assert_true(mounted.inspect_staged_text_geometry(owner, candidate) is Ok(_))
  assert_true(scope.target() == old_target)
  assert_true(scope.snapshot().focus_owner() == old_focus)
  assert_true(scope.snapshot().node(1UL).unwrap().bounds() == old_root)
  // An exact-owner candidate does not give access to normal publication.
  assert_true(mounted.publish(candidate) is Err(_))
  assert_true(scope.target() == old_target)
  // A fresh acquisition on the same numeric binding invalidates the captured
  // focus proposal even if all field and session identity numbers are equal.
  scope.request_focus(scope.target(), owner.binding).unwrap()
  assert_true(scope.snapshot().focus_owner() != old_focus)
  assert_true(mounted.inspect_staged_text_geometry(owner, candidate) is Err(_))
  assert_false(mounted.terminal_owner_is_current(owner))
  let old_commit = @text_host.TextInputEvent::new(
    @platform.WindowId::new(1L),
    1L,
    7UL,
    @text_host.Commit(text="日本"),
  )
  assert_true(mounted.reserve_owned_text(owner, old_commit) is Err(_))
  assert_true(mounted.text_input(7UL, old_commit) is Err(_))
  assert_true(mounted.begin_held_text(7UL) is Err(_))
  assert_eq(mounted.focused_text().unwrap().document().text(), "")
  assert_false(mounted.has_pending_actions())
  assert_true(
    mounted.stage_owned_text_geometry(
      owner, view, 800.0, 480.0, 1.5, owner_focus_measure,
    )
    is Err(_),
  )
  assert_true(
    owner.matches_session(@platform.WindowId::new(1L), 7UL, owner.binding),
  )
}

///|
test "continuous owned frame keeps focus acquisition and queued action is retained on refusal" {
  let mounted = Mounted::new(@platform.WindowId::new(1L))
  let key = @view.NodeKey::new("name")
  let view = @view.column(@view.NodeKey::new("root"), [
    @view.text_field(key, @view.TextFieldProps::new("", "Name")),
  ])
  ignore(mounted.commit(view, 640.0, 480.0, 1.0, owner_focus_measure).unwrap())
  assert_true(mounted.focus(key))
  let owner = mounted.capture_terminal_text_owner(7UL).unwrap()
  let scope = mounted.scope.unwrap()
  let original_focus = scope.snapshot().focus_owner()
  ignore(mounted.commit(view, 640.0, 480.0, 1.0, owner_focus_measure).unwrap())
  assert_true(scope.snapshot().focus_owner() == original_focus)
  assert_true(mounted.terminal_owner_is_current(owner))
  assert_true(mounted.runtime.enqueue_text_changed(owner.token, "retained"))
  let prepared = mounted
    .stage(view, 640.0, 480.0, 1.0, owner_focus_measure)
    .unwrap()
  assert_true(mounted.publish(prepared) is Err(_))
  assert_true(scope.snapshot().focus_owner() == original_focus)
  assert_true(mounted.runtime.has_pending_actions())
  assert_true(
    mounted.runtime.next_action() is Some(@view.TextChanged(_, "retained")),
  )
}
