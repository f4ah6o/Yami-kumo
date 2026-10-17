///|
fn theme_frame(app : @shared_counter.NativeTheme) -> @shared_counter.ThemeFrame {
  app.render(640.0, 480.0, 1.0, measure).unwrap()
}

///|
fn theme_drain(app : @shared_counter.NativeTheme) -> Bool {
  app.drain_one(640.0, 480.0, 1.0, measure).unwrap()
}

///|
test "common theme fixture preserves one keyed GPUI press across App theme commits" {
  let app = @shared_counter.NativeTheme::new(@platform.WindowId::new(1L)).unwrap()
  let first = theme_frame(app)
  let key = @view.NodeKey::new("increment")
  let id = first.frame().binding_id(key)
  let bounds = first.frame().bounds(key).unwrap()
  ignore(app.handle_event(event(1L, down(bounds))))
  let held = theme_frame(app)
  assert_true(held.frame().pressed(key))
  assert_true(held.frame().focused(key))
  assert_true(app.control("t", 640.0, 480.0, 1.0, measure).unwrap())
  let switched = theme_frame(app)
  assert_eq(switched.frame().binding_id(key), id)
  assert_true(switched.frame().pressed(key))
  assert_true(switched.frame().focused(key))
  assert_eq(switched.model().theme().name(), "dark")
  assert_eq(switched.model().value(), 0)
  ignore(app.handle_event(event(2L, up(bounds))))
  assert_true(theme_drain(app))
  assert_false(theme_drain(app))
  assert_eq(theme_frame(app).model().value(), 1)
  assert_eq(theme_frame(app).action_keys(), ["increment"])
  app.dispose()
}

///|
test "common theme fixture retains Space across theme and rejects stale gated releases" {
  let app = @shared_counter.NativeTheme::new(@platform.WindowId::new(1L)).unwrap()
  ignore(theme_frame(app))
  let key = @view.NodeKey::new("increment")
  assert_true(app.control("f", 640.0, 480.0, 1.0, measure).unwrap())
  ignore(app.handle_event(event(1L, key_down(@primitives.Space))))
  assert_true(theme_frame(app).frame().pressed(key))
  assert_true(app.control("t", 640.0, 480.0, 1.0, measure).unwrap())
  assert_true(theme_frame(app).frame().pressed(key))
  ignore(app.handle_event(event(2L, key_up(@primitives.Space))))
  assert_true(theme_drain(app))
  assert_eq(theme_frame(app).model().value(), 1)
  ignore(app.handle_event(event(3L, key_down(@primitives.Space))))
  assert_true(app.control("l", 640.0, 480.0, 1.0, measure).unwrap())
  assert_true(app.control("t", 640.0, 480.0, 1.0, measure).unwrap())
  assert_true(app.control("n", 640.0, 480.0, 1.0, measure).unwrap())
  ignore(app.handle_event(event(4L, key_up(@primitives.Space))))
  assert_false(theme_drain(app))
  assert_eq(theme_frame(app).model().value(), 1)
  assert_true(theme_frame(app).frame().focused(key))
  let bounds = theme_frame(app).frame().bounds(key).unwrap()
  ignore(app.handle_event(event(5L, down(bounds))))
  assert_true(app.control("d", 640.0, 480.0, 1.0, measure).unwrap())
  assert_true(app.control("t", 640.0, 480.0, 1.0, measure).unwrap())
  assert_true(app.control("n", 640.0, 480.0, 1.0, measure).unwrap())
  ignore(app.handle_event(event(6L, up(bounds))))
  assert_false(theme_drain(app))
  assert_false(theme_frame(app).frame().focused(key))
  assert_eq(theme_frame(app).model().value(), 1)
  ignore(app.handle_event(event(7L, down(bounds))))
  ignore(app.handle_event(event(8L, up(bounds))))
  assert_true(theme_drain(app))
  assert_eq(theme_frame(app).model().value(), 2)
  app.dispose()
}

///|
test "failed theme fixture paint leaves App model accepted theme focus and input live" {
  let app = @shared_counter.NativeTheme::new(@platform.WindowId::new(1L)).unwrap()
  let first = theme_frame(app)
  let key = @view.NodeKey::new("increment")
  let bounds = first.frame().bounds(key).unwrap()
  ignore(app.handle_event(event(1L, down(bounds))))
  let held = theme_frame(app)
  assert_true(app.control("t", 640.0, 480.0, 1.0, failed_measure) is Err(_))
  let restored = theme_frame(app)
  assert_eq(restored.model(), first.model())
  assert_eq(restored.frame().theme(), held.frame().theme())
  assert_eq(restored.frame().binding_id(key), first.frame().binding_id(key))
  assert_true(restored.frame().pressed(key))
  assert_true(restored.frame().focused(key))
  ignore(app.handle_event(event(2L, up(bounds))))
  assert_true(theme_drain(app))
  assert_eq(theme_frame(app).model().value(), 1)
  app.dispose()
}

///|
test "actual theme-toggle semantic action uses the same common model update" {
  let app = @shared_counter.NativeTheme::new(@platform.WindowId::new(1L)).unwrap()
  let first = theme_frame(app)
  let toggle = @view.NodeKey::new("theme-toggle")
  let bounds = first.frame().bounds(toggle).unwrap()
  ignore(app.handle_event(event(1L, down(bounds))))
  ignore(app.handle_event(event(2L, up(bounds))))
  assert_true(theme_drain(app))
  let next = theme_frame(app)
  assert_eq(next.model().theme().name(), "dark")
  assert_eq(next.model().value(), 0)
  assert_eq(next.frame().binding_id(toggle), first.frame().binding_id(toggle))
  assert_eq(next.action_keys(), ["theme-toggle"])
  app.dispose()
}
