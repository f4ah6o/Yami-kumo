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
  let click : @common.NativeTestClick = fn(window, point) {
    host.post_test_click(window, point)
  }
  let escape : @common.NativeTestEscape = fn(window) {
    host.post_test_escape(window)
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
  let result = @common.run_native_sample(
    host,
    @common.Macos,
    macos_measure,
    capture,
    click,
    escape,
    accessibility_port=Some(accessibility_port),
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
