///|
fn lifecycle_measure(
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
test "private App drains Changed and Released work and rejects stale owners" {
  let counter = NativeCounter::new(@platform.WindowId::new(1L)).unwrap()
  ignore(counter.render(640.0, 480.0, 1.0, lifecycle_measure).unwrap())
  let app = counter.app
  let state = counter.state
  let lifetime = app.lifetime()
  let key = @view.NodeKey::new("increment")
  let callback = counter.mount.callback(key).unwrap()
  for index in 0..<100 {
    assert_true(counter.mount.activate(callback))
    assert_true(
      counter.drain_one(640.0, 480.0, 1.0, lifecycle_measure).unwrap(),
    )
    assert_eq(counter.count().unwrap(), index + 1)
    assert_eq(app.pending_work(), 0)
    assert_true(app.lifecycle() is @app.Running)
    assert_true(state.is_live())
  }
  counter.dispose()
  assert_eq(app.pending_work(), 0)
  assert_true(app.lifecycle() is @app.Stopped)
  assert_true(!lifetime.is_alive())
  assert_true(!lifetime.is_running())
  assert_true(!state.is_live())
  assert_true(app.read(state, model => model.value()) is Err(_))
  assert_true(app.update(state, context => context.notify()) is Err(_))
  assert_true(!counter.mount.activate(callback))
  assert_true(!counter.drain_one(640.0, 480.0, 1.0, lifecycle_measure).unwrap())
  counter.dispose()
  assert_eq(app.pending_work(), 0)
  assert_true(app.lifecycle() is @app.Stopped)
}
