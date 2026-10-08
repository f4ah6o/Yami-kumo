///|
test "resize drops input routing until its stale pending frame is completed and relaid out" {
  let gate = PresentationGate::{ rendered: false, pending_stale: false, }
  gate.mark_presented()
  assert_true(gate.input_ready())

  gate.invalidate_layout(true)
  assert_true(!gate.input_ready())
  assert_true(!gate.completed_frame_is_current())
  assert_true(!gate.input_ready())

  gate.mark_presented()
  assert_true(gate.input_ready())
  assert_true(gate.completed_frame_is_current())
}
