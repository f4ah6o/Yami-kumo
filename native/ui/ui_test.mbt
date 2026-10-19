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
fn composition_event(
  sequence : Int64,
  composition : @primitives.CompositionEvent,
) -> @platform.Event {
  @platform.Event::new(
    @platform.WindowId::new(1L),
    sequence,
    1.0,
    @platform.Composition(composition),
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

///|
fn spacing_near(actual : Double, expected : Double) -> Unit raise {
  assert_true((actual - expected).abs() <= 1.0)
}

///|
fn check_spacing_box(
  frame : @ui.Frame,
  name : String,
  names : Array[String],
  gap : Double,
  padding : Double,
  row : Bool,
) -> Unit raise {
  let outer = frame.bounds(@view.NodeKey::new(name)).unwrap()
  let children = names.map(name => {
    frame.bounds(@view.NodeKey::new(name)).unwrap()
  })
  let mut left = children[0].left()
  let mut top = children[0].top()
  let mut right = children[0].right()
  let mut bottom = children[0].bottom()
  for child in children {
    if child.left() < left {
      left = child.left()
    }
    if child.top() < top {
      top = child.top()
    }
    if child.right() > right {
      right = child.right()
    }
    if child.bottom() > bottom {
      bottom = child.bottom()
    }
  }
  spacing_near(left - outer.left(), padding)
  spacing_near(top - outer.top(), padding)
  spacing_near(outer.right() - right, padding)
  spacing_near(outer.bottom() - bottom, padding)
  for i in 1..<children.length() {
    spacing_near(
      if row {
        children[i].left() - children[i - 1].right()
      } else {
        children[i].top() - children[i - 1].bottom()
      },
      gap,
    )
  }
}

///|
test "explicit stack fixed geometry uses no font metrics and measures all edges" {
  let mounted = mount()
  let frame = mounted
    .commit(@model.spacing_geometry_view(), 640.0, 480.0, 1.0, failed_measure)
    .unwrap()
  check_spacing_box(
    frame,
    "fixed",
    ["fixed-row", "fixed-card"],
    8.0,
    24.0,
    false,
  )
  check_spacing_box(frame, "fixed-row", ["box-a", "box-b"], 12.0, 4.0, true)
  check_spacing_box(frame, "fixed-card", ["box-c"], 12.0, 17.0, false)
  assert_eq(
    frame.bounds(@view.NodeKey::new("box-a")).unwrap().size().width(),
    16.0,
  )
  assert_eq(
    frame.bounds(@view.NodeKey::new("box-a")).unwrap().size().height(),
    16.0,
  )
  assert_eq(
    frame.bounds(@view.NodeKey::new("box-b")).unwrap().size().width(),
    32.0,
  )
  assert_eq(
    frame.bounds(@view.NodeKey::new("box-b")).unwrap().size().height(),
    32.0,
  )
  assert_eq(
    frame.bounds(@view.NodeKey::new("fixed-row")).unwrap().size().width(),
    68.0,
  )
  assert_eq(
    frame.bounds(@view.NodeKey::new("fixed")).unwrap().size().width(),
    116.0,
  )
  assert_eq(
    frame.bounds(@view.NodeKey::new("fixed")).unwrap().size().height(),
    130.0,
  )
}

///|
test "same-key spacing keeps binding focus and unchanged held input but cancels moved bounds" {
  let mounted = mount()
  let initial = @model.SpacingModel::new()
  let view = initial.view()
  let increment = @view.NodeKey::new("increment")
  let first = render(mounted, view~)
  assert_true(mounted.focus(increment))
  ignore(mounted.handle_event(event(1L, key_down(@primitives.Space))).unwrap())
  let held = render(mounted, view~)
  assert_true(held.pressed(increment))
  assert_eq(held.binding_id(increment), first.binding_id(increment))
  ignore(mounted.handle_event(event(2L, key_up(@primitives.Space))).unwrap())
  assert_eq(mounted.next_action(), Some(@view.Activate(increment)))
  ignore(mounted.handle_event(event(3L, key_down(@primitives.Space))).unwrap())
  let expanded = initial.update(
    @view.Activate(@view.NodeKey::new("spacing-toggle")),
  )
  let changed = render(mounted, view=expanded.view())
  assert_eq(changed.binding_id(increment), first.binding_id(increment))
  assert_eq(
    changed.binding_id(@view.NodeKey::new("counter")),
    first.binding_id(@view.NodeKey::new("counter")),
  )
  assert_true(changed.focused(increment))
  assert_true(!changed.pressed(increment))
  ignore(mounted.handle_event(event(4L, key_up(@primitives.Space))).unwrap())
  assert_true(mounted.next_action() is None)
  check_spacing_box(
    changed,
    "counter",
    ["heading", "value", "actions", "preview"],
    12.0,
    16.0,
    false,
  )
  check_spacing_box(
    changed,
    "actions",
    ["increment", "spacing-toggle"],
    16.0,
    8.0,
    true,
  )
  check_spacing_box(changed, "preview", ["card-label"], 12.0, 17.0, false)
  ignore(mounted.handle_event(event(5L, key_down(@primitives.Space))).unwrap())
  ignore(mounted.handle_event(event(6L, key_up(@primitives.Space))).unwrap())
  assert_eq(mounted.next_action(), Some(@view.Activate(increment)))
}

///|
test "all closed tokens and empty explicit Row Column have exact intrinsic padding" {
  for
    token in [
      @view.Zero,
      @view.Four,
      @view.Eight,
      @view.Twelve,
      @view.Sixteen,
      @view.TwentyFour,
    ] {
    let spacing = @view.StackSpacing::new(token, token)
    let root = @view.NodeKey::new("empty-stack")
    for
      view in [
        @view.row_with_spacing(root, [], spacing),
        @view.column_with_spacing(root, [], spacing),
      ] {
      let mounted = mount()
      let frame = mounted
        .commit(view, 640.0, 480.0, 1.0, failed_measure)
        .unwrap()
      let bounds = frame.bounds(root).unwrap()
      assert_eq(bounds.size().width(), 2.0 * token.pixels())
      assert_eq(bounds.size().height(), 2.0 * token.pixels())
      assert_true(!mounted.focus(root))
      assert_true(frame.binding_id(root) is Some(_))
      assert_eq(frame.binding_id(@view.NodeKey::new("absent")), None)
    }
  }
}

///|
fn palette_view(
  token : @view.ButtonPaletteToken?,
  disabled~ : Bool = false,
  loading~ : Bool = false,
) -> @view.View {
  let key = @view.NodeKey::new("palette")
  match token {
    None => @view.button(key, "Palette", disabled~, loading~)
    Some(value) =>
      @view.button_with_palette(key, "Palette", value, disabled~, loading~)
  }
}

///|
fn item_color(item : @scene.SceneItem) -> @primitives.Color {
  match item {
    @scene.QuadItem(color~, ..) | @scene.TextRunItem(color~, ..) => color
    _ => abort("expected measured text or quad")
  }
}

///|
fn expected_color(
  token : @view.ButtonPaletteToken,
  role : @view.ButtonPaintRole,
) -> @primitives.Color {
  let c = token.color(role)
  @primitives.Color::rgba(c.red(), c.green(), c.blue(), c.alpha()).unwrap()
}

///|
test "palette native every role is delegated and measured geometry is preserved" {
  let key = @view.NodeKey::new("palette")
  for token in [@view.Light, @view.Dark] {
    // Each portable input state is selected through public controls, never RGB.
    for state in 0..<7 {
      let mount = @ui.Mounted::new(@platform.WindowId::new(1L))
      let initial = mount
        .commit(palette_view(None), 800.0, 600.0, 1.0, measure)
        .unwrap()
      let bounds = initial.bounds(key).unwrap()
      let point = @primitives.Point::new(
        bounds.left() + 4.0,
        bounds.top() + 4.0,
      ).unwrap()
      if state == 1 || state == 2 || state == 3 {
        assert_true(mount.focus(key))
      }
      if state == 2 || state == 3 {
        ignore(
          mount
          .handle_event(event(1L, @primitives.PointerMoved(position=point)))
          .unwrap(),
        )
      }
      if state == 3 {
        ignore(mount.handle_event(event(2L, down(bounds))).unwrap())
      }
      let frame = mount
        .commit(
          palette_view(
            Some(token),
            disabled=state == 5 || state == 6,
            loading=state == 4 || state == 6,
          ),
          800.0,
          600.0,
          1.0,
          measure,
        )
        .unwrap()
      assert_true(frame.bounds(key) == initial.bounds(key))
      assert_true(frame.label_bounds(key) == initial.label_bounds(key))
      assert_eq(frame.binding_id(key), initial.binding_id(key))
      assert_eq(frame.button_palette(key), Some(token))
      let border = if state >= 5 {
        @view.DisabledBorder
      } else if state >= 1 && state <= 3 {
        @view.FocusedBorder
      } else {
        @view.NormalBorder
      }
      let fill = if state >= 5 {
        @view.DisabledFill
      } else if state == 4 {
        @view.LoadingFill
      } else if state == 3 {
        @view.PressedFill
      } else if state == 2 {
        @view.HoveredFill
      } else {
        @view.NormalFill
      }
      let foreground = if state >= 5 {
        @view.DisabledForeground
      } else {
        @view.EnabledForeground
      }
      let items = frame.snapshot().items()
      assert_eq(items.length(), 4)
      assert_true(item_color(items[1]) == expected_color(token, border))
      assert_true(item_color(items[2]) == expected_color(token, fill))
      assert_true(item_color(items[3]) == expected_color(token, foreground))
      assert_true(items[3] is @scene.TextRunItem(..))
      assert_eq(frame.pressed(key), state == 3)
      assert_eq(frame.hovered(key), state == 2 || state == 3)
      assert_eq(frame.enabled(key), state < 5)
      assert_eq(frame.loading(key), state == 4 || state == 6)
    }
  }
}

///|
test "palette changes retain held press focus callbacks and queued activation" {
  let key = @view.NodeKey::new("palette")
  let mount = @ui.Mounted::new(@platform.WindowId::new(1L))
  let first = mount
    .commit(palette_view(None), 800.0, 600.0, 1.0, measure)
    .unwrap()
  let bounds = first.bounds(key).unwrap()
  assert_true(mount.focus(key))
  let callback = mount.callback(key).unwrap()
  ignore(mount.handle_event(event(1L, down(bounds))).unwrap())
  for token in [Some(@view.Light), Some(@view.Dark), None] {
    let frame = mount
      .commit(palette_view(token), 800.0, 600.0, 1.0, measure)
      .unwrap()
    assert_true(frame.pressed(key) && frame.focused(key))
    assert_eq(frame.binding_id(key), first.binding_id(key))
    assert_true(frame.label_bounds(key) == first.label_bounds(key))
    assert_true(mount.activate(callback))
    assert_eq(mount.next_action(), Some(@view.Activate(key)))
  }
  assert_true(mount.activate(callback))
  ignore(
    mount
    .commit(palette_view(Some(@view.Light)), 800.0, 600.0, 1.0, measure)
    .unwrap(),
  )
  assert_eq(mount.next_action(), Some(@view.Activate(key)))
  let failed = mount.stage(
    palette_view(Some(@view.Dark)),
    800.0,
    600.0,
    1.0,
    failed_measure,
  )
  assert_true(failed is Err(_))
  let stale = mount
    .stage(palette_view(Some(@view.Dark)), 800.0, 600.0, 1.0, measure)
    .unwrap()
  ignore(mount.commit(palette_view(None), 800.0, 600.0, 1.0, measure).unwrap())
  assert_true(mount.publish(stale) is Err(_))
  ignore(mount.handle_event(event(2L, up(bounds))).unwrap())
  assert_eq(mount.next_action(), Some(@view.Activate(key)))
  assert_eq(mount.next_action(), None)
}

///|
test "palette all gate and input overlaps use accepted core states for role selection" {
  let key = @view.NodeKey::new("palette")
  for token in [@view.Light, @view.Dark] {
    for flags in 0..<32 {
      let focused = flags % 2 == 1
      let hovered = flags / 2 % 2 == 1
      let pressed = flags / 4 % 2 == 1
      let disabled = flags / 8 % 2 == 1
      let loading = flags / 16 % 2 == 1
      let mount = @ui.Mounted::new(@platform.WindowId::new(1L))
      let frame = mount
        .commit(palette_view(Some(token)), 800.0, 600.0, 1.0, measure)
        .unwrap()
      let bounds = frame.bounds(key).unwrap()
      if focused {
        assert_true(mount.focus(key))
      }
      if hovered {
        ignore(
          mount
          .handle_event(
            event(
              1L,
              @primitives.PointerMoved(
                position=@primitives.Point::new(
                  bounds.left() + 4.0,
                  bounds.top() + 4.0,
                ).unwrap(),
              ),
            ),
          )
          .unwrap(),
        )
      }
      if pressed {
        ignore(mount.handle_event(event(2L, down(bounds))).unwrap())
      }
      let actual = mount
        .commit(
          palette_view(Some(token), disabled~, loading~),
          800.0,
          600.0,
          1.0,
          measure,
        )
        .unwrap()
      let border = if !actual.enabled(key) {
        @view.DisabledBorder
      } else if actual.focused(key) {
        @view.FocusedBorder
      } else {
        @view.NormalBorder
      }
      let fill = if !actual.enabled(key) {
        @view.DisabledFill
      } else if actual.loading(key) {
        @view.LoadingFill
      } else if actual.pressed(key) {
        @view.PressedFill
      } else if actual.hovered(key) {
        @view.HoveredFill
      } else {
        @view.NormalFill
      }
      let foreground = if !actual.enabled(key) {
        @view.DisabledForeground
      } else {
        @view.EnabledForeground
      }
      let items = actual.snapshot().items()
      assert_true(item_color(items[1]) == expected_color(token, border))
      assert_true(item_color(items[2]) == expected_color(token, fill))
      assert_true(item_color(items[3]) == expected_color(token, foreground))
      // Dark explicitly matches the legacy entry, including complete scene IDs,
      // measured origins, bounds and metadata, for every accepted state overlap.
      if token == @view.Dark {
        let legacy = mount
          .commit(
            palette_view(None, disabled~, loading~),
            800.0,
            600.0,
            1.0,
            measure,
          )
          .unwrap()
        assert_eq(
          legacy.snapshot().canonical_json(),
          actual.snapshot().canonical_json(),
        )
      }
    }
  }
}

///|
test "explicit palettes preserve core overlong label rejection and atomic frame" {
  let key = @view.NodeKey::new("palette")
  let mount = @ui.Mounted::new(@platform.WindowId::new(1L))
  let before = mount
    .commit(palette_view(None), 800.0, 600.0, 1.0, measure)
    .unwrap()
  let callback = mount.callback(key).unwrap()
  for token in [@view.Light, @view.Dark] {
    let invalid = @view.button_with_palette(
      key,
      String::make(65537, 'a'),
      token,
    )
    assert_true(
      mount.commit(invalid, 800.0, 600.0, 1.0, (_text, size) => {
        measure("short", size)
      })
      is Err(_),
    )
    assert_eq(
      mount.frame().unwrap().snapshot().canonical_json(),
      before.snapshot().canonical_json(),
    )
    assert_eq(mount.frame().unwrap().button_palette(key), None)
    assert_true(mount.activate(callback))
    assert_eq(mount.next_action(), Some(@view.Activate(key)))
  }
}

///|
fn pair(palette : @view.ButtonPaletteToken?) -> @view.View {
  fn button(key : String) -> @view.View {
    match palette {
      None => @view.button(@view.NodeKey::new(key), key)
      Some(token) =>
        @view.button_with_palette(@view.NodeKey::new(key), key, token)
    }
  }
  @view.row(@view.NodeKey::new("root"), [button("first"), button("second")])
}

///|
test "legacy routed click without motion retains previous core hover" {
  let mount = @ui.Mounted::new(@platform.WindowId::new(1L))
  let first = @view.NodeKey::new("first")
  let second = @view.NodeKey::new("second")
  let initial = mount.commit(pair(None), 800.0, 600.0, 1.0, measure).unwrap()
  let a = initial.bounds(first).unwrap()
  let b = initial.bounds(second).unwrap()
  ignore(
    mount
    .handle_event(
      event(
        1L,
        @primitives.PointerMoved(
          position=@primitives.Point::new(a.left() + 4.0, a.top() + 4.0).unwrap(),
        ),
      ),
    )
    .unwrap(),
  )
  ignore(mount.handle_event(event(2L, down(a))).unwrap())
  ignore(mount.handle_event(event(3L, up(a))).unwrap())
  let before = mount.commit(pair(None), 800.0, 600.0, 1.0, measure).unwrap()
  assert_true(before.hovered(first) && !before.hovered(second))
  // Valid public event sequence: routed click has coordinates, but no separate motion event.
  ignore(mount.handle_event(event(4L, down(b))).unwrap())
  ignore(mount.handle_event(event(5L, up(b))).unwrap())
  let legacy = mount.commit(pair(None), 800.0, 600.0, 1.0, measure).unwrap()
  assert_true(legacy.hovered(first) && legacy.hovered(second))
  assert_true(!legacy.focused(first) && legacy.focused(second))
  assert_true(!legacy.pressed(first) && !legacy.pressed(second))
  for token in [Some(@view.Light), Some(@view.Dark), None] {
    let themed = mount.commit(pair(token), 800.0, 600.0, 1.0, measure).unwrap()
    assert_true(themed.hovered(first) && themed.hovered(second))
    assert_eq(themed.binding_id(first), initial.binding_id(first))
    assert_eq(themed.binding_id(second), initial.binding_id(second))
  }
  // An actual delivered motion reaches both existing controllers and clears the former owner.
  ignore(
    mount
    .handle_event(
      event(
        6L,
        @primitives.PointerMoved(
          position=@primitives.Point::new(b.left() + 4.0, b.top() + 4.0).unwrap(),
        ),
      ),
    )
    .unwrap(),
  )
  let moved = mount
    .commit(pair(Some(@view.Light)), 800.0, 600.0, 1.0, measure)
    .unwrap()
  assert_true(!moved.hovered(first) && moved.hovered(second))
}

///|
test "dispatch witness distinguishes unconsumed motion from ignored input" {
  let mounted = mount()
  let point = @primitives.Point::new(20.0, 20.0).unwrap()
  let motion = @primitives.PointerMoved(position=point)
  assert_eq(mounted.last_dispatched_input_sequence(), 0L)
  // Not ready; no successful dispatch.
  assert_false(mounted.handle_event(event(1L, motion)).unwrap())
  assert_eq(mounted.last_dispatched_input_sequence(), 0L)
  ignore(render(mounted))
  // A foreign window cannot consume the owned sequence or dispatch witness.
  assert_false(
    mounted
    .handle_event(
      @platform.Event::new(
        @platform.WindowId::new(2L),
        2L,
        1.0,
        @platform.Input(motion),
      ),
    )
    .unwrap(),
  )
  assert_eq(mounted.last_dispatched_input_sequence(), 0L)
  assert_false(mounted.handle_event(event(2L, motion)).unwrap())
  assert_eq(mounted.last_dispatched_input_sequence(), 2L)
  assert_false(mounted.handle_event(event(2L, motion)).unwrap())
  assert_eq(mounted.last_dispatched_input_sequence(), 2L)
  ignore(
    mounted
    .handle_event(
      @platform.Event::new(
        @platform.WindowId::new(1L),
        3L,
        1.0,
        @platform.FocusChanged(false),
      ),
    )
    .unwrap(),
  )
  assert_false(mounted.handle_event(event(4L, motion)).unwrap())
  assert_eq(mounted.last_dispatched_input_sequence(), 2L)
  ignore(
    mounted
    .handle_event(
      @platform.Event::new(
        @platform.WindowId::new(1L),
        5L,
        1.0,
        @platform.FocusChanged(true),
      ),
    )
    .unwrap(),
  )
  assert_false(
    mounted
    .handle_event(
      @platform.Event::new(
        @platform.WindowId::new(1L),
        6L,
        2.0,
        @platform.Input(motion),
      ),
    )
    .unwrap(),
  )
  assert_eq(mounted.last_dispatched_input_sequence(), 2L)
  assert_false(mounted.handle_event(event(7L, motion)).unwrap())
  assert_eq(mounted.last_dispatched_input_sequence(), 2L)
  ignore(render(mounted))
  assert_false(mounted.handle_event(event(8L, motion)).unwrap())
  assert_eq(mounted.last_dispatched_input_sequence(), 8L)
  mounted.dispose()
  assert_false(mounted.handle_event(event(9L, motion)).unwrap())
  assert_eq(mounted.last_dispatched_input_sequence(), 8L)
}

///|
test "Button-only adapter gates composition lifetime without dispatching an activation" {
  let mounted = mount()
  ignore(render(mounted))
  let motion = @primitives.PointerMoved(
    position=@primitives.Point::new(20.0, 20.0).unwrap(),
  )
  for
    (sequence, composition) in [
      (1L, @primitives.CompositionEvent::Start),
      (2L, @primitives.CompositionEvent::Update(text="に", cursor_utf16=1)),
      (3L, @primitives.CompositionEvent::Commit(text="日")),
      (4L, @primitives.CompositionEvent::Cancel),
    ] {
    let composition_event = @platform.Event::new(
      @platform.WindowId::new(1L),
      sequence,
      1.0,
      @platform.Composition(composition),
    )
    assert_false(mounted.handle_event(composition_event).unwrap())
    assert_true(mounted.next_action() is None)
    assert_eq(mounted.last_dispatched_input_sequence(), 0L)
    // Composition consumes the sequence lifetime even though this Button-only
    // adapter has no text editor. Same-sequence input must not be replayed.
    assert_false(mounted.handle_event(event(sequence, motion)).unwrap())
    assert_eq(mounted.last_dispatched_input_sequence(), 0L)
  }
  assert_false(mounted.handle_event(event(5L, motion)).unwrap())
  assert_eq(mounted.last_dispatched_input_sequence(), 5L)
  assert_true(mounted.next_action() is None)
}

///|
fn text_field_view(
  value~ : String = "日本語",
  read_only~ : Bool = false,
  disabled~ : Bool = false,
) -> @view.View {
  @view.column(@view.NodeKey::new("root"), [
    @view.text_field(
      @view.NodeKey::new("field"),
      @view.TextFieldProps::new(
        value,
        "Name",
        read_only~,
        disabled~,
      ),
    ),
  ])
}

///|
test "native adapter renders an editable TextField with measured bounds" {
  let mounted = mount()
  let view = text_field_view()
  let frame = render(mounted, view=view)
  let bounds = frame.bounds(@view.NodeKey::new("field")).unwrap()
  assert_true(bounds.size().width() >= 240.0)
  assert_true(bounds.size().height() >= 64.0)
  assert_true(frame.snapshot().items().length() > 0)
  assert_true(mounted.view() is Some(_))
  mounted.dispose()
}

///|
test "native TextField routes committed typing through TextChanged" {
  let mounted = mount()
  ignore(render(mounted, view=text_field_view()))
  assert_true(mounted.focus(@view.NodeKey::new("field")))
  assert_true(
    mounted
    .handle_event(event(2L, @primitives.TextInput(text="a")))
    .unwrap(),
  )
  match mounted.next_action() {
    Some(@view.TextChanged(key, value)) => {
      assert_eq(key, @view.NodeKey::new("field"))
      assert_eq(value, "a日本語")
    }
    _ => fail("expected TextChanged")
  }
  mounted.dispose()
}

///|
test "native TextField focuses on click and edits at the clicked caret" {
  let mounted = mount()
  let frame = render(mounted, view=text_field_view())
  let bounds = frame.bounds(@view.NodeKey::new("field")).unwrap()
  let point = @primitives.Point::new(
    bounds.right() - 8.0,
    bounds.top() + 32.0,
  ).unwrap()
  assert_true(
    mounted
    .handle_event(
      event(
        2L,
        @primitives.PointerButtonPressed(
          position=point,
          button=@primitives.Primary,
          modifiers=@primitives.Modifiers::none(),
        ),
      ),
    )
    .unwrap(),
  )
  assert_true(mounted.focus(@view.NodeKey::new("field")))
  assert_true(mounted.text_caret(@view.NodeKey::new("field")) is Some(_))
  assert_true(
    mounted
    .handle_event(event(3L, @primitives.TextInput(text="!")))
    .unwrap(),
  )
  match mounted.next_action() {
    Some(@view.TextChanged(_, value)) => assert_eq(value, "日本語!")
    _ => fail("expected TextChanged")
  }
  assert_true(
    mounted
    .handle_event(event(4L, key_down(@primitives.Backspace)))
    .unwrap(),
  )
  match mounted.next_action() {
    Some(@view.TextChanged(_, value)) => assert_eq(value, "日本語")
    _ => fail("expected TextChanged")
  }
  mounted.dispose()
}

///|
test "native TextField applies host composition as preview then commit" {
  let mounted = mount()
  ignore(render(mounted, view=text_field_view()))
  assert_true(mounted.focus(@view.NodeKey::new("field")))
  assert_true(
    mounted
    .handle_event(composition_event(2L, @primitives.Start))
    .unwrap(),
  )
  assert_true(
    mounted
    .handle_event(
      composition_event(
        3L,
        @primitives.Update(text="にほん", cursor_utf16=3),
      ),
    )
    .unwrap(),
  )
  assert_true(mounted.next_action() is None)
  assert_true(
    mounted
    .handle_event(composition_event(4L, @primitives.Commit(text="日本")))
    .unwrap(),
  )
  match mounted.next_action() {
    Some(@view.TextChanged(_, value)) => assert_eq(value, "日本日本語")
    _ => fail("expected TextChanged")
  }
  mounted.dispose()
}

///|
test "native TextField cancels host composition without a committed edit" {
  let mounted = mount()
  ignore(render(mounted, view=text_field_view()))
  assert_true(mounted.focus(@view.NodeKey::new("field")))
  assert_true(
    mounted
    .handle_event(
      composition_event(
        2L,
        @primitives.Update(text="にほん", cursor_utf16=3),
      ),
    )
    .unwrap(),
  )
  assert_true(mounted.next_action() is None)
  assert_true(
    mounted
    .handle_event(composition_event(3L, @primitives.Cancel))
    .unwrap(),
  )
  assert_true(mounted.next_action() is None)
  mounted.dispose()
}

///|
test "native TextField Escape restores the previous focus owner" {
  let mounted = mount()
  let view = @view.column(@view.NodeKey::new("root"), [
    @view.button(@view.NodeKey::new("button"), "Increment"),
    @view.text_field(
      @view.NodeKey::new("field"),
      @view.TextFieldProps::new("日本語", "Name"),
    ),
  ])
  ignore(render(mounted, view=view))
  assert_true(mounted.focus(@view.NodeKey::new("button")))
  assert_true(mounted.focus(@view.NodeKey::new("field")))
  assert_true(
    mounted.handle_event(event(2L, key_down(@primitives.Escape))).unwrap(),
  )
  assert_true(
    mounted.handle_event(event(3L, key_down(@primitives.Enter))).unwrap(),
  )
  match mounted.next_action() {
    Some(@view.Activate(key)) =>
      assert_eq(key, @view.NodeKey::new("button"))
    _ => fail("expected restored Button activation")
  }
  mounted.dispose()
}

///|
test "native TextField submit and read-only behavior" {
  let mounted = mount()
  ignore(render(mounted, view=text_field_view(read_only=true)))
  assert_true(mounted.focus(@view.NodeKey::new("field")))
  assert_false(
    mounted
    .handle_event(event(2L, @primitives.TextInput(text="x")))
    .unwrap(),
  )
  assert_true(mounted.next_action() is None)
  mounted.dispose()

  let editable = mount()
  ignore(render(editable, view=text_field_view()))
  assert_true(editable.focus(@view.NodeKey::new("field")))
  assert_true(
    editable
    .handle_event(event(2L, key_down(@primitives.Enter)))
    .unwrap(),
  )
  match editable.next_action() {
    Some(@view.Submitted(key)) =>
      assert_eq(key, @view.NodeKey::new("field"))
    _ => fail("expected Submitted")
  }
  editable.dispose()
}

///|
test "native adapter rejects Dialog instead of showing a non-modal imitation" {
  let mounted = mount()
  let modal = @view.dialog(
    @view.NodeKey::new("dialog"),
    @view.DialogProps::new(true, "Confirm"),
    [@view.button(@view.NodeKey::new("ok"), "OK")],
  )
  let view = @view.column(@view.NodeKey::new("root"), [modal])
  assert_true(mounted.commit(view, 640.0, 480.0, 1.0, measure) is Err(_))
  assert_true(mounted.frame() is None)
}
