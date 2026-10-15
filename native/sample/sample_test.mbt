///|
fn sample_test_rect(
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> @primitives.Rect {
  match @primitives.Rect::new(x, y, width, height) {
    Ok(value) => value
    Err(_) => abort("valid sample-test rectangle rejected")
  }
}

///|
fn sample_test_point(x : Double, y : Double) -> @primitives.Point {
  match @primitives.Point::new(x, y) {
    Ok(value) => value
    Err(_) => abort("valid sample-test point rejected")
  }
}

///|
fn sample_test_measure(
  value : String,
  size : Double,
) -> Result[@text_layout.TextMeasurement, @diagnostics.FrameworkError] {
  match @text.TextDocument::new(value) {
    Err(_) =>
      Err(
        @diagnostics.FrameworkError::new(
          @diagnostics.InvalidInput,
          "sample_test_measure",
          message="invalid test document",
        ),
      )
    Ok(document) => {
      let width = value.length().to_double() * size * 0.6
      let logical = sample_test_rect(0.0, 0.0, width, size * 1.25)
      let ink = sample_test_rect(-1.0, -2.0, width + 1.0, size * 1.25 + 2.0)
      let carets : Array[@text_layout.CaretGeometry] = []
      let mut offset = 0
      let mut x = 0.0
      match
        @text_layout.CaretGeometry::new(
          offset,
          true,
          sample_test_rect(x, 0.0, 1.0, size),
          sample_test_rect(x, 0.0, 1.0, size),
        ) {
        Ok(value) => carets.push(value)
        Err(_) => abort("valid initial sample-test caret rejected")
      }
      for scalar in value.iter() {
        offset += if scalar.to_int() > 0xFFFF { 2 } else { 1 }
        x += size * 0.6
        match
          @text_layout.CaretGeometry::new(
            offset,
            true,
            sample_test_rect(x, 0.0, 1.0, size),
            sample_test_rect(x, 0.0, 1.0, size),
          ) {
          Ok(value) => carets.push(value)
          Err(_) => abort("valid sample-test caret rejected")
        }
      }
      match
        @text_layout.TextMeasurement::new(
          document,
          logical,
          ink,
          size * 0.8,
          1,
          0,
          carets,
        ) {
        Ok(value) => Ok(value)
        Err(_) =>
          Err(
            @diagnostics.FrameworkError::new(
              @diagnostics.InvalidInput,
              "sample_test_measure",
              message="invalid test measurement",
            ),
          )
      }
    }
  }
}

///|
fn new_sample(disabled? : Bool = false) -> @sample.NativeSample raise {
  match @sample.NativeSample::new(theme=@components.Theme::light(), disabled~) {
    Ok(value) => value
    Err(_) => fail("sample app and state should initialize")
  }
}

///|
fn render_sample(sample : @sample.NativeSample) -> @sample.SampleFrame raise {
  match sample.render(800.0, 600.0, 1.0, sample_test_measure) {
    Ok(value) => value
    Err(_) => fail("sample should render with valid fake text measurements")
  }
}

///|
fn assert_sample_count(
  sample : @sample.NativeSample,
  expected : Int,
) -> Unit raise {
  let actual = match sample.count() {
    Err(_) => fail("sample entity state should remain readable")
    Ok(value) => value
  }
  assert_eq(actual, expected)
}

///|
fn button_center(frame : @sample.SampleFrame) -> @primitives.Point {
  let bounds = frame.button_bounds()
  sample_test_point(
    bounds.left() + bounds.size().width() / 2.0,
    bounds.top() + bounds.size().height() / 2.0,
  )
}

///|
fn pointer_event(
  pressed : Bool,
  point : @primitives.Point,
) -> @primitives.InputEvent {
  if pressed {
    @primitives.PointerButtonPressed(
      position=point,
      button=@primitives.Primary,
      modifiers=@primitives.Modifiers::none(),
    )
  } else {
    @primitives.PointerButtonReleased(
      position=point,
      button=@primitives.Primary,
      modifiers=@primitives.Modifiers::none(),
    )
  }
}

///|
test "shared sample uses Flex layout and App Entity state to rerender Text after a matching click" {
  let sample = new_sample()
  let initial = render_sample(sample)
  let point = button_center(initial)
  assert_eq(initial.counter_text(), "Clicks: 0")
  assert_eq(initial.button_bounds().size().height(), 36.0)
  assert_eq(initial.counter_bounds().size().width(), 240.0)
  match sample.handle_input(pointer_event(true, point)) {
    Err(_) => fail("pointer down should route through the element tree")
    Ok(false) => ()
    Ok(true) => fail("pointer down must not activate the Button")
  }
  match sample.handle_input(pointer_event(false, point)) {
    Err(_) => fail("matching pointer up should dispatch")
    Ok(true) => ()
    Ok(false) => fail("matching primary down/up should activate once")
  }
  assert_sample_count(sample, 1)
  let after = render_sample(sample)
  assert_eq(after.counter_text(), "Clicks: 1")
  assert_true(initial.canonical_scene() != after.canonical_scene())
  assert_true(after.canonical_scene().contains("Clicks: 1"))
}

///|
test "accessibility activation uses the live Button snapshot and the same App Entity counter" {
  let sample = new_sample()
  let frame = render_sample(sample)
  let initial = match sample.button_accessibility_snapshot() {
    Err(_) =>
      fail("live sample Button should expose its accessibility snapshot")
    Ok(None) => fail("rendered sample Button should be accessible")
    Ok(Some(value)) => value
  }
  assert_eq(initial.id(), @sample.SAMPLE_BUTTON_ID)
  assert_eq(initial.name(), "Click me")
  assert_true(initial.enabled())
  assert_true(!initial.loading())
  assert_true(!initial.focused())
  assert_eq(initial.activations(), 0)
  assert_true(initial.bounds() == frame.button_bounds())

  assert_true(sample.activate_accessibility_button(initial) is Ok(true))
  assert_sample_count(sample, 1)
  assert_true(sample.activate_accessibility_button(initial) is Ok(false))

  let updated = match sample.button_accessibility_snapshot() {
    Err(_) => fail("updated App Entity count should remain accessible")
    Ok(None) => fail("updated sample Button should remain accessible")
    Ok(Some(value)) => value
  }
  assert_eq(updated.activations(), 1)
  assert_true(initial.same_revision(updated))
  assert_true(sample.activate_accessibility_button(updated) is Ok(true))
  assert_sample_count(sample, 2)
}

///|
test "accessibility activation rejects disabled, unfocused-stale, and invalidated snapshots" {
  let disabled = new_sample(disabled=true)
  let _ = render_sample(disabled)
  let disabled_snapshot = match disabled.button_accessibility_snapshot() {
    Err(_) => fail("disabled sample Button should expose its state")
    Ok(None) => fail("disabled rendered Button should be accessible")
    Ok(Some(value)) => value
  }
  assert_true(!disabled_snapshot.enabled())
  assert_true(
    disabled.activate_accessibility_button(disabled_snapshot) is Ok(false),
  )
  assert_sample_count(disabled, 0)

  let sample = new_sample()
  let frame = render_sample(sample)
  let stale = match sample.button_accessibility_snapshot() {
    Err(_) => fail("rendered sample Button should expose its state")
    Ok(None) => fail("rendered sample Button should be accessible")
    Ok(Some(value)) => value
  }
  assert_true(
    sample.handle_input(pointer_event(true, button_center(frame))) is Ok(false),
  )
  let focused = match sample.button_accessibility_snapshot() {
    Err(_) => fail("focused sample Button should expose its state")
    Ok(None) => fail("focused sample Button should remain accessible")
    Ok(Some(value)) => value
  }
  assert_true(focused.focused())
  assert_true(sample.activate_accessibility_button(stale) is Ok(false))
  assert_sample_count(sample, 0)

  sample.invalidate_layout()
  assert_true(sample.button_accessibility_snapshot() is Ok(None))
  assert_true(sample.activate_accessibility_button(focused) is Ok(false))
  assert_sample_count(sample, 0)
}

///|
test "accessibility snapshots are scoped to their sample and exact layout generation" {
  let first = new_sample()
  let first_frame = render_sample(first)
  let first_snapshot = match first.button_accessibility_snapshot() {
    Err(_) => fail("first sample Button should expose its snapshot")
    Ok(None) => fail("rendered first sample Button should be accessible")
    Ok(Some(value)) => value
  }

  let second = new_sample()
  let second_frame = render_sample(second)
  let second_snapshot = match second.button_accessibility_snapshot() {
    Err(_) => fail("second sample Button should expose its snapshot")
    Ok(None) => fail("rendered second sample Button should be accessible")
    Ok(Some(value)) => value
  }
  assert_true(first_frame.button_bounds() == second_frame.button_bounds())
  assert_true(!first_snapshot.same_revision(second_snapshot))
  assert_true(second.activate_accessibility_button(first_snapshot) is Ok(false))
  assert_sample_count(first, 0)
  assert_sample_count(second, 0)

  first.invalidate_layout()
  assert_true(first.button_accessibility_snapshot() is Ok(None))
  let rerendered_frame = render_sample(first)
  let rerendered_snapshot = match first.button_accessibility_snapshot() {
    Err(_) => fail("rerendered sample Button should expose its snapshot")
    Ok(None) => fail("rerendered sample Button should be accessible")
    Ok(Some(value)) => value
  }
  assert_true(first_frame.button_bounds() == rerendered_frame.button_bounds())
  assert_true(!first_snapshot.same_revision(rerendered_snapshot))
  assert_true(first.activate_accessibility_button(first_snapshot) is Ok(false))
  assert_true(
    first.activate_accessibility_button(rerendered_snapshot) is Ok(true),
  )
  assert_sample_count(first, 1)
}

///|
test "a failed render cannot revive an old accessibility snapshot" {
  let sample = new_sample()
  let first_frame = render_sample(sample)
  let stale = match sample.button_accessibility_snapshot() {
    Err(_) => fail("rendered sample Button should expose its snapshot")
    Ok(None) => fail("rendered sample Button should be accessible")
    Ok(Some(value)) => value
  }

  assert_true(sample.render(0.0, 600.0, 1.0, sample_test_measure) is Err(_))
  assert_true(sample.button_accessibility_snapshot() is Ok(None))
  assert_true(sample.activate_accessibility_button(stale) is Ok(false))

  let rerendered_frame = render_sample(sample)
  let current = match sample.button_accessibility_snapshot() {
    Err(_) => fail("rerendered sample Button should expose its snapshot")
    Ok(None) => fail("rerendered sample Button should be accessible")
    Ok(Some(value)) => value
  }
  assert_true(first_frame.button_bounds() == rerendered_frame.button_bounds())
  assert_true(!stale.same_revision(current))
  assert_true(sample.activate_accessibility_button(stale) is Ok(false))
  assert_sample_count(sample, 0)
}

///|
test "shared sample allocates disjoint stable scene item IDs" {
  let sample = new_sample()
  let frame = render_sample(sample)
  let seen : Array[UInt64] = []
  for item in frame.snapshot().items() {
    for prior in seen {
      assert_true(prior != item.id())
    }
    seen.push(item.id())
  }
  assert_true(seen.contains(10))
  assert_true(seen.contains(20))
  assert_true(seen.contains(30))
  assert_true(seen.contains(40))
}

///|
test "unmatched, outside and repeated releases never activate a Button" {
  let sample = new_sample()
  let frame = render_sample(sample)
  let inside = button_center(frame)
  let outside = sample_test_point(20.0, 20.0)
  assert_true(sample.handle_input(pointer_event(false, inside)) is Ok(false))
  assert_true(sample.handle_input(pointer_event(true, inside)) is Ok(false))
  assert_true(sample.handle_input(pointer_event(false, outside)) is Ok(false))
  assert_true(sample.handle_input(pointer_event(false, inside)) is Ok(false))
  assert_sample_count(sample, 0)
}

///|
test "disabled Button cannot receive focus or activate from a host click" {
  let sample = new_sample(disabled=true)
  let frame = render_sample(sample)
  let point = button_center(frame)
  assert_true(sample.handle_input(pointer_event(true, point)) is Ok(false))
  assert_true(sample.handle_input(pointer_event(false, point)) is Ok(false))
  assert_sample_count(sample, 0)
}

///|
test "focus loss cancels an armed pointer gesture" {
  let sample = new_sample()
  let frame = render_sample(sample)
  let point = button_center(frame)
  assert_true(sample.handle_input(pointer_event(true, point)) is Ok(false))
  sample.focus_changed(false)
  assert_true(sample.handle_input(pointer_event(false, point)) is Ok(false))
  assert_sample_count(sample, 0)
}

///|
test "same-layout repaint preserves a held pointer and focus until matching release" {
  let sample = new_sample()
  let initial = render_sample(sample)
  let point = button_center(initial)
  assert_true(!initial.button_pressed())
  assert_true(sample.handle_input(pointer_event(true, point)) is Ok(false))

  let pressed = render_sample(sample)
  assert_true(pressed.button_bounds() == initial.button_bounds())
  assert_true(pressed.button_pressed())
  let focused = match sample.button_accessibility_snapshot() {
    Err(_) => fail("repainted Button should expose its focus state")
    Ok(None) => fail("repainted Button should remain accessible")
    Ok(Some(value)) => value
  }
  assert_true(focused.focused())
  assert_eq(focused.activations(), 0)

  assert_true(
    sample.handle_input(pointer_event(false, button_center(pressed)))
    is Ok(true),
  )
  assert_sample_count(sample, 1)
  let released = render_sample(sample)
  assert_true(!released.button_pressed())
}

///|
test "Enter activates on every down and remains unpressed through repaint and release" {
  let sample = new_sample()
  let initial = render_sample(sample)
  let point = button_center(initial)
  assert_true(sample.handle_input(pointer_event(true, point)) is Ok(false))
  assert_true(sample.handle_input(pointer_event(false, point)) is Ok(true))
  let focused = render_sample(sample)
  assert_true(!focused.button_pressed())

  assert_true(
    sample.handle_input(
      @primitives.KeyPressed(
        key=@primitives.Enter,
        modifiers=@primitives.Modifiers::none(),
        repeat=false,
      ),
    )
    is Ok(true),
  )
  assert_sample_count(sample, 2)
  let after_first_down = render_sample(sample)
  assert_true(after_first_down.button_bounds() == focused.button_bounds())
  assert_true(!after_first_down.button_pressed())
  let focused_snapshot = match sample.button_accessibility_snapshot() {
    Err(_) => fail("repainted Button should expose its focus state")
    Ok(None) => fail("repainted Button should remain accessible")
    Ok(Some(value)) => value
  }
  assert_true(focused_snapshot.focused())
  assert_eq(focused_snapshot.activations(), 2)

  assert_true(
    sample.handle_input(
      @primitives.KeyPressed(
        key=@primitives.Enter,
        modifiers=@primitives.Modifiers::none(),
        repeat=true,
      ),
    )
    is Ok(true),
  )
  assert_sample_count(sample, 3)
  assert_true(
    sample.handle_input(
      @primitives.KeyReleased(
        key=@primitives.Enter,
        modifiers=@primitives.Modifiers::none(),
      ),
    )
    is Ok(false),
  )
  assert_sample_count(sample, 3)
  let released = render_sample(sample)
  assert_true(released.button_bounds() == after_first_down.button_bounds())
  assert_true(!released.button_pressed())
}

///|
test "resize invalidates the old press before the view is rebuilt" {
  let sample = new_sample()
  let frame = render_sample(sample)
  let old_point = button_center(frame)
  assert_true(sample.handle_input(pointer_event(true, old_point)) is Ok(false))
  sample.invalidate_layout()
  match sample.render(800.0, 500.0, 1.0, sample_test_measure) {
    Err(_) => fail("sample should relayout after resize")
    Ok(_) => ()
  }
  assert_true(sample.handle_input(pointer_event(false, old_point)) is Ok(false))
  assert_sample_count(sample, 0)
}

///|
test "Enter activates on down and Space activates once on matching release" {
  let sample = new_sample()
  let frame = render_sample(sample)
  let point = button_center(frame)
  assert_true(sample.handle_input(pointer_event(true, point)) is Ok(false))
  assert_true(sample.handle_input(pointer_event(false, point)) is Ok(true))
  let _after_click = render_sample(sample)
  assert_true(
    sample.handle_input(
      @primitives.KeyPressed(
        key=@primitives.Enter,
        modifiers=@primitives.Modifiers::none(),
        repeat=false,
      ),
    )
    is Ok(true),
  )
  assert_sample_count(sample, 2)
  let after_enter_down = render_sample(sample)
  assert_true(!after_enter_down.button_pressed())
  assert_true(
    sample.handle_input(
      @primitives.KeyReleased(
        key=@primitives.Enter,
        modifiers=@primitives.Modifiers::none(),
      ),
    )
    is Ok(false),
  )
  assert_sample_count(sample, 2)

  assert_true(
    sample.handle_input(
      @primitives.KeyPressed(
        key=@primitives.Space,
        modifiers=@primitives.Modifiers::none(),
        repeat=false,
      ),
    )
    is Ok(false),
  )
  assert_sample_count(sample, 2)
  let held_space = render_sample(sample)
  assert_true(held_space.button_bounds() == after_enter_down.button_bounds())
  assert_true(held_space.button_pressed())
  let held_snapshot = match sample.button_accessibility_snapshot() {
    Err(_) => fail("held Space Button should expose its focus state")
    Ok(None) => fail("held Space Button should remain accessible")
    Ok(Some(value)) => value
  }
  assert_true(held_snapshot.focused())
  assert_eq(held_snapshot.activations(), 2)
  assert_true(
    sample.handle_input(
      @primitives.KeyPressed(
        key=@primitives.Space,
        modifiers=@primitives.Modifiers::none(),
        repeat=true,
      ),
    )
    is Ok(false),
  )
  assert_sample_count(sample, 2)
  let repeated_space = render_sample(sample)
  assert_true(repeated_space.button_bounds() == held_space.button_bounds())
  assert_true(repeated_space.button_pressed())
  let repeated_snapshot = match sample.button_accessibility_snapshot() {
    Err(_) => fail("repeated Space Button should expose its focus state")
    Ok(None) => fail("repeated Space Button should remain accessible")
    Ok(Some(value)) => value
  }
  assert_true(repeated_snapshot.focused())
  assert_eq(repeated_snapshot.activations(), 2)
  assert_true(
    sample.handle_input(
      @primitives.KeyReleased(
        key=@primitives.Space,
        modifiers=@primitives.Modifiers::none(),
      ),
    )
    is Ok(true),
  )
  assert_sample_count(sample, 3)
  assert_true(
    sample.handle_input(
      @primitives.KeyReleased(
        key=@primitives.Space,
        modifiers=@primitives.Modifiers::none(),
      ),
    )
    is Ok(false),
  )
  let released_space = render_sample(sample)
  assert_true(!released_space.button_pressed())
}

///|
test "focus loss cancels a held Space before its release" {
  let sample = new_sample()
  let frame = render_sample(sample)
  let point = button_center(frame)
  assert_true(sample.handle_input(pointer_event(true, point)) is Ok(false))
  assert_true(sample.handle_input(pointer_event(false, point)) is Ok(true))
  let _focused = render_sample(sample)
  assert_true(
    sample.handle_input(
      @primitives.KeyPressed(
        key=@primitives.Space,
        modifiers=@primitives.Modifiers::none(),
        repeat=false,
      ),
    )
    is Ok(false),
  )
  sample.focus_changed(false)
  assert_true(
    sample.handle_input(
      @primitives.KeyReleased(
        key=@primitives.Space,
        modifiers=@primitives.Modifiers::none(),
      ),
    )
    is Ok(false),
  )
  assert_sample_count(sample, 1)
  let canceled = render_sample(sample)
  assert_true(!canceled.button_pressed())
  let unfocused = match sample.button_accessibility_snapshot() {
    Err(_) => fail("blurred Button should expose its state")
    Ok(None) => fail("blurred Button should remain accessible")
    Ok(Some(value)) => value
  }
  assert_true(!unfocused.focused())
}

///|
test "Enter down cancels an earlier held Space without a stale release action" {
  let sample = new_sample()
  let frame = render_sample(sample)
  let point = button_center(frame)
  assert_true(sample.handle_input(pointer_event(true, point)) is Ok(false))
  assert_true(sample.handle_input(pointer_event(false, point)) is Ok(true))
  let _focused = render_sample(sample)
  assert_true(
    sample.handle_input(
      @primitives.KeyPressed(
        key=@primitives.Space,
        modifiers=@primitives.Modifiers::none(),
        repeat=false,
      ),
    )
    is Ok(false),
  )
  let held_space = render_sample(sample)
  assert_true(held_space.button_pressed())
  assert_true(
    sample.handle_input(
      @primitives.KeyPressed(
        key=@primitives.Enter,
        modifiers=@primitives.Modifiers::none(),
        repeat=false,
      ),
    )
    is Ok(true),
  )
  assert_sample_count(sample, 2)
  let after_enter = render_sample(sample)
  assert_true(!after_enter.button_pressed())
  assert_true(
    sample.handle_input(
      @primitives.KeyReleased(
        key=@primitives.Space,
        modifiers=@primitives.Modifiers::none(),
      ),
    )
    is Ok(false),
  )
  assert_true(
    sample.handle_input(
      @primitives.KeyReleased(
        key=@primitives.Enter,
        modifiers=@primitives.Modifiers::none(),
      ),
    )
    is Ok(false),
  )
  assert_sample_count(sample, 2)
  assert_true(!render_sample(sample).button_pressed())
}

///|
test "unfocused and disabled Enter events do not activate" {
  let unfocused = new_sample()
  let _frame = render_sample(unfocused)
  assert_true(
    unfocused.handle_input(
      @primitives.KeyPressed(
        key=@primitives.Enter,
        modifiers=@primitives.Modifiers::none(),
        repeat=false,
      ),
    )
    is Ok(false),
  )
  assert_sample_count(unfocused, 0)

  let disabled = new_sample(disabled=true)
  let _disabled_frame = render_sample(disabled)
  assert_true(
    disabled.handle_input(
      @primitives.KeyPressed(
        key=@primitives.Enter,
        modifiers=@primitives.Modifiers::none(),
        repeat=false,
      ),
    )
    is Ok(false),
  )
  assert_true(
    disabled.handle_input(
      @primitives.KeyReleased(
        key=@primitives.Enter,
        modifiers=@primitives.Modifiers::none(),
      ),
    )
    is Ok(false),
  )
  assert_sample_count(disabled, 0)
}
