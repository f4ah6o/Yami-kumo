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
///|
pub type NativeButtonAXPublish = (
  @platform.WindowId,
  Int64,
  @sample.NativeButtonAccessibilitySnapshot,
) -> Result[Int64, @diagnostics.FrameworkError]

///|
pub type NativeButtonAXRevoke = (@platform.WindowId, Int64) -> Result[
  Unit,
  @diagnostics.FrameworkError,
]

///|
pub type NativeButtonAXTakeRequest = (@platform.WindowId) -> Result[
  Int64?,
  @diagnostics.FrameworkError,
]

///|
/// Optional native accessibility transport for the sample's existing Button.
/// The shared runner retains the current sample snapshot and validates actions;
/// a platform adapter only publishes, revokes, and returns opaque tokens.
pub struct NativeButtonAXPort {
  publish : NativeButtonAXPublish
  revoke : NativeButtonAXRevoke
  take_request : NativeButtonAXTakeRequest
}

///|
pub fn NativeButtonAXPort::new(
  publish : NativeButtonAXPublish,
  revoke : NativeButtonAXRevoke,
  take_request : NativeButtonAXTakeRequest,
) -> NativeButtonAXPort {
  { publish, revoke, take_request, }
}

///|
priv struct NativeButtonAXBinding {
  snapshot : @sample.NativeButtonAccessibilitySnapshot
  transport_token : Int64
}

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
/// supply E2E-scoped native frame readback. The platform driver supplies input.
pub fn run_native_sample(
  host : &@platform.Backend,
  platform : NativeSamplePlatform,
  measure : @components.TextMeasure,
  capture : NativeFrameCapture,
  accessibility_port? : NativeButtonAXPort? = None,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let args = @env.args()
  let e2e = args.contains("--e2e") ||
    @env.get_env_var("YAMI_NATIVE_UI_E2E") == Some("1")
  let smoke = args.contains("--smoke") ||
    @env.get_env_var("YAMI_NATIVE_UI_SMOKE") == Some("1")
  let ax_e2e = args.contains("--ax-e2e") ||
    @env.get_env_var("YAMI_NATIVE_UI_AX_E2E") == Some("1")
  if (e2e && smoke) || (e2e && ax_e2e) || (smoke && ax_e2e) {
    return Err(
      runner_error(
        "run_native_sample", "native UI proof modes cannot be combined",
      ),
    )
  }
  if ax_e2e && (!(platform is Macos) || accessibility_port is None) {
    return Err(
      runner_error(
        "run_native_sample", "AX E2E requires the macOS Button accessibility adapter",
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
    host, window, sample, platform, measure, capture, e2e, smoke, ax_e2e,
    accessibility_port, evidence_dir, evidence,
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
  e2e : Bool,
  smoke : Bool,
  ax_e2e : Bool,
  accessibility_port : NativeButtonAXPort?,
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
  let mut accessibility_binding : NativeButtonAXBinding? = None
  while !destroyed && ((!e2e && !smoke && !ax_e2e) || ticks < 2000) {
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
                      host, window, frame, e2e, evidence_dir, capture, evidence,
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
            accessibility_binding = match accessibility_port {
              None => accessibility_binding
              Some(port) =>
                match
                  revoke_native_button_accessibility(
                    port, window, accessibility_binding,
                  ) {
                  Err(error) => return Err(error)
                  Ok(value) => value
                }
            }
            match host.destroy_window(window) {
              Err(error) => return Err(error)
              Ok(_) => ()
            }
          }
          @platform.Destroyed => destroyed = true
          @platform.ExitRequested => {
            requested_close = true
            accessibility_binding = match accessibility_port {
              None => accessibility_binding
              Some(port) =>
                match
                  revoke_native_button_accessibility(
                    port, window, accessibility_binding,
                  ) {
                  Err(error) => return Err(error)
                  Ok(value) => value
                }
            }
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
    if !requested_close && !destroyed {
      match accessibility_port {
        None => ()
        Some(port) =>
          match
            take_native_button_accessibility_actions(
              port, window, sample, accessibility_binding,
            ) {
            Err(error) => return Err(error)
            Ok((next_binding, activated)) => {
              accessibility_binding = next_binding
              if activated {
                final_count = match sample.count() {
                  Err(error) => return Err(error)
                  Ok(value) => value
                }
                emit_native_marker(
                  "YAMI_NATIVE_UI_CLICK {\"count\":\{final_count},\"value\":\{final_count},\"buttonId\":40,\"source\":\"accessibility\"}",
                )
                dirty = true
              }
            }
          }
      }
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
        accessibility_binding = match accessibility_port {
          None => accessibility_binding
          Some(port) =>
            match
              sync_native_button_accessibility(
                port, window, sample, accessibility_binding,
              ) {
              Err(error) => return Err(error)
              Ok(value) => value
            }
        }
        if ax_e2e && presented_frames == 1 {
          let title = json_escape(window_title())
          emit_native_marker(
            "YAMI_NATIVE_UI_AX_READY {\"windowId\":\{window.value()},\"title\":\"\{title}\",\"buttonId\":40}",
          )
        }
        match
        publish_frame(
          host, window, frame, e2e, evidence_dir, capture, evidence,
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
    accessibility_binding = match accessibility_port {
      None => accessibility_binding
      Some(port) =>
        match
          revoke_native_button_accessibility(
            port, window, accessibility_binding,
          ) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
    }
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
  } else if ax_e2e {
    if final_count != 1 || presented_frames < 2 {
      return Err(
        runner_error(
          "run_native_loop", "native AX E2E closed before one accepted action was presented",
        ),
      )
    }
    emit_native_marker(
      "YAMI_NATIVE_UI_AX_COMPLETE {\"count\":\{final_count},\"value\":\{final_count},\"destroyed\":true,\"windowId\":\{window.value()}}",
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
fn native_button_ax_snapshot_matches(
  left : @sample.NativeButtonAccessibilitySnapshot,
  right : @sample.NativeButtonAccessibilitySnapshot,
) -> Bool {
  left.id() == right.id() &&
  left.name() == right.name() &&
  left.bounds() == right.bounds() &&
  left.enabled() == right.enabled() &&
  left.loading() == right.loading() &&
  left.focused() == right.focused() &&
  left.activations() == right.activations() &&
  left.same_revision(right)
}

///|
fn native_button_ax_requires_new_binding(
  previous : @sample.NativeButtonAccessibilitySnapshot,
  current : @sample.NativeButtonAccessibilitySnapshot,
) -> Bool {
  !previous.same_revision(current) ||
  previous.id() != current.id() ||
  previous.name() != current.name() ||
  previous.bounds() != current.bounds() ||
  previous.enabled() != current.enabled() ||
  previous.loading() != current.loading()
}

///|
fn sync_native_button_accessibility(
  port : NativeButtonAXPort,
  window : @platform.WindowId,
  sample : @sample.NativeSample,
  binding : NativeButtonAXBinding?,
) -> Result[NativeButtonAXBinding?, @diagnostics.FrameworkError] {
  let current = match sample.button_accessibility_snapshot() {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  match (binding, current) {
    (None, None) => Ok(None)
    (Some(previous), None) =>
      match (port.revoke)(window, previous.transport_token) {
        Err(error) => Err(error)
        Ok(_) => Ok(None)
      }
    (None, Some(snapshot)) =>
      match (port.publish)(window, 0, snapshot) {
        Err(error) => Err(error)
        Ok(token) => Ok(Some({ snapshot, transport_token: token, }))
      }
    (Some(previous), Some(snapshot)) => {
      if native_button_ax_snapshot_matches(previous.snapshot, snapshot) {
        return Ok(Some(previous))
      }
      let existing_token = if native_button_ax_requires_new_binding(
          previous.snapshot,
          snapshot,
        ) {
        match (port.revoke)(window, previous.transport_token) {
          Err(error) => return Err(error)
          Ok(_) => Int64::from_int(0)
        }
      } else {
        previous.transport_token
      }
      match (port.publish)(window, existing_token, snapshot) {
        Err(error) => Err(error)
        Ok(token) => Ok(Some({ snapshot, transport_token: token, }))
      }
    }
  }
}

///|
/// Drain the bounded host request queue. A token is only actionable while it
/// names the current Yami snapshot; accepted actions immediately refresh the
/// same owner state before another queued request is considered.
fn take_native_button_accessibility_actions(
  port : NativeButtonAXPort,
  window : @platform.WindowId,
  sample : @sample.NativeSample,
  binding : NativeButtonAXBinding?,
) -> Result[(NativeButtonAXBinding?, Bool), @diagnostics.FrameworkError] {
  let mut current_binding = match
    sync_native_button_accessibility(port, window, sample, binding) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let mut accepted = false
  let mut drained = false
  let mut consumed = 0
  while consumed < 64 && !drained {
    match (port.take_request)(window) {
      Err(error) => return Err(error)
      Ok(None) => drained = true
      Ok(Some(token)) => {
        consumed += 1
        match current_binding {
          Some(binding) if binding.transport_token == token =>
            match sample.activate_accessibility_button(binding.snapshot) {
              Err(error) => return Err(error)
              Ok(false) => ()
              Ok(true) => {
                accepted = true
                current_binding = match
                  sync_native_button_accessibility(
                    port, window, sample, current_binding,
                  ) {
                  Err(error) => return Err(error)
                  Ok(value) => value
                }
              }
            }
          _ => ()
        }
      }
    }
  }
  Ok((current_binding, accepted))
}

///|
fn revoke_native_button_accessibility(
  port : NativeButtonAXPort,
  window : @platform.WindowId,
  binding : NativeButtonAXBinding?,
) -> Result[NativeButtonAXBinding?, @diagnostics.FrameworkError] {
  match binding {
    None => Ok(None)
    Some(value) =>
      match (port.revoke)(window, value.transport_token) {
        Err(error) => Err(error)
        Ok(_) => Ok(None)
      }
  }
}

///|
fn publish_frame(
  _host : &@platform.Backend,
  window : @platform.WindowId,
  frame : @sample.SampleFrame,
  e2e : Bool,
  evidence_dir : String?,
  capture : NativeFrameCapture,
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
