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
    subsystem="shared-counter-windows",
    message~,
  )
}

///|
fn main {
  let host = match @windows_host.Host::start() {
    Err(error) => abort(@shared_counter_host.format_error(error))
    Ok(value) => value
  }
  let capture : @shared_counter_host.FrameCapture = fn(window) {
    @testing.capture_frame(host, window)
  }
  let result = @shared_counter_host.run(
    host,
    @shared_counter_host.Windows,
    windows_measure,
    capture,
  )
  let stopped = host.stop()
  match result {
    Err(error) => abort(@shared_counter_host.format_error(error))
    Ok(_) => ()
  }
  match stopped {
    Err(error) => abort(@shared_counter_host.format_error(error))
    Ok(_) => ()
  }
}
