///|
test "settings presents frames and releases a failed portable session before fallback" {
  let host = @testing.ScriptedBackend::new(800.0, 600.0, 1.5).unwrap()
  for _ in 0..<6 {
    ignore(host.enqueue(@platform.FrameCompleted, 1.5))
  }
  ignore(host.enqueue(@platform.Destroyed, 1.5))
  let ended = Ref(false)
  let armed = Ref(false)
  let released_before_fallback = Ref(false)
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) },
    fn(_, _) {
      Err(runner_error("test_update", "transport unavailable"))
    },
    fn(epoch) { Ok(epoch) },
    fn(_) {
      ended.val = true
      Ok(())
    },
    fn(_) { Ok(None) },
  )
  let direct : NativeDirectText = fn(_, enabled) {
    if enabled {
      released_before_fallback.val = ended.val
    }
    armed.val = enabled
    Ok(())
  }
  run_native_settings_sample(
    host,
    Linux,
    text_runner_measure,
    text_port=Some(port),
    direct_text=Some(direct),
    next_platform_event=Some(fn(timeout) {
      ignore(host.set_metrics(800.0, 600.0, 1.5))
      host.next_event(timeout_ms=timeout)
    }),
  ).unwrap()
  assert_true(released_before_fallback.val)
  assert_true(ended.val)
  assert_true(!armed.val)
  assert_true(host.present_count() >= 2)
  let snapshot = host.last_present().unwrap()
  assert_eq(snapshot.scale(), 1.5)
  assert_eq(snapshot.viewport().size().width(), 800.0)
  assert_eq(snapshot.viewport().size().height(), 600.0)
}
