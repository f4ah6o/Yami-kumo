///|
/// Closed entry adapter: retains the native receipt and a copy of its complete
/// preedit or simple-commit payload, including style and target incarnation.
priv struct SettingsGeometryArrivalAdapter {
  route : @ubuntu_host.RetainedOrderedRoute
  receipt : @ubuntu_host.RetainedOrderedReceipt
  target : @ubuntu_host.TextSessionTarget
  source : @ubuntu_host.TextSessionEvent
  portable : @text_host.TextInputEvent
  geometry_generation : UInt64
}

///|
fn same_geometry_target(a : @ubuntu_host.TextSessionTarget, b : @ubuntu_host.TextSessionTarget) -> Bool {
  a.window == b.window && a.sequence == b.sequence && a.epoch == b.epoch &&
    a.seat == b.seat && a.proxy_generation == b.proxy_generation && a.serial == b.serial
}

///|
fn same_geometry_source(a : @ubuntu_host.TextSessionEvent, b : @ubuntu_host.TextSessionEvent) -> Bool {
  match (a, b) {
    (@ubuntu_host.Preedit(text=at, fallback=af, cursor_utf16=ac, styles=as_),
     @ubuntu_host.Preedit(text=bt, fallback=bf, cursor_utf16=bc, styles=bs)) => {
      if at != bt || af != bf || ac != bc || as_.length() != bs.length() { return false }
      for i = 0; i < as_.length(); i = i + 1 {
        if as_[i].range != bs[i].range || as_[i].style != bs[i].style { return false }
      }
      true
    }
    (@ubuntu_host.Commit(text=at, deletion=None, position=None),
     @ubuntu_host.Commit(text=bt, deletion=None, position=None)) => at == bt
    _ => false
  }
}

///|
fn same_geometry_portable(a : @text_host.TextInputEvent, b : @text_host.TextInputEvent) -> Bool {
  if a.window() != b.window() || a.epoch() != b.epoch() || a.sequence() != b.sequence() { return false }
  match (a.kind(), b.kind()) {
    (@text_host.Preedit(text=at, cursor=ac), @text_host.Preedit(text=bt, cursor=bc)) => at == bt && ac == bc
    (@text_host.Commit(text=at), @text_host.Commit(text=bt)) => at == bt
    _ => false
  }
}

///|
fn SettingsGeometryArrivalAdapter::new(
  route : @ubuntu_host.RetainedOrderedRoute,
  receipt : @ubuntu_host.RetainedOrderedReceipt,
) -> Result[SettingsGeometryArrivalAdapter, @diagnostics.FrameworkError] {
  let pending = match route.pending_geometry() {
    Some(value) => value
    None => return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "geometry_pending_missing"))
  }
  if route.geometry_handoff_in_progress() || route.owned_geometry_text() is Some(_) ||
    route.reserved_geometry_text() is Some(_) || receipt.is_native_stale() || receipt.is_native_revoked() {
    return Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "geometry_arrival_unavailable"))
  }
  let (target, source, portable) = match (receipt.native_event(), receipt.event()) {
    (Some(@ubuntu_host.TextSession(target, @ubuntu_host.Preedit(text~, fallback~, cursor_utf16~, styles~))), @ubuntu_host.Text(portable)) =>
      (target, @ubuntu_host.Preedit(text~, fallback~, cursor_utf16~, styles=styles.map(fn(value) { value })), portable)
    (Some(@ubuntu_host.TextSession(target, @ubuntu_host.Commit(text~, deletion=None, position=None))), @ubuntu_host.Text(portable)) =>
      (target, @ubuntu_host.Commit(text~, deletion=None, position=None), portable)
    _ => return Err(@diagnostics.FrameworkError::new(@diagnostics.UnsupportedCapability, "geometry_arrival_kind"))
  }
  if target.window != pending.window() || receipt.native_window() != target.window ||
    target.epoch != pending.native_epoch() || target.sequence != receipt.native_sequence().to_int64() ||
    receipt.root() != pending.root() || receipt.epoch() != pending.epoch() ||
    portable.window() != target.window || portable.sequence() <= 0L || portable.epoch() != pending.epoch() {
    return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "geometry_arrival_owner"))
  }
  Ok({ route, receipt, target, source, portable, geometry_generation: pending.generation() })
}

///|
fn SettingsGeometryArrivalAdapter::matches_owned(
  self : SettingsGeometryArrivalAdapter, owned : @ubuntu_host.GeometryOwnedText,
) -> Bool {
  owned.window() == self.target.window && owned.root() == self.receipt.root() &&
    owned.epoch() == self.receipt.epoch() && owned.native_epoch() == self.target.epoch &&
    owned.native_sequence() == self.receipt.native_sequence() &&
    owned.geometry_generation() == self.geometry_generation &&
    same_geometry_target(owned.native_target(), self.target) &&
    same_geometry_source(owned.native_text(), self.source) &&
    same_geometry_portable(owned.event(), self.portable)
}

///|
fn SettingsGeometryArrivalAdapter::inspect_owned(
  self : SettingsGeometryArrivalAdapter,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if self.route.geometry_handoff_in_progress() {
    return Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "geometry_handoff_in_progress"))
  }
  let pending = match self.route.pending_geometry() {
    Some(value) => value
    None => return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "geometry_pending_missing"))
  }
  if pending.generation() != self.geometry_generation || pending.window() != self.target.window ||
    pending.root() != self.receipt.root() || pending.epoch() != self.receipt.epoch() ||
    pending.native_epoch() != self.target.epoch || self.route.binding_epoch() != Some(self.receipt.epoch()) ||
    self.route.native_epoch() != Some(self.target.epoch) {
    return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "geometry_handoff_route_changed"))
  }
  match self.route.owned_geometry_text() {
    Some(value) if self.matches_owned(value) => Ok(())
    _ => Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "geometry_owned_slot_unavailable"))
  }
}

///|
fn SettingsGeometryArrivalAdapter::transfer(
  self : SettingsGeometryArrivalAdapter,
) -> Result[Unit, @diagnostics.FrameworkError] {
  match self.route.handoff_geometry_head(self.receipt) {
    Err(error) => Err(error)
    Ok(_) => self.inspect_owned()
  }
}

///|
/// Inspect the same route-owned record after native-local geometry acceptance.
/// This does not take the slot, authorize field/model application, publish a
/// scene, or prove that a compositor rendered the candidate. The caller must
/// recheck the original common owner in the same synchronous owner step.
fn SettingsGeometryArrivalAdapter::inspect_after_geometry_acceptance(
  self : SettingsGeometryArrivalAdapter,
  geometry : SettingsGeometryAdapter,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if self.route.geometry_handoff_in_progress() {
    return Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "geometry_handoff_in_progress"))
  }
  let accepted = match geometry.receipt {
    Some(value) => value
    None => return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "geometry_receipt_missing"))
  }
  let pending = accepted.pending()
  if !self.route.geometry_receipt_is_current(accepted) || !geometry.matches(pending) ||
    pending.generation() != self.geometry_generation || pending.window() != self.target.window ||
    pending.root() != self.receipt.root() || pending.epoch() != self.receipt.epoch() ||
    pending.native_epoch() != self.target.epoch {
    return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "geometry_accepted_owner_changed"))
  }
  match self.route.owned_geometry_text() {
    Some(value) if self.matches_owned(value) => Ok(())
    _ => Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "geometry_owned_slot_unavailable"))
  }
}
