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

///|
test "native error details include the framework message" {
  let error = @diagnostics.FrameworkError::new(
    @diagnostics.NativeFailure,
    "run_native_loop",
    message="native sample timed out before closing",
  )
  assert_eq(
    format_framework_error(error),
    "run_native_loop: native_failure: native sample timed out before closing",
  )
}
