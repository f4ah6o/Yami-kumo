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
test "text runner begins, updates and ends a session around a commit" {
  let host = @testing.ScriptedBackend::new(640.0, 360.0, 1.0).unwrap()
  ignore(
    host.enqueue(
      @platform.Input(
        @primitives.KeyPressed(
          key=@primitives.Tab,
          repeat=false,
          modifiers=@primitives.Modifiers::none(),
        ),
      ),
      1.0,
    ),
  )
  // The first input arrives before the initial frame is ready and is ignored.
  ignore(
    host.enqueue(
      @platform.Input(
        @primitives.KeyPressed(
          key=@primitives.Tab,
          repeat=false,
          modifiers=@primitives.Modifiers::none(),
        ),
      ),
      1.0,
    ),
  )
  ignore(host.enqueue(@platform.FrameCompleted, 1.0))
  ignore(host.enqueue(@platform.FrameCompleted, 1.0))
  ignore(host.enqueue(@platform.Destroyed, 1.0))
  let begun : Ref[Int32] = Ref(0)
  let updates : Ref[Array[String]] = Ref([])
  let cancelled : Ref[Int32] = Ref(0)
  let ended : Ref[Bool] = Ref(false)
  let queue : Ref[Array[@text_host.TextInputEvent]] = Ref([
    @text_host.TextInputEvent::new(
      host.window(),
      1L,
      7UL,
      @text_host.Preedit(text="にほん", cursor=3),
    ),
    @text_host.TextInputEvent::new(
      host.window(),
      2L,
      7UL,
      @text_host.Commit(text="日本語"),
    ),
    @text_host.TextInputEvent::new(host.window(), 3L, 7UL, @text_host.FocusLost),
  ])
  let turn : Ref[Bool] = Ref(false)
  let port = NativeTextInputPort::new(
    fn(_window, _root) {
      begun.val += 1
      Ok(7UL)
    },
    fn(epoch, state) {
      updates.val.push(state.document().text())
      Ok(epoch)
    },
    fn(epoch) {
      cancelled.val += 1
      Ok(epoch + 1UL)
    },
    fn(_epoch) {
      ended.val = true
      Ok(())
    },
    fn(_timeout) {
      // One observation per tick, so the runner reaches its frame commit
      // between the preview, the commit and the focus loss.
      if turn.val {
        turn.val = false
        return Ok(None)
      }
      turn.val = true
      if queue.val.length() == 0 {
        Ok(None)
      } else {
        Ok(Some(queue.val.remove(0)))
      }
    },
  )
  let publishes : Ref[Array[String]] = Ref([])
  let revoked : Ref[Int] = Ref(0)
  let ax_port = NativeTextAXPort::new(
    fn(_window, _existing, snapshot) {
      publishes.val.push(snapshot.value)
      Ok(42L)
    },
    fn(_window, _token) {
      revoked.val += 1
      Ok(())
    },
  )
  let result = run_native_text_sample(
    host,
    Macos,
    text_runner_measure,
    text_port=Some(port),
    accessibility_port=Some(ax_port),
  )
  match result {
    Err(error) => abort(error.message().unwrap_or("text runner failed"))
    Ok(_) => ()
  }
  assert_eq(begun.val, 1)
  assert_true(ended.val)
  assert_eq(cancelled.val, 1)
  assert_true(updates.val.contains("日本語"))
  assert_true(publishes.val.length() > 0)
  assert_eq(publishes.val[publishes.val.length() - 1], "日本語")
  assert_eq(revoked.val, 1)
}
