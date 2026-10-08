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
test "keyboard activation requires a matching key press and release" {
  let sample = new_sample()
  let frame = render_sample(sample)
  let point = button_center(frame)
  assert_true(sample.handle_input(pointer_event(true, point)) is Ok(false))
  assert_true(sample.handle_input(pointer_event(false, point)) is Ok(true))
  let _after_click = render_sample(sample)
  match
    sample.handle_input(
      @primitives.KeyPressed(
        key=@primitives.Enter,
        modifiers=@primitives.Modifiers::none(),
        repeat=false,
      ),
    ) {
    Ok(false) => ()
    _ => fail("Enter down should arm the focused Button without activation")
  }
  assert_true(
    sample.handle_input(
      @primitives.KeyReleased(
        key=@primitives.Enter,
        modifiers=@primitives.Modifiers::none(),
      ),
    )
    is Ok(true),
  )
  assert_sample_count(sample, 2)
  let _after_enter = render_sample(sample)
  match
    sample.handle_input(
      @primitives.KeyPressed(
        key=@primitives.Space,
        modifiers=@primitives.Modifiers::none(),
        repeat=false,
      ),
    ) {
    Ok(false) => ()
    _ => fail("Space down should remain routed after a state-driven rerender")
  }
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
}
