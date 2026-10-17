///|
fn measure(
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
fn failed_measure(
  _value : String,
  _size : Double,
) -> Result[@text_layout.TextMeasurement, @diagnostics.FrameworkError] {
  Err(
    @diagnostics.FrameworkError::new(
      @diagnostics.InvalidInput,
      "injected measurement failure",
    ),
  )
}

///|
fn event(sequence : Int64, input : @primitives.InputEvent) -> @platform.Event {
  @platform.Event::new(
    @platform.WindowId::new(1L),
    sequence,
    1.0,
    @platform.Input(input),
  )
}

///|
fn down(bounds : @primitives.Rect) -> @primitives.InputEvent {
  @primitives.PointerButtonPressed(
    position=@primitives.Point::new(bounds.left() + 4.0, bounds.top() + 4.0).unwrap(),
    button=@primitives.Primary,
    modifiers=@primitives.Modifiers::none(),
  )
}

///|
fn up(bounds : @primitives.Rect) -> @primitives.InputEvent {
  @primitives.PointerButtonReleased(
    position=@primitives.Point::new(bounds.left() + 4.0, bounds.top() + 4.0).unwrap(),
    button=@primitives.Primary,
    modifiers=@primitives.Modifiers::none(),
  )
}

///|
fn key_down(
  key : @primitives.Key,
  repeat~ : Bool = false,
) -> @primitives.InputEvent {
  @primitives.KeyPressed(key~, repeat~, modifiers=@primitives.Modifiers::none())
}

///|
fn key_up(key : @primitives.Key) -> @primitives.InputEvent {
  @primitives.KeyReleased(key~, modifiers=@primitives.Modifiers::none())
}

///|
fn counter(disabled~ : Bool = false) -> @shared_counter.NativeCounter {
  @shared_counter.NativeCounter::new(@platform.WindowId::new(1L), disabled~).unwrap()
}

///|
fn render(app : @shared_counter.NativeCounter) -> @shared_counter.CounterFrame {
  app.render(640.0, 480.0, 1.0, measure).unwrap()
}

///|
fn drain(app : @shared_counter.NativeCounter) -> Bool {
  app.drain_one(640.0, 480.0, 1.0, measure).unwrap()
}

///|
test "real adapter and single App-owned shared model match fixed 0 1 2 fixture" {
  let app = counter()
  let frame = render(app)
  let bounds = frame.button_bounds()
  let trace = [frame.count()]
  let revision = app.model_revision().unwrap()
  for index in 0..<2 {
    let sequence = index.to_int64() * 2L + 1L
    ignore(app.handle_event(event(sequence, down(bounds))))
    assert_eq(app.count().unwrap(), index)
    assert_true(render(app).button_pressed())
    ignore(app.handle_event(event(sequence + 1L, up(bounds))))
    assert_eq(app.count().unwrap(), index)
    assert_true(drain(app))
    assert_true(!drain(app))
    let frame = render(app)
    trace.push(frame.count())
    assert_true(frame.button_focused())
    assert_true(!frame.button_pressed())
    assert_true(frame.button_enabled())
    assert_true(!frame.button_loading())
  }
  assert_eq(trace, [0, 1, 2])
  assert_eq(app.actions().length(), 2)
  assert_eq(app.model_revision().unwrap(), revision + 2UL)
  app.actions().clear()
  assert_eq(app.actions().length(), 2)
  app.dispose()
  app.dispose()
  assert_true(app.count() is Err(_))
  assert_true(!app.handle_event(event(5L, down(bounds))).unwrap())
}

///|
test "real adapter disabled loading enabled fixture is 0 0 0 1" {
  let app = counter(disabled=true)
  let trace = [render(app).count()]
  let bounds = render(app).button_bounds()
  ignore(app.handle_event(event(1L, down(bounds))))
  ignore(app.handle_event(event(2L, up(bounds))))
  assert_true(!drain(app))
  trace.push(app.count().unwrap())
  app.set_mode(false, true, 640.0, 480.0, 1.0, measure).unwrap()
  assert_true(render(app).button_loading())
  ignore(app.handle_event(event(3L, down(bounds))))
  ignore(app.handle_event(event(4L, up(bounds))))
  assert_true(!drain(app))
  trace.push(app.count().unwrap())
  app.set_mode(false, false, 640.0, 480.0, 1.0, measure).unwrap()
  ignore(app.handle_event(event(5L, down(bounds))))
  ignore(app.handle_event(event(6L, up(bounds))))
  assert_true(drain(app))
  trace.push(app.count().unwrap())
  assert_eq(trace, [0, 0, 0, 1])
  assert_eq(app.actions().length(), 1)
}

///|
test "failed next frame stages before model update and preserves accepted model view" {
  let app = counter()
  let initial = render(app)
  let revision = app.model_revision().unwrap()
  ignore(app.handle_event(event(1L, down(initial.button_bounds()))))
  ignore(app.handle_event(event(2L, up(initial.button_bounds()))))
  assert_true(app.drain_one(640.0, 480.0, 1.0, failed_measure) is Err(_))
  assert_eq(app.count().unwrap(), 0)
  assert_eq(app.model_revision().unwrap(), revision)
  assert_eq(app.actions().length(), 0)
  assert_eq(render(app).count(), 0)
  assert_true(
    app.set_mode(true, false, 640.0, 480.0, 1.0, failed_measure) is Err(_),
  )
  assert_true(render(app).button_enabled())
  ignore(app.handle_event(event(3L, down(initial.button_bounds()))))
  ignore(app.handle_event(event(4L, up(initial.button_bounds()))))
  assert_true(drain(app))
  assert_eq(render(app).count(), 1)
}

///|
test "queued input drains individually through model and same-layout commit preserves pointer plus Space" {
  let app = counter()
  let bounds = render(app).button_bounds()
  ignore(app.handle_event(event(1L, down(bounds))))
  ignore(app.handle_event(event(2L, key_down(@primitives.Space))))
  ignore(app.handle_event(event(3L, key_up(@primitives.Space))))
  assert_eq(app.count().unwrap(), 0)
  assert_true(drain(app))
  assert_eq(render(app).count(), 1)
  assert_true(render(app).button_pressed())
  ignore(app.handle_event(event(4L, up(bounds))))
  assert_true(drain(app))
  assert_eq(render(app).count(), 2)
  assert_eq(app.actions().length(), 2)
}

///|
test "resize focus loss and disposal cancel queued model work" {
  let app = counter()
  let bounds = render(app).button_bounds()
  ignore(app.handle_event(event(1L, down(bounds))))
  ignore(app.handle_event(event(2L, up(bounds))))
  ignore(
    app.handle_event(
      @platform.Event::new(
        @platform.WindowId::new(1L),
        3L,
        1.0,
        @platform.Resized(width=800.0, height=480.0),
      ),
    ),
  )
  assert_true(!drain(app))
  ignore(render(app))
  ignore(app.handle_event(event(4L, down(bounds))))
  ignore(app.handle_event(event(5L, key_down(@primitives.Enter))))
  ignore(
    app.handle_event(
      @platform.Event::new(
        @platform.WindowId::new(1L),
        6L,
        1.0,
        @platform.FocusChanged(false),
      ),
    ),
  )
  assert_true(!drain(app))
  assert_eq(render(app).count(), 0)
  ignore(
    app.handle_event(
      @platform.Event::new(
        @platform.WindowId::new(1L),
        7L,
        1.0,
        @platform.Destroyed,
      ),
    ),
  )
  assert_true(app.count() is Err(_))
  assert_true(!drain(app))
}

///|
test "two queued native activations each commit before the next drain" {
  let app = counter()
  let bounds = render(app).button_bounds()
  ignore(app.handle_event(event(1L, down(bounds))))
  ignore(app.handle_event(event(2L, key_down(@primitives.Space))))
  ignore(app.handle_event(event(3L, key_up(@primitives.Space))))
  ignore(app.handle_event(event(4L, up(bounds))))
  assert_eq(app.count().unwrap(), 0)
  assert_true(drain(app))
  let first = render(app)
  assert_eq(first.count(), 1)
  assert_true(drain(app))
  let second = render(app)
  assert_eq(second.count(), 2)
  assert_true(second.revision() > first.revision())
  assert_true(!drain(app))
}

///|
test "measurement callback cannot reenter model drain and disposal prevents publication" {
  let app = counter()
  let bounds = render(app).button_bounds()
  ignore(app.handle_event(event(1L, down(bounds))))
  ignore(app.handle_event(event(2L, up(bounds))))
  let refused = Ref(false)
  assert_true(
    app
    .drain_one(640.0, 480.0, 1.0, (text, size) => {
      refused.val = !app.drain_one(640.0, 480.0, 1.0, measure).unwrap()
      measure(text, size)
    })
    .unwrap(),
  )
  assert_true(refused.val)
  assert_eq(app.count().unwrap(), 1)
  ignore(app.handle_event(event(3L, down(bounds))))
  ignore(app.handle_event(event(4L, up(bounds))))
  assert_true(
    app.drain_one(640.0, 480.0, 1.0, (text, size) => {
      app.dispose()
      measure(text, size)
    })
    is Err(_),
  )
  assert_true(app.count() is Err(_))
  assert_eq(app.actions().length(), 1)
}

///|
test "Card bootstrap keeps one model and decorated view through actual adapter updates" {
  let app = @shared_counter.NativeCounter::new(
    @platform.WindowId::new(1L),
    card=true,
  ).unwrap()
  let trace = []
  for index in 0..<3 {
    let frame = render(app)
    trace.push(frame.count())
    assert_eq(frame.heading_bounds().left() - frame.card_bounds().left(), 17.0)
    assert_eq(frame.heading_bounds().top() - frame.card_bounds().top(), 17.0)
    assert_eq(
      frame.button_bounds().top() - frame.counter_bounds().bottom(),
      12.0,
    )
    assert_eq(
      frame.card_bounds().bottom() - frame.button_bounds().bottom(),
      17.0,
    )
    if index > 0 {
      assert_true(frame.button_focused())
    }
    if index < 2 {
      let sequence = index.to_int64() * 2L + 1L
      ignore(app.handle_event(event(sequence, down(frame.button_bounds()))))
      ignore(app.handle_event(event(sequence + 1L, up(frame.button_bounds()))))
      assert_true(drain(app))
    }
  }
  assert_eq(trace, [0, 1, 2])
  app.set_mode(false, true, 640.0, 480.0, 1.0, measure).unwrap()
  let frame = render(app)
  assert_true(frame.button_loading())
  assert_eq(frame.heading_bounds().left() - frame.card_bounds().left(), 17.0)
  assert_eq(app.count().unwrap(), 2)
  app.dispose()
}

///|
test "shared spacing consumer drives count toggle count toggle with stable bindings and focus" {
  let app = @shared_counter.NativeCounter::new(
    @platform.WindowId::new(1L),
    spacing=true,
  ).unwrap()
  let initial = render(app)
  let increment_id = initial.button_binding_id()
  let toggle_id = initial.toggle_binding_id()
  assert_true(increment_id != toggle_id)
  let counts = [initial.count()]
  let expanded = [initial.expanded()]
  let initial_revision = app.model_revision().unwrap()
  for index in 0..<4 {
    let frame = render(app)
    let is_toggle = index % 2 == 1
    let bounds = if is_toggle {
      frame.toggle_bounds()
    } else {
      frame.button_bounds()
    }
    let sequence = index.to_int64() * 2L + 1L
    ignore(app.handle_event(event(sequence, down(bounds))))
    let held = render(app)
    assert_true(
      if is_toggle {
        held.toggle_pressed()
      } else {
        held.button_pressed()
      },
    )
    // An unchanged-geometry repaint retains the existing Button's held state.
    assert_eq(held.button_binding_id(), increment_id)
    assert_eq(held.toggle_binding_id(), toggle_id)
    ignore(app.handle_event(event(sequence + 1L, up(bounds))))
    assert_true(drain(app))
    assert_false(drain(app))
    let after = render(app)
    counts.push(after.count())
    expanded.push(after.expanded())
    assert_eq(after.button_binding_id(), increment_id)
    assert_eq(after.toggle_binding_id(), toggle_id)
    assert_eq(after.button_focused(), !is_toggle)
    assert_eq(after.toggle_focused(), is_toggle)
    assert_false(after.button_pressed())
    assert_false(after.toggle_pressed())
    if index == 1 {
      assert_true(after.button_bounds() != initial.button_bounds())
      assert_true(after.toggle_bounds() != initial.toggle_bounds())
    }
  }
  let final_frame = render(app)
  assert_eq(counts, [0, 1, 1, 2, 2])
  assert_eq(expanded, [false, false, true, true, false])
  assert_eq(final_frame.action_keys(), [
    "increment", "spacing-toggle", "increment", "spacing-toggle",
  ])
  assert_true(final_frame.button_bounds() == initial.button_bounds())
  assert_true(final_frame.toggle_bounds() == initial.toggle_bounds())
  assert_eq(app.model_revision().unwrap(), initial_revision + 4UL)
  final_frame.action_keys().clear()
  assert_eq(final_frame.action_keys().length(), 4)
  app.dispose()
}

///|
test "spacing consumer observations follow intrinsic union gaps padding and fixed Card" {
  let app = @shared_counter.NativeCounter::new(
    @platform.WindowId::new(1L),
    spacing=true,
  ).unwrap()
  for phase in 0..<2 {
    let frame = render(app)
    let outer = frame.stack_bounds()
    let row = frame.row_bounds()
    let heading = frame.heading_bounds()
    let count = frame.counter_bounds()
    let button = frame.button_bounds()
    let toggle = frame.toggle_bounds()
    let card = frame.card_bounds()
    let label = frame.card_label_bounds()
    let outer_gap = if phase == 0 { 0.0 } else { 12.0 }
    let outer_padding = if phase == 0 { 4.0 } else { 16.0 }
    let inner_gap = if phase == 0 { 4.0 } else { 16.0 }
    let inner_padding = if phase == 0 { 0.0 } else { 8.0 }
    assert_eq(heading.left() - outer.left(), outer_padding)
    assert_eq(heading.top() - outer.top(), outer_padding)
    assert_eq(count.top() - heading.bottom(), outer_gap)
    assert_eq(row.top() - count.bottom(), outer_gap)
    assert_eq(card.top() - row.bottom(), outer_gap)
    assert_eq(outer.bottom() - card.bottom(), outer_padding)
    // The row is the widest direct child; other children remain intrinsic.
    assert_eq(outer.right() - row.right(), outer_padding)
    assert_eq(button.left() - row.left(), inner_padding)
    assert_eq(button.top() - row.top(), inner_padding)
    assert_eq(toggle.left() - button.right(), inner_gap)
    assert_eq(row.right() - toggle.right(), inner_padding)
    assert_eq(row.bottom() - button.bottom(), inner_padding)
    assert_eq(label.left() - card.left(), 17.0)
    assert_eq(label.top() - card.top(), 17.0)
    assert_eq(card.right() - label.right(), 17.0)
    assert_eq(card.bottom() - label.bottom(), 17.0)
    if phase == 0 {
      ignore(app.handle_event(event(1L, down(toggle))))
      ignore(app.handle_event(event(2L, up(toggle))))
      assert_true(drain(app))
    }
  }
  app.dispose()
}

///|
test "Card and spacing consumer modes cannot silently override one another" {
  assert_true(
    @shared_counter.NativeCounter::new(
      @platform.WindowId::new(1L),
      card=true,
      spacing=true,
    )
    is Err(_),
  )
}
