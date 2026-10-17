///|
fn theme_motion(bounds : @primitives.Rect) -> @primitives.InputEvent {
  @primitives.PointerMoved(
    position=@primitives.Point::new(bounds.left() + 4.0, bounds.top() + 4.0).unwrap(),
  )
}

///|
fn theme_item_color(frame : @ui.Frame, id : UInt64) -> @primitives.Color {
  for item in frame.snapshot().items() {
    if item.id() == id {
      return match item {
        @scene.QuadItem(color~, ..) | @scene.TextRunItem(color~, ..) => color
        _ => abort("expected Button quad or measured text run")
      }
    }
  }
  abort("expected Button item missing")
}

///|
fn assert_theme_color(
  actual : @primitives.Color,
  expected : @theme.Color,
) -> Unit raise {
  assert_eq(actual.red(), expected.red())
  assert_eq(actual.green(), expected.green())
  assert_eq(actual.blue(), expected.blue())
  assert_eq(actual.alpha(), 255)
}

///|
fn button_theme_slots(theme : @theme.Theme) -> Array[@theme.Color] {
  let colors = theme.button_colors()
  [
    colors.normal_border,
    colors.focused_border,
    colors.disabled_border,
    colors.normal_fill,
    colors.hovered_fill,
    colors.pressed_fill,
    colors.loading_fill,
    colors.disabled_fill,
    colors.enabled_foreground,
    colors.disabled_foreground,
  ]
}

///|
fn theme_override_view(palette : @view.ButtonPaletteToken?) -> @view.View {
  let explicit = @view.NodeKey::new("explicit")
  @view.row(@view.NodeKey::new("theme-root"), [
    @view.button(@view.NodeKey::new("inherited"), "Inherited"),
    match palette {
      Some(token) => @view.button_with_palette(explicit, "Explicit", token)
      None => @view.button(explicit, "Explicit")
    },
  ])
}

///|
fn assert_button_theme_colors(
  frame : @ui.Frame,
  key : @view.NodeKey,
  border : @theme.Color,
  fill : @theme.Color,
  foreground : @theme.Color,
) -> Unit raise {
  let id = frame.binding_id(key).unwrap()
  assert_theme_color(theme_item_color(frame, id + 1UL), border)
  assert_theme_color(theme_item_color(frame, id + 2UL), fill)
  assert_theme_color(theme_item_color(frame, id + 3UL), foreground)
}

///|
test "both themes cover all 32 overlapping input and gate requests with fixed role expectations" {
  // A disabled/loading transition clears in-flight input in GPUI. Keeping the
  // expected results explicit prevents the test from copying paint branches.
  // Bits: disabled, focus request, loading, hover request, pointer press.
  let expected = [
    (0, 3, 8, false, false, false),
    (2, 7, 9, false, false, false),
    (1, 3, 8, true, false, false),
    (2, 7, 9, false, false, false),
    (0, 6, 8, false, false, false),
    (2, 7, 9, false, false, false),
    (1, 6, 8, true, false, false),
    (2, 7, 9, false, false, false),
    (0, 4, 8, false, true, false),
    (2, 7, 9, false, false, false),
    (1, 4, 8, true, true, false),
    (2, 7, 9, false, false, false),
    (0, 6, 8, false, false, false),
    (2, 7, 9, false, false, false),
    (1, 6, 8, true, false, false),
    (2, 7, 9, false, false, false),
    (1, 5, 8, true, false, true),
    (2, 7, 9, false, false, false),
    (1, 5, 8, true, false, true),
    (2, 7, 9, false, false, false),
    (1, 6, 8, true, false, false),
    (2, 7, 9, false, false, false),
    (1, 6, 8, true, false, false),
    (2, 7, 9, false, false, false),
    (1, 5, 8, true, true, true),
    (2, 7, 9, false, false, false),
    (1, 5, 8, true, true, true),
    (2, 7, 9, false, false, false),
    (1, 6, 8, true, false, false),
    (2, 7, 9, false, false, false),
    (1, 6, 8, true, false, false),
    (2, 7, 9, false, false, false),
  ]
  let outside = @primitives.Rect::new(600.0, 400.0, 30.0, 30.0).unwrap()
  for theme in [@theme.Light, @theme.Dark] {
    let slots = button_theme_slots(theme)
    for mask in 0..<32 {
      let mounted = @ui.Mounted::new(
        @platform.WindowId::new(1L),
        theme=Some(theme),
      )
      let initial = render(mounted)
      let bounds = initial.bounds(key()).unwrap()
      if (mask & 2) != 0 {
        assert_true(mounted.focus(key()))
      }
      if (mask & 16) != 0 {
        assert_true(mounted.handle_event(event(1L, down(bounds))).unwrap())
      }
      ignore(
        mounted
        .handle_event(
          event(
            2L,
            theme_motion(if (mask & 8) != 0 { bounds } else { outside }),
          ),
        )
        .unwrap(),
      )
      let view = button_view(disabled=(mask & 1) != 0, loading=(mask & 4) != 0)
      let frame = render(mounted, view~)
      let (border, fill, foreground, focused, hovered, pressed) = expected[mask]
      let id = frame.binding_id(key()).unwrap()
      assert_theme_color(theme_item_color(frame, id + 1UL), slots[border])
      assert_theme_color(theme_item_color(frame, id + 2UL), slots[fill])
      assert_theme_color(theme_item_color(frame, id + 3UL), slots[foreground])
      assert_eq(frame.theme(), Some(theme))
      assert_eq(frame.binding_id(key()), initial.binding_id(key()))
      assert_true(frame.bounds(key()) == initial.bounds(key()))
      assert_true(frame.label_bounds(key()) == initial.label_bounds(key()))
      assert_eq(frame.focused(key()), focused)
      assert_eq(frame.hovered(key()), hovered)
      assert_eq(frame.pressed(key()), pressed)
      assert_true(mounted.next_action() is None)
      let other = if theme == @theme.Light { @theme.Dark } else { @theme.Light }
      assert_true(mounted.set_theme(Some(other)))
      assert_eq(mounted.frame().unwrap().theme(), Some(theme))
      let changed = render(mounted, view~)
      let changed_slots = button_theme_slots(other)
      assert_theme_color(
        theme_item_color(changed, id + 1UL),
        changed_slots[border],
      )
      assert_theme_color(
        theme_item_color(changed, id + 2UL),
        changed_slots[fill],
      )
      assert_theme_color(
        theme_item_color(changed, id + 3UL),
        changed_slots[foreground],
      )
      assert_eq(changed.theme(), Some(other))
      assert_eq(changed.binding_id(key()), frame.binding_id(key()))
      assert_true(changed.bounds(key()) == frame.bounds(key()))
      assert_true(changed.label_bounds(key()) == frame.label_bounds(key()))
      assert_eq(changed.focused(key()), focused)
      assert_eq(changed.hovered(key()), hovered)
      assert_eq(changed.pressed(key()), pressed)
      ignore(mounted.handle_event(event(3L, up(bounds))).unwrap())
      assert_eq(
        mounted.next_action(),
        if pressed {
          Some(@view.Activate(key()))
        } else {
          None
        },
      )
      assert_true(mounted.next_action() is None)
      mounted.dispose()
    }
  }
}

///|
test "theme requests preserve accepted frame input and identity through failed staging and successful retry" {
  let mounted = @ui.Mounted::new(
    @platform.WindowId::new(1L),
    theme=Some(@theme.Light),
  )
  let initial = render(mounted)
  let callback = mounted.callback(key()).unwrap()
  let bounds = initial.bounds(key()).unwrap()
  ignore(mounted.handle_event(event(1L, down(bounds))).unwrap())
  let held = render(mounted)
  let held_json = held.snapshot().canonical_json()
  let old_staged = mounted
    .stage(button_view(), 640.0, 480.0, 1.0, measure)
    .unwrap()
  assert_true(mounted.set_theme(Some(@theme.Dark)))
  assert_eq(mounted.theme(), Some(@theme.Dark))
  assert_eq(mounted.frame().unwrap().theme(), Some(@theme.Light))
  assert_true(mounted.publish(old_staged) is Err(_))
  assert_true(
    mounted.commit(button_view(), 640.0, 480.0, 1.0, failed_measure) is Err(_),
  )
  assert_eq(mounted.frame().unwrap().revision(), held.revision())
  assert_eq(mounted.frame().unwrap().snapshot().canonical_json(), held_json)
  assert_eq(mounted.view(), Some(button_view()))
  assert_true(mounted.activate(callback))
  let candidate = mounted
    .stage(button_view(), 640.0, 480.0, 1.0, measure)
    .unwrap()
  assert_true(mounted.set_theme(Some(@theme.Dark)))
  let dark = mounted.publish(candidate).unwrap()
  assert_eq(dark.theme(), Some(@theme.Dark))
  assert_eq(held.theme(), Some(@theme.Light))
  assert_eq(held.snapshot().canonical_json(), held_json)
  assert_eq(dark.binding_id(key()), initial.binding_id(key()))
  assert_true(dark.bounds(key()) == initial.bounds(key()))
  assert_true(dark.focused(key()))
  assert_true(dark.pressed(key()))
  assert_true(dark.hovered(key()))
  assert_eq(mounted.next_action(), Some(@view.Activate(key())))
  assert_true(mounted.next_action() is None)
  ignore(mounted.handle_event(event(2L, up(bounds))).unwrap())
  assert_eq(mounted.next_action(), Some(@view.Activate(key())))
  assert_true(mounted.next_action() is None)
}

///|
test "theme swaps retain Space and Enter arming and their existing activation timing" {
  let mounted = mount()
  let initial = render(mounted)
  assert_true(mounted.focus(key()))
  ignore(mounted.handle_event(event(1L, key_down(@primitives.Space))).unwrap())
  assert_true(mounted.set_theme(Some(@theme.Light)))
  let light = render(mounted)
  assert_true(light.pressed(key()))
  assert_true(light.focused(key()))
  assert_eq(light.binding_id(key()), initial.binding_id(key()))
  ignore(
    mounted
    .handle_event(event(2L, key_down(@primitives.Space, repeat=true)))
    .unwrap(),
  )
  assert_true(mounted.next_action() is None)
  assert_true(mounted.set_theme(Some(@theme.Dark)))
  assert_true(render(mounted).pressed(key()))
  ignore(mounted.handle_event(event(3L, key_up(@primitives.Space))).unwrap())
  assert_eq(mounted.next_action(), Some(@view.Activate(key())))
  assert_true(mounted.next_action() is None)
  ignore(mounted.handle_event(event(4L, key_down(@primitives.Enter))).unwrap())
  assert_eq(mounted.next_action(), Some(@view.Activate(key())))
  assert_true(mounted.set_theme(None))
  let legacy = render(mounted)
  assert_eq(legacy.theme(), None)
  assert_true(legacy.pressed(key()))
  ignore(
    mounted
    .handle_event(event(5L, key_down(@primitives.Enter, repeat=true)))
    .unwrap(),
  )
  ignore(mounted.handle_event(event(6L, key_up(@primitives.Enter))).unwrap())
  assert_true(mounted.next_action() is None)
  ignore(mounted.handle_event(event(7L, key_down(@primitives.Enter))).unwrap())
  assert_eq(mounted.next_action(), Some(@view.Activate(key())))
  assert_true(mounted.next_action() is None)
}

///|
test "outside release loading disable and focus loss still cancel across theme changes" {
  let mounted = @ui.Mounted::new(
    @platform.WindowId::new(1L),
    theme=Some(@theme.Light),
  )
  let initial = render(mounted)
  let bounds = initial.bounds(key()).unwrap()
  let outside = @primitives.Rect::new(600.0, 400.0, 30.0, 30.0).unwrap()
  ignore(mounted.handle_event(event(1L, down(bounds))).unwrap())
  assert_true(mounted.set_theme(Some(@theme.Dark)))
  assert_true(render(mounted).pressed(key()))
  ignore(mounted.handle_event(event(2L, up(outside))).unwrap())
  assert_true(mounted.next_action() is None)
  assert_true(!render(mounted).pressed(key()))
  ignore(mounted.handle_event(event(3L, key_down(@primitives.Space))).unwrap())
  assert_true(mounted.set_theme(Some(@theme.Light)))
  let loading = render(mounted, view=button_view(loading=true))
  assert_true(loading.focused(key()))
  assert_true(!loading.pressed(key()))
  assert_true(mounted.set_theme(Some(@theme.Dark)))
  ignore(render(mounted))
  ignore(mounted.handle_event(event(4L, key_up(@primitives.Space))).unwrap())
  assert_true(mounted.next_action() is None)
  ignore(mounted.handle_event(event(5L, down(bounds))).unwrap())
  assert_true(mounted.set_theme(Some(@theme.Light)))
  let disabled = render(mounted, view=button_view(disabled=true))
  assert_true(!disabled.focused(key()))
  assert_true(!disabled.pressed(key()))
  ignore(render(mounted))
  assert_true(mounted.focus(key()))
  ignore(mounted.handle_event(event(6L, up(bounds))).unwrap())
  assert_true(mounted.next_action() is None)
  ignore(mounted.handle_event(event(7L, key_down(@primitives.Space))).unwrap())
  assert_true(mounted.set_theme(Some(@theme.Dark)))
  ignore(render(mounted))
  ignore(
    mounted
    .handle_event(
      @platform.Event::new(
        @platform.WindowId::new(1L),
        8L,
        1.0,
        @platform.FocusChanged(false),
      ),
    )
    .unwrap(),
  )
  ignore(
    mounted
    .handle_event(
      @platform.Event::new(
        @platform.WindowId::new(1L),
        9L,
        1.0,
        @platform.FocusChanged(true),
      ),
    )
    .unwrap(),
  )
  assert_true(mounted.focus(key()))
  ignore(mounted.handle_event(event(10L, key_up(@primitives.Space))).unwrap())
  assert_true(mounted.next_action() is None)
  ignore(mounted.handle_event(event(11L, down(bounds))).unwrap())
  ignore(mounted.handle_event(event(12L, up(bounds))).unwrap())
  assert_eq(mounted.next_action(), Some(@view.Activate(key())))
  assert_true(mounted.next_action() is None)
}

///|
test "unset theme restores the exact legacy scene and setters reject reentrancy or disposal" {
  let mounted = mount()
  let legacy = render(mounted)
  assert_eq(mounted.theme(), None)
  assert_eq(legacy.theme(), None)
  for theme in [@theme.Light, @theme.Dark] {
    assert_true(mounted.set_theme(Some(theme)))
    let themed = render(mounted)
    assert_eq(themed.theme(), Some(theme))
    assert_eq(themed.binding_id(key()), legacy.binding_id(key()))
    match theme {
      @theme.Light =>
        assert_true(
          themed.snapshot().canonical_json() !=
          legacy.snapshot().canonical_json(),
        )
      @theme.Dark =>
        assert_eq(
          themed.snapshot().canonical_json(),
          legacy.snapshot().canonical_json(),
        )
    }
  }
  assert_true(mounted.set_theme(None))
  let restored = render(mounted)
  assert_eq(
    restored.snapshot().canonical_json(),
    legacy.snapshot().canonical_json(),
  )
  assert_eq(restored.binding_id(key()), legacy.binding_id(key()))
  let rejected = Ref(false)
  let frame = mounted
    .commit(button_view(), 640.0, 480.0, 1.0, (text, size) => {
      rejected.val = !mounted.set_theme(Some(@theme.Dark))
      measure(text, size)
    })
    .unwrap()
  assert_true(rejected.val)
  assert_eq(mounted.theme(), None)
  assert_eq(frame.theme(), None)
  mounted.dispose()
  assert_true(!mounted.set_theme(Some(@theme.Light)))
  assert_eq(mounted.theme(), None)
  assert_true(mounted.frame() is None)
}

///|
test "per-Button palette overrides root theme and removing it resumes fallback without replacing held input" {
  let mounted = @ui.Mounted::new(
    @platform.WindowId::new(1L),
    theme=Some(@theme.Dark),
  )
  let explicit = @view.NodeKey::new("explicit")
  let inherited = @view.NodeKey::new("inherited")
  let light = @theme.Light.button_colors()
  let dark = @theme.Dark.button_colors()
  let view = theme_override_view(Some(@view.Light))
  let first = render(mounted, view~)
  let callback = mounted.callback(explicit).unwrap()
  assert_eq(first.theme(), Some(@theme.Dark))
  assert_eq(first.button_palette(explicit), Some(@view.Light))
  assert_eq(first.button_palette(inherited), None)
  assert_button_theme_colors(
    first,
    explicit,
    light.normal_border,
    light.normal_fill,
    light.enabled_foreground,
  )
  assert_button_theme_colors(
    first,
    inherited,
    dark.normal_border,
    dark.normal_fill,
    dark.enabled_foreground,
  )
  assert_true(mounted.focus(explicit))
  ignore(mounted.handle_event(event(1L, key_down(@primitives.Space))).unwrap())
  let held = render(mounted, view~)
  let explicit_id = first.binding_id(explicit).unwrap()
  assert_true(held.pressed(explicit))
  assert_true(held.focused(explicit))
  assert_true(mounted.set_theme(Some(@theme.Light)))
  let light_root = render(mounted, view~)
  assert_eq(light_root.theme(), Some(@theme.Light))
  assert_button_theme_colors(
    light_root,
    inherited,
    light.normal_border,
    light.normal_fill,
    light.enabled_foreground,
  )
  for offset in [1UL, 2UL, 3UL] {
    assert_true(
      theme_item_color(light_root, explicit_id + offset) ==
      theme_item_color(held, explicit_id + offset),
    )
  }
  assert_true(mounted.set_theme(None))
  let no_root_theme = render(mounted, view~)
  assert_eq(no_root_theme.theme(), None)
  assert_eq(no_root_theme.button_palette(explicit), Some(@view.Light))
  assert_button_theme_colors(
    no_root_theme,
    explicit,
    light.focused_border,
    light.pressed_fill,
    light.enabled_foreground,
  )
  assert_button_theme_colors(
    no_root_theme,
    inherited,
    dark.normal_border,
    dark.normal_fill,
    dark.enabled_foreground,
  )
  assert_true(mounted.set_theme(Some(@theme.Dark)))
  let removed = render(mounted, view=theme_override_view(None))
  assert_eq(removed.theme(), Some(@theme.Dark))
  assert_eq(removed.button_palette(explicit), None)
  assert_button_theme_colors(
    removed,
    explicit,
    dark.focused_border,
    dark.pressed_fill,
    dark.enabled_foreground,
  )
  for frame in [light_root, no_root_theme, removed] {
    assert_eq(frame.binding_id(explicit), first.binding_id(explicit))
    assert_eq(frame.binding_id(inherited), first.binding_id(inherited))
    assert_true(frame.bounds(explicit) == first.bounds(explicit))
    assert_true(frame.label_bounds(explicit) == first.label_bounds(explicit))
    assert_true(frame.focused(explicit))
    assert_true(frame.pressed(explicit))
    assert_true(frame.enabled(explicit))
    assert_true(!frame.loading(explicit))
  }
  assert_true(mounted.set_theme(None))
  let legacy = render(mounted, view=theme_override_view(None))
  assert_eq(legacy.theme(), None)
  assert_eq(legacy.button_palette(explicit), None)
  assert_eq(
    legacy.snapshot().canonical_json(),
    removed.snapshot().canonical_json(),
  )
  assert_eq(mounted.last_dispatched_input_sequence(), 1L)
  assert_true(mounted.activate(callback))
  assert_eq(mounted.next_action(), Some(@view.Activate(explicit)))
  assert_eq(mounted.next_action(), None)
  ignore(mounted.handle_event(event(2L, key_up(@primitives.Space))).unwrap())
  assert_eq(mounted.last_dispatched_input_sequence(), 2L)
  assert_eq(mounted.next_action(), Some(@view.Activate(explicit)))
  assert_eq(mounted.next_action(), None)
}
