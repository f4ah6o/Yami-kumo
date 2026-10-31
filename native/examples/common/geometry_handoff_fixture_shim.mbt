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
/// FIXTURE ONLY: build an owned stage and a contiguous synthetic native prefix.
pub fn fixture_handoff_owner() -> (SettingsRunOwner, UInt64) {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(3UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, fixture_handoff_measure, text_port=Some(port)).unwrap()
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, fixture_handoff_measure).unwrap())
  ignore(owner.mounted.focus(@shared_settings.settings_name()))
  let binding = owner.mounted.focused_text().unwrap().binding_id()
  owner.session = Some({ epoch: 3UL, binding })
  owner.host_epoch = Some(3UL)
  owner.host_epoch_verified = true
  owner.terminal_owner = Some(owner.mounted.capture_terminal_text_owner(3UL).unwrap())
  owner.entered_target = Some((7, 11L, 4))
  for i = 1; i <= 20; i = i + 1 {
    let platform = @platform.Event::new(owner.window, i.to_int64(), 1.0, @platform.FocusChanged(true))
    let receipt = NativeRetainedReceipt::new(Some(OrderedPlatform(platform)), owner.window, i, binding, 3UL, fn() { Ok(()) })
    owner.acknowledged_receipts.push({ receipt, stage: ReceiptPlatformHandled })
  }
  owner.suspended = true
  owner.dirty = true
  owner.stage_dirty_scene().unwrap()
  ignore(owner.attempt_staged_host_geometry(fn(_, _) { Err(runner_error("fixture", "uncertain")) }))
  (owner, binding)
}
