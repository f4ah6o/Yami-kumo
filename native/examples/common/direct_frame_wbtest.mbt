///|
fn direct_frame_fixture() -> (SettingsRunOwner, @ui.Frame) {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port)).unwrap()
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, text_runner_measure).unwrap())
  if !owner.mounted.focus(@shared_settings.settings_name()) { abort("fixture focus failed") }
  let field = owner.mounted.focused_text().unwrap()
  owner.session = Some({ epoch: 7UL, binding: field.binding_id() })
  owner.host_epoch = Some(7UL)
  owner.host_epoch_verified = true
  owner.terminal_owner = Some(owner.mounted.capture_terminal_text_owner(7UL).unwrap())
  let event = @platform.Event::new(owner.window, 1L, 1.0, @platform.Input(@primitives.TextInput(text="日")))
  let native = NativeRetainedReceipt::direct(event, 1, field.binding_id(), 7UL, 5, 1L, fn() { Ok(()) })
  owner.pending_host_receipt = Some(native)
  owner.inflight = Some(OrderedPlatform(event))
  owner.reserve_pending_direct(native).unwrap()
  owner.ack_owned_receipt().unwrap()
  owner.complete_pending_direct().unwrap()
  let frame = owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, text_runner_measure).unwrap()
  let after = owner.mounted.focused_text().unwrap()
  owner.last_document = after.document().text()
  owner.last_caret = settings_caret(after.caret())
  owner.dirty = false
  (owner, frame)
}

///|
test "direct frame observes only the exact applied prefix captured at present" {
  let (owner, frame) = direct_frame_fixture()
  assert_true(owner.prepare_direct_frame(frame) is Some(_))
  owner.present_with_frame_publication(frame, fn(_, _) { Ok(()) }).unwrap()
  let proof = owner.pending_direct_frame.unwrap()
  assert_true(proof.presented)
  assert_false(proof.completed)
  assert_eq(proof.watermark, 1)
  let later = @platform.Event::new(owner.window, 2L, 1.0, @platform.FrameCompleted)
  owner.acknowledged_receipts.push({
    receipt: NativeRetainedReceipt::new(Some(OrderedPlatform(later)), owner.window, 2, owner.session.unwrap().binding, 7UL, fn() { Ok(()) }),
    stage: ReceiptPlatformHandled,
  })
  owner.complete_frame_publication()
  assert_true(proof.completed)
  assert_eq(owner.completed_direct_frame.unwrap().watermark, 1)
  assert_eq(owner.acknowledged_receipt_count(), 2)
  assert_false(owner.can_stop())
}

///|
test "direct frame failure or model ABA retains the proof without completion" {
  let (owner, frame) = direct_frame_fixture()
  assert_true(owner.present_with_frame_publication(frame, fn(_, _) { Err(runner_error("fixture", "present failed")) }) is Err(_))
  assert_true(owner.pending_direct_frame is Some(_))
  owner.complete_frame_publication()
  assert_true(owner.completed_direct_frame is None)
  let (other, next) = direct_frame_fixture()
  other.present_with_frame_publication(next, fn(_, _) { Ok(()) }).unwrap()
  let original = other.settings
  other.replace_settings(original.update(@shared_settings.Ui(@view.TextChanged(@shared_settings.settings_name(), "別"))))
  other.replace_settings(original)
  other.complete_frame_publication()
  assert_true(other.pending_direct_frame is Some(_))
  assert_true(other.completed_direct_frame is None)
  assert_false(other.can_stop())
}

///|
test "direct frame rejects missing delivery proof and invalidated geometry" {
  let (owner, frame) = direct_frame_fixture()
  owner.direct_receipts.clear()
  assert_true(owner.prepare_direct_frame(frame) is None)
  assert_eq(owner.acknowledged_receipt_count(), 1)
  let (other, next) = direct_frame_fixture()
  other.present_with_frame_publication(next, fn(_, _) { Ok(()) }).unwrap()
  other.mounted.invalidate_layout()
  other.complete_frame_publication()
  assert_true(other.pending_direct_frame is Some(_))
  assert_true(other.completed_direct_frame is None)
  assert_false(other.can_stop())
}

///|
test "direct frame refuses a model that may include an unresolved later receipt" {
  let (owner, frame) = direct_frame_fixture()
  let unknown = @platform.Event::new(owner.window, 2L, 1.0,
    @platform.Input(@primitives.KeyPressed(key=@primitives.Character("x"), repeat=false, modifiers=@primitives.Modifiers::none())))
  owner.acknowledged_receipts.push({
    receipt: NativeRetainedReceipt::new(Some(OrderedPlatform(unknown)), owner.window, 2, owner.session.unwrap().binding, 7UL, fn() { Ok(()) }),
    stage: ReceiptAcknowledgedOnly,
  })
  assert_true(owner.prepare_direct_frame(frame) is None)
  assert_eq(owner.acknowledged_receipt_count(), 2)
  assert_false(owner.can_stop())
}
