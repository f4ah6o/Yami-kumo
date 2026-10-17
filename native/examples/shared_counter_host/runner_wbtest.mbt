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
