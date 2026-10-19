///|
test "presentation gate discards one obsolete completion and waits for new geometry" {
  let gate = PresentationGate::{ rendered: true, pending_stale: false, }
  gate.invalidate(true)
  assert_false(gate.rendered)
  assert_false(gate.complete())
  assert_true(gate.complete())
  gate.rendered = true
  gate.changed(true)
  assert_true(gate.rendered)
  assert_false(gate.complete())
  assert_true(gate.complete())
}

///|
test "protocol JSON escaping preserves literals and control characters" {
  assert_eq(escape_json("a\"\\\n\t\u0001"), "a\\\"\\\\\\n\\t\\u0001")
}

///|
test "theme fixture controls use native navigation key-down only" {
  for
    (key, command) in [
      (@primitives.PageUp, "t"),
      (@primitives.PageDown, "c"),
      (@primitives.Home, "n"),
      (@primitives.End, "d"),
      (@primitives.ArrowUp, "l"),
      (@primitives.ArrowDown, "b"),
      (@primitives.ArrowLeft, "f"),
      (@primitives.ArrowRight, "arm-inside"),
      (@primitives.Delete, "arm-outside"),
    ] {
    assert_eq(
      theme_control_key(
        @primitives.KeyPressed(
          key~,
          modifiers=@primitives.Modifiers::none(),
          repeat=false,
        ),
      ),
      Some(command),
    )
    assert_eq(
      theme_control_key(
        @primitives.KeyPressed(
          key~,
          modifiers=@primitives.Modifiers::none(),
          repeat=true,
        ),
      ),
      None,
    )
    assert_eq(
      theme_control_key(
        @primitives.KeyReleased(key~, modifiers=@primitives.Modifiers::none()),
      ),
      None,
    )
  }
  for
    key in [
      @primitives.Space,
      @primitives.Enter,
      @primitives.Tab,
      @primitives.Character("c"),
    ] {
    assert_eq(
      theme_control_key(
        @primitives.KeyPressed(
          key~,
          modifiers=@primitives.Modifiers::none(),
          repeat=false,
        ),
      ),
      None,
    )
  }
}

///|
test "palette trace distinguishes successful unconsumed motion and replay" {
  let event = @platform.Event::new(
    @platform.WindowId::new(1L),
    7L,
    1.0,
    @platform.Input(
      @primitives.PointerMoved(
        position=@primitives.Point::new(12.0, 34.0).unwrap(),
      ),
    ),
  )
  assert_eq(
    palette_event_json(event, false, 5L, 7L),
    "{\"sequence\":7,\"scale\":1,\"consumed\":false,\"dispatched\":true,\"beforeDispatch\":5,\"afterDispatch\":7,\"kind\":\"move\",\"x\":12,\"y\":34}",
  )
  assert_eq(
    palette_event_json(event, false, 7L, 7L),
    "{\"sequence\":7,\"scale\":1,\"consumed\":false,\"dispatched\":false,\"beforeDispatch\":7,\"afterDispatch\":7,\"kind\":\"move\",\"x\":12,\"y\":34}",
  )
}

///|
fn pointer_test_event(
  window : Int64,
  sequence : Int64,
  scale : Double,
  x : Double,
  y : Double,
) -> @platform.Event {
  @platform.Event::new(
    @platform.WindowId::new(window),
    sequence,
    scale,
    @platform.Input(
      @primitives.PointerMoved(position=@primitives.Point::new(x, y).unwrap()),
    ),
  )
}

///|
test "theme pointer receipt requires fresh owned dispatched motion at the armed target" {
  let pointer = ThemePointerReceipt::new(@platform.WindowId::new(1L))
  let arm = pointer_test_event(1L, 10L, 1.0, 0.0, 0.0)
  assert_true(
    pointer.observe(pointer_test_event(1L, 11L, 1.0, 75.0, 54.0), 9L, 11L)
    is None,
  )
  assert_true(pointer.arm(arm, 1, 75.0, 54.0))
  assert_false(pointer.arm(arm, 1, 75.0, 54.0))
  for
    (event, before, after) in [
      (pointer_test_event(1L, 10L, 1.0, 75.0, 54.0), 9L, 10L),
      (pointer_test_event(2L, 11L, 1.0, 75.0, 54.0), 9L, 11L),
      (pointer_test_event(1L, 11L, 2.0, 75.0, 54.0), 9L, 11L),
      (pointer_test_event(1L, 11L, 1.0, 80.0, 54.0), 9L, 11L),
      (pointer_test_event(1L, 11L, 1.0, 75.0, 60.0), 9L, 11L),
      (pointer_test_event(1L, 11L, 1.0, 75.0, 54.0), 11L, 11L),
    (pointer_test_event(1L, 11L, 1.0, 75.0, 54.0), 12L, 11L),
      (pointer_test_event(1L, 11L, 1.0, 75.0, 54.0), 9L, 10L),
    ] {
    assert_true(pointer.observe(event, before, after) is None)
    assert_true(pointer.waiting)
  }
  assert_eq(
    pointer.observe(pointer_test_event(1L, 12L, 1.0, 75.0, 54.0), 11L, 12L),
    Some(
      "{\"request\":1,\"phase\":1,\"windowId\":1,\"armSequence\":10,\"scale\":1,\"sequence\":12,\"dispatchedSequence\":12,\"x\":75,\"y\":54}",
    ),
  )
  assert_false(pointer.waiting)
  assert_true(
    pointer.observe(pointer_test_event(1L, 13L, 1.0, 75.0, 54.0), 12L, 13L)
    is None,
  )
  // A repeated same-position operation has a new request and needs new motion.
  assert_true(
    pointer.arm(pointer_test_event(1L, 20L, 1.0, 0.0, 0.0), 2, 75.0, 54.0),
  )
  assert_eq(pointer.request, 2)
  assert_true(
    pointer.observe(pointer_test_event(1L, 12L, 1.0, 75.0, 54.0), 11L, 12L)
    is None,
  )
  assert_true(pointer.waiting)
  assert_true(
    pointer.observe(pointer_test_event(1L, 21L, 1.0, 75.0, 54.0), 20L, 21L)
    is Some(_),
  )
}
