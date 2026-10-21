///|
fn text_runner_measure(
  value : String,
  size : Double,
) -> Result[@text_layout.TextMeasurement, @diagnostics.FrameworkError] {
  let document = @text.TextDocument::new(value).unwrap()
  let width = value.length().to_double() * size * 0.6
  let logical = @primitives.Rect::new(0.0, 0.0, width, size * 1.25).unwrap()
  let ink = @primitives.Rect::new(-1.0, -2.0, width + 1.0, size * 1.25 + 2.0).unwrap()
  let carets = []
  let mut offset = 0
  let mut x = 0.0
  let rect = @primitives.Rect::new(x, 0.0, 1.0, size).unwrap()
  carets.push(
    @text_layout.CaretGeometry::new(offset, true, rect, rect).unwrap(),
  )
  for scalar in value.iter() {
    offset += if scalar.to_int() > 0xFFFF { 2 } else { 1 }
    x += size * 0.6
    let rect = @primitives.Rect::new(x, 0.0, 1.0, size).unwrap()
    carets.push(
      @text_layout.CaretGeometry::new(offset, true, rect, rect).unwrap(),
    )
  }
  Ok(
    @text_layout.TextMeasurement::new(
      document,
      logical,
      ink,
      size * 0.8,
      1,
      0,
      carets,
    ).unwrap(),
  )
}

///|
fn settings_test_key(
  host : @testing.ScriptedBackend,
  key : @primitives.Key,
) -> Unit {
  ignore(
    host.enqueue(
      @platform.Input(
        @primitives.KeyPressed(
          key~,
          repeat=false,
          modifiers=@primitives.Modifiers::none(),
        ),
      ),
      1.0,
    ),
  )
  ignore(
    host.enqueue(
      @platform.Input(
        @primitives.KeyReleased(key~, modifiers=@primitives.Modifiers::none()),
      ),
      1.0,
    ),
  )
  for _ in 0..<3 {
    ignore(host.enqueue(@platform.FrameCompleted, 1.0))
  }
}

///|
test "Settings restores TextField after cancel and confirm and revokes open Dialog AX on teardown" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  ignore(host.enqueue(@platform.FocusChanged(true), 1.0))
  for _ in 0..<4 {
    ignore(host.enqueue(@platform.FrameCompleted, 1.0))
  }
  settings_test_key(host, @primitives.Enter)
  settings_test_key(host, @primitives.Escape)
  settings_test_key(host, @primitives.Enter)
  settings_test_key(host, @primitives.Enter)
  for _ in 0..<5 {
    ignore(host.enqueue(@platform.FrameCompleted, 1.0))
  }
  settings_test_key(host, @primitives.Enter)
  ignore(host.enqueue(@platform.Destroyed, 1.0))
  let begun = Ref(0)
  let ended = Ref(0)
  let delivered = Ref(false)
  let epoch = Ref(0UL)
  let documents : Array[String] = []
  let measured : Array[String] = []
  let valid = Ref(true)
  let text_live = Ref(false)
  let dialog_live = Ref(false)
  let dialog_opens = Ref(0)
  let dialog_closes = Ref(0)
  let text_port = @common.NativeTextInputPort::new(
    fn(_, _) {
      begun.val += 1
      epoch.val += 1UL
      Ok(epoch.val)
    },
    fn(current, state) {
      documents.push(state.document().text())
      Ok(current)
    },
    fn(current) { Ok(current + 1UL) },
    fn(_) {
      ended.val += 1
      Ok(())
    },
    fn(_) {
      if delivered.val {
        return Ok(None)
      }
      delivered.val = true
      Ok(
        Some(
          @text_host.TextInputEvent::new(
            host.window(),
            1L,
            epoch.val,
            @text_host.Commit(text="日本語"),
          ),
        ),
      )
    },
  )
  let text_ax = @common.NativeTextAXPort::new(
    fn(_, existing, snapshot) {
      valid.val = valid.val && !dialog_live.val
      valid.val = valid.val &&
        existing == (if text_live.val { 41L } else { 0L })
      valid.val = valid.val && snapshot.focused
      text_live.val = true
      Ok(41L)
    },
    fn(_, token) {
      valid.val = valid.val && token == 41L
      valid.val = valid.val && text_live.val
      text_live.val = false
      Ok(())
    },
  )
  let dialog_ax = @common.NativeDialogAXPort::new(
    fn(_, existing, title, bounds) {
      valid.val = valid.val && !text_live.val
      valid.val = valid.val && title == "Save changes?"
      valid.val = valid.val &&
        bounds.size().width() > 0.0 &&
        bounds.size().height() > 0.0
      valid.val = valid.val &&
        existing == (if dialog_live.val { 42L } else { 0L })
      if !dialog_live.val {
        dialog_opens.val += 1
      }
      dialog_live.val = true
      Ok(42L)
    },
    fn(_, token) {
      valid.val = valid.val && token == 42L
      valid.val = valid.val && dialog_live.val
      dialog_live.val = false
      dialog_closes.val += 1
      Ok(())
    },
  )
  @common.run_native_settings_sample(
    host,
    @common.Macos,
    fn(value, size) {
      measured.push(value)
      text_runner_measure(value, size)
    },
    text_port=Some(text_port),
    accessibility_port=Some(text_ax),
    dialog_port=Some(dialog_ax),
  ).unwrap()
  assert_true(valid.val)
  assert_eq(dialog_opens.val, 3)
  assert_eq(dialog_closes.val, 3)
  assert_eq(begun.val, 3)
  assert_eq(ended.val, begun.val)
  assert_true(documents.contains("日本語"))
  assert_true(measured.contains("Saving..."))
  assert_true(measured.contains("Saved"))
  assert_eq(documents[documents.length() - 1], "日本語")
  assert_false(text_live.val)
  assert_false(dialog_live.val)
}
