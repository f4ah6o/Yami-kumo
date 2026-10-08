///|
/// Host backend selected by a thin platform entrypoint.
pub(all) enum NativeSamplePlatform {
  Macos
  Linux
  Windows
}

///|
pub type NativeFrameCapture = (@platform.WindowId) -> Result[
  @testing.FrameCapture,
  @diagnostics.FrameworkError,
]

///|
pub type NativeTestClick = (@platform.WindowId, @primitives.Point) -> Result[
  Unit,
  @diagnostics.FrameworkError,
]

///|
pub type NativeTestEscape = (@platform.WindowId) -> Result[
  Unit,
  @diagnostics.FrameworkError,
]

///|
priv struct FrameEvidence {
  mut initial : @testing.FrameCapture?
}

///|
extern "C" fn flush_native_stdout() -> Unit = "yami_native_ui_flush_stdout"

///|
/// Flush protocol markers so a driver can react while the native app is live.
fn emit_native_marker(line : String) -> Unit {
  println(line)
  flush_native_stdout()
}

///|
pub fn format_framework_error(error : @diagnostics.FrameworkError) -> String {
  let prefix = error.operation() + ": " + error.code().label()
  match error.message() {
    Some(message) => prefix + ": " + message
    None => prefix
  }
}

///|
/// Keep pointer/key routing synchronized with the layout currently in flight.
priv struct PresentationGate {
  mut rendered : Bool
  mut pending_stale : Bool
}

///|
fn PresentationGate::input_ready(self : PresentationGate) -> Bool {
  self.rendered
}

///|
fn PresentationGate::invalidate_layout(
  self : PresentationGate,
  has_pending_frame : Bool,
) -> Unit {
  self.rendered = false
  if has_pending_frame {
    self.pending_stale = true
  }
}

///|
fn PresentationGate::mark_presented(self : PresentationGate) -> Unit {
  self.rendered = true
}

///|
fn PresentationGate::completed_frame_is_current(
  self : PresentationGate,
) -> Bool {
  if self.pending_stale {
    self.pending_stale = false
    false
  } else {
    true
  }
}

///|
/// Run the same common sample and event controller on each native backend.
/// Platform mains only start a Host, adapt its text-measurement provider and
/// supply E2E-scoped native input/readback callbacks.
pub fn run_native_sample(
  host : &@platform.Backend,
  platform : NativeSamplePlatform,
  measure : @components.TextMeasure,
  capture : NativeFrameCapture,
  test_click : NativeTestClick,
  test_escape : NativeTestEscape,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let args = @env.args()
  let e2e = args.contains("--e2e") ||
    @env.get_env_var("YAMI_NATIVE_UI_E2E") == Some("1")
  let smoke = args.contains("--smoke") ||
    @env.get_env_var("YAMI_NATIVE_UI_SMOKE") == Some("1")
  if e2e && smoke {
    return Err(
      runner_error(
        "run_native_sample", "--e2e and --smoke cannot be used together",
      ),
    )
  }
  if e2e && @env.get_env_var("GPUI_NATIVE_E2E") != Some("1") {
    return Err(
      runner_error(
        "run_native_sample", "E2E frame readback requires GPUI_NATIVE_E2E=1",
      ),
    )
  }
  let evidence_dir = @env.get_env_var("YAMI_NATIVE_UI_EVIDENCE_DIR")
  if e2e && (evidence_dir is None || evidence_dir == Some("")) {
    return Err(
      runner_error(
        "run_native_sample", "E2E mode requires YAMI_NATIVE_UI_EVIDENCE_DIR",
      ),
    )
  }
  let required = [
    @platform.NativeWindow,
    @platform.QuadFrames,
    @platform.GrayscaleTextFrames,
    @platform.PointerKeyboard,
  ]
  for capability in required {
    match host.require_capability(capability) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  let title = match @env.get_env_var("YAMI_NATIVE_UI_WINDOW_TITLE") {
    Some(value) if value.length() > 0 => value
    _ => "Yami-kumo Native UI"
  }
  let window = match host.create_window(title, 800.0, 600.0) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let sample = match
    @sample.NativeSample::new(theme=@components.Theme::light()) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let evidence = { initial: None, }
  let result = run_native_loop(
    host, window, sample, platform, measure, capture, test_click, test_escape, e2e,
    smoke, evidence_dir, evidence,
  )
  let stopped = sample.shutdown()
  match result {
    Err(error) => Err(error)
    Ok(_) => stopped
  }
}

///|
fn run_native_loop(
  host : &@platform.Backend,
  window : @platform.WindowId,
  sample : @sample.NativeSample,
  platform : NativeSamplePlatform,
  measure : @components.TextMeasure,
  capture : NativeFrameCapture,
  test_click : NativeTestClick,
  test_escape : NativeTestEscape,
  e2e : Bool,
  smoke : Bool,
  evidence_dir : String?,
  evidence : FrameEvidence,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let mut dirty = true
  let gate = PresentationGate::{ rendered: false, pending_stale: false, }
  let mut pending : @sample.SampleFrame? = None
  let mut requested_close = false
  let mut destroyed = false
  let mut ticks = 0
  let mut presented_frames = 0
  let mut sequence : Int64 = 0
  let mut final_count = 0
  while !destroyed && ((!e2e && !smoke) || ticks < 2000) {
    ticks += 1
    let event = match host.next_event(timeout_ms=16) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    match event {
      None => ()
      Some(value) if value.window() == window => {
        if value.sequence() <= sequence {
          return Err(
            runner_error(
              "run_native_loop", "host event sequence did not advance",
            ),
          )
        }
        sequence = value.sequence()
        match value.kind() {
          @platform.Created => dirty = true
          @platform.Resized(..) | @platform.ScaleChanged => {
            sample.invalidate_layout()
            gate.invalidate_layout(pending is Some(_))
            dirty = true
          }
          @platform.FocusChanged(focused) => sample.focus_changed(focused)
          @platform.VisibilityChanged(visible) => if visible { dirty = true }
          @platform.Input(input) =>
            match input {
              @primitives.KeyPressed(key=@primitives.Escape, ..) =>
                match host.request_close(window) {
                  Err(error) => return Err(error)
                  Ok(_) => ()
                }
              _ if gate.input_ready() =>
                match sample.handle_input(input) {
                  Err(error) => return Err(error)
                  Ok(true) => {
                    final_count = match sample.count() {
                      Err(error) => return Err(error)
                      Ok(value) => value
                    }
                    emit_native_marker(
                      "YAMI_NATIVE_UI_CLICK {\"count\":\{final_count},\"value\":\{final_count},\"buttonId\":40}",
                    )
                    dirty = true
                  }
                  Ok(false) => ()
                }
              _ => ()
            }
          @platform.FrameCompleted =>
            match pending {
              None => ()
              Some(frame) => {
                pending = None
                if gate.completed_frame_is_current() {
                  presented_frames += 1
                  match
                    publish_frame(
                      host, window, frame, platform, e2e, evidence_dir, capture,
                      test_click, test_escape, evidence,
                    ) {
                    Err(error) => return Err(error)
                    Ok(_) => ()
                  }
                  if smoke && presented_frames == 1 {
                    match host.request_close(window) {
                      Err(error) => return Err(error)
                      Ok(_) => ()
                    }
                  }
                }
              }
            }
          @platform.CloseRequested => {
            requested_close = true
            match host.destroy_window(window) {
              Err(error) => return Err(error)
              Ok(_) => ()
            }
          }
          @platform.Destroyed => destroyed = true
          @platform.ExitRequested => {
            requested_close = true
            match host.destroy_window(window) {
              Err(error) => return Err(error)
              Ok(_) => ()
            }
          }
          @platform.Wake | @platform.Moved(..) => ()
        }
      }
      Some(_) => ()
    }
    if dirty && pending is None && !requested_close && !destroyed {
      let (width, height, scale) = match host.window_metrics(window) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      let frame = match sample.render(width, height, scale, measure) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      match host.present(window, frame.snapshot()) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      dirty = false
      gate.mark_presented()
      if platform is Macos {
        // Mac's Host.present waits for its Metal command buffer to complete.
        // Linux and Windows report FrameCompleted through their event queues.
        presented_frames += 1
        match
          publish_frame(
            host, window, frame, platform, e2e, evidence_dir, capture, test_click,
            test_escape, evidence,
          ) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
        if smoke && presented_frames == 1 {
          match host.request_close(window) {
            Err(error) => return Err(error)
            Ok(_) => ()
          }
        }
      } else {
        pending = Some(frame)
      }
    }
  }
  if !destroyed {
    // Bound test runs even when the host never presents or receives a close.
    let _ = host.request_close(window)
    let _ = host.destroy_window(window)
    return Err(
      runner_error(
        "run_native_loop", "native sample timed out before the host destroyed its window",
      ),
    )
  }
  final_count = match sample.count() {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if e2e {
    if final_count != 1 || presented_frames < 2 {
      return Err(
        runner_error(
          "run_native_loop", "native E2E closed before count 1 completed and presented",
        ),
      )
    }
    emit_native_marker(
      "YAMI_NATIVE_UI_COMPLETE {\"count\":\{final_count},\"value\":\{final_count},\"destroyed\":true,\"windowId\":\{window.value()}}",
    )
  } else if smoke {
    if presented_frames == 0 {
      return Err(
        runner_error(
          "run_native_loop", "native smoke closed without a completed frame",
        ),
      )
    }
    emit_native_marker(
      "YAMI_NATIVE_UI_SMOKE {\"frames\":\{presented_frames},\"destroyed\":true}",
    )
  }
  Ok(())
}

///|
fn publish_frame(
  _host : &@platform.Backend,
  window : @platform.WindowId,
  frame : @sample.SampleFrame,
  platform : NativeSamplePlatform,
  e2e : Bool,
  evidence_dir : String?,
  capture : NativeFrameCapture,
  test_click : NativeTestClick,
  test_escape : NativeTestEscape,
  evidence : FrameEvidence,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if !e2e {
    return Ok(())
  }
  let count = frame.count()
  if count != 0 && count != 1 {
    return Err(
      runner_error(
        "publish_frame", "E2E only supports the initial and one-click sample states",
      ),
    )
  }
  let expected_text = if count == 0 { "Clicks: 0" } else { "Clicks: 1" }
  if frame.counter_text() != expected_text ||
    !frame.canonical_scene().contains(expected_text) {
    return Err(
      runner_error(
        "publish_frame", "sample frame does not contain the current App Entity counter text",
      ),
    )
  }
  let captured = match capture(window) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let root_size = frame.root_bounds().size()
  if abs_int((root_size.width() * captured.scale()).to_int() - captured.width()) >
    1 ||
    abs_int(
      (root_size.height() * captured.scale()).to_int() - captured.height(),
    ) >
    1 {
    return Err(
      runner_error(
        "publish_frame", "logical host metrics and native capture dimensions disagree",
      ),
    )
  }
  let text_pixels = match
    contrast_pixels(
      captured,
      frame.counter_bounds(),
      frame.counter_background(),
    ) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let button_pixels = match
    contrast_pixels(captured, frame.button_bounds(), frame.button_background()) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let button_label_pixels = match
    contrast_pixels(
      captured,
      frame.button_label_bounds(),
      frame.button_background(),
    ) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if text_pixels <= 0 || button_pixels <= 0 || button_label_pixels <= 0 {
    return Err(
      runner_error(
        "publish_frame", "native capture has no visible counter glyphs or Button surface and label pixels",
      ),
    )
  }
  let changed_pixels = if count == 0 {
    0
  } else {
    match evidence.initial {
      None =>
        return Err(
          runner_error(
            "publish_frame", "count-0 native capture is missing before count 1",
          ),
        )
      Some(before) =>
        match changed_pixels_in(before, captured, frame.counter_bounds()) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
    }
  }
  if count == 1 && changed_pixels == 0 {
    return Err(
      runner_error(
        "publish_frame", "count-1 native capture did not change any counter ROI pixels",
      ),
    )
  }
  let path = match evidence_dir {
    None =>
      return Err(
        runner_error("publish_frame", "E2E evidence directory is missing"),
      )
    Some(directory) =>
      directory + (if count == 0 { "/before.ppm" } else { "/after.ppm" })
  }
  match captured.write_ppm(path) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if count == 0 {
    evidence.initial = Some(captured)
  }
  let escaped_path = json_escape(path)
  let frame_json = "{\"path\":\"\{escaped_path}\",\"width\":\{captured.width()},\"height\":\{captured.height()},\"scale\":\{captured.scale()}}"
  let viewport_json = "{\"width\":\{root_size.width()},\"height\":\{root_size.height()},\"scale\":\{captured.scale()}}"
  emit_native_marker(
    "YAMI_NATIVE_UI_PRESENTED {\"count\":\{count},\"value\":\{count},\"scene\":\{frame.canonical_scene()},\"frame\":\{frame_json},\"viewport\":\{viewport_json},\"textPixels\":\{text_pixels},\"buttonPixels\":\{button_pixels},\"buttonLabelPixels\":\{button_label_pixels},\"changedPixels\":\{changed_pixels},\"button\":\{rect_json(frame.button_bounds())},\"buttonLabel\":\{rect_json(frame.button_label_bounds())},\"counter\":\{rect_json(frame.counter_bounds())}}",
  )
  if count == 0 {
    let title = json_escape(window_title())
    emit_native_marker(
      "YAMI_NATIVE_UI_READY {\"windowId\":\{window.value()},\"title\":\"\{title}\",\"buttonId\":40,\"scale\":\{captured.scale()},\"button\":\{rect_json(frame.button_bounds())},\"buttonLabel\":\{rect_json(frame.button_label_bounds())},\"counter\":\{rect_json(frame.counter_bounds())}}",
    )
    if platform is Macos {
      let button = frame.button_bounds()
      let center = match
        @primitives.Point::new(
          button.left() + button.size().width() / 2.0,
          button.top() + button.size().height() / 2.0,
        ) {
        Err(_) =>
          return Err(runner_error("publish_frame", "Button center is invalid"))
        Ok(value) => value
      }
      match test_click(window, center) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    }
  } else if platform is Macos {
    match test_escape(window) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
fn contrast_pixels(
  capture : @testing.FrameCapture,
  bounds : @primitives.Rect,
  background : @primitives.Color,
) -> Result[Int, @diagnostics.FrameworkError] {
  let scale = capture.scale()
  let left = max(0, (bounds.left() * scale).to_int())
  let top = max(0, (bounds.top() * scale).to_int())
  let right = min(capture.width(), (bounds.right() * scale).to_int())
  let bottom = min(capture.height(), (bounds.bottom() * scale).to_int())
  let pixels = capture.rgba8_top_left()
  let mut visible = 0
  let mut y = top
  while y < bottom {
    let mut x = left
    while x < right {
      let offset = (y * capture.width() + x) * 4
      let red = pixels.unsafe_get(offset).to_int()
      let green = pixels.unsafe_get(offset + 1).to_int()
      let blue = pixels.unsafe_get(offset + 2).to_int()
      let distance = abs_int(red - background.red()) +
        abs_int(green - background.green()) +
        abs_int(blue - background.blue())
      if distance >= 24 {
        visible += 1
      }
      x += 1
    }
    y += 1
  }
  if left >= right || top >= bottom {
    Err(
      runner_error(
        "contrast_pixels", "native text region is outside the captured frame",
      ),
    )
  } else {
    Ok(visible)
  }
}

///|
fn changed_pixels_in(
  before : @testing.FrameCapture,
  after : @testing.FrameCapture,
  bounds : @primitives.Rect,
) -> Result[Int, @diagnostics.FrameworkError] {
  if before.width() != after.width() ||
    before.height() != after.height() ||
    before.scale() != after.scale() {
    return Err(
      runner_error(
        "changed_pixels_in", "native frame dimensions or scale changed during the sample click",
      ),
    )
  }
  let scale = before.scale()
  let left = max(0, (bounds.left() * scale).to_int())
  let top = max(0, (bounds.top() * scale).to_int())
  let right = min(before.width(), (bounds.right() * scale).to_int())
  let bottom = min(before.height(), (bounds.bottom() * scale).to_int())
  let first = before.rgba8_top_left()
  let second = after.rgba8_top_left()
  let mut changed = 0
  let mut y = top
  while y < bottom {
    let mut x = left
    while x < right {
      let offset = (y * before.width() + x) * 4
      if first.unsafe_get(offset) != second.unsafe_get(offset) ||
        first.unsafe_get(offset + 1) != second.unsafe_get(offset + 1) ||
        first.unsafe_get(offset + 2) != second.unsafe_get(offset + 2) {
        changed += 1
      }
      x += 1
    }
    y += 1
  }
  Ok(changed)
}

///|
fn rect_json(bounds : @primitives.Rect) -> String {
  "{\"x\":\{bounds.left()},\"y\":\{bounds.top()},\"width\":\{bounds.size().width()},\"height\":\{bounds.size().height()}}"
}

///|
fn window_title() -> String {
  match @env.get_env_var("YAMI_NATIVE_UI_WINDOW_TITLE") {
    Some(value) if value.length() > 0 => value
    _ => "Yami-kumo Native UI"
  }
}

///|
fn json_escape(value : String) -> String {
  let output = StringBuilder()
  for character in value.iter() {
    match character.to_int() {
      0x22 => output.write_string("\\\"")
      0x5C => output.write_string("\\\\")
      0x08 => output.write_string("\\b")
      0x09 => output.write_string("\\t")
      0x0A => output.write_string("\\n")
      0x0C => output.write_string("\\f")
      0x0D => output.write_string("\\r")
      value if value < 0x20 => {
        output.write_string("\\u00")
        output.write_char(hex_digit(value >> 4))
        output.write_char(hex_digit(value & 0xF))
      }
      _ => output.write_char(character)
    }
  }
  output.to_string()
}

///|
fn hex_digit(value : Int) -> Char {
  match value {
    0 => '0'
    1 => '1'
    2 => '2'
    3 => '3'
    4 => '4'
    5 => '5'
    6 => '6'
    7 => '7'
    8 => '8'
    9 => '9'
    10 => 'a'
    11 => 'b'
    12 => 'c'
    13 => 'd'
    14 => 'e'
    _ => 'f'
  }
}

///|
fn abs_int(value : Int) -> Int {
  if value < 0 {
    -value
  } else {
    value
  }
}

///|
fn min(left : Int, right : Int) -> Int {
  if left < right {
    left
  } else {
    right
  }
}

///|
fn max(left : Int, right : Int) -> Int {
  if left > right {
    left
  } else {
    right
  }
}

///|
fn runner_error(
  operation : String,
  message : String,
) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    @diagnostics.NativeFailure,
    operation,
    subsystem="native-sample-runner",
    message~,
  )
}
