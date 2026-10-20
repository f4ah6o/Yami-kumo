///|
fn macos_measure(
  value : String,
  size : Double,
) -> Result[@text_layout.TextMeasurement, @diagnostics.FrameworkError] {
  let document = match @text.TextDocument::new(value) {
    Err(_) => return Err(macos_error("text document is invalid"))
    Ok(value) => value
  }
  match @macos_text.measure(document, "sans", size) {
    Ok(value) => Ok(value)
    Err(_) => Err(macos_error("CoreText rejected the native Text measurement"))
  }
}

///|
fn macos_error(message : String) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    @diagnostics.ConversionFailed,
    "macos_measure",
    subsystem="native-sample-macos",
    message~,
  )
}

///|
fn main {
  let host = match @mac_host.Host::start() {
    Err(error) =>
      abort(
        "macOS native Host startup failed: " +
        @common.format_framework_error(error),
      )
    Ok(value) => value
  }
  let capture : @common.NativeFrameCapture = fn(window) {
    @testing.capture_frame(host, window)
  }
  let publish_accessibility_button : @common.NativeButtonAXPublish = fn(
    window,
    existing_binding,
    snapshot,
  ) {
    host.publish_button_accessibility(
      window,
      existing_binding,
      @mac_host.ButtonAccessibilitySnapshot::new(
        snapshot.name(),
        snapshot.bounds(),
        snapshot.enabled(),
        snapshot.loading(),
        snapshot.focused(),
        snapshot.activations(),
      ),
    )
  }
  let revoke_accessibility_button : @common.NativeButtonAXRevoke = fn(
    window,
    token,
  ) {
    host.revoke_button_accessibility(window, token)
  }
  let take_accessibility_request : @common.NativeButtonAXTakeRequest = fn(
    window,
  ) {
    host.take_button_accessibility_request(window)
  }
  let accessibility_port = @common.NativeButtonAXPort::new(
    publish_accessibility_button, revoke_accessibility_button, take_accessibility_request,
  )
  let text_begin : @common.NativeTextBegin = fn(window, root) {
    host.begin_text_input(window, root)
  }
  let text_update : @common.NativeTextUpdate = fn(epoch, state) {
    host.update_text_input(epoch, state)
  }
  let text_cancel : @common.NativeTextCancel = fn(epoch) {
    host.cancel_text_input(epoch)
  }
  let text_end : @common.NativeTextEnd = fn(epoch) {
    host.end_text_input(epoch)
  }
  let text_next : @common.NativeTextNext = fn(timeout) {
    host.next_text_input(timeout_ms=timeout)
  }
  let text_port = @common.NativeTextInputPort::new(
    text_begin, text_update, text_cancel, text_end, text_next,
  )
  let result = @common.run_native_entry(
    host,
    @common.Macos,
    macos_measure,
    capture,
    accessibility_port=Some(accessibility_port),
    text_port=Some(text_port),
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
