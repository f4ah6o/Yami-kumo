///|
/// The only platform distinction is synchronous versus event-completed presentation.
pub(all) enum NativePlatform {
  Macos
  Linux
  Windows
}

///|
pub type FrameCapture = (@platform.WindowId) -> Result[
  @testing.FrameCapture,
  @diagnostics.FrameworkError,
]

///|
/// A copied macOS AX projection for the one shared-shell main Button.
pub struct ShellAXSnapshot {
  priv name : String
  priv bounds : @primitives.Rect
  priv enabled : Bool
  priv loading : Bool
  priv focused : Bool
  priv activations : Int32
}

///|
pub fn ShellAXSnapshot::new(
  name : String,
  bounds : @primitives.Rect,
  enabled : Bool,
  loading : Bool,
  focused : Bool,
  activations : Int32,
) -> ShellAXSnapshot {
  { name, bounds, enabled, loading, focused, activations, }
}

///|
pub fn ShellAXSnapshot::name(self : ShellAXSnapshot) -> String {
  self.name
}

///|
pub fn ShellAXSnapshot::bounds(self : ShellAXSnapshot) -> @primitives.Rect {
  self.bounds
}

///|
pub fn ShellAXSnapshot::enabled(self : ShellAXSnapshot) -> Bool {
  self.enabled
}

///|
pub fn ShellAXSnapshot::loading(self : ShellAXSnapshot) -> Bool {
  self.loading
}

///|
pub fn ShellAXSnapshot::focused(self : ShellAXSnapshot) -> Bool {
  self.focused
}

///|
pub fn ShellAXSnapshot::activations(self : ShellAXSnapshot) -> Int32 {
  self.activations
}

///|
pub type ShellAXPublish = (
  @platform.WindowId,
  Int64,
  ShellAXSnapshot,
) -> Result[Int64, @diagnostics.FrameworkError]

///|
pub type ShellAXRevoke = (@platform.WindowId, Int64) -> Result[
  Unit,
  @diagnostics.FrameworkError,
]

///|
pub type ShellAXTakeRequest = (@platform.WindowId) -> Result[
  Int64?,
  @diagnostics.FrameworkError,
]

///|
/// Optional macOS AX transport for the shared shell's main Button. The shared
/// runner owns the snapshot and semantic action; the platform only publishes,
/// revokes, and returns opaque tokens.
pub struct ShellAXPort {
  priv publish : ShellAXPublish
  priv revoke : ShellAXRevoke
  priv take_request : ShellAXTakeRequest
}

///|
pub fn ShellAXPort::new(
  publish : ShellAXPublish,
  revoke : ShellAXRevoke,
  take_request : ShellAXTakeRequest,
) -> ShellAXPort {
  { publish, revoke, take_request, }
}

///|
fn sync_shell_ax(
  port : ShellAXPort,
  window : @platform.WindowId,
  frame : @shared_counter.CounterFrame,
  activations : Int32,
  existing : Int64?,
) -> Result[Int64?, @diagnostics.FrameworkError] {
  let snapshot = ShellAXSnapshot::new(
    "Increment",
    frame.button_bounds(),
    frame.button_enabled(),
    frame.button_loading(),
    frame.button_focused(),
    activations,
  )
  match (port.publish)(
    window,
    match existing {
      Some(value) => value
      None => Int64::from_int(0)
    },
    snapshot,
  ) {
    Err(error) => Err(error)
    Ok(token) => Ok(Some(token))
  }
}

///|
fn revoke_shell_ax(
  port : ShellAXPort,
  window : @platform.WindowId,
  binding : Int64?,
) -> Result[Unit, @diagnostics.FrameworkError] {
  match binding {
    None => Ok(())
    Some(token) => (port.revoke)(window, token)
  }
}

///|
extern "C" fn flush_stdout() -> Unit = "yami_shared_ui_flush_stdout"

///|
fn emit(marker : String, payload : String) -> Unit {
  println(marker + " " + payload)
  flush_stdout()
}

///|
pub fn format_error(error : @diagnostics.FrameworkError) -> String {
  error.operation() +
  ": " +
  error.code().label() +
  (match error.message() {
    Some(value) => ": " + value
    None => ""
  })
}

///|
priv struct PresentationGate {
  mut rendered : Bool
  mut pending_stale : Bool
}

///|
fn PresentationGate::invalidate(
  self : PresentationGate,
  pending : Bool,
) -> Unit {
  self.rendered = false
  if pending {
    self.pending_stale = true
  }
}

///|
fn PresentationGate::changed(self : PresentationGate, pending : Bool) -> Unit {
  if pending {
    self.pending_stale = true
  }
}

///|
fn PresentationGate::complete(self : PresentationGate) -> Bool {
  let current = !self.pending_stale
  self.pending_stale = false
  current
}

///|
priv struct Proof {
  fixture : String
  mut phase : Int32
  mut releases : Int32
  mut actions : Int32
  mut frame_index : Int32
  mut last_payload : String?
  mut last_phase : Int32
  events : Array[String]
  mut frame_trace : String
}

///|
/// Run the common Model/view/update through one App Entity on an actual Host.
/// Test-only gate phases affect view props, never the domain Model or controller.
pub fn run(
  host : &@platform.Backend,
  platform : NativePlatform,
  measure : @components.TextMeasure,
  capture : FrameCapture,
  accessibility_port? : ShellAXPort? = None,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let e2e = @env.get_env_var("YAMI_NATIVE_UI_E2E") == Some("1")
  let ax_e2e = @env.get_env_var("YAMI_NATIVE_UI_AX_E2E") == Some("1")
  let fixture = match @env.get_env_var("YAMI_SHARED_UI_FIXTURE") {
    None => "counter"
    Some("counter") => "counter"
    Some("card") => "card"
    Some("spacing") => "spacing"
    Some("theme") => "theme"
    Some("palette") => "palette"
    Some("shell") => "shell"
    Some("shell-compact") => "shell-compact"
    Some("shell-visible") => "shell-visible"
    Some("shell-visible-compact") => "shell-visible-compact"
    Some("disabled-loading") if e2e => "disabled-loading"
    _ => return Err(runner_error("invalid shared counter fixture"))
  }
  let directory = @env.get_env_var("YAMI_NATIVE_UI_EVIDENCE_DIR")
  if e2e &&
    (
      @env.get_env_var("GPUI_NATIVE_E2E") != Some("1") ||
      directory is None ||
      directory == Some("")
    ) {
    return Err(
      runner_error(
        "E2E requires opt-in frame capture and an evidence directory",
      ),
    )
  }
  for
    capability in [
      @platform.NativeWindow,
      @platform.QuadFrames,
      @platform.GrayscaleTextFrames,
      @platform.PointerKeyboard,
    ] {
    match host.require_capability(capability) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  let title = match @env.get_env_var("YAMI_NATIVE_UI_WINDOW_TITLE") {
    Some(value) if value.length() > 0 => value
    _ => "Yami-kumo Shared Counter"
  }
  if fixture == "theme" {
    return run_theme(host, platform, measure, capture, e2e, directory, title)
  }
  let (width, height) = match fixture {
    "shell" | "shell-visible" => (1000.0, 700.0)
    "shell-compact" | "shell-visible-compact" => (700.0, 700.0)
    _ => (800.0, 600.0)
  }
  let window = match host.create_window(title, width, height) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let app = match
    @shared_counter.NativeCounter::new(
      window,
      disabled=fixture == "disabled-loading",
      card=fixture == "card",
      spacing=fixture == "spacing",
      palette=fixture == "palette",
      shell=fixture == "shell" || fixture == "shell-compact" ||
        fixture == "shell-visible" || fixture == "shell-visible-compact",
    ) {
    Err(error) => {
      let _ = host.destroy_window(window)
      return Err(error)
    }
    Ok(value) => value
  }
  let result = run_loop(
    host,
    window,
    app,
    platform,
    measure,
    capture,
    e2e,
    fixture,
    directory,
    title,
    accessibility_port,
    ax_e2e,
  )
  app.dispose()
  match result {
    Err(error) => {
      let _ = host.destroy_window(window)
      Err(error)
    }
    Ok(_) => Ok(())
  }
}

///|
fn run_loop(
  host : &@platform.Backend,
  window : @platform.WindowId,
  app : @shared_counter.NativeCounter,
  platform : NativePlatform,
  measure : @components.TextMeasure,
  capture : FrameCapture,
  e2e : Bool,
  fixture : String,
  directory : String?,
  title : String,
  accessibility_port : ShellAXPort?,
  ax_e2e : Bool,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let gate = PresentationGate::{ rendered: false, pending_stale: false, }
  let proof = Proof::{
    fixture,
    phase: 0,
    releases: 0,
    actions: 0,
    frame_index: 0,
    last_payload: None,
    last_phase: -1,
    events: [],
    frame_trace: "",
  }
  let mut pending : @shared_counter.CounterFrame? = None
  let mut current : @shared_counter.CounterFrame? = None
  let mut dirty = true
  let mut closing = false
  let mut destroyed = false
  let mut sequence : Int64 = 0
  let mut ticks = 0
  let mut ax_binding : Int64? = None
  let mut ax_ready = false
  while !destroyed && (!e2e || ticks < 4000) {
    ticks += 1
    match accessibility_port {
      Some(port) =>
        match (port.take_request)(window) {
          Err(error) => return Err(error)
          Ok(None) => ()
          Ok(Some(token)) =>
            match ax_binding {
              Some(binding) if binding == token =>
                match app.activate_increment() {
                  Err(error) => return Err(error)
                  Ok(false) => ()
                  Ok(true) => {
                    let (width, height, scale) = match
                      host.window_metrics(window) {
                      Err(error) => return Err(error)
                      Ok(value) => value
                    }
                    let mut drained = 0
                    while true {
                      match app.drain_one(width, height, scale, measure) {
                        Err(error) => return Err(error)
                        Ok(false) => break
                        Ok(true) => {
                          proof.actions += 1
                          drained += 1
                          if drained > 32 {
                            return Err(
                              runner_error("unbounded shared action queue"),
                            )
                          }
                        }
                      }
                    }
                    if drained > 0 {
                      proof.phase = proof.actions
                      gate.invalidate(pending is Some(_))
                      if pending is Some(_) {
                        app.invalidate_layout()
                      }
                      dirty = true
                    }
                  }
                }
              _ => ()
            }
        }
      None => ()
    }
    let event = match host.next_event(timeout_ms=16) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    match event {
      Some(value) if value.window() == window => {
        if value.sequence() <= sequence {
          return Err(runner_error("host event sequence did not advance"))
        }
        sequence = value.sequence()
        // Even non-input events reach the adapter's window/sequence lifetime gate.
        let before_dispatch = app.last_dispatched_input_sequence()
        let consumed = match app.handle_event(value) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
        if e2e && fixture == "palette" {
          if proof.events.length() >= 4096 {
            return Err(runner_error("palette event trace limit exceeded"))
          }
          let after_dispatch = app.last_dispatched_input_sequence()
          proof.events.push(
            palette_event_json(value, consumed, before_dispatch, after_dispatch),
          )
        }
        match value.kind() {
          @platform.Created => dirty = true
          @platform.Resized(..) | @platform.ScaleChanged => {
            gate.invalidate(pending is Some(_))
            dirty = true
          }
          @platform.FocusChanged(_) => {
            gate.changed(pending is Some(_))
            dirty = true
          }
          @platform.VisibilityChanged(visible) =>
            if visible {
              dirty = true
            } else {
              gate.invalidate(pending is Some(_))
            }
          @platform.Input(input) =>
            match input {
              @primitives.KeyPressed(key=@primitives.Escape, ..) =>
                match host.request_close(window) {
                  Err(error) => return Err(error)
                  Ok(_) => ()
                }
              _ if gate.rendered &&
                !closing &&
                (match current {
                  Some(frame) => frame.snapshot().scale() == value.scale()
                  None => false
                }) => {
                let (width, height, scale) = match host.window_metrics(window) {
                  Err(error) => return Err(error)
                  Ok(value) => value
                }
                let mut drained = 0
                while true {
                  match app.drain_one(width, height, scale, measure) {
                    Err(error) => return Err(error)
                    Ok(false) => break
                    Ok(true) => {
                      drained += 1
                      proof.actions += 1
                      if drained > 32 {
                        return Err(
                          runner_error("unbounded shared action queue"),
                        )
                      }
                    }
                  }
                }
                let inside_release = match (input, current) {
                  (
                    @primitives.PointerButtonReleased(
                      position~,
                      button=@primitives.Primary,
                      ..
                    ),
                    Some(frame),
                  ) =>
                    if (fixture == "spacing" && proof.phase % 2 == 1) ||
                      (
                        fixture == "palette" &&
                        (proof.phase == 1 || proof.phase >= 3)
                      ) {
                      frame.toggle_bounds().contains(position)
                    } else {
                      frame.button_bounds().contains(position)
                    }
                  _ => false
                }
                if e2e && inside_release {
                  proof.releases += 1
                  if fixture == "disabled-loading" && proof.phase < 2 {
                    proof.phase += 1
                    match
                      app.set_mode(
                        false,
                        proof.phase == 1,
                        width,
                        height,
                        scale,
                        measure,
                      ) {
                      Err(error) => return Err(error)
                      Ok(_) => ()
                    }
                    gate.invalidate(pending is Some(_))
                    if pending is Some(_) {
                      app.invalidate_layout()
                    }
                  } else {
                    proof.phase = if fixture != "disabled-loading" {
                      proof.actions
                    } else {
                      3
                    }
                  }
                }
                if drained > 0 {
                  gate.invalidate(pending is Some(_))
                  if pending is Some(_) {
                    app.invalidate_layout()
                  }
                }
                gate.changed(pending is Some(_))
                dirty = true
              }
              _ =>
                // The adapter has rejected mismatched scale or invalid geometry.
                // Request a new accepted frame without replaying this input.
                if !closing {
                  gate.invalidate(pending is Some(_))
                  dirty = true
                }
            }
          @platform.FrameCompleted =>
            match pending {
              None => ()
              Some(frame) => {
                pending = None
                if gate.complete() && e2e {
                  match
                    publish(window, frame, capture, directory, title, proof) {
                    Err(error) => return Err(error)
                    Ok(_) => ()
                  }
                }
              }
            }
          @platform.CloseRequested | @platform.ExitRequested => {
            closing = true
            match accessibility_port {
              Some(port) =>
                match revoke_shell_ax(port, window, ax_binding) {
                  Err(error) => return Err(error)
                  Ok(_) => ax_binding = None
                }
              None => ()
            }
            match host.destroy_window(window) {
              Err(error) => return Err(error)
              Ok(_) => ()
            }
          }
          @platform.Destroyed => {
            match accessibility_port {
              Some(port) =>
                match revoke_shell_ax(port, window, ax_binding) {
                  Err(error) => return Err(error)
                  Ok(_) => ax_binding = None
                }
              None => ()
            }
            destroyed = true
          }
          @platform.Wake | @platform.Moved(..) => ()
        }
      }
      _ => ()
    }
    if dirty && pending is None && !closing && !destroyed {
      let (width, height, scale) = match host.window_metrics(window) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      let frame = match app.render(width, height, scale, measure) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      if e2e && fixture == "palette" {
        // Freeze before presentation: later completion events cannot relabel this scene.
        proof.frame_trace = "\"inputTrace\":{\"revision\":\{frame.revision()},\"throughSequence\":\{sequence},\"events\":[" +
          proof.events.join(",") +
          "]},"
      }
      match host.present(window, frame.snapshot()) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      dirty = false
      gate.rendered = true
      current = Some(frame)
      match accessibility_port {
        Some(port) =>
          ax_binding = match
            sync_shell_ax(port, window, frame, proof.actions, ax_binding) {
            Err(error) => return Err(error)
            Ok(value) => value
          }
        None => ()
      }
      if ax_e2e && !ax_ready {
        emit(
          "YAMI_NATIVE_UI_AX_READY",
          "{\"windowId\":\{window.value()},\"title\":\"" +
          escape_json(title) +
          "\",\"buttonId\":\{frame.button_binding_id()}}",
        )
        ax_ready = true
      }
      if platform is Macos {
        if e2e {
          match publish(window, frame, capture, directory, title, proof) {
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
    return Err(runner_error("host window destruction timed out"))
  }
  if ax_e2e {
    emit(
      "YAMI_NATIVE_UI_AX_COMPLETE",
      "{\"count\":\{proof.actions},\"value\":\{proof.actions},\"destroyed\":true,\"windowId\":\{window.value()}}",
    )
  }
  if e2e && !ax_e2e {
    let render_only = fixture == "shell-visible" ||
      fixture == "shell-visible-compact"
    let expected_phase = if render_only {
      0
    } else if fixture == "palette" {
      5
    } else if fixture == "spacing" {
      4
    } else if fixture != "disabled-loading" {
      2
    } else {
      3
    }
    let expected_actions = if render_only {
      0
    } else if fixture == "palette" {
      5
    } else if fixture == "spacing" {
      4
    } else if fixture != "disabled-loading" {
      2
    } else {
      1
    }
    if proof.last_phase != expected_phase ||
      proof.actions != expected_actions ||
      proof.releases != expected_phase {
      return Err(
        runner_error("counter closed before the complete fixture was presented"),
      )
    }
    match proof.last_payload {
      None =>
        return Err(runner_error("counter closed without presented evidence"))
      Some(payload) =>
        emit("YAMI_NATIVE_UI_COMPLETE", "{\"destroyed\":true," + payload)
    }
  }
  Ok(())
}

///|
fn shell_json(frame : @shared_counter.CounterFrame) -> String {
  let mode = match frame.shell_mode() {
    Some(@view.Wide) => "wide"
    Some(@view.Compact) => "compact"
    None => "none"
  }
  let regions = StringBuilder()
  regions.write_string("{")
  let entries : Array[(String, @view.ShellRegion)] = [
    ("brand", @view.Brand),
    ("navigationTrigger", @view.NavigationTrigger),
    ("globalSearch", @view.GlobalSearch),
    ("headerActions", @view.HeaderActions),
    ("accountMenu", @view.AccountMenu),
    ("rail", @view.Rail),
    ("sidebar", @view.Sidebar),
    ("tabs", @view.Tabs),
    ("main", @view.Main),
    ("contextPanel", @view.ContextPanel),
    ("bottomBar", @view.BottomBar),
  ]
  for index, entry in entries {
    let (name, region) = entry
    if index > 0 {
      regions.write_string(",")
    }
    regions.write_string("\"" + name + "\":")
    regions.write_string(
      match frame.shell_region_bounds(region) {
        Some(rect) => rect_json(rect)
        None => "null"
      },
    )
  }
  regions.write_string("}")
  "\"shell\":{\"mode\":\"" + mode + "\",\"regions\":" + regions.to_string() + "},"
}

///|
fn publish(
  window : @platform.WindowId,
  frame : @shared_counter.CounterFrame,
  capture : FrameCapture,
  directory : String?,
  title : String,
  proof : Proof,
) -> Result[Unit, @diagnostics.FrameworkError] {
  // Transient hover/press presentations are real frames, but are not fixture
  // observations. A phase is recorded once, after its button has settled.
  if frame.button_pressed() ||
    frame.toggle_pressed() ||
    proof.phase == proof.last_phase {
    return Ok(())
  }
  let directory = match directory {
    Some(value) => value
    None => return Err(runner_error("missing capture directory"))
  }
  let captured = match capture(window) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let index = proof.frame_index
  proof.frame_index += 1
  let path = directory + "/frame-\{index}.ppm"
  match captured.write_ppm(path) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let actions = StringBuilder()
  actions.write_string("[")
  for index = 0; index < proof.actions; index = index + 1 {
    if index > 0 {
      actions.write_string(",")
    }
    actions.write_string("\"Activate\"")
  }
  actions.write_string("]")
  let spacing_payload = if proof.fixture == "palette" {
    palette_json(frame) + proof.frame_trace
  } else if proof.fixture == "spacing" {
    spacing_json(frame)
  } else {
    ""
  }
  // Store a JSON object tail so completion can add destroyed without reparsing.
  let payload = spacing_payload + shell_json(frame) +
    "\"fixture\":\"\{proof.fixture}\",\"phase\":\{proof.phase},\"count\":\{frame.count()},\"value\":\{frame.count()},\"enabled\":\{frame.button_enabled()},\"loading\":\{frame.button_loading()},\"pressed\":\{frame.button_pressed()},\"focused\":\{frame.button_focused()},\"releases\":\{proof.releases},\"actions\":\{actions.to_string()},\"windowId\":\{window.value()},\"title\":\"\{escape_json(title)}\",\"buttonName\":\"Increment\",\"inputMode\":\"ax-frame\",\"button\":\{rect_json(frame.button_bounds())},\"buttonLabel\":\{rect_json(frame.button_label_bounds())},\"counter\":\{rect_json(frame.counter_bounds())},\"card\":\{rect_json(frame.card_bounds())},\"heading\":\{rect_json(frame.heading_bounds())},\"root\":\{rect_json(frame.root_bounds())},\"scale\":\{captured.scale()},\"scene\":\{frame.snapshot().canonical_json()},\"frame\":{\"path\":\"\{escape_json(path)}\",\"width\":\{captured.width()},\"height\":\{captured.height()},\"scale\":\{captured.scale()}}}"
  emit("YAMI_NATIVE_UI_PRESENTED", "{" + payload)
  if proof.last_payload is None {
    emit("YAMI_NATIVE_UI_READY", "{" + payload)
  }
  proof.last_payload = Some(payload)
  proof.last_phase = proof.phase
  Ok(())
}

///|
fn rect_json(rect : @primitives.Rect) -> String {
  "{\"x\":\{rect.left()},\"y\":\{rect.top()},\"width\":\{rect.size().width()},\"height\":\{rect.size().height()}}"
}

///|
fn escape_json(value : String) -> String {
  let output = StringBuilder()
  for character in value.iter() {
    match character.to_int() {
      0x22 => output.write_string("\\\"")
      0x5c => output.write_string("\\\\")
      0x08 => output.write_string("\\b")
      0x09 => output.write_string("\\t")
      0x0a => output.write_string("\\n")
      0x0c => output.write_string("\\f")
      0x0d => output.write_string("\\r")
      code if code < 0x20 => {
        output.write_string("\\u00")
        let digits = "0123456789abcdef"
        output.write_char(digits[code >> 4].to_char().unwrap())
        output.write_char(digits[code & 15].to_char().unwrap())
      }
      _ => output.write_char(character)
    }
  }
  output.to_string()
}

///|
fn runner_error(message : String) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    @diagnostics.NativeFailure,
    "shared_counter_host",
    subsystem="shared-ui",
    message~,
  )
}

///|
fn spacing_json(frame : @shared_counter.CounterFrame) -> String {
  let keys = StringBuilder()
  keys.write_string("[")
  for index, key in frame.action_keys() {
    if index > 0 {
      keys.write_string(",")
    }
    keys.write_string("\"" + escape_json(key) + "\"")
  }
  keys.write_string("]")
  "\"spacing\":{\"expanded\":\{frame.expanded()},\"stack\":\{rect_json(frame.stack_bounds())},\"row\":\{rect_json(frame.row_bounds())},\"cardLabel\":\{rect_json(frame.card_label_bounds())},\"toggle\":\{rect_json(frame.toggle_bounds())},\"toggleLabel\":\{rect_json(frame.toggle_label_bounds())},\"togglePressed\":\{frame.toggle_pressed()},\"toggleFocused\":\{frame.toggle_focused()},\"buttonId\":\{frame.button_binding_id()},\"toggleId\":\{frame.toggle_binding_id()},\"actionKeys\":\{keys.to_string()}},"
}

///|
/// All observations come from the accepted frame, never subsequent live input.
fn palette_json(frame : @shared_counter.CounterFrame) -> String {
  let token = match frame.button_palette() {
    None => "none"
    Some(Light) => "light"
    Some(Dark) => "dark"
  }
  let toggle_token = match frame.toggle_palette() {
    None => "none"
    Some(Light) => "light"
    Some(Dark) => "dark"
  }
  let keys = StringBuilder()
  keys.write_string("[")
  for index, key in frame.action_keys() {
    if index > 0 {
      keys.write_string(",")
    }
    keys.write_string("\"" + escape_json(key) + "\"")
  }
  keys.write_string("]")
  "\"palette\":{\"token\":\"\{token}\",\"toggleToken\":\"\{toggle_token}\",\"hovered\":\{frame.button_hovered()},\"toggleEnabled\":\{frame.toggle_enabled()},\"toggleLoading\":\{frame.toggle_loading()},\"toggleHovered\":\{frame.toggle_hovered()},\"togglePressed\":\{frame.toggle_pressed()},\"toggleFocused\":\{frame.toggle_focused()},\"toggle\":\{rect_json(frame.toggle_bounds())},\"toggleLabel\":\{rect_json(frame.toggle_label_bounds())},\"buttonId\":\{frame.button_binding_id()},\"toggleId\":\{frame.toggle_binding_id()},\"revision\":\{frame.revision()},\"actionKeys\":\{keys.to_string()}},"
}

///|
fn palette_event_json(
  event : @platform.Event,
  consumed : Bool,
  before_dispatch : Int64,
  after_dispatch : Int64,
) -> String {
  let dispatched = after_dispatch == event.sequence() &&
    after_dispatch != before_dispatch
  let detail = match event.kind() {
    @platform.Input(@primitives.PointerMoved(position~)) =>
      "\"kind\":\"move\",\"x\":\{position.x()},\"y\":\{position.y()}"
    @platform.Input(
      @primitives.PointerButtonPressed(
        position~,
        button=@primitives.Primary,
        ..
      )
    ) => "\"kind\":\"primary-down\",\"x\":\{position.x()},\"y\":\{position.y()}"
    @platform.Input(
      @primitives.PointerButtonReleased(
        position~,
        button=@primitives.Primary,
        ..
      )
    ) => "\"kind\":\"primary-up\",\"x\":\{position.x()},\"y\":\{position.y()}"
    @platform.Input(_) => "\"kind\":\"other-input\""
    @platform.FocusChanged(focused) =>
      "\"kind\":\"focus\",\"focused\":\{focused}"
    _ => "\"kind\":\"other-window\""
  }
  "{\"sequence\":\{event.sequence()},\"scale\":\{event.scale()},\"consumed\":\{consumed},\"dispatched\":\{dispatched},\"beforeDispatch\":\{before_dispatch},\"afterDispatch\":\{after_dispatch}," +
  detail +
  "}"
}
