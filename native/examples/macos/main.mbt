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
      abort("macOS native Host startup failed: " + error.code().label())
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
  let result = @common.run_native_sample(
    host,
    @common.Macos,
    macos_measure,
    capture,
    click,
    escape,
  )
  let stopped = host.stop()
  match result {
    Err(error) => abort(error.operation() + ": " + error.code().label())
    Ok(_) => ()
  }
  match stopped {
    Err(error) => abort(error.operation() + ": " + error.code().label())
    Ok(_) => ()
  }
}
