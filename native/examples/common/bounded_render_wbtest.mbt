///|
test "bounded IME steps apply preedit and commit without presenting a frame" {
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
  owner.terminal_owner = Some(owner.mounted.capture_terminal_text_owner(7UL).unwrap())
  owner.gate.rendered = true
  owner.suspended = true
  owner.live_step_ready = true
  owner.live_step_generation = 1L
  let preview = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Preedit(text="にほん", cursor=3))
  head.val = Some(NativeRetainedReceipt::new(Some(OrderedText(preview)), owner.window, 1, binding, 7UL, fn() { head.val = None; Ok(()) }))
  assert_true(owner.advance_once(1L).unwrap() is ContinuationStepped)
  assert_true(owner.mounted.focused_text().unwrap().composing())
  assert_eq(owner.model().name(), "")
  assert_eq(host.present_count(), 0)
  assert_true(owner.dirty)
  let commit = @text_host.TextInputEvent::new(owner.window, 2L, 7UL, @text_host.Commit(text="日本"))
  head.val = Some(NativeRetainedReceipt::new(Some(OrderedText(commit)), owner.window, 2, binding, 7UL, fn() { head.val = None; Ok(()) }))
  assert_true(owner.advance_once(2L).unwrap() is ContinuationStepped)
  assert_eq(owner.model().name(), "日本")
  assert_eq(owner.mounted.focused_text().unwrap().document().text(), "日本")
  assert_eq(owner.last_document, "")
  assert_eq(host.present_count(), 0)
  assert_true(owner.dirty)
  assert_true(owner.pending_frame is None)
  assert_false(owner.can_stop())
}
