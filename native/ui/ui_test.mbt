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
fn key() -> @view.NodeKey {
  @view.NodeKey::new("button")
}

///|
fn button_view(
  disabled~ : Bool = false,
  loading~ : Bool = false,
  label~ : String = "Increment",
) -> @view.View {
  @view.column(@view.NodeKey::new("root"), [
    @view.text(@view.NodeKey::new("value"), "Count: 0"),
    @view.button(key(), label, disabled~, loading~),
  ])
}

///|
fn mount() -> @ui.Mounted {
  @ui.Mounted::new(@platform.WindowId::new(1L))
}

///|
fn render(mount : @ui.Mounted, view~ : @view.View = button_view()) -> @ui.Frame {
  mount.commit(view, 640.0, 480.0, 1.0, measure).unwrap()
}

///|
test "adapter uses real flex for nested rows columns and distinct literal text" {
  let mounted = mount()
  let view = @view.column(@view.NodeKey::new("root"), [
    @view.row(@view.NodeKey::new("row"), [
      @view.text(@view.NodeKey::new("one"), "<one>"),
      @view.text(@view.NodeKey::new("two"), "&two"),
    ]),
    @view.button(key(), "Increment"),
  ])
  let frame = render(mounted, view~)
  let one = frame.bounds(@view.NodeKey::new("one")).unwrap()
  let two = frame.bounds(@view.NodeKey::new("two")).unwrap()
  let button = frame.bounds(key()).unwrap()
  assert_true(two.left() >= one.right() + 11.0)
  assert_eq(one.top(), two.top())
  assert_true(button.top() >= one.bottom() + 11.0)
  assert_true(button.size().width() >= 24.0 && button.size().height() >= 24.0)
  assert_eq(frame.snapshot().items().length(), 6)
  assert_true(
    frame.label_bounds(key()).unwrap().size().width() < button.size().width(),
  )
  mounted.dispose()
}

///|
test "same-layout repaint retains existing Button press; outside release cancels" {
  let mounted = mount()
  let initial = render(mounted)
  let bounds = initial.bounds(key()).unwrap()
  assert_true(mounted.handle_event(event(1L, down(bounds))).unwrap())
  let held = render(mounted)
  assert_true(held.pressed(key()))
  assert_true(held.focused(key()))
  assert_true(mounted.handle_event(event(2L, up(bounds))).unwrap())
  assert_true(mounted.next_action() is Some(@view.Activate(_)))
  assert_true(mounted.next_action() is None)
  ignore(mounted.handle_event(event(3L, down(bounds))))
  let outside = @primitives.Rect::new(600.0, 400.0, 30.0, 30.0).unwrap()
  assert_true(mounted.handle_event(event(4L, up(outside))).unwrap())
  assert_true(!render(mounted).pressed(key()))
  assert_true(mounted.next_action() is None)
}

///|
test "foreign roots removed retyped reinserted keys and disposed callbacks stay inert" {
  let first = mount()
  let second = mount()
  ignore(render(first))
  ignore(render(second))
  let old = first.callback(key()).unwrap()
  assert_true(!second.activate(old))
  assert_true(first.activate(old))
  ignore(render(first, view=@view.text(key(), "retyped")))
  assert_true(first.next_action() is None)
  assert_true(!first.activate(old))
  ignore(render(first))
  assert_true(!first.activate(old))
  let current = first.callback(key()).unwrap()
  ignore(render(first, view=@view.column(@view.NodeKey::new("root"), [])))
  ignore(render(first))
  assert_true(!first.activate(current))
  let last = first.callback(key()).unwrap()
  first.dispose()
  first.dispose()
  assert_true(!first.activate(last))
  assert_true(first.next_action() is None)
  assert_true(first.frame() is None)
  assert_true(first.commit(button_view(), 640.0, 480.0, 1.0, measure) is Err(_))
}

///|
test "failed staging cannot publish new tokens with old accepted geometry" {
  let mounted = mount()
  let old = render(mounted)
  let callback = mounted.callback(key()).unwrap()
  ignore(mounted.handle_event(event(1L, down(old.bounds(key()).unwrap()))))
  let replacement = @view.button(@view.NodeKey::new("new"), "new")
  assert_true(
    mounted.commit(replacement, 640.0, 480.0, 1.0, failed_measure) is Err(_),
  )
  assert_true(mounted.callback(@view.NodeKey::new("new")) is None)
  assert_eq(mounted.view(), Some(button_view()))
  assert_eq(mounted.frame().unwrap().revision(), old.revision())
  assert_true(render(mounted).pressed(key()))
  assert_true(mounted.activate(callback))
  let duplicate = @view.column(key(), [@view.button(key(), "same key")])
  assert_true(mounted.commit(duplicate, 640.0, 480.0, 1.0, measure) is Err(_))
  assert_true(
    mounted.commit(button_view(), 640.0, 480.0, -1.0, measure) is Err(_),
  )
  assert_true(mounted.next_action() is Some(_))
  let staged = mounted.stage(replacement, 640.0, 480.0, 1.0, measure).unwrap()
  let other = mount()
  assert_true(other.publish(staged) is Err(_))
  assert_true(mounted.publish(staged) is Ok(_))
  assert_true(mounted.publish(staged) is Err(_))
  assert_true(!mounted.activate(callback))
}

///|
test "preparation is invalid after input focus resize or disposal and rejects reentrancy" {
  let mounted = mount()
  let frame = render(mounted)
  let staged = mounted.stage(button_view(), 640.0, 480.0, 1.0, measure).unwrap()
  ignore(mounted.handle_event(event(1L, down(frame.bounds(key()).unwrap()))))
  assert_true(mounted.publish(staged) is Err(_))
  let staged = mounted.stage(button_view(), 640.0, 480.0, 1.0, measure).unwrap()
  assert_true(mounted.focus(key()))
  assert_true(mounted.publish(staged) is Err(_))
  let staged = mounted.stage(button_view(), 640.0, 480.0, 1.0, measure).unwrap()
  mounted.invalidate_layout()
  assert_true(mounted.publish(staged) is Err(_))
  let rejected = Ref(false)
  ignore(
    mounted
    .commit(button_view(), 640.0, 480.0, 1.0, (text, size) => {
      rejected.val = mounted.commit(button_view(), 640.0, 480.0, 1.0, measure)
        is Err(_)
      measure(text, size)
    })
    .unwrap(),
  )
  assert_true(rejected.val)
  assert_true(
    mounted.commit(button_view(), 640.0, 480.0, 1.0, (text, size) => {
      mounted.dispose()
      measure(text, size)
    })
    is Err(_),
  )
  assert_true(mounted.frame() is None)
}

///|
test "sequence window focus resize scale and destruction reject stale input" {
  let mounted = mount()
  let bounds = render(mounted).bounds(key()).unwrap()
  ignore(mounted.handle_event(event(1L, down(bounds))))
  let foreign = @platform.Event::new(
    @platform.WindowId::new(2L),
    1000L,
    1.0,
    @platform.Input(up(bounds)),
  )
  assert_true(!mounted.handle_event(foreign).unwrap())
  assert_true(!mounted.handle_event(event(1L, up(bounds))).unwrap())
  assert_true(!mounted.handle_event(event(0L, up(bounds))).unwrap())
  assert_true(mounted.next_action() is None)
  ignore(mounted.handle_event(event(2L, up(bounds))))
  ignore(
    mounted.handle_event(
      @platform.Event::new(
        @platform.WindowId::new(1L),
        3L,
        1.0,
        @platform.Resized(width=800.0, height=480.0),
      ),
    ),
  )
  assert_true(mounted.next_action() is None)
  assert_true(mounted.frame() is None)
  assert_true(!mounted.handle_event(event(4L, down(bounds))).unwrap())
  ignore(render(mounted))
  ignore(mounted.handle_event(event(5L, down(bounds))))
  ignore(
    mounted.handle_event(
      @platform.Event::new(
        @platform.WindowId::new(1L),
        6L,
        2.0,
        @platform.Input(up(bounds)),
      ),
    ),
  )
  assert_true(mounted.frame() is None)
  ignore(render(mounted))
  ignore(mounted.handle_event(event(7L, down(bounds))))
  ignore(
    mounted.handle_event(
      @platform.Event::new(
        @platform.WindowId::new(1L),
        8L,
        1.0,
        @platform.FocusChanged(false),
      ),
    ),
  )
  assert_true(!mounted.handle_event(event(9L, up(bounds))).unwrap())
  assert_true(!render(mounted).pressed(key()))
  ignore(
    mounted.handle_event(
      @platform.Event::new(
        @platform.WindowId::new(1L),
        10L,
        1.0,
        @platform.FocusChanged(true),
      ),
    ),
  )
  ignore(mounted.handle_event(event(11L, up(bounds))))
  assert_true(mounted.next_action() is None)
  ignore(
    mounted.handle_event(
      @platform.Event::new(
        @platform.WindowId::new(1L),
        12L,
        1.0,
        @platform.Destroyed,
      ),
    ),
  )
  assert_true(mounted.is_disposed())
}

///|
test "label change cancels press and pending callback; loading retains enabled focus" {
  let mounted = mount()
  let bounds = render(mounted).bounds(key()).unwrap()
  assert_true(mounted.focus(key()))
  assert_true(mounted.next_focus_result() is Some(_))
  ignore(mounted.handle_event(event(1L, key_down(@primitives.Space))))
  assert_true(render(mounted).pressed(key()))
  let old = mounted.callback(key()).unwrap()
  let renamed = render(mounted, view=button_view(label="Renamed"))
  assert_true(!renamed.pressed(key()))
  assert_true(!mounted.activate(old))
  ignore(mounted.handle_event(event(2L, key_up(@primitives.Space))))
  assert_true(mounted.next_action() is None)
  let loading = render(mounted, view=button_view(loading=true))
  assert_true(loading.focused(key()))
  assert_true(!loading.pressed(key()))
  ignore(mounted.handle_event(event(3L, key_down(@primitives.Enter))))
  assert_true(mounted.next_action() is None)
  ignore(render(mounted))
  ignore(mounted.handle_event(event(4L, up(bounds))))
  assert_true(mounted.next_action() is None)
  let disabled = render(mounted, view=button_view(disabled=true))
  assert_true(!disabled.focused(key()))
}

///|
test "native Button policy remains first nonrepeat Enter first held key and pointer plus Space" {
  let mounted = mount()
  let bounds = render(mounted).bounds(key()).unwrap()
  assert_true(mounted.focus(key()))
  ignore(
    mounted.handle_event(event(1L, key_down(@primitives.Enter, repeat=true))),
  )
  assert_true(mounted.next_action() is None)
  ignore(mounted.handle_event(event(2L, key_down(@primitives.Enter))))
  ignore(
    mounted.handle_event(event(3L, key_down(@primitives.Enter, repeat=true))),
  )
  assert_true(mounted.next_action() is Some(_))
  assert_true(mounted.next_action() is None)
  ignore(mounted.handle_event(event(4L, key_up(@primitives.Enter))))
  ignore(mounted.handle_event(event(5L, key_down(@primitives.Space))))
  ignore(mounted.handle_event(event(6L, key_down(@primitives.Enter))))
  ignore(mounted.handle_event(event(7L, key_up(@primitives.Enter))))
  assert_true(mounted.next_action() is None)
  assert_true(render(mounted).pressed(key()))
  ignore(mounted.handle_event(event(8L, key_up(@primitives.Space))))
  assert_true(mounted.next_action() is Some(_))
  ignore(mounted.handle_event(event(9L, down(bounds))))
  ignore(mounted.handle_event(event(10L, key_down(@primitives.Space))))
  ignore(mounted.handle_event(event(11L, key_up(@primitives.Space))))
  assert_true(mounted.next_action() is Some(_))
  assert_true(render(mounted).pressed(key()))
  ignore(mounted.handle_event(event(12L, up(bounds))))
  assert_true(mounted.next_action() is Some(_))
  assert_true(mounted.next_action() is None)
}

///|
test "changed accepted bounds cancel press and pending activation without reviving callbacks" {
  let mounted = mount()
  let initial = render(mounted)
  let bounds = initial.bounds(key()).unwrap()
  ignore(mounted.handle_event(event(1L, down(bounds))))
  ignore(mounted.handle_event(event(2L, key_down(@primitives.Enter))))
  let callback = mounted.callback(key()).unwrap()
  let moved = @view.column(@view.NodeKey::new("root"), [
    @view.text(@view.NodeKey::new("above"), "extra"),
    button_view(),
  ])
  // The duplicate root is rejected before accepting any changed geometry.
  assert_true(mounted.commit(moved, 640.0, 480.0, 1.0, measure) is Err(_))
  let moved = @view.column(@view.NodeKey::new("outer"), [
    @view.text(@view.NodeKey::new("above"), "extra"),
    button_view(),
  ])
  let frame = render(mounted, view=moved)
  assert_true(frame.bounds(key()).unwrap() != bounds)
  assert_true(!frame.pressed(key()))
  assert_true(mounted.next_action() is None)
  assert_true(!mounted.activate(callback))
  ignore(mounted.handle_event(event(3L, up(frame.bounds(key()).unwrap()))))
  assert_true(mounted.next_action() is None)
}

///|
test "enabled loading enabled gate transitions revoke queued activations and callbacks" {
  let mounted = mount()
  ignore(render(mounted))
  assert_true(mounted.focus(key()))
  let callback = mounted.callback(key()).unwrap()
  assert_true(mounted.activate(callback))
  ignore(render(mounted, view=button_view(loading=true)))
  ignore(render(mounted))
  assert_true(mounted.next_action() is None)
  assert_true(!mounted.activate(callback))
  assert_true(render(mounted).focused(key()))
  let callback = mounted.callback(key()).unwrap()
  assert_true(mounted.activate(callback))
  ignore(render(mounted, view=button_view(disabled=true)))
  ignore(render(mounted))
  assert_true(mounted.next_action() is None)
  assert_true(!mounted.activate(callback))
  assert_true(!render(mounted).focused(key()))
}

///|
test "scene text rejection is atomic even after measurement and layout succeed" {
  let mounted = mount()
  let initial = render(mounted)
  let callback = mounted.callback(key()).unwrap()
  let label = String::make(65537, 'a')
  let replacement = @view.text(@view.NodeKey::new("long"), label)
  // The scene text limit is independently validated after a valid short
  // measurement. This injected provider isolates scene rejection from layout.
  assert_true(
    mounted.commit(replacement, 640.0, 480.0, 1.0, (_text, size) => {
      measure("short", size)
    })
    is Err(_),
  )
  assert_eq(mounted.view(), Some(button_view()))
  assert_eq(mounted.frame().unwrap().revision(), initial.revision())
  assert_true(mounted.callback(@view.NodeKey::new("long")) is None)
  assert_true(mounted.activate(callback))
}

///|
test "independent root disposal leaves another root live through repeated cycles" {
  let survivor = mount()
  ignore(render(survivor))
  let callback = survivor.callback(key()).unwrap()
  for _ in 0..<100 {
    let mounted = mount()
    ignore(render(mounted))
    let removed = mounted.callback(key()).unwrap()
    mounted.dispose()
    assert_true(!survivor.activate(removed))
    assert_true(survivor.activate(callback))
    assert_true(survivor.next_action() is Some(_))
  }
  assert_true(survivor.frame() is Some(_))
}

///|
test "identical native roots reject foreign copied preparations and callbacks symmetrically" {
  // Both owners intentionally have the same window ID, keys, labels, native ID
  // allocation sequence and frame revision. None of these confer authority.
  let first = mount()
  let second = mount()
  let first_frame = render(first)
  let second_frame = render(second)
  assert_eq(first.view(), second.view())
  assert_eq(first_frame.revision(), second_frame.revision())
  assert_true(first_frame.bounds(key()) == second_frame.bounds(key()))
  let first_callback = first.callback(key()).unwrap()
  let copied_callback = first_callback
  let second_callback = second.callback(key()).unwrap()
  for _ in 0..<3 {
    assert_true(!second.activate(copied_callback))
    assert_true(!first.activate(second_callback))
    assert_true(first.next_action() is None)
    assert_true(second.next_action() is None)
  }
  assert_true(first.activate(copied_callback))
  assert_true(second.activate(second_callback))
  assert_eq(first.next_action(), Some(@view.Activate(key())))
  assert_eq(second.next_action(), Some(@view.Activate(key())))
  let first_prepared = first
    .stage(button_view(), 640.0, 480.0, 1.0, measure)
    .unwrap()
  let copied_prepared = first_prepared
  let second_prepared = second
    .stage(button_view(), 640.0, 480.0, 1.0, measure)
    .unwrap()
  for _ in 0..<3 {
    assert_true(second.publish(copied_prepared) is Err(_))
    assert_true(first.publish(second_prepared) is Err(_))
    assert_eq(first.frame().unwrap().revision(), first_frame.revision())
    assert_eq(second.frame().unwrap().revision(), second_frame.revision())
  }
  let accepted = first.publish(copied_prepared).unwrap()
  assert_eq(accepted.revision(), first_frame.revision() + 1UL)
  assert_true(first.publish(first_prepared) is Err(_))
  assert_true(second.publish(first_prepared) is Err(_))
  assert_eq(first.frame().unwrap().revision(), accepted.revision())
  assert_true(second.publish(second_prepared) is Ok(_))
  assert_true(second.publish(second_prepared) is Err(_))
  // A successful unchanged repaint preserves callbacks, but retiring geometry
  // and restoring identical content must never revive their old epoch.
  assert_true(first.activate(first_callback))
  first.invalidate_layout()
  ignore(render(first))
  assert_true(first.next_action() is None)
  assert_true(!first.activate(copied_callback))
  let current = first.callback(key()).unwrap()
  assert_true(first.activate(current))
  assert_eq(first.next_action(), Some(@view.Activate(key())))
  first.dispose()
  assert_true(!first.activate(current))
  assert_true(!second.activate(current))
  assert_true(second.activate(second_callback))
  assert_eq(second.next_action(), Some(@view.Activate(key())))
}

///|
test "measurement invalidation changes preparation authority without disposing the owner" {
  let mounted = mount()
  ignore(render(mounted))
  let old = mounted.callback(key()).unwrap()
  assert_true(
    mounted.stage(button_view(), 640.0, 480.0, 1.0, (text, size) => {
      mounted.invalidate_layout()
      measure(text, size)
    })
    is Err(_),
  )
  assert_true(!mounted.is_disposed())
  assert_eq(mounted.view(), Some(button_view()))
  assert_true(mounted.frame() is None)
  assert_true(!mounted.activate(old))
  ignore(render(mounted))
  assert_true(!mounted.activate(old))
  assert_true(mounted.activate(mounted.callback(key()).unwrap()))
  assert_eq(mounted.next_action(), Some(@view.Activate(key())))
}

///|
// Matches button-interrupted-loading/disabled in contract-v1.json. These are
// portable adapter events, not actual native-window/keyboard qualification.
test "Button state fixtures cancel held Space pointer and Enter repeats across gate cycles" {
  for disabled in [false, true] {
    let mounted = mount()
    let bounds = render(mounted).bounds(key()).unwrap()
    let gated = button_view(disabled~, loading=!disabled)
    let counts = [0]
    assert_true(mounted.focus(key()))
    ignore(mounted.handle_event(event(1L, key_down(@primitives.Space))))
    assert_true(render(mounted).pressed(key()))
    let frame = render(mounted, view=gated)
    assert_true(!frame.pressed(key()))
    assert_eq(frame.focused(key()), !disabled)
    ignore(render(mounted))
    ignore(mounted.handle_event(event(2L, key_up(@primitives.Space))))
    assert_true(mounted.next_action() is None)
    counts.push(0)
    ignore(mounted.handle_event(event(3L, down(bounds))))
    assert_true(render(mounted).pressed(key()))
    ignore(render(mounted, view=gated))
    ignore(render(mounted))
    ignore(mounted.handle_event(event(4L, up(bounds))))
    assert_true(mounted.next_action() is None)
    counts.push(0)
    assert_true(mounted.focus(key()))
    ignore(mounted.handle_event(event(5L, key_down(@primitives.Enter))))
    assert_true(mounted.next_action() is Some(@view.Activate(_)))
    assert_true(mounted.next_action() is None)
    counts.push(1)
    ignore(render(mounted, view=gated))
    ignore(render(mounted))
    ignore(
      mounted.handle_event(event(6L, key_down(@primitives.Enter, repeat=true))),
    )
    ignore(mounted.handle_event(event(7L, key_up(@primitives.Enter))))
    assert_true(mounted.next_action() is None)
    counts.push(1)
    ignore(mounted.handle_event(event(8L, down(bounds))))
    ignore(mounted.handle_event(event(9L, up(bounds))))
    assert_true(mounted.next_action() is Some(@view.Activate(_)))
    assert_true(mounted.next_action() is None)
    counts.push(2)
    assert_eq(counts, [0, 0, 0, 1, 1, 2])
    mounted.dispose()
  }
}

///|
test "loading consumes focused activation keys without actions and disabled wins over loading" {
  let mounted = mount()
  ignore(render(mounted))
  assert_true(mounted.focus(key()))
  ignore(render(mounted, view=button_view(loading=true)))
  assert_true(!mounted.focus(key()))
  assert_true(render(mounted, view=button_view(loading=true)).focused(key()))
  assert_true(
    mounted.handle_event(event(1L, key_down(@primitives.Enter))).unwrap(),
  )
  assert_true(
    mounted.handle_event(event(2L, key_up(@primitives.Enter))).unwrap(),
  )
  assert_true(
    mounted.handle_event(event(3L, key_down(@primitives.Space))).unwrap(),
  )
  assert_true(
    mounted.handle_event(event(4L, key_up(@primitives.Space))).unwrap(),
  )
  assert_true(mounted.next_action() is None)
  let frame = render(mounted, view=button_view(disabled=true, loading=true))
  assert_true(!frame.focused(key()) && !frame.pressed(key()))
  assert_true(!mounted.focus(key()))
  assert_true(
    !mounted.handle_event(event(5L, key_down(@primitives.Enter))).unwrap(),
  )
  assert_true(!mounted.activate(mounted.callback(key()).unwrap()))
  assert_true(mounted.next_action() is None)
  ignore(render(mounted))
  assert_true(!render(mounted).focused(key()))
}

///|
fn quad_color(frame : @ui.Frame, index : Int32) -> @primitives.Color {
  match frame.snapshot().items()[index] {
    @scene.QuadItem(color~, ..) => color
    _ => abort("expected Button quad")
  }
}

///|
test "GPUI hover and retained-focus painting survive unchanged repaint with explicit profile differences" {
  let mounted = mount()
  let initial = render(mounted)
  let bounds = initial.bounds(key()).unwrap()
  let motion = @primitives.PointerMoved(
    position=@primitives.Point::new(bounds.left() + 4.0, bounds.top() + 4.0).unwrap(),
  )
  ignore(mounted.handle_event(event(1L, motion)))
  let hovered = render(mounted)
  assert_true(quad_color(initial, 3) != quad_color(hovered, 3))
  assert_true(quad_color(hovered, 3) == quad_color(render(mounted), 3))
  ignore(mounted.handle_event(event(2L, down(bounds))))
  ignore(mounted.handle_event(event(3L, up(bounds))))
  assert_true(mounted.next_action() is Some(_))
  let focused = render(mounted)
  assert_true(focused.focused(key()))
  // Existing GPUI paints a focus border even for pointer-obtained focus.
  assert_true(quad_color(focused, 2) != quad_color(initial, 2))
  let loading = render(mounted, view=button_view(loading=true))
  assert_true(loading.focused(key()))
  assert_true(quad_color(loading, 2) == quad_color(focused, 2))
  let enabled = render(mounted)
  assert_true(enabled.focused(key()))
  assert_true(quad_color(enabled, 3) == quad_color(initial, 3))
  ignore(mounted.handle_event(event(4L, motion)))
  assert_true(quad_color(render(mounted), 3) == quad_color(hovered, 3))
  let renamed = render(mounted, view=button_view(label="Renamed"))
  assert_true(renamed.focused(key()))
  assert_true(quad_color(renamed, 3) == quad_color(initial, 3))
  let disabled = render(mounted, view=button_view(disabled=true))
  assert_true(!disabled.focused(key()))
  ignore(mounted.handle_event(event(5L, motion)))
  assert_true(
    quad_color(render(mounted, view=button_view(disabled=true)), 3) ==
    quad_color(disabled, 3),
  )
  assert_true(mounted.next_action() is None)
}

///|
test "removed and retyped held buttons cannot activate a freshly focused replacement" {
  for
    replacement in [
      @view.text(key(), "Replacement text"),
      @view.column(@view.NodeKey::new("root"), []),
    ] {
    let mounted = mount()
    let bounds = render(mounted).bounds(key()).unwrap()
    assert_true(mounted.focus(key()))
    ignore(mounted.handle_event(event(1L, key_down(@primitives.Space))))
    ignore(render(mounted, view=replacement))
    ignore(render(mounted))
    assert_true(mounted.focus(key()))
    ignore(mounted.handle_event(event(2L, key_up(@primitives.Space))))
    assert_true(mounted.next_action() is None)
    ignore(mounted.handle_event(event(3L, down(bounds))))
    ignore(render(mounted, view=replacement))
    ignore(render(mounted))
    ignore(mounted.handle_event(event(4L, up(bounds))))
    assert_true(mounted.next_action() is None)
    ignore(mounted.handle_event(event(5L, down(bounds))))
    ignore(mounted.handle_event(event(6L, up(bounds))))
    assert_true(mounted.next_action() is Some(_))
    assert_true(mounted.next_action() is None)
    mounted.dispose()
  }
}

///|
test "Card insets gaps paint identity and noninteractive nesting" {
  let key = @view.NodeKey::new("card")
  let child = @view.NodeKey::new("child")
  let label = @view.NodeKey::new("label")
  let children = [@view.text(label, "<Card & text>"), @view.button(child, "Go")]
  let mount = @ui.Mounted::new(@platform.WindowId::new(1L))
  let frame = mount
    .commit(@view.card(key, children), 800.0, 600.0, 1.0, measure)
    .unwrap()
  let outer = frame.bounds(key).unwrap()
  let first = frame.bounds(label).unwrap()
  let last = frame.bounds(child).unwrap()
  assert_eq(first.left() - outer.left(), 17.0)
  assert_eq(first.top() - outer.top(), 17.0)
  assert_eq(outer.right() - first.right(), 17.0)
  assert_eq(outer.bottom() - last.bottom(), 17.0)
  assert_eq(last.top() - first.bottom(), 12.0)
  let items = frame.snapshot().items()
  match items[1] {
    @scene.QuadItem(bounds~, color~, ..) => {
      assert_true(bounds == outer)
      assert_eq(color.red(), 166)
      assert_eq(color.green(), 171)
      assert_eq(color.blue(), 178)
    }
    _ => abort("Card outer border quad missing")
  }
  match items[2] {
    @scene.QuadItem(bounds~, color~, ..) => {
      assert_eq(bounds.left() - outer.left(), 1.0)
      assert_eq(bounds.top() - outer.top(), 1.0)
      assert_eq(outer.right() - bounds.right(), 1.0)
      assert_eq(outer.bottom() - bounds.bottom(), 1.0)
      assert_eq(color.red(), 245)
      assert_eq(color.green(), 247)
      assert_eq(color.blue(), 250)
    }
    _ => abort("Card interior quad missing")
  }

  assert_true(!mount.focus(key))
  assert_true(mount.focus(child))
  assert_true(!mount.activate(mount.callback(key).unwrap()))
  ignore(mount.handle_event(event(1L, key_down(@primitives.Space))))
  let same = mount
    .commit(@view.card(key, children), 800.0, 600.0, 1.0, measure)
    .unwrap()
  assert_true(same.focused(child))
  assert_true(same.pressed(child))
  ignore(mount.handle_event(event(2L, key_up(@primitives.Space))))
  assert_eq(mount.next_action(), Some(@view.Activate(child)))
  let nested = @view.card(@view.NodeKey::new("outer"), [
    @view.card(key, children),
  ])
  let frame = mount.commit(nested, 800.0, 600.0, 1.0, measure).unwrap()
  assert_eq(
    frame.bounds(key).unwrap().left() -
    frame.bounds(@view.NodeKey::new("outer")).unwrap().left(),
    17.0,
  )
  assert_true(frame.focused(child))
  assert_true(frame.snapshot().items().length() > 4)
}
