///|
test "bounded dirty staging preserves preedit and blocks continuation until discarded" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let updates = Ref(0)
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { updates.val += 1; Ok(epoch) }, fn(epoch) { Ok(epoch) },
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
  owner.gate.rendered = true
  owner.suspended = true
  owner.live_step_ready = true
  owner.live_step_generation = 1L
  let preedit = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Preedit(text="にほん", cursor=3))
  head.val = Some(NativeRetainedReceipt::new(Some(OrderedText(preedit)), owner.window, 1, binding, 7UL, fn() { head.val = None; Ok(()) }))
  assert_true(owner.advance_once(1L).unwrap() is ContinuationStepped)
  assert_true(owner.dirty)
  owner.stage_dirty_scene().unwrap()
  let staged = owner.staged_dirty_geometry().unwrap()
  assert_true(staged.composing())
  assert_eq(staged.preview().text(), "にほん")
  assert_eq(staged.committed().text(), "")
  assert_true(owner.stage_dirty_scene() is Err(_))
  assert_true(owner.advance_generation() is None)
  assert_true(owner.terminal_step(PollOnce) is Err(_))
  // Simulate only the local consequence of an uncertain host update. This
  // does not exercise a native host or establish that it can be reconciled.
  owner.host_epoch_verified = false
  assert_true(owner.discard_staged_dirty_scene() is Err(_))
  assert_true(owner.staged_dirty_geometry() is Err(_))
  assert_true(owner.try_terminal_text_cutoff() is Err(_))
  assert_true(owner.pending_dirty_stage is Some(_))
  assert_true(owner.mounted.terminal_owner_is_current(lease))
  assert_true(owner.mounted.focused_text().unwrap().composing())
  assert_eq(owner.model().name(), "")
  assert_eq(updates.val, 0)
  assert_eq(host.present_count(), 0)
  // Whitebox restoration represents no host proof; it merely checks that
  // preservation of the candidate did not make local inspection impossible.
  owner.host_epoch_verified = true
  assert_eq(owner.staged_dirty_geometry().unwrap().preview().text(), "にほん")
  assert_eq(updates.val, 0)
  assert_eq(host.present_count(), 0)
  assert_true(owner.mounted.terminal_owner_is_current(lease))
  host.set_metrics(640.0, 480.0, 1.5).unwrap()
  assert_true(owner.staged_dirty_geometry() is Err(_))
  owner.discard_staged_dirty_scene().unwrap()
  assert_true(owner.advance_generation() is Some(2L))
  owner.stage_dirty_scene().unwrap()
  assert_eq(owner.staged_dirty_geometry().unwrap().preview().text(), "にほん")
  owner.discard_staged_dirty_scene().unwrap()
  assert_true(owner.mounted.focused_text().unwrap().composing())
  assert_eq(owner.model().name(), "")
  let commit = @text_host.TextInputEvent::new(owner.window, 2L, 7UL, @text_host.Commit(text="日本"))
  head.val = Some(NativeRetainedReceipt::new(Some(OrderedText(commit)), owner.window, 2, binding, 7UL, fn() { head.val = None; Ok(()) }))
  assert_true(owner.advance_once(2L).unwrap() is ContinuationStepped)
  assert_eq(owner.model().name(), "日本")
  owner.stage_dirty_scene().unwrap()
  let committed = owner.staged_dirty_geometry().unwrap()
  assert_false(committed.composing())
  assert_eq(committed.preview().text(), "日本")
  assert_eq(committed.committed().text(), "日本")
  owner.discard_staged_dirty_scene().unwrap()
  assert_eq(updates.val, 0)
  assert_eq(host.present_count(), 0)
  assert_false(owner.can_stop())
}

///|
test "bounded dirty stage measurement failure retains the original preedit" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let fail = Ref(false)
  let measure = fn(value, size) {
    if fail.val && value == "にほん" { Err(runner_error("fixture", "measurement failed")) }
    else { text_runner_measure(value, size) }
  }
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, measure, text_port=Some(port)).unwrap()
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, measure).unwrap())
  assert_true(owner.mounted.focus(@shared_settings.settings_name()))
  let binding = owner.mounted.focused_text().unwrap().binding_id()
  owner.session = Some({ epoch: 7UL, binding })
  owner.host_epoch = Some(7UL)
  owner.host_epoch_verified = true
  let lease = owner.mounted.capture_terminal_text_owner(7UL).unwrap()
  owner.terminal_owner = Some(lease)
  let preedit = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Preedit(text="にほん", cursor=3))
  owner.deliver_owned_observation(preedit).unwrap()
  owner.suspended = true
  owner.dirty = true
  fail.val = true
  assert_true(owner.stage_dirty_scene() is Err(_))
  assert_true(owner.pending_dirty_stage is None)
  assert_true(owner.mounted.focused_text().unwrap().composing())
  assert_true(owner.mounted.terminal_owner_is_current(lease))
  assert_eq(owner.model().name(), "")
  assert_eq(host.present_count(), 0)
  fail.val = false
  owner.stage_dirty_scene().unwrap()
  assert_eq(owner.staged_dirty_geometry().unwrap().preview().text(), "にほん")
  owner.discard_staged_dirty_scene().unwrap()
  assert_true(owner.mounted.focused_text().unwrap().composing())
}

///|
test "bounded dirty stage rejects metrics changed by its measurement callback" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let trigger = Ref(false)
  let measure = fn(value, size) {
    if trigger.val {
      trigger.val = false
      ignore(host.set_metrics(800.0, 480.0, 1.5))
    }
    text_runner_measure(value, size)
  }
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, measure, text_port=Some(port)).unwrap()
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, measure).unwrap())
  assert_true(owner.mounted.focus(@shared_settings.settings_name()))
  let binding = owner.mounted.focused_text().unwrap().binding_id()
  owner.session = Some({ epoch: 7UL, binding })
  owner.host_epoch = Some(7UL)
  owner.host_epoch_verified = true
  let lease = owner.mounted.capture_terminal_text_owner(7UL).unwrap()
  owner.terminal_owner = Some(lease)
  let preedit = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Preedit(text="にほん", cursor=3))
  owner.deliver_owned_observation(preedit).unwrap()
  owner.suspended = true
  owner.dirty = true
  trigger.val = true
  assert_true(owner.stage_dirty_scene() is Err(_))
  assert_true(owner.pending_dirty_stage is None)
  assert_true(owner.mounted.focused_text().unwrap().composing())
  assert_true(owner.mounted.terminal_owner_is_current(lease))
  assert_eq(owner.model().name(), "")
  assert_eq(host.present_count(), 0)
  owner.stage_dirty_scene().unwrap()
  assert_eq(owner.staged_dirty_geometry().unwrap().preview().text(), "にほん")
  owner.discard_staged_dirty_scene().unwrap()
}
