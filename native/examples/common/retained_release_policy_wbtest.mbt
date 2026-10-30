///|
/// Regression for the observed release-shaped unsupported receipt: identity
/// and an active owner alone do not prove physical press ownership. This test
/// is deliberately a retained failure, not a successful IME acceptance.
test "unproven printable release keeps original owner and native ACK pending" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(1UL) },
    fn(epoch, _) { Ok(epoch) },
    fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) },
    fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(
    host,
    Linux,
    text_runner_measure,
    text_port=Some(port),
  ).unwrap()
  let _ = owner.mounted
    .commit(owner.settings.view(), 640.0, 480.0, 1.0, text_runner_measure)
    .unwrap()
  assert_true(owner.mounted.focus(@shared_settings.settings_name()))
  let binding = owner.mounted.focused_text().unwrap().binding_id()
  let session : TextSession = { epoch: 1UL, binding, }
  owner.session = Some(session)
  owner.host_epoch = Some(1UL)
  owner.host_epoch_verified = true
  owner.terminal_owner = Some(
    owner.mounted.capture_terminal_text_owner(1UL).unwrap(),
  )
  owner.entered_target = Some((1, 14L, 1))
  let preedit = @text_host.TextInputEvent::new(
    owner.window,
    1L,
    1UL,
    @text_host.Preedit(text="ｎ", cursor=1),
  )
  assert_true(
    deliver_text_observation(owner.mounted, session, preedit).unwrap(),
  )
  assert_true(owner.mounted.focused_text().unwrap().composing())
  let calls = Ref(0)
  let receipt = NativeRetainedReceipt::new(
    None,
    owner.window,
    11,
    binding,
    1UL,
    fn() {
      calls.val += 1
      Ok(())
    },
  )
  owner.pending_host_receipt = Some(receipt)
  owner.suspended = true
  assert_true(owner.ack_owned_receipt() is Err(_))
  assert_eq(calls.val, 0)
  assert_true(owner.pending_receipt_identity() is Some((_, 11, _, _)))
  assert_true(owner.terminal_step(PollOnce) is Err(_))
  assert_true(owner.mounted.focused_text().unwrap().composing())
  assert_false(owner.can_stop())
  assert_eq(host.stop_count(), 0)
}
