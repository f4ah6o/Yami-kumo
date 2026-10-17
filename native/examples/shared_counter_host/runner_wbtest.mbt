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
