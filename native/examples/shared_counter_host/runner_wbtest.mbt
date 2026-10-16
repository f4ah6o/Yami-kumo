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
