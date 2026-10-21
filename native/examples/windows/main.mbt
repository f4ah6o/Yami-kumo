///|
fn windows_measure(
  value : String,
  size : Double,
) -> Result[@text_layout.TextMeasurement, @diagnostics.FrameworkError] {
  let document = match @text.TextDocument::new(value) {
    Err(_) => return Err(windows_error("text document is invalid"))
    Ok(value) => value
  }
  match @windows_text.measure(document, "Segoe UI", size) {
    Ok(value) => Ok(value)
    Err(_) =>
      Err(windows_error("DirectWrite rejected the native Text measurement"))
  }
}

///|
fn windows_error(message : String) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    @diagnostics.ConversionFailed,
    "windows_measure",
    subsystem="native-sample-windows",
    message~,
  )
}

///|
fn main {
  let host = match @windows_host.Host::start() {
    Err(error) =>
      abort(
        "Windows native Host startup failed: " +
        @common.format_framework_error(error),
      )
    Ok(value) => value
  }
  let capture : @common.NativeFrameCapture = fn(window) {
    @testing.capture_frame(host, window)
  }
  let accessibility_session = WindowsButtonAccessibilitySession::new()
  let accessibility_port = accessibility_session.port()
  let route = @windows_host.TextHostRoute::new(host)
  let text_begin : @common.NativeTextBegin = fn(window, root) {
    route.begin_text_input(window, root)
  }
  let text_update : @common.NativeTextUpdate = fn(epoch, state) {
    route.update_text_input(epoch, state)
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
  let result = @common.run_native_entry(
    host,
    @common.Windows,
    windows_measure,
    capture,
    accessibility_port=Some(accessibility_port),
    text_port=Some(text_port),
    settings_platform_next=Some(next_platform),
  )
  accessibility_session.close()
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
