///|
pub type NativeTextBegin = (@platform.WindowId, UInt64) -> Result[
  UInt64,
  @diagnostics.FrameworkError,
]

///|
pub type NativeTextUpdate = (UInt64, @text_host.TextInputState) -> Result[
  UInt64,
  @diagnostics.FrameworkError,
]

///|
pub type NativeTextCancel = (UInt64) -> Result[
  UInt64,
  @diagnostics.FrameworkError,
]

///|
pub type NativeTextEnd = (UInt64) -> Result[Unit, @diagnostics.FrameworkError]

///|
pub type NativeTextNext = (Int32) -> Result[
  @text_host.TextInputEvent?,
  @diagnostics.FrameworkError,
]

///|
/// Optional portable text-input transport supplied by a host entrypoint. The
/// runner owns begin/update/cancel/end and maps observations into the focused
/// field; the port only translates the host's trait methods.
pub struct NativeTextInputPort {
  begin : NativeTextBegin
  update : NativeTextUpdate
  cancel : NativeTextCancel
  end : NativeTextEnd
  next : NativeTextNext
}

///|
pub fn NativeTextInputPort::new(
  begin : NativeTextBegin,
  update : NativeTextUpdate,
  cancel : NativeTextCancel,
  end : NativeTextEnd,
  next : NativeTextNext,
) -> NativeTextInputPort {
  { begin, update, cancel, end, next, }
}

///|
/// One copied TextField observation for a host accessibility projection.
pub struct NativeTextAXSnapshot {
  value : String
  bounds : @primitives.Rect
  focused : Bool
  editable : Bool
}

///|
/// Optional TextField accessibility transport. The runner publishes the focused
/// field's copied value/frame/focus and revokes it when focus or the session
/// ends. Selection is not published; the host adapter keeps its last value.
pub struct NativeTextAXPort {
  publish : (@platform.WindowId, Int64, NativeTextAXSnapshot) -> Result[
    Int64,
    @diagnostics.FrameworkError,
  ]
  revoke : (@platform.WindowId, Int64) -> Result[Unit, @diagnostics.FrameworkError]
}

///|
pub fn NativeTextAXPort::new(
  publish : (@platform.WindowId, Int64, NativeTextAXSnapshot) -> Result[
    Int64,
    @diagnostics.FrameworkError,
  ],
  revoke : (@platform.WindowId, Int64) -> Result[Unit, @diagnostics.FrameworkError],
) -> NativeTextAXPort {
  { publish, revoke, }
}

///|
priv struct TextSession {
  epoch : UInt64
  binding : UInt64
}

///|
/// Dispatch to the Button sample by default or the TextField sample when a text
/// proof mode is requested. Platform mains stay free of mode switches.
pub fn run_native_entry(
  host : &@platform.Backend,
  platform : NativeSamplePlatform,
  measure : @components.TextMeasure,
  capture : NativeFrameCapture,
  accessibility_port~ : NativeButtonAXPort? = None,
  text_port~ : NativeTextInputPort? = None,
  text_accessibility_port~ : NativeTextAXPort? = None,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let args = @env.args()
  if args.contains("--text-e2e") ||
    @env.get_env_var("YAMI_NATIVE_UI_TEXT_E2E") == Some("1") {
    return run_native_text_sample(
      host,
      platform,
      measure,
      text_port~,
      accessibility_port=text_accessibility_port,
    )
  }
  run_native_sample(host, platform, measure, capture, accessibility_port~)
}

///|
fn text_event_phase(kind : @text_host.TextInputEventKind) -> String {
  match kind {
    @text_host.Preedit(..) => "preedit"
    @text_host.Commit(..) => "commit"
    @text_host.Cancel => "cancel"
    @text_host.FocusLost => "focus-lost"
    @text_host.Geometry(..) => "geometry"
  }
}

///|
fn text_event_json(kind : @text_host.TextInputEventKind) -> String {
  match kind {
    @text_host.Preedit(text~, cursor~) =>
      "\"text\":\"\{json_escape(text)}\",\"cursor\":\{cursor}"
    @text_host.Commit(text~) => "\"text\":\"\{json_escape(text)}\""
    _ => "\"text\":\"\""
  }
}

///|
fn end_text_session(
  port : NativeTextInputPort,
  session : TextSession,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let epoch = match (port.cancel)(session.epoch) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  (port.end)(epoch)
}

///|
fn text_window_size() -> (Double, Double) {
  (640.0, 360.0)
}

///|
/// Run one controlled TextField on a host that exposes
/// `text_host.TextInputHost`. The runner starts a session when the field gains
/// focus, republishes the committed document and caret, applies ordered
/// observations through `Mounted::text_input`, and ends the session on focus
/// loss. `--text-e2e` enables the mode and emits machine-readable markers.
pub fn run_native_text_sample(
  host : &@platform.Backend,
  platform : NativeSamplePlatform,
  measure : @components.TextMeasure,
  text_port~ : NativeTextInputPort? = None,
  accessibility_port~ : NativeTextAXPort? = None,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let port = match text_port {
    Some(value) => value
    None =>
      return Err(
        runner_error(
          "run_native_text_sample", "the selected host does not implement portable text input",
        ),
      )
  }
  let (width, height) = text_window_size()
  let title = "Yami-kumo TextField"
  let window = match host.create_window(title, width, height) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let mounted = @ui.Mounted::new(window)
  let sample = @text_sample.TextSample::new()
  let mut session : TextSession? = None
  let mut ax_token : Int64 = 0
  let mut last_document = ""
  let mut last_caret = @primitives.Rect::new(0.0, 0.0, 0.0, 0.0).unwrap()
  let mut dirty = true
  let mut ticks = 0
  let mut destroyed = false
  let mut last_sequence : Int64 = 0
  let tick_limit = if platform is Macos { 2000 } else { 600 }
  while !destroyed && ticks < tick_limit {
    ticks += 1
    // Drain portable text observations before the ordinary event queue.
    let mut drained = 0
    while drained < 32 {
      let current = match session {
        Some(value) => value
        None => break
      }
      let event = match (port.next)(0) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      let event = match event {
        Some(value) => value
        None => break
      }
      drained += 1
      if event.epoch() != current.epoch {
        continue
      }
      let handled = match mounted.text_input(current.epoch, event) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      if handled {
        dirty = true
        // Apply the field's semantic actions before the next commit so a
        // committed value is not replaced by a stale owning value.
        while mounted.next_action() is Some(action) {
          if sample.apply(action) {
            dirty = true
          }
        }
        emit_native_marker(
          "YAMI_NATIVE_UI_TEXT {\"phase\":\"\{text_event_phase(event.kind())}\",\{text_event_json(event.kind())},\"epoch\":\{current.epoch}}",
        )
      }
      match event.kind() {
        @text_host.FocusLost | @text_host.Cancel => {
          match end_text_session(port, current) {
            Err(error) => return Err(error)
            Ok(_) => ()
          }
          session = None
          last_document = ""
        }
        _ => ()
      }
    }
    let event = match host.next_event(timeout_ms=16) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    match event {
      None => ()
      Some(value) if value.window() == window => {
        if value.sequence() <= last_sequence {
          return Err(
            runner_error(
              "run_native_text_sample", "host event sequence did not advance",
            ),
          )
        }
        last_sequence = value.sequence()
        match value.kind() {
          @platform.Destroyed => {
            destroyed = true
            dirty = false
          }
          @platform.CloseRequested | @platform.ExitRequested => {
            destroyed = true
            dirty = false
          }
          @platform.Resized(..) | @platform.ScaleChanged =>
            mounted.invalidate_layout()
          @platform.FocusChanged(focused) => {
            ignore(mounted.handle_event(value))
            if !focused {
              match session {
                Some(current) => {
                  match end_text_session(port, current) {
                    Err(error) => return Err(error)
                    Ok(_) => ()
                  }
                  session = None
                  last_document = ""
                }
                None => ()
              }
            }
            dirty = true
          }
          @platform.Input(_) => {
            ignore(mounted.handle_event(value))
            dirty = true
          }
          @platform.Composition(_) => {
            ignore(mounted.handle_event(value))
            dirty = true
          }
          _ => ()
        }
      }
      Some(_) => ()
    }
    if dirty && !destroyed {
      let frame = match
        mounted.commit(sample.view(), width, height, 1.0, measure) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      dirty = false
      while mounted.next_action() is Some(action) {
        if sample.apply(action) {
          dirty = true
        }
      }
      let focused = frame.focused(@text_sample.text_sample_field())
      match session {
        None =>
          if focused {
            match mounted.focused_text() {
              Some(state) => {
                let epoch = match (port.begin)(window, state.binding_id()) {
                  Err(error) => return Err(error)
                  Ok(value) => value
                }
                let epoch = match
                  (port.update)(
                    epoch,
                    @text_host.TextInputState::new(
                      state.document(),
                      state.caret(),
                    ),
                  ) {
                  Err(error) => return Err(error)
                  Ok(value) => value
                }
                session = Some({ epoch, binding: state.binding_id(), })
                last_document = state.document().text()
                last_caret = state.caret()
                emit_native_marker(
                  "YAMI_NATIVE_UI_TEXT {\"phase\":\"begin\",\"epoch\":\{epoch},\"value\":\"\{json_escape(last_document)}\"}",
                )
              }
              None => ()
            }
          }
        Some(current) =>
          if !focused {
            match end_text_session(port, current) {
              Err(error) => return Err(error)
              Ok(_) => ()
            }
            session = None
            last_document = ""
          } else {
            match mounted.focused_text() {
              Some(state) =>
                if state.document().text() != last_document ||
                  state.caret() != last_caret {
                  let epoch = match
                    (port.update)(
                      current.epoch,
                      @text_host.TextInputState::new(
                        state.document(),
                        state.caret(),
                      ),
                    ) {
                    Err(error) => return Err(error)
                    Ok(value) => value
                  }
                  session = Some({ epoch, binding: current.binding, })
                  last_document = state.document().text()
                  last_caret = state.caret()
                }
              None => ()
            }
          }
      }
      match accessibility_port {
        Some(ax) =>
          match
            (frame.bounds(@text_sample.text_sample_field()),
             mounted.focused_text()) {
            (Some(bounds), Some(state)) => {
              let snapshot : NativeTextAXSnapshot = {
                value: state.document().text(),
                bounds,
                focused: true,
                editable: true,
              }
              ax_token = match (ax.publish)(window, ax_token, snapshot) {
                Err(error) => return Err(error)
                Ok(value) => value
              }
            }
            _ =>
              if ax_token != 0 {
                match (ax.revoke)(window, ax_token) {
                  Err(error) => return Err(error)
                  Ok(_) => ()
                }
                ax_token = 0
              }
          }
        None => ()
      }
      let submitted = match sample.submitted() {
        Some(value) => value
        None => ""
      }
      emit_native_marker(
        "YAMI_NATIVE_UI_TEXT {\"phase\":\"frame\",\"value\":\"\{json_escape(sample.value())}\",\"submitted\":\"\{json_escape(submitted)}\",\"focused\":\{focused}}",
      )
    }
  }
  match session {
    Some(current) =>
      match end_text_session(port, current) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    None => ()
  }
  if ax_token != 0 {
    match accessibility_port {
      Some(ax) =>
        match (ax.revoke)(window, ax_token) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      None => ()
    }
    ax_token = 0
  }
  mounted.dispose()
  if destroyed || ticks >= tick_limit {
    Ok(())
  } else {
    Err(runner_error("run_native_text_sample", "text sample loop ended early"))
  }
}
