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
fn main {
  let host = match @ubuntu_host.Host::start() {
    Err(error) =>
      abort("Ubuntu native Host startup failed: " + error.code().label())
    Ok(value) => value
  }
  let capture : @common.NativeFrameCapture = fn(window) {
    @testing.capture_frame(host, window)
  }
  let no_click : @common.NativeTestClick = fn(_window, _point) { Ok(()) }
  let no_escape : @common.NativeTestEscape = fn(_window) { Ok(()) }
  let result = @common.run_native_sample(
    host,
    @common.Linux,
    ubuntu_measure,
    capture,
    no_click,
    no_escape,
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
