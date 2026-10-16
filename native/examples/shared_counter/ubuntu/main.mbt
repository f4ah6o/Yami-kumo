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
    subsystem="shared-counter-ubuntu",
    message~,
  )
}

///|
fn main {
  let host = match @ubuntu_host.Host::start() {
    Err(error) => abort(@shared_counter_host.format_error(error))
    Ok(value) => value
  }
  let capture : @shared_counter_host.FrameCapture = fn(window) {
    @testing.capture_frame(host, window)
  }
  let result = @shared_counter_host.run(
    host,
    @shared_counter_host.Linux,
    ubuntu_measure,
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
