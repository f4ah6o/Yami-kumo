///|
priv struct ThemeProof {
  mut phase : Int32
  mut last_phase : Int32
  mut last_payload : String?
  mut input_sequence : Int64
}

///|
fn theme_control_key(input : @primitives.InputEvent) -> String? {
  // Windows emits printable letters through TextInput, while these logical
  // navigation keys are delivered consistently by all three native hosts.
  match input {
    @primitives.KeyPressed(key~, repeat=false, ..) =>
      match key {
        @primitives.PageUp => Some("t")
        @primitives.PageDown => Some("c")
        @primitives.Home => Some("n")
        @primitives.End => Some("d")
        @primitives.ArrowUp => Some("l")
        @primitives.ArrowDown => Some("b")
        @primitives.ArrowLeft => Some("f")
        @primitives.ArrowRight => Some("arm-inside")
        @primitives.Delete => Some("arm-outside")
        _ => None
      }
    _ => None
  }
}

///|
fn run_theme(
  host : &@platform.Backend,
  platform : NativePlatform,
  measure : @components.TextMeasure,
  capture : FrameCapture,
  e2e : Bool,
  directory : String?,
  title : String,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let window = match host.create_window(title, 800.0, 600.0) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let app = match @shared_counter.NativeTheme::new(window) {
    Err(error) => {
      let _ = host.destroy_window(window)
      return Err(error)
    }
    Ok(value) => value
  }
  let result = theme_loop(
    host, window, app, platform, measure, capture, e2e, directory, title,
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
fn theme_loop(
  host : &@platform.Backend,
  window : @platform.WindowId,
  app : @shared_counter.NativeTheme,
  platform : NativePlatform,
  measure : @components.TextMeasure,
  capture : FrameCapture,
  e2e : Bool,
  directory : String?,
  title : String,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let proof = ThemeProof::{
    phase: 0,
    last_phase: -1,
    last_payload: None,
    input_sequence: 0L,
  }
  let pointer = ThemePointerReceipt::new(window)
  let gate = PresentationGate::{ rendered: false, pending_stale: false, }
  let mut pending : @shared_counter.ThemeFrame? = None
  let mut current : @shared_counter.ThemeFrame? = None
  let mut dirty = true
  let mut closing = false
  let mut destroyed = false
  let mut sequence : Int64 = 0L
  let mut ticks = 0
  while !destroyed && (!e2e || ticks < 12000) {
    ticks += 1
    let event = match host.next_event(timeout_ms=16) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    match event {
      Some(value) if value.window() == window => {
        if value.sequence() <= sequence {
          return Err(runner_error("theme host sequence did not advance"))
        }
        sequence = value.sequence()
        if pointer.waiting {
          match value.kind() {
            @platform.FocusChanged(_)
            | @platform.Resized(..)
            | @platform.ScaleChanged
            | @platform.VisibilityChanged(_)
            | @platform.CloseRequested
            | @platform.Destroyed
            | @platform.ExitRequested =>
              return Err(
                runner_error(
                  "theme pointer request interrupted by window change",
                ),
              )
            _ => ()
          }
        }
        let before_dispatch = app.last_dispatched_input_sequence()
        match app.handle_event(value) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
        if e2e {
          match
            pointer.observe(
              value,
              before_dispatch,
              app.last_dispatched_input_sequence(),
            ) {
            Some(receipt) => emit("YAMI_NATIVE_UI_POINTER_MOVED", receipt)
            None => ()
          }
        }
        match value.kind() {
          @platform.Created => dirty = true
          @platform.Resized(..) | @platform.ScaleChanged => {
            gate.invalidate(pending is Some(_))
            app.invalidate_layout()
            dirty = true
          }
          @platform.FocusChanged(_) => {
            gate.changed(pending is Some(_))
            dirty = true
          }
          // Composition is a separate host event, not a Button activation.
          // Keep presentation current without synthesizing committed text input.
          @platform.Composition(_) => dirty = true
          @platform.VisibilityChanged(visible) => {
            if !visible {
              gate.invalidate(pending is Some(_))
              app.invalidate_layout()
            }
            dirty = true
          }
          @platform.Input(input) => {
            proof.input_sequence = sequence
            match input {
              @primitives.KeyPressed(key=@primitives.Escape, ..) =>
                match host.request_close(window) {
                  Err(error) => return Err(error)
                  Ok(_) => ()
                }
              _ if !closing => {
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
                      if drained > 32 {
                        return Err(runner_error("unbounded theme action queue"))
                      }
                    }
                  }
                }
                match theme_control_key(input) {
                  Some("arm-inside") | Some("arm-outside") if e2e => {
                    let frame = match current {
                      Some(frame) => frame.frame()
                      None =>
                        return Err(
                          runner_error(
                            "pointer request before accepted geometry",
                          ),
                        )
                    }
                    let (x, y) = if theme_control_key(input) ==
                      Some("arm-inside") {
                      let bounds = frame
                        .bounds(@view.NodeKey::new("increment"))
                        .unwrap()
                      (
                        bounds.left() + bounds.size().width() / 2.0,
                        bounds.top() + bounds.size().height() / 2.0,
                      )
                    } else {
                      let bounds = frame.root_bounds()
                      (bounds.right() - 16.0, bounds.bottom() - 16.0)
                    }
                    if !pointer.arm(value, proof.phase, x, y) {
                      return Err(
                        runner_error("overlapping theme pointer request"),
                      )
                    }
                    emit(
                      "YAMI_NATIVE_UI_POINTER_ARMED",
                      pointer.identity_json(),
                    )
                  }
                  Some("arm-inside") | Some("arm-outside") => ()
                  Some("c") if e2e => {
                    if pointer.waiting || proof.phase != proof.last_phase {
                      return Err(
                        runner_error("overlapping theme capture requests"),
                      )
                    }
                    proof.phase += 1
                  }
                  Some(key) =>
                    match app.control(key, width, height, scale, measure) {
                      Err(error) => return Err(error)
                      Ok(_) => ()
                    }
                  _ => ()
                }
                // A color change cannot revoke an already accepted gesture.
                // A queued obsolete presentation is simply superseded.
                gate.changed(pending is Some(_))
                dirty = true
              }
              _ => ()
            }
          }
          @platform.FrameCompleted =>
            match pending {
              Some(frame) => {
                pending = None
                if gate.complete() && e2e {
                  match
                    publish_theme(
                      window, frame, capture, directory, title, proof,
                    ) {
                    Err(error) => return Err(error)
                    Ok(_) => ()
                  }
                }
              }
              None => ()
            }
          @platform.CloseRequested | @platform.ExitRequested => {
            closing = true
            match host.destroy_window(window) {
              Err(error) => return Err(error)
              Ok(_) => ()
            }
          }
          @platform.Destroyed => destroyed = true
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
      current = Some(frame)
      match host.present(window, frame.frame().snapshot()) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      dirty = false
      gate.rendered = true
      if platform is Macos {
        if e2e {
          match publish_theme(window, frame, capture, directory, title, proof) {
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
    return Err(runner_error("theme host window destruction timed out"))
  }
  if e2e {
    if proof.last_phase != 35 || proof.phase != proof.last_phase {
      return Err(runner_error("theme host closed before all 36 captures"))
    }
    match proof.last_payload {
      Some(payload) =>
        emit("YAMI_NATIVE_UI_COMPLETE", "{\"destroyed\":true," + payload)
      None =>
        return Err(runner_error("theme host closed without presented evidence"))
    }
  }
  Ok(())
}

///|
fn publish_theme(
  window : @platform.WindowId,
  value : @shared_counter.ThemeFrame,
  capture : FrameCapture,
  directory : String?,
  title : String,
  proof : ThemeProof,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if proof.phase == proof.last_phase {
    return Ok(())
  }
  let directory = match directory {
    Some(value) => value
    None => return Err(runner_error("missing theme capture directory"))
  }
  let frame = value.frame()
  let model = value.model()
  if frame.theme() != Some(model.theme()) {
    return Err(runner_error("theme Model and accepted palette disagree"))
  }
  let captured = match capture(window) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let path = directory + "/frame-\{proof.phase}.ppm"
  match captured.write_ppm(path) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let key = @view.NodeKey::new("increment")
  let toggle = @view.NodeKey::new("theme-toggle")
  let disabled = model.mode() == @fixture.Disabled ||
    model.mode() == @fixture.DisabledLoading
  let loading = model.mode() == @fixture.Loading ||
    model.mode() == @fixture.DisabledLoading
  let actions = StringBuilder()
  actions.write_string("[")
  for index, key in value.action_keys() {
    if index > 0 {
      actions.write_string(",")
    }
    actions.write_string("\"" + escape_json(key) + "\"")
  }
  actions.write_string("]")
  let payload = "\"fixture\":\"theme\",\"phase\":\{proof.phase},\"theme\":\"\{model.theme().name()}\",\"mode\":\"\{model.mode().name()}\",\"count\":\{model.value()},\"value\":\{model.value()},\"enabled\":\{!disabled},\"loading\":\{loading},\"pressed\":\{frame.pressed(key)},\"focused\":\{frame.focused(key)},\"hovered\":\{frame.hovered(key)},\"actionKeys\":\{actions.to_string()},\"buttonId\":\{frame.binding_id(key).unwrap()},\"toggleId\":\{frame.binding_id(toggle).unwrap()},\"revision\":\{frame.revision()},\"inputSequence\":\{proof.input_sequence},\"windowId\":\{window.value()},\"title\":\"\{escape_json(title)}\",\"button\":\{rect_json(frame.bounds(key).unwrap())},\"buttonLabel\":\{rect_json(frame.label_bounds(key).unwrap())},\"counter\":\{rect_json(frame.bounds(@view.NodeKey::new("value")).unwrap())},\"heading\":\{rect_json(frame.bounds(@view.NodeKey::new("heading")).unwrap())},\"toggle\":\{rect_json(frame.bounds(toggle).unwrap())},\"toggleLabel\":\{rect_json(frame.label_bounds(toggle).unwrap())},\"root\":\{rect_json(frame.root_bounds())},\"scale\":\{captured.scale()},\"scene\":\{frame.snapshot().canonical_json()},\"frame\":{\"path\":\"\{escape_json(path)}\",\"width\":\{captured.width()},\"height\":\{captured.height()},\"scale\":\{captured.scale()}}}"
  emit("YAMI_NATIVE_UI_PRESENTED", "{" + payload)
  if proof.last_payload is None {
    emit("YAMI_NATIVE_UI_READY", "{" + payload)
  }
  proof.last_phase = proof.phase
  proof.last_payload = Some(payload)
  Ok(())
}
