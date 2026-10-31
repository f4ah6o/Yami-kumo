///|
test "delivered post-cutoff Enter opens Settings dialog while old receipt stays owned" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let head : Ref[NativeRetainedReceipt?] = Ref(None)
  let cutoffs = Ref(0)
  let ordered = NativeOrderedTextPort::with_retained_receipts(
    fn(_) { Ok(head.val) }, fn(_) { cutoffs.val += 1; Ok(()) },
  )
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
  owner.bounded_resume = true
  let text = @platform.Event::new(owner.window, 1L, 1.0, @platform.Input(@primitives.TextInput(text="abc")))
  head.val = Some(NativeRetainedReceipt::direct(text, 1, binding, 7UL, 5, 1L, fn() { head.val = None; Ok(()) }))
  owner.drive().unwrap()
  assert_eq(owner.model().name(), "abc")
  let tab = @platform.Event::new(owner.window, 2L, 1.0,
    @platform.Input(@primitives.KeyPressed(key=@primitives.Tab, repeat=false, modifiers=@primitives.Modifiers::none())))
  head.val = Some(NativeRetainedReceipt::new(Some(OrderedPlatform(tab)), owner.window, 2, binding, 7UL, fn() { head.val = None; Ok(()) }))
  owner.drive().unwrap()
  assert_true(owner.held_tab is Some(_))
  owner.drive().unwrap()
  assert_eq(cutoffs.val, 1)
  assert_true(owner.session is None)
  let frame = owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, text_runner_measure).unwrap()
  assert_true(frame.focused(@shared_settings.settings_save()))
  let enter = @platform.Event::new(owner.window, 3L, 1.0,
    @platform.Input(@primitives.KeyPressed(key=@primitives.Enter, repeat=false, modifiers=@primitives.Modifiers::none())))
  head.val = Some(NativeRetainedReceipt::new(Some(OrderedPlatform(enter)), owner.window, 3, binding, 7UL, fn() { head.val = None; Ok(()) }))
  owner.drive().unwrap()
  let action = owner.mounted.next_action().unwrap()
  assert_true(action is @view.Activate(key) && key == @shared_settings.settings_save())
  owner.replace_settings(owner.settings.update(@shared_settings.Ui(action)))
  assert_true(owner.model().dialog_open())
  let dialog = owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, text_runner_measure).unwrap()
  assert_true(dialog.focused(@shared_settings.settings_confirm()))
  // Neither local observation nor native cutoff releases the original owner.
  assert_true(owner.terminal_owner is Some(_))
  assert_eq(owner.direct_receipts.length(), 1)
  assert_false(owner.can_stop())
}
