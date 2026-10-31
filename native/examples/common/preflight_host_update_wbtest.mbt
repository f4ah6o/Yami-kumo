///|
fn preflight_update_owner() -> (SettingsRunOwner, @testing.ScriptedBackend) {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let window = @platform.WindowId::new(1L)
  let pending : Array[NativeOrderedEvent] = [
    OrderedPlatform(@platform.Event::new(window, 1L, 1.0, @platform.FrameCompleted)),
    OrderedPlatform(@platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted)),
    OrderedText(@text_host.TextInputEvent::new(window, 1L, 7UL, @text_host.Preedit(text="にほん", cursor=3))),
    OrderedPlatform(@platform.Event::new(window, 3L, 1.0, @platform.FrameCompleted)),
  ]
  let updates = Ref(0)
  let ordered = NativeOrderedTextPort::new(
    fn(_) { Ok(if pending.is_empty() { None } else { Some(pending.remove(0)) }) },
    fn(_) { Ok(()) },
  )
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) },
    fn(_, _) { updates.val += 1; if updates.val == 1 { Ok(7UL) } else { Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "fixture_preflight")) } },
    fn(epoch) { Ok(epoch) }, fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = match run_native_settings_retained(host, Linux, text_runner_measure, text_port=Some(port), ordered_text=Some(ordered)) {
    Suspended(value, _) => value
    _ => abort("geometry update must suspend")
  }
  (owner, host)
}

///|
test "preflight retry retains original frame and preedit across Busy" {
  let (owner, host) = preflight_update_owner()
  assert_true(owner.pending_host_update is Some(_))
  let pending = owner.pending_host_update.unwrap()
  let progress = pending.owner.observed_progress()
  let before_present = host.present_count()
  assert_false(owner.host_epoch_verified())
  let attempts = Ref(0)
  let same = Ref(false)
  let retry = fn(window : @platform.WindowId, binding : UInt64, epoch : UInt64, state : @text_host.TextInputState) {
    attempts.val += 1
    same.val = window == pending.window && binding == pending.binding && epoch == pending.epoch &&
      state.document() == pending.state.document() && state.caret() == pending.state.caret()
    if attempts.val == 1 { Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "fifo")) } else { Ok(epoch) }
  }
  assert_true(owner.retry_captured_host_update(retry) is Err(_))
  assert_true(owner.pending_host_update is Some(_))
  assert_eq(pending.owner.observed_progress(), progress)
  assert_false(owner.host_epoch_verified())
  owner.retry_captured_host_update(retry).unwrap()
  assert_eq(attempts.val, 2)
  assert_true(same.val)
  assert_true(owner.host_epoch_verified())
  assert_true(owner.pending_host_update is None)
  assert_true(owner.dirty)
  assert_true(owner.mounted.focused_text().unwrap().composing())
  assert_eq(owner.model().name(), "")
  assert_true(owner.advance_generation() is None)
  assert_false(owner.can_stop())
  assert_eq(host.present_count(), before_present)
  assert_true(owner.retry_captured_host_update(retry) is Err(_))
  assert_eq(attempts.val, 2)
}

///|
test "preflight retry rejects a changed target before invoking native" {
  let (owner, _) = preflight_update_owner()
  assert_true(owner.pending_host_update is Some(_))
  let calls = Ref(0)
  owner.host_epoch = Some(8UL)
  assert_true(owner.retry_captured_host_update(fn(_, _, epoch, _) { calls.val += 1; Ok(epoch) }) is Err(_))
  assert_eq(calls.val, 0)
  assert_true(owner.pending_host_update is Some(_))
  assert_false(owner.host_epoch_verified())
}

///|
test "preflight retry rejects changed metrics and preserves accepted-but-stale result" {
  let (owner, host) = preflight_update_owner()
  let calls = Ref(0)
  host.set_metrics(800.0, 480.0, 1.5).unwrap()
  assert_true(owner.retry_captured_host_update(fn(_, _, epoch, _) { calls.val += 1; Ok(epoch) }) is Err(_))
  assert_eq(calls.val, 0)
  assert_true(owner.pending_host_update is Some(_))
  host.set_metrics(640.0, 480.0, 1.0).unwrap()
  assert_true(owner.retry_captured_host_update(fn(_, _, epoch, _) {
    calls.val += 1
    owner.mounted.dispose()
    Ok(epoch)
  }) is Err(_))
  assert_eq(calls.val, 1)
  assert_true(owner.pending_host_update is Some(_))
  assert_false(owner.host_epoch_verified())
  assert_true(owner.retry_captured_host_update(fn(_, _, epoch, _) { calls.val += 1; Ok(epoch) }) is Err(_))
  assert_eq(calls.val, 1)
  assert_false(owner.can_stop())
}
