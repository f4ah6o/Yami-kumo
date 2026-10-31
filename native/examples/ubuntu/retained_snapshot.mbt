///|
/// Read the retained FIFO head without dispatch, ACK, model update or retry.
/// Values are observations from this exact live route, never proof of a prior
/// update outcome, host quiescence, scene consistency or permission to stop.
fn inspect_retained_head(
  route : @ubuntu_host.RetainedOrderedRoute, owner_host_verified : Bool,
) -> Result[Int64, @diagnostics.FrameworkError] {
  inspect_retained_head_from(route, owner_host_verified, fn() { route.peek() })
}

///| The production entry supplies only `route.peek`; injection permits a
/// fixture to prove a failed peek cannot trigger dispatch or acknowledgment.
fn inspect_retained_head_from(
  route : @ubuntu_host.RetainedOrderedRoute, owner_host_verified : Bool,
  peek : () -> Result[@ubuntu_host.RetainedOrderedReceipt?, @diagnostics.FrameworkError],
) -> Result[Int64, @diagnostics.FrameworkError] {
  let pending = route.pending_geometry() is Some(_)
  let handoff = route.geometry_handoff_in_progress()
  let owned = route.owned_geometry_text() is Some(_)
  let reserved = route.reserved_geometry_text() is Some(_)
  let portable_epoch = route.binding_epoch().unwrap_or(0UL)
  let native_epoch = route.native_epoch().unwrap_or(0)
  let record = match peek() {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  match record {
    None => {
      println("YAMI_SETTINGS_RETAINED_HEAD {\"present\":false,\"pending_geometry\":\{pending},\"handoff\":\{handoff},\"owned\":\{owned},\"reserved\":\{reserved},\"portable_epoch\":\{portable_epoch},\"native_epoch\":\{native_epoch},\"owner_host_verified\":\{owner_host_verified}}")
      Ok(0L)
    }
    Some(receipt) => {
      let kind = match receipt.native_event() {
        Some(@ubuntu_host.TextSession(_, event)) => match event {
          @ubuntu_host.Preedit(..) => "preedit"
          @ubuntu_host.Commit(..) => "commit"
          @ubuntu_host.Entered => "entered"
          @ubuntu_host.Left => "left"
          @ubuntu_host.ForwardedPressed(..) => "forwarded_pressed"
          @ubuntu_host.ForwardedReleased(..) => "forwarded_released"
        }
        Some(@ubuntu_host.Platform(event)) => match event.kind() {
          @platform.FrameCompleted => "frame_completed"
          @platform.Resized(..) => "resized"
          @platform.ScaleChanged => "scale_changed"
          @platform.FocusChanged(_) => "focus_changed"
          @platform.Destroyed => "destroyed"
          @platform.CloseRequested => "close_requested"
          @platform.ExitRequested => "exit_requested"
          @platform.Input(@primitives.PointerMoved(..)) => "pointer_moved"
          @platform.Input(@primitives.KeyPressed(..)) => "key_pressed"
          @platform.Input(@primitives.KeyReleased(..)) => "key_released"
          @platform.Input(_) => "other_input"
          _ => "other_platform"
        }
        None => "unmapped"
      }
      let classification = match receipt.event() {
        @ubuntu_host.Text(_) => "text"
        @ubuntu_host.Platform(_) => "platform"
        @ubuntu_host.Lifecycle(_, _) => "lifecycle"
        @ubuntu_host.Unhandled(_) => "unhandled"
      }
      let sequence = receipt.native_sequence().to_int64()
      let window = receipt.native_window().value()
      let root = receipt.root()
      let epoch = receipt.epoch()
      let stale = receipt.is_native_stale()
      let revoked = receipt.is_native_revoked()
      let composition_epoch = receipt.composition_epoch()
      let has_target = receipt.native_event() is Some(@ubuntu_host.TextSession(_, _))
      let (seat, proxy, target_epoch, serial) = match receipt.native_event() {
        Some(@ubuntu_host.TextSession(target, _)) => (target.seat, target.proxy_generation, target.epoch, target.serial)
        _ => (0L, 0, 0, 0)
      }
      println("YAMI_SETTINGS_RETAINED_HEAD {\"present\":true,\"kind\":\"\{kind}\",\"classification\":\"\{classification}\",\"sequence\":\{sequence},\"window\":\{window},\"root\":\{root},\"epoch\":\{epoch},\"composition_epoch\":\{composition_epoch},\"has_target\":\{has_target},\"seat\":\{seat},\"proxy\":\{proxy},\"target_epoch\":\{target_epoch},\"serial\":\{serial},\"stale\":\{stale},\"revoked\":\{revoked},\"pending_geometry\":\{pending},\"handoff\":\{handoff},\"owned\":\{owned},\"reserved\":\{reserved},\"portable_epoch\":\{portable_epoch},\"native_epoch\":\{native_epoch},\"owner_host_verified\":\{owner_host_verified}}")
      Ok(sequence)
    }
  }
}
