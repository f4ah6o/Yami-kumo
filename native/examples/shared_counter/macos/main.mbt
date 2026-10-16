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
    subsystem="shared-counter-macos",
    message~,
  )
}

///|
fn main {
  let host = match @mac_host.Host::start() {
    Err(error) => abort(@shared_counter_host.format_error(error))
    Ok(value) => value
  }
  let capture : @shared_counter_host.FrameCapture = fn(window) {
    @testing.capture_frame(host, window)
  }
  let result = @shared_counter_host.run(
    host,
    @shared_counter_host.Macos,
    macos_measure,
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
