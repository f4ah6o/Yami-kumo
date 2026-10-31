///|
/// Characterizes a blocked path; PASS does not mean resize recovery works.
test "metrics change after uncertain host update blocks same candidate retry" {
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
  let lease = owner.mounted.capture_terminal_text_owner(7UL).unwrap()
  owner.terminal_owner = Some(lease)
  let preedit = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Preedit(text="にほん", cursor=3))
  owner.deliver_owned_observation(preedit).unwrap()
  owner.suspended = true
  owner.dirty = true
  owner.stage_dirty_scene().unwrap()
  let calls = Ref(0)
  let callback = fn(retry, _) {
    calls.val += 1
    if retry { Ok(()) } else { Err(runner_error("fixture", "host result uncertain")) }
  }
  assert_true(owner.attempt_staged_host_geometry(callback) is Err(_))
  assert_eq(calls.val, 1)
  host.set_metrics(800.0, 600.0, 1.5).unwrap()
  assert_true(owner.attempt_staged_host_geometry(callback) is Err(_))
  assert_eq(calls.val, 1)
  assert_true(owner.pending_dirty_stage is Some(_))
  assert_true(owner.mounted.terminal_owner_is_current(lease))
  assert_true(owner.mounted.focused_text().unwrap().composing())
  assert_false(owner.host_epoch_verified())
  assert_true(owner.discard_staged_dirty_scene() is Err(_))
  assert_true(owner.try_terminal_text_cutoff() is Err(_))
  assert_eq(owner.model().name(), "")
  assert_eq(host.present_count(), 0)
}
