///|
/// Characterizes one possible ordering behind a live refusal. This synthetic
/// setup does not assert that the uninstrumented live run had these flags.
test "frame continuation need not make a later queued preedit dirty" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let head : Ref[NativeRetainedReceipt?] = Ref(None)
  let ordered = NativeOrderedTextPort::with_retained_receipts(fn(_) { Ok(head.val) }, fn(_) { Ok(()) })
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port), ordered_text=Some(ordered)).unwrap()
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, text_runner_measure).unwrap())
  assert_true(owner.mounted.focus(@shared_settings.settings_name()))
  let binding = owner.mounted.focused_text().unwrap().binding_id()
  owner.session = Some({ epoch: 7UL, binding })
  owner.host_epoch = Some(7UL)
  owner.host_epoch_verified = true
  let lease = owner.mounted.capture_terminal_text_owner(7UL).unwrap()
  owner.terminal_owner = Some(lease)
  let first = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Preedit(text="ｎ", cursor=1))
  owner.deliver_owned_observation(first).unwrap()
  // Characterize a frame already submitted for the first preedit. This setup
  // is deliberate whitebox state, not evidence of the actual live flags.
  owner.dirty = false
  owner.pending_frame = Some("fixture frame")
  owner.gate.rendered = true
  owner.suspended = true
  owner.live_step_ready = true
  owner.live_step_generation = 1L
  let frame = @platform.Event::new(owner.window, 2L, 1.0, @platform.FrameCompleted)
  head.val = Some(NativeRetainedReceipt::new(Some(OrderedPlatform(frame)), owner.window, 2, binding, 7UL, fn() { head.val = None; Ok(()) }))
  assert_true(owner.advance_once(1L).unwrap() is ContinuationStepped)
  assert_false(owner.dirty)
  assert_true(owner.pending_frame is None)
  assert_true(owner.pending_dirty_stage is None)
  assert_true(owner.stage_dirty_scene() is Err(_))
  assert_true(owner.mounted.terminal_owner_is_current(lease))
  assert_true(owner.mounted.focused_text().unwrap().composing())
  assert_eq(owner.model().name(), "")
  let next = @text_host.TextInputEvent::new(owner.window, 2L, 7UL, @text_host.Preedit(text="に", cursor=1))
  head.val = Some(NativeRetainedReceipt::new(Some(OrderedText(next)), owner.window, 3, binding, 7UL, fn() { head.val = None; Ok(()) }))
  assert_true(owner.advance_once(2L).unwrap() is ContinuationStepped)
  assert_true(owner.dirty)
  owner.stage_dirty_scene().unwrap()
  assert_eq(owner.staged_dirty_geometry().unwrap().preview().text(), "に")
  assert_eq(owner.model().name(), "")
  assert_false(owner.can_stop())
}
