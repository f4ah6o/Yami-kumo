///|
fn ubuntu_measure(
  value : String,
  size : Double,
) -> Result[@text_layout.TextMeasurement, @diagnostics.FrameworkError] {
  let document = match @text.TextDocument::new(value) {
    Err(_) => return Err(ubuntu_error("text document is invalid"))
    Ok(value) => value
  }
  match @linux_text.measure(document, "sans", size) {
    Ok(value) => Ok(value)
    Err(_) => Err(ubuntu_error("Pango rejected the native Text measurement"))
  }
}

///|
fn ubuntu_error(message : String) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    @diagnostics.ConversionFailed,
    "ubuntu_measure",
    subsystem="native-sample-ubuntu",
    message~,
  )
}

///|
fn ubuntu_text_caret(
  caret : @primitives.Rect,
) -> Result[@primitives.Rect, @diagnostics.FrameworkError] {
  // text-input-v1 takes signed integral surface-logical endpoints, while
  // Pango may return fractional logical geometry. Preserve the entire caret;
  // do not multiply by output scale or truncate a negative coordinate.
  let left = caret.left().floor()
  let top = caret.top().floor()
  let right = caret.right().ceil()
  let bottom = caret.bottom().ceil()
  let error = @diagnostics.FrameworkError::new(
    @diagnostics.InvalidInput,
    "ubuntu_text_caret",
    subsystem="native-sample-ubuntu",
    message="caret is outside the integral Wayland rectangle range",
  )
  for value in [left, top, right, bottom] {
    if value.is_nan() ||
      value.is_inf() ||
      value < -2147483648.0 ||
      value > 2147483647.0 {
      return Err(error)
    }
  }
  let width = right - left
  let height = bottom - top
  if caret.size().width() <= 0.0 ||
    caret.size().height() <= 0.0 ||
    width < 1.0 ||
    height < 1.0 ||
    width > 2147483647.0 ||
    height > 2147483647.0 {
    return Err(error)
  }
  match @primitives.Rect::new(left, top, width, height) {
    Ok(value) => Ok(value)
    Err(_) => Err(error)
  }
}

///|
fn ubuntu_text_state(
  state : @text_host.TextInputState,
) -> Result[@text_host.TextInputState, @diagnostics.FrameworkError] {
  let caret = match ubuntu_text_caret(state.caret()) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok(
    @text_host.TextInputState::new(state.document(), caret).with_preedit(
      state.preedit(),
    ),
  )
}

///|
fn main {
  let host = match @ubuntu_host.Host::start() {
    Err(error) =>
      abort(
        "Ubuntu native Host startup failed: " +
        @common.format_framework_error(error),
      )
    Ok(value) => value
  }
  let capture : @common.NativeFrameCapture = fn(window) {
    @testing.capture_frame(host, window)
  }
  let route = @ubuntu_host.TextHostRoute::new(host)
  let text_begin : @common.NativeTextBegin = fn(window, root) {
    route.begin_text_input(window, root)
  }
  let text_update : @common.NativeTextUpdate = fn(epoch, state) {
    let normalized = match ubuntu_text_state(state) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    route.update_text_input(epoch, normalized)
  }
  let text_cancel : @common.NativeTextCancel = fn(epoch) {
    route.cancel_text_input(epoch)
  }
  let text_end : @common.NativeTextEnd = fn(epoch) {
    route.end_text_input(epoch)
  }
  let text_next : @common.NativeTextNext = fn(timeout) {
    route.next_text_input(timeout_ms=timeout)
  }
  let text_port = @common.NativeTextInputPort::new(
    text_begin, text_update, text_cancel, text_end, text_next,
  )
  let next_platform : @common.NativePlatformNext = fn(timeout) {
    route.next_platform_event(timeout_ms=timeout)
  }
  // Weston installs no text-input-v1 manager, so the settings lane falls
  // back to the compositor key path armed through the host's direct
  // keyboard-text mode.
  let direct_text : @common.NativeDirectText = fn(window, enabled) {
    host.set_direct_keyboard_text(window, enabled)
  }
  let result = @common.run_native_entry(
    host,
    @common.Linux,
    ubuntu_measure,
    capture,
    text_port=Some(text_port),
    settings_platform_next=Some(next_platform),
    settings_direct_text=Some(direct_text),
  )
  let stopped = host.stop()
  match result {
    Err(error) => abort(@common.format_framework_error(error))
    Ok(_) => ()
  }
  match stopped {
    Err(error) => abort(@common.format_framework_error(error))
    Ok(_) => ()
  }
}
