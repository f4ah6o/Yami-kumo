///|
fn remeasure_native_test_measure(
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
  let first = @primitives.Rect::new(0.0, 0.0, 1.0, size).unwrap()
  carets.push(@text_layout.CaretGeometry::new(0, true, first, first).unwrap())
  for scalar in value.iter() {
    offset += if scalar.to_int() > 0xFFFF { 2 } else { 1 }
    let caret = @primitives.Rect::new(offset.to_double(), 0.0, 1.0, size).unwrap()
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
test "terminal geometry preview preserves composing owner and pending commit" {
  let mounted = Mounted::new(@platform.WindowId::new(1L))
  let key = @view.NodeKey::new("name")
  let view = @view.column(@view.NodeKey::new("root"), [
    @view.text_field(key, @view.TextFieldProps::new("", "Name")),
  ])
  ignore(
    mounted
    .commit(view, 640.0, 480.0, 1.0, remeasure_native_test_measure)
    .unwrap(),
  )
  assert_true(mounted.focus(key))
  let owner = mounted.capture_terminal_text_owner(7UL).unwrap()
  mounted.invalidate_layout()
  let preedit = @text_host.TextInputEvent::new(
    @platform.WindowId::new(1L),
    1L,
    7UL,
    @text_host.Preedit(text="にほん", cursor=3),
  )
  assert_true(!mounted.apply_terminal_observation(owner, preedit).unwrap())
  let before = binding_for(mounted.bindings, key).unwrap().field.unwrap()
  assert_true(before.is_composing())
  let seen : Array[String] = []
  let measured : @components.TextMeasure = fn(value, size) {
    seen.push(value)
    // Simulate a different measurement environment at the same logical font.
    remeasure_native_test_measure(value, size + 2.0)
  }
  let preview = mounted
    .preview_terminal_geometry(owner, view, 800.0, 600.0, 2.0, measured)
    .unwrap()
  assert_true(preview.frame().snapshot().items().length() > 0)
  assert_true(preview.caret().size().height() > 0.0)
  assert_true(preview.caret().size().height() > before.caret_rect().unwrap().size().height())
  assert_true(seen.contains("にほん"))
  assert_true(seen.contains(""))
  let after = binding_for(mounted.bindings, key).unwrap().field.unwrap()
  assert_true(after.document() == before.document())
  assert_eq(after.revision(), before.revision())
  assert_true(after.is_composing())
  assert_true(!mounted.ready)
  let fail_rollback : @components.TextMeasure = fn(value, size) {
    if value == "" {
      Err(adapter_error("injected rollback failure"))
    } else {
      remeasure_native_test_measure(value, size)
    }
  }
  assert_true(
    mounted.preview_terminal_geometry(
      owner, view, 800.0, 600.0, 2.0, fail_rollback,
    )
    is Err(_),
  )
  let missing = @view.column(@view.NodeKey::new("root"), [])
  assert_true(
    mounted.preview_terminal_geometry(
      owner, missing, 800.0, 600.0, 2.0, measured,
    )
    is Err(_),
  )
  let foreign = Mounted::new(@platform.WindowId::new(1L))
  ignore(
    foreign.commit(view, 640.0, 480.0, 1.0, remeasure_native_test_measure).unwrap(),
  )
  assert_true(foreign.focus(key))
  ignore(foreign.capture_terminal_text_owner(7UL).unwrap())
  foreign.invalidate_layout()
  assert_true(
    foreign.preview_terminal_geometry(
      owner, view, 800.0, 600.0, 2.0, measured,
    )
    is Err(_),
  )
  foreign.dispose()
  let reenter : @components.TextMeasure = fn(value, size) {
    mounted.invalidate_layout()
    remeasure_native_test_measure(value, size)
  }
  assert_true(
    mounted.preview_terminal_geometry(owner, view, 800.0, 600.0, 2.0, reenter)
    is Err(_),
  )
  assert_eq(
    binding_for(mounted.bindings, key).unwrap().field.unwrap().revision(),
    before.revision(),
  )
  let commit = @text_host.TextInputEvent::new(
    @platform.WindowId::new(1L),
    2L,
    7UL,
    @text_host.Commit(text="日本"),
  )
  assert_true(mounted.apply_terminal_commit(owner, commit).unwrap())
  assert_true(
    mounted.next_terminal_text_action(owner).unwrap()
    is Some(@view.TextChanged(_, "日本")),
  )
  assert_true(mounted.apply_terminal_commit(owner, commit) is Err(_))
  mounted.dispose()
}
