///|
/// A direct keyboard route has no native IME geometry update. Reject before
/// staging or marking the retained owner uncertain.
fn with_ime_geometry_only(
  direct : Bool,
  action : () -> Result[Unit, @diagnostics.FrameworkError],
) -> Result[Unit, @diagnostics.FrameworkError] {
  if direct {
    return Err(@diagnostics.FrameworkError::new(@diagnostics.UnsupportedCapability, "geometry_direct_unsupported"))
  }
  action()
}

///|
/// Ubuntu-only adapter retaining the actual route receipt. Common's callback
/// return is not itself native proof, and this adapter does not publish a scene.
priv struct SettingsGeometryAdapter {
  route : @ubuntu_host.RetainedOrderedRoute
  window : @platform.WindowId
  root : UInt64
  epoch : UInt64
  native_epoch : Int32
  state : @text_host.TextInputState
  mut intent : @ubuntu_host.RetainedGeometryIntent?
  // This is set only by an actual route reserve error. The GPUI reserve
  // contract returns before installing an intent or entering native update.
  mut reserve_rejected : Bool
  mut receipt : @ubuntu_host.RetainedGeometryReceipt?
}

///|
fn same_geometry_state(a : @text_host.TextInputState, b : @text_host.TextInputState) -> Bool {
  let preedit_same = match (a.preedit(), b.preedit()) {
    (None, None) => true
    (Some(left), Some(right)) => left.text() == right.text() && left.selection() == right.selection()
    _ => false
  }
  a.document() == b.document() && a.caret() == b.caret() && preedit_same
}

///|
fn SettingsGeometryAdapter::new(
  route : @ubuntu_host.RetainedOrderedRoute,
  geometry : @ui.StagedTextGeometry,
  state : @text_host.TextInputState,
) -> Result[SettingsGeometryAdapter, @diagnostics.FrameworkError] {
  let (window, epoch, root, _) = geometry.identity()
  let native_epoch = match route.native_epoch() {
    Some(value) if value > 0 => value
    _ => return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "geometry_native_epoch"))
  }
  if route.binding_epoch() != Some(epoch) || route.pending_geometry() is Some(_) ||
    state.document() != geometry.committed() || state.preedit() is Some(_) {
    return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "geometry_original_owner"))
  }
  Ok({ route, window, root, epoch, native_epoch, state, intent: None, reserve_rejected: false, receipt: None })
}

///|
fn SettingsGeometryAdapter::matches(
  self : SettingsGeometryAdapter,
  pending : @ubuntu_host.RetainedGeometryPending,
) -> Bool {
  pending.window() == self.window && pending.root() == self.root &&
    pending.epoch() == self.epoch && pending.native_epoch() == self.native_epoch &&
    same_geometry_state(pending.state(), self.state)
}

///|
fn SettingsGeometryAdapter::attempt(
  self : SettingsGeometryAdapter, retry : Bool, state : @text_host.TextInputState,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let normalized = match ubuntu_text_state(state) { Ok(value) => value; Err(error) => return Err(error) }
  if !same_geometry_state(normalized, self.state) || self.receipt is Some(_) ||
    self.route.binding_epoch() != Some(self.epoch) || self.route.native_epoch() != Some(self.native_epoch) {
    return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "geometry_candidate_changed"))
  }
  let intent = match self.intent {
    Some(value) if retry => value
    Some(_) =>
      return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "geometry_duplicate_attempt"))
    None => {
      if retry && !self.reserve_rejected {
        return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "geometry_intent_missing"))
      }
      let value = match self.route.reserve_geometry_intent(self.epoch, normalized) {
        Err(error) => { self.reserve_rejected = true; return Err(error) }
        Ok(value) => value
      }
      // Retain the opaque owner-bound intent before any further checks or native
      // submission. A later validation error must not lose it.
      self.intent = Some(value)
      self.reserve_rejected = false
      value
    }
  }
  let reserved = intent.pending()
  let pending = match self.route.pending_geometry() {
    Some(value) => value
    None => return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "geometry_pending_missing"))
  }
  if !self.matches(reserved) || !self.matches(pending) || reserved.generation() != pending.generation() ||
    self.route.geometry_intent_stage(intent) is None {
    return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "geometry_intent_changed"))
  }
  let result = self.route.submit_geometry_intent(intent)
  match result {
    Err(error) => Err(error)
    Ok(receipt) => {
      // Retain even a receipt that fails the following checks. The host may
      // already have changed; validation failure is not permission to drop it.
      self.receipt = Some(receipt)
      let pending = receipt.pending()
      if !self.matches(pending) || reserved.generation() != pending.generation() ||
        !self.route.geometry_receipt_is_current(receipt) {
        return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "geometry_receipt_changed"))
      }
      Ok(())
    }
  }
}
