///|
/// One normal-render geometry attempt and its native route proof. This is a
/// single bounded slot; it never owns or acknowledges FIFO input.
priv struct SettingsPreflightAdapter {
  route : @ubuntu_host.RetainedOrderedRoute
  mut proof : @ubuntu_host.RetainedGeometryPreflight?
  mut accepted : @ubuntu_host.RetainedGeometryReceipt?
  mut uncertain : Bool
}

///| Read-only exact-owner check; it neither submits nor acknowledges input.
fn SettingsPreflightAdapter::verify(
  self : SettingsPreflightAdapter, window : @platform.WindowId,
  root : UInt64, epoch : UInt64, state : @text_host.TextInputState,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let normalized = match ubuntu_text_state(state) { Ok(value) => value; Err(error) => return Err(error) }
  let proof = match self.proof {
    Some(value) if !self.uncertain && self.accepted is None => value
    _ => return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "preflight_proof_unavailable"))
  }
  let (original_window, original_root, original_epoch, native_epoch) = proof.identity()
  if original_window != window || original_root != root || original_epoch != epoch ||
    self.route.binding_epoch() != Some(epoch) || self.route.native_epoch() != Some(native_epoch) ||
    !same_geometry_state(proof.state(), normalized) || !self.route.preflight_geometry_is_current(proof) {
    return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "preflight_owner_changed"))
  }
  Ok(())
}

///|
fn SettingsPreflightAdapter::attempt(
  self : SettingsPreflightAdapter, epoch : UInt64, state : @text_host.TextInputState,
) -> Result[UInt64, @diagnostics.FrameworkError] {
  if self.proof is Some(_) || self.accepted is Some(_) || self.uncertain {
    return Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "preflight_original_unresolved"))
  }
  match self.route.attempt_geometry(epoch, state) {
    @ubuntu_host.GeometryAccepted(_) => Ok(epoch)
    @ubuntu_host.GeometryPreflightRejected(error, proof) => {
      self.proof = Some(proof)
      Err(error)
    }
    @ubuntu_host.GeometryOutcomeUncertain(error) => {
      self.uncertain = true
      Err(error)
    }
  }
}

///|
/// Retry the same owner-bound candidate only. A native-entered failure is
/// latched as uncertain; an accepted receipt is retained before any later
/// validation, and subsequent calls only inspect that receipt.
fn SettingsPreflightAdapter::retry(
  self : SettingsPreflightAdapter, window : @platform.WindowId,
  root : UInt64, epoch : UInt64, state : @text_host.TextInputState,
) -> Result[UInt64, @diagnostics.FrameworkError] {
  let normalized = match ubuntu_text_state(state) { Ok(value) => value; Err(error) => return Err(error) }
  if self.uncertain || self.route.binding_epoch() != Some(epoch) {
    return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "preflight_outcome_uncertain"))
  }
  match self.accepted {
    Some(receipt) => {
      let pending = receipt.pending()
      if pending.window() != window || pending.root() != root || pending.epoch() != epoch ||
        !same_geometry_state(pending.state(), normalized) || !self.route.geometry_receipt_is_current(receipt) {
        return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "preflight_accepted_owner_changed"))
      }
      return Ok(epoch)
    }
    None => ()
  }
  let proof = match self.proof {
    Some(value) => value
    None => return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "preflight_proof_unavailable"))
  }
  let (original_window, original_root, original_epoch, native_epoch) = proof.identity()
  if original_window != window || original_root != root || original_epoch != epoch ||
    self.route.native_epoch() != Some(native_epoch) || !same_geometry_state(proof.state(), normalized) ||
    !self.route.preflight_geometry_is_current(proof) {
    return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "preflight_owner_changed"))
  }
  match self.route.retry_preflight_geometry(proof) {
    @ubuntu_host.GeometryAccepted(receipt) => {
      self.proof = None
      self.accepted = Some(receipt)
      let pending = receipt.pending()
      if pending.window() != window || pending.root() != root || pending.epoch() != epoch ||
        pending.native_epoch() != native_epoch || !same_geometry_state(pending.state(), normalized) ||
        !self.route.geometry_receipt_is_current(receipt) {
        return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "preflight_accepted_owner_changed"))
      }
      Ok(epoch)
    }
    @ubuntu_host.GeometryPreflightRejected(error, next) => { self.proof = Some(next); Err(error) }
    @ubuntu_host.GeometryOutcomeUncertain(error) => { self.proof = None; self.uncertain = true; Err(error) }
  }
}
