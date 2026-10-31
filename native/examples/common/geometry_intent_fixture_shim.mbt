///|
/// FIXTURE ONLY. This synthetic measurement is never a production dependency.
fn fixture_handoff_measure(value : String, size : Double) -> Result[@text_layout.TextMeasurement, @diagnostics.FrameworkError] {
  let document = @text.TextDocument::new(value).unwrap()
  let logical = @primitives.Rect::new(0.0, 0.0, value.length().to_double() * size * 0.6, size * 1.25).unwrap()
  let ink = @primitives.Rect::new(-1.0, -2.0, logical.size().width() + 1.0, size * 1.25 + 2.0).unwrap()
  let carets = []
  let mut offset = 0
  let mut x = 0.0
  let first = @primitives.Rect::new(x, 0.0, 1.0, size).unwrap()
  carets.push(@text_layout.CaretGeometry::new(offset, true, first, first).unwrap())
  for scalar in value.iter() {
    offset += if scalar.to_int() > 0xFFFF { 2 } else { 1 }
    x += size * 0.6
    let rect = @primitives.Rect::new(x, 0.0, 1.0, size).unwrap()
    carets.push(@text_layout.CaretGeometry::new(offset, true, rect, rect).unwrap())
  }
  Ok(@text_layout.TextMeasurement::new(document, logical, ink, size * 0.8, 1, 0, carets).unwrap())
}

///|
/// FIXTURE ONLY: make a synthetic local consumer owner without opening IME.
pub fn fixture_intent_owner() -> (SettingsRunOwner, UInt64) {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(1UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, fixture_handoff_measure, text_port=Some(port)).unwrap()
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, fixture_handoff_measure).unwrap())
  ignore(owner.mounted.focus(@shared_settings.settings_name()))
  let binding = owner.mounted.focused_text().unwrap().binding_id()
  (owner, binding)
}

///|
/// FIXTURE ONLY: record the already-ACKed synthetic native Entered prefix.
pub fn fixture_prepare_intent_owner(
  owner : SettingsRunOwner, binding : UInt64, epoch : UInt64, native_epoch : Int32,
) -> Unit {
  owner.session = Some({ epoch, binding })
  owner.host_epoch = Some(epoch)
  owner.host_epoch_verified = true
  owner.terminal_owner = Some(owner.mounted.capture_terminal_text_owner(epoch).unwrap())
  owner.entered_target = Some((native_epoch, 117L, 4))
  let entered = NativeRetainedReceipt::entered(owner.window, 1, binding, epoch, native_epoch, 117L, 4, fn() { Ok(()) })
  owner.acknowledged_receipts.push({ receipt: entered, stage: ReceiptOwnerEntered })
  owner.suspended = true
  owner.dirty = true
  owner.stage_dirty_scene().unwrap()
}

///| FIXTURE ONLY: original owner sees the exact preedit already ACKed at FIFO head.
pub fn fixture_prepare_intent_owner_with_preedit(
  owner : SettingsRunOwner, binding : UInt64, epoch : UInt64, native_epoch : Int32,
  preedit : @text_host.TextInputEvent,
) -> Unit {
  owner.session = Some({ epoch, binding })
  owner.host_epoch = Some(epoch)
  owner.host_epoch_verified = true
  owner.terminal_owner = Some(owner.mounted.capture_terminal_text_owner(epoch).unwrap())
  owner.entered_target = Some((native_epoch, 117L, 4))
  let entered = NativeRetainedReceipt::entered(owner.window, 1, binding, epoch, native_epoch, 117L, 4, fn() { Ok(()) })
  owner.acknowledged_receipts.push({ receipt: entered, stage: ReceiptOwnerEntered })
  owner.deliver_owned_observation(preedit).unwrap()
  let prior = NativeRetainedReceipt::new(Some(OrderedText(preedit)), owner.window, 2, binding, epoch, fn() { Ok(()) })
  owner.acknowledged_receipts.push({ receipt: prior, stage: ReceiptNoModelAction })
  owner.suspended = true
  owner.dirty = true
  owner.stage_dirty_scene().unwrap()
}

///| Fixture only: inspect preedit without mutating the held owner.
pub fn fixture_intent_preedit_is_retained(owner : SettingsRunOwner) -> Bool {
  match owner.mounted.focused_text() {
    Some(field) => field.composing() && field.document().text() == ""
    None => false
  }
}
