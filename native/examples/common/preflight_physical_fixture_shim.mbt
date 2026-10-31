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

///| FIXTURE ONLY: produce a suspended original owner with a matching preedit
/// and explicit prior prefix, without calling a real compositor or IME.
pub fn fixture_preflight_release_entry() -> (SettingsEntryController, @text_host.TextInputState) {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(1UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, fixture_handoff_measure, text_port=Some(port)).unwrap()
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, fixture_handoff_measure).unwrap())
  ignore(owner.mounted.focus(@shared_settings.settings_name()))
  let field = owner.mounted.focused_text().unwrap()
  let binding = field.binding_id()
  owner.session = Some({ epoch: 1UL, binding })
  owner.host_epoch = Some(1UL)
  owner.host_epoch_verified = true
  let lease = owner.mounted.capture_terminal_text_owner(1UL).unwrap()
  owner.terminal_owner = Some(lease)
  owner.entered_target = Some((1, 117L, 4))
  let focus = @platform.Event::new(owner.window, 1L, 1.0, @platform.FocusChanged(true))
  owner.acknowledged_receipts.push({ receipt: NativeRetainedReceipt::new(Some(OrderedPlatform(focus)), owner.window, 1, 0UL, 0UL, fn() { Ok(()) }), stage: ReceiptPlatformHandled })
  owner.acknowledged_receipts.push({ receipt: NativeRetainedReceipt::entered(owner.window, 2, binding, 1UL, 1, 117L, 4, fn() { Ok(()) }), stage: ReceiptOwnerEntered })
  let preedit = @text_host.TextInputEvent::new(owner.window, 1L, 1UL, @text_host.Preedit(text="にほん", cursor=3))
  owner.deliver_owned_observation(preedit).unwrap()
  owner.acknowledged_receipts.push({ receipt: NativeRetainedReceipt::new(Some(OrderedText(preedit)), owner.window, 3, binding, 1UL, fn() { Ok(()) }), stage: ReceiptNoModelAction })
  let updated = owner.mounted.focused_text().unwrap()
  let state = @text_host.TextInputState::new(updated.document(), settings_caret(updated.caret()))
  owner.pending_host_update = Some({ owner: lease, model: owner.settings, fence: owner.model_fence, state,
    window: owner.window, epoch: 1UL, binding, entered: owner.entered_target, progress: lease.observed_progress(),
    frame_revision: owner.mounted.frame().unwrap().revision(), metrics: (640.0, 480.0, 1.0),
    composing: true, release_ack_attempted: false })
  owner.suspended = true
  owner.host_epoch_verified = false
  ({ host, outcome: Suspended(owner, runner_error("fixture", "preflight")), stop_attempted: false, stopped: false }, state)
}
