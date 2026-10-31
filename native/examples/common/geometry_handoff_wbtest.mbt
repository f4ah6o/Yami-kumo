///|
fn geometry_handoff_owner() -> (SettingsRunOwner, @testing.ScriptedBackend, UInt64) {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port)).unwrap()
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, text_runner_measure).unwrap())
  ignore(owner.mounted.focus(@shared_settings.settings_name()))
  let binding = owner.mounted.focused_text().unwrap().binding_id()
  owner.session = Some({ epoch: 7UL, binding })
  owner.host_epoch = Some(7UL)
  owner.host_epoch_verified = true
  owner.terminal_owner = Some(owner.mounted.capture_terminal_text_owner(7UL).unwrap())
  owner.entered_target = Some((7, 11L, 4))
  owner.suspended = true
  owner.dirty = true
  ignore(owner.stage_dirty_scene())
  ignore(owner.attempt_staged_host_geometry(fn(_, _) { Err(runner_error("fixture", "uncertain")) }))
  (owner, host, binding)
}

///|
test "geometry handoff reserves exact text before callback and never applies it" {
  let (owner, host, binding) = geometry_handoff_owner()
  let calls = Ref(0)
  let reentry_blocked = Ref(false)
  let event = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Commit(text="日本"))
  let receipt = NativeRetainedReceipt::new(Some(OrderedText(event)), owner.window, 1, binding, 7UL, fn() {
    calls.val += 1
    reentry_blocked.val = owner.transfer_geometry_arrival() is Err(_)
    Ok(())
  })
  owner.reserve_geometry_arrival(receipt, (7, 11L, 4)).unwrap()
  assert_true(owner.reserve_geometry_arrival(receipt, (7, 11L, 4)) is Err(_))
  assert_true(owner.attempt_staged_host_geometry(fn(_, _) { Ok(()) }) is Err(_))
  assert_eq(calls.val, 0)
  owner.transfer_geometry_arrival().unwrap()
  assert_true(reentry_blocked.val)
  assert_eq(calls.val, 1)
  assert_true(owner.geometry_arrival.unwrap().state is GeometryArrivalCallbackSucceeded)
  assert_true(owner.transfer_geometry_arrival() is Err(_))
  assert_eq(calls.val, 1)
  owner.entered_target = Some((8, 11L, 4))
  assert_true(owner.attempt_staged_host_geometry(fn(_, _) { Ok(()) }) is Err(_))
  assert_true(owner.geometry_arrival.unwrap().state is GeometryArrivalCallbackSucceeded)
  owner.entered_target = Some((7, 11L, 4)) // Whitebox only; not native owner proof.
  assert_eq(owner.model().name(), "")
  assert_eq(owner.mounted.focused_text().unwrap().document().text(), "")
  assert_true(owner.pending_dirty_stage is Some(_))
  assert_true(owner.try_terminal_text_cutoff() is Err(_))
  assert_false(owner.can_stop())
  assert_eq(host.present_count(), 0)
}

///|
test "geometry handoff failure remains uncertain and unsupported events stay at host" {
  let (owner, _, binding) = geometry_handoff_owner()
  let calls = Ref(0)
  let event = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Commit(text="日本"))
  let wrong = NativeRetainedReceipt::new(None, owner.window, 1, binding, 7UL, fn() { calls.val += 1; Ok(()) })
  assert_true(owner.reserve_geometry_arrival(wrong, (7, 11L, 4)) is Err(_))
  let skipped_event = @text_host.TextInputEvent::new(owner.window, 2L, 7UL, @text_host.Commit(text="後"))
  let skipped = NativeRetainedReceipt::new(Some(OrderedText(skipped_event)), owner.window, 2, binding, 7UL, fn() { calls.val += 1; Ok(()) })
  assert_true(owner.reserve_geometry_arrival(skipped, (7, 11L, 4)) is Err(_))
  let receipt = NativeRetainedReceipt::new(Some(OrderedText(event)), owner.window, 1, binding, 7UL, fn() {
    calls.val += 1
    Err(runner_error("fixture", "ack outcome unknown"))
  })
  assert_true(owner.reserve_geometry_arrival(receipt, (8, 11L, 4)) is Err(_))
  owner.reserve_geometry_arrival(receipt, (7, 11L, 4)).unwrap()
  assert_true(owner.transfer_geometry_arrival() is Err(_))
  assert_true(owner.geometry_arrival.unwrap().state is GeometryArrivalAttempted)
  assert_true(owner.attempt_staged_host_geometry(fn(_, _) { Ok(()) }) is Err(_))
  assert_true(owner.transfer_geometry_arrival() is Err(_))
  assert_eq(calls.val, 1)
  let queries = Ref(0)
  assert_true(owner.reconcile_geometry_arrival(fn() {
    queries.val += 1
    Err(runner_error("fixture", "route slot unavailable"))
  }) is Err(_))
  assert_true(owner.geometry_arrival.unwrap().state is GeometryArrivalAttempted)
  owner.reconcile_geometry_arrival(fn() { queries.val += 1; Ok(()) }).unwrap()
  assert_eq(queries.val, 2)
  assert_true(owner.geometry_arrival.unwrap().state is GeometryArrivalCallbackSucceeded)
  assert_true(owner.reconcile_geometry_arrival(fn() { Ok(()) }) is Err(_))
  assert_eq(calls.val, 1)
  assert_false(owner.host_epoch_verified())
  assert_eq(owner.model().name(), "")
  assert_true(owner.pending_dirty_stage is Some(_))
}

///|
test "owner loss during callback retains the attempted original receipt" {
  let (owner, _, binding) = geometry_handoff_owner()
  let event = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Commit(text="日本"))
  let receipt = NativeRetainedReceipt::new(Some(OrderedText(event)), owner.window, 1, binding, 7UL, fn() {
    owner.mounted.dispose()
    Err(runner_error("fixture", "native outcome unknown"))
  })
  owner.reserve_geometry_arrival(receipt, (7, 11L, 4)).unwrap()
  assert_true(owner.transfer_geometry_arrival() is Err(_))
  assert_true(owner.geometry_arrival.unwrap().state is GeometryArrivalAttempted)
  assert_true(owner.geometry_arrival.unwrap().receipt.event is Some(OrderedText(_)))
  assert_true(owner.reconcile_geometry_arrival(fn() { Ok(()) }) is Err(_))
  assert_true(owner.transfer_geometry_arrival() is Err(_))
  assert_true(owner.pending_dirty_stage is Some(_))
  assert_eq(owner.model().name(), "")
  assert_false(owner.can_stop())
}

///|
test "handoff preserves active preedit and the later commit as separate stages" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port)).unwrap()
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, text_runner_measure).unwrap())
  assert_true(owner.mounted.focus(@shared_settings.settings_name()))
  let binding = owner.mounted.focused_text().unwrap().binding_id()
  owner.session = Some({ epoch: 7UL, binding })
  owner.host_epoch = Some(7UL)
  owner.host_epoch_verified = true
  owner.terminal_owner = Some(owner.mounted.capture_terminal_text_owner(7UL).unwrap())
  owner.entered_target = Some((7, 11L, 4))
  // Host sequence 1 is a platform record. Portable text numbering starts at 1
  // independently when the preedit is admitted at native sequence 2.
  let platform = @platform.Event::new(owner.window, 1L, 1.0, @platform.FocusChanged(true))
  let first = NativeRetainedReceipt::new(Some(OrderedPlatform(platform)), owner.window, 1, binding, 7UL, fn() { Ok(()) })
  owner.acknowledged_receipts.push({ receipt: first, stage: ReceiptPlatformHandled })
  let preedit = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Preedit(text="にほん", cursor=3))
  owner.deliver_owned_observation(preedit).unwrap()
  let prior = NativeRetainedReceipt::new(Some(OrderedText(preedit)), owner.window, 2, binding, 7UL, fn() { Ok(()) })
  owner.acknowledged_receipts.push({ receipt: prior, stage: ReceiptNoModelAction })
  owner.suspended = true
  owner.dirty = true
  owner.stage_dirty_scene().unwrap()
  assert_true(owner.attempt_staged_host_geometry(fn(_, _) { Err(runner_error("fixture", "uncertain")) }) is Err(_))
  let commit = @text_host.TextInputEvent::new(owner.window, 2L, 7UL, @text_host.Commit(text="日本"))
  let stale = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Commit(text="古"))
  let stale_receipt = NativeRetainedReceipt::new(Some(OrderedText(stale)), owner.window, 3, binding, 7UL, fn() { Ok(()) })
  assert_true(owner.reserve_geometry_arrival(stale_receipt, (7, 11L, 4)) is Err(_))
  let skipped = @text_host.TextInputEvent::new(owner.window, 3L, 7UL, @text_host.Commit(text="先"))
  let skipped_receipt = NativeRetainedReceipt::new(Some(OrderedText(skipped)), owner.window, 3, binding, 7UL, fn() { Ok(()) })
  assert_true(owner.reserve_geometry_arrival(skipped_receipt, (7, 11L, 4)) is Err(_))
  let replay = NativeRetainedReceipt::new(Some(OrderedText(commit)), owner.window, 2, binding, 7UL, fn() { Ok(()) })
  assert_true(owner.reserve_geometry_arrival(replay, (7, 11L, 4)) is Err(_))
  let next = NativeRetainedReceipt::new(Some(OrderedText(commit)), owner.window, 3, binding, 7UL, fn() { Ok(()) })
  owner.reserve_geometry_arrival(next, (7, 11L, 4)).unwrap()
  owner.transfer_geometry_arrival().unwrap()
  assert_true(owner.mounted.focused_text().unwrap().composing())
  assert_eq(owner.mounted.focused_text().unwrap().document().text(), "")
  assert_eq(owner.model().name(), "")
  match owner.geometry_arrival.unwrap().receipt.event {
    Some(OrderedText(value)) => assert_true(value.kind() is @text_host.Commit(text="日本"))
    _ => fail("original commit must remain available")
  }
  assert_true(owner.pending_dirty_stage is Some(_))
  assert_true(owner.try_terminal_text_cutoff() is Err(_))
}

///|
test "reentrant owner loss during slot query does not release the receipt" {
  let (owner, _, binding) = geometry_handoff_owner()
  let event = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Commit(text="日本"))
  let receipt = NativeRetainedReceipt::new(Some(OrderedText(event)), owner.window, 1, binding, 7UL, fn() {
    Err(runner_error("fixture", "native outcome unknown"))
  })
  owner.reserve_geometry_arrival(receipt, (7, 11L, 4)).unwrap()
  assert_true(owner.transfer_geometry_arrival() is Err(_))
  assert_true(owner.reconcile_geometry_arrival(fn() {
    owner.mounted.dispose()
    Ok(())
  }) is Err(_))
  assert_true(owner.geometry_arrival.unwrap().state is GeometryArrivalAttempted)
  assert_true(owner.geometry_arrival.unwrap().receipt.event is Some(OrderedText(_)))
  assert_true(owner.pending_dirty_stage is Some(_))
  assert_false(owner.can_stop())
}

///|
test "preapply inspection retains original owner and is not an application" {
  let (owner, _, binding) = geometry_handoff_owner()
  let event = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Commit(text="日本"))
  let receipt = NativeRetainedReceipt::new(Some(OrderedText(event)), owner.window, 1, binding, 7UL, fn() { Ok(()) })
  owner.reserve_geometry_arrival(receipt, (7, 11L, 4)).unwrap()
  assert_true(owner.inspect_geometry_arrival_before_apply() is Err(_))
  owner.transfer_geometry_arrival().unwrap()
  assert_true(owner.inspect_geometry_arrival_before_apply() is Err(_))
  owner.attempt_staged_host_geometry(fn(_, _) { Ok(()) }).unwrap()
  owner.inspect_geometry_arrival_before_apply().unwrap()
  owner.inspect_geometry_arrival_before_apply().unwrap()
  assert_true(owner.geometry_arrival_state() is Some((1, 2)))
  assert_eq(owner.model().name(), "")
  assert_true(owner.pending_dirty_stage is Some(_))
  assert_false(owner.host_epoch_verified())
  assert_true(owner.drive() is Err(_))
  assert_false(owner.can_stop())
  owner.entered_target = Some((8, 11L, 4))
  assert_true(owner.inspect_geometry_arrival_before_apply() is Err(_))
  assert_true(owner.geometry_arrival_state() is Some((1, 2)))
  assert_eq(owner.model().name(), "")
}
