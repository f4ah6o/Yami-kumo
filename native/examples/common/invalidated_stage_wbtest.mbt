///|
test "bounded staging remeasures original preedit after resize invalidation" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let updates = Ref(0)
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { updates.val += 1; Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port)).unwrap()
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, text_runner_measure).unwrap())
  assert_true(owner.mounted.focus(@shared_settings.settings_name()))
  let binding = owner.mounted.focused_text().unwrap().binding_id()
  owner.session = Some({ epoch: 7UL, binding })
  owner.host_epoch = Some(7UL)
  owner.host_epoch_verified = true
  let lease = owner.mounted.capture_terminal_text_owner(7UL).unwrap()
  owner.terminal_owner = Some(lease)
  let preedit = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Preedit(text="にほん", cursor=3))
  owner.deliver_owned_observation(preedit).unwrap()
  owner.mounted.invalidate_layout()
  owner.gate.invalidate_layout(false)
  owner.dirty = true
  owner.suspended = true
  host.set_metrics(800.0, 480.0, 1.5).unwrap()
  assert_false(owner.mounted.terminal_owner_is_current(lease))
  owner.stage_dirty_scene().unwrap()
  let staged = owner.staged_dirty_geometry().unwrap()
  assert_true(staged.composing())
  assert_eq(staged.preview().text(), "にほん")
  assert_eq(staged.committed().text(), "")
  assert_true(staged.identity() is (_, 7UL, id, _) && id == binding)
  assert_eq(owner.model().name(), "")
  assert_eq(updates.val, 0)
  assert_eq(host.present_count(), 0)
  owner.mounted.invalidate_layout()
  assert_true(owner.staged_dirty_geometry() is Err(_))
  owner.discard_staged_dirty_scene().unwrap()
  owner.stage_dirty_scene().unwrap()
  assert_eq(owner.staged_dirty_geometry().unwrap().preview().text(), "にほん")
  owner.discard_staged_dirty_scene().unwrap()
  assert_true(owner.terminal_owner is Some(_))
  assert_false(owner.can_stop())
  assert_eq(updates.val, 0)
  assert_eq(host.present_count(), 0)
}

///|
test "reentrant invalidation is not promoted to a safe resize stage" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let owner_ref : Ref[SettingsRunOwner?] = Ref(None)
  let trigger = Ref(false)
  let measure = fn(value, size) {
    if trigger.val {
      trigger.val = false
      match owner_ref.val { Some(owner) => owner.mounted.invalidate_layout(); None => () }
    }
    text_runner_measure(value, size)
  }
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, measure, text_port=Some(port)).unwrap()
  owner_ref.val = Some(owner)
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, measure).unwrap())
  assert_true(owner.mounted.focus(@shared_settings.settings_name()))
  let binding = owner.mounted.focused_text().unwrap().binding_id()
  owner.session = Some({ epoch: 7UL, binding })
  owner.host_epoch = Some(7UL)
  owner.host_epoch_verified = true
  owner.terminal_owner = Some(owner.mounted.capture_terminal_text_owner(7UL).unwrap())
  owner.suspended = true
  owner.dirty = true
  trigger.val = true
  assert_true(owner.stage_dirty_scene() is Err(_))
  assert_true(owner.pending_dirty_stage is None)
  assert_true(owner.stage_dirty_scene() is Err(_))
  assert_true(owner.terminal_owner is Some(_))
  assert_true(owner.session is Some(current) && current.epoch == 7UL && current.binding == binding)
  assert_true(owner.host_epoch is Some(7UL))
  assert_true(owner.host_epoch_verified)
  assert_false(owner.mounted.has_pending_actions())
  assert_eq(owner.model().name(), "")
  assert_eq(host.present_count(), 0)
  assert_eq(host.stop_count(), 0)
  assert_false(owner.can_stop())
}
