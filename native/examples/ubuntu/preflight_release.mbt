///|
/// Resolve only the original printable-release head under both the preserved
/// geometry proof and the existing strict native physical-provenance policy.
/// Neither the accepted scene nor a later record is touched here.
fn resolve_preflight_release(
  entry : @common.SettingsEntryController,
  route : @ubuntu_host.RetainedOrderedRoute,
  preflight : SettingsPreflightAdapter,
  held : Ref[@ubuntu_host.RetainedOrderedReceipt?],
  sequence : Int64,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let owner = match entry.owner() {
    Some(value) if entry.suspended() => value
    _ => return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "preflight_release_owner"))
  }
  let receipt = match held.val {
    Some(value) => value
    None => {
      let value = match route.peek() {
        Ok(Some(value)) => value
        Ok(None) => return Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "preflight_release_empty"))
        Err(error) => return Err(error)
      }
      if sequence <= 0L || value.native_sequence().to_int64() != sequence ||
        value.is_native_stale() || value.is_native_revoked() || !(value.event() is @ubuntu_host.Unhandled(_)) {
        return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "preflight_release_head"))
      }
      // Verify that the adapter can observe a printable release before taking
      // any local responsibility. This is still not permission to ACK.
      match value.physical_release_evidence() {
        Ok(Some(_)) => ()
        Ok(None) => return Err(@diagnostics.FrameworkError::new(@diagnostics.UnsupportedCapability, "preflight_release_evidence"))
        Err(error) => return Err(error)
      }
      held.val = Some(value)
      value
    }
  }
  if receipt.native_sequence().to_int64() != sequence || receipt.is_native_stale() || receipt.is_native_revoked() {
    return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "preflight_release_receipt_changed"))
  }
  match owner.pending_receipt_identity() {
    None => {
      let candidate = @common.NativeRetainedReceipt::new(
        None, receipt.native_window(), receipt.native_sequence(), receipt.root(), receipt.epoch(),
        fn() { receipt.ack() },
      )
      match owner.stage_preflight_unsupported(candidate, fn(window, root, epoch, state) {
        preflight.verify(window, root, epoch, state)
      }) { Err(error) => return Err(error); Ok(_) => () }
    }
    Some((window, native_sequence, root, epoch)) if window == receipt.native_window() &&
      native_sequence == receipt.native_sequence() && root == receipt.root() && epoch == receipt.epoch() => ()
    _ => return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "preflight_release_owner_changed"))
  }
  let result = owner.with_preflight_unsupported_policy(sequence, fn(window, root, epoch, state) {
    preflight.verify(window, root, epoch, state)
  }, fn(entered, ack) {
    let (native_epoch, native_seat, native_proxy) = entered
    let evidence = match receipt.physical_release_evidence() {
      Ok(Some(value)) => value
      Ok(None) => return Err(@diagnostics.FrameworkError::new(@diagnostics.UnsupportedCapability, "preflight_release_evidence"))
      Err(error) => return Err(error)
    }
    let target = evidence.target()
    if !evidence.claim_before_any_window() || evidence.host_window_generation() != Some(1) ||
      evidence.focus_generation() != 1 || !(evidence.prior() is @ubuntu_host.NoPressObservedSinceFocus) ||
      target.window != receipt.native_window() || target.sequence != receipt.native_sequence().to_int64() ||
      target.epoch != native_epoch || target.seat != native_seat || target.proxy_generation != native_proxy ||
      route.native_epoch() != Some(target.epoch) {
      return Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "preflight_release_provenance"))
    }
    ack()
  })
  // If ACK succeeded but the owner changed afterward, the common ledger keeps
  // the receipt; do not perform a second ACK even when the step returns Err.
  if owner.pending_receipt_identity() is None { held.val = None }
  result
}
