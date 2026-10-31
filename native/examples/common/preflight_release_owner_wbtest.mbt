///|
fn preflight_release_owner() -> (SettingsRunOwner, UInt64) {
  let (owner, _) = preflight_update_owner()
  let pending = owner.pending_host_update.unwrap()
  let target = (7, 11L, 4)
  owner.entered_target = Some(target)
  owner.pending_host_update = Some({ ..pending, entered: Some(target), })
  let entered = NativeRetainedReceipt::entered(owner.window, 1, pending.binding, pending.epoch, 7, 11L, 4, fn() { Ok(()) })
  owner.acknowledged_receipts.push({ receipt: entered, stage: ReceiptOwnerEntered })
  let preedit = @text_host.TextInputEvent::new(owner.window, 1L, pending.epoch, @text_host.Preedit(text="にほん", cursor=3))
  let prior = NativeRetainedReceipt::new(Some(OrderedText(preedit)), owner.window, 2, pending.binding, pending.epoch, fn() { Ok(()) })
  owner.acknowledged_receipts.push({ receipt: prior, stage: ReceiptNoModelAction })
  (owner, pending.binding)
}

///|
test "preflight release checks proof and original prefix before one ACK and retry" {
  let (owner, binding) = preflight_release_owner()
  let verified = Ref(false)
  let checks = Ref(0)
  let acks = Ref(0)
  let verify = fn(_window : @platform.WindowId, _binding : UInt64, _epoch : UInt64, _state : @text_host.TextInputState) {
    checks.val += 1
    if verified.val { Ok(()) } else { Err(runner_error("fixture", "proof stale")) }
  }
  let receipt = NativeRetainedReceipt::new(None, owner.window, 3, binding, 7UL, fn() { acks.val += 1; Ok(()) })
  assert_true(owner.stage_preflight_unsupported(receipt, verify) is Err(_))
  assert_true(owner.pending_receipt_identity() is None)
  assert_eq(acks.val, 0)
  verified.val = true
  owner.stage_preflight_unsupported(receipt, verify).unwrap()
  verified.val = false
  assert_true(owner.with_preflight_unsupported_policy(3L, verify, fn(_, ack) { ack() }) is Err(_))
  assert_eq(acks.val, 0)
  assert_true(owner.pending_receipt_identity() is Some(_))
  verified.val = true
  owner.with_preflight_unsupported_policy(3L, verify, fn(_, ack) { ack() }).unwrap()
  assert_eq(acks.val, 1)
  assert_true(owner.pending_receipt_identity() is None)
  assert_true(owner.receipt_stage_for_sequence(3L) is Some(ReceiptUnsupportedAcknowledged))
  assert_false(owner.host_epoch_verified())
  assert_true(owner.pending_host_update is Some(_))
  assert_true(owner.advance_generation() is None)
  assert_true(owner.with_preflight_unsupported_policy(3L, verify, fn(_, ack) { ack() }) is Err(_))
  assert_eq(acks.val, 1)
  owner.retry_captured_host_update(fn(_, _, epoch, _) { Ok(epoch) }).unwrap()
  assert_true(owner.host_epoch_verified())
  assert_true(owner.mounted.focused_text().unwrap().composing())
  assert_eq(owner.model().name(), "")
  assert_true(owner.dirty)
  assert_false(owner.can_stop())
  assert_true(checks.val >= 3)
}

///|
test "preflight release never repeats an uncertain ACK or reassigns another head" {
  let (owner, binding) = preflight_release_owner()
  let checks = Ref(0)
  let verify = fn(_window : @platform.WindowId, _binding : UInt64, _epoch : UInt64, _state : @text_host.TextInputState) { checks.val += 1; Ok(()) }
  let acks = Ref(0)
  let text = @text_host.TextInputEvent::new(owner.window, 2L, 7UL, @text_host.Commit(text="日本"))
  let text_head = NativeRetainedReceipt::new(Some(OrderedText(text)), owner.window, 3, binding, 7UL, fn() { acks.val += 1; Ok(()) })
  assert_true(owner.stage_preflight_unsupported(text_head, verify) is Err(_))
  assert_eq(checks.val, 0)
  assert_eq(acks.val, 0)
  let wrong = NativeRetainedReceipt::new(None, owner.window, 4, binding, 7UL, fn() { acks.val += 1; Ok(()) })
  assert_true(owner.stage_preflight_unsupported(wrong, verify) is Err(_))
  assert_true(owner.pending_receipt_identity() is None)
  let receipt = NativeRetainedReceipt::new(None, owner.window, 3, binding, 7UL, fn() {
    acks.val += 1
    Err(runner_error("fixture", "ACK outcome unknown"))
  })
  owner.stage_preflight_unsupported(receipt, verify).unwrap()
  assert_true(owner.with_preflight_unsupported_policy(3L, verify, fn(_, ack) { ack() }) is Err(_))
  assert_eq(acks.val, 1)
  assert_true(owner.with_preflight_unsupported_policy(3L, verify, fn(_, ack) { ack() }) is Err(_))
  assert_eq(acks.val, 1)
  assert_true(owner.pending_receipt_identity() is Some(_))
  assert_true(owner.pending_host_update is Some(_))
  assert_false(owner.host_epoch_verified())
  assert_false(owner.can_stop())
}
