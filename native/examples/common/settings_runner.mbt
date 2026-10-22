///|
/// Optional platform-record source while a host text route owns the queue.
/// Route-backed hosts park ordinary records in their own ordered queue, so the
/// runner must not read `Host::next_event` directly.
pub type NativePlatformNext = (
  Int32
) -> Result[@platform.Event?, @diagnostics.FrameworkError]

///|
/// Optional direct-keyboard text transport used when the host has no portable
/// text-input session (for example Weston without text-input-v1). Arming it
/// keeps typed characters on the compositor key path as committed text input;
/// disarming it on focus loss keeps stale epochs from being delivered.
pub type NativeDirectText = (
  @platform.WindowId,
  Bool,
) -> Result[Unit, @diagnostics.FrameworkError]

///|
pub type NativeDialogAXPublish = (
  @platform.WindowId,
  Int64,
  String,
  @primitives.Rect
) -> Result[Int64, @diagnostics.FrameworkError]

///|
pub type NativeDialogAXRevoke = (
  @platform.WindowId,
  Int64
) -> Result[Unit, @diagnostics.FrameworkError]

///|
/// Optional Dialog accessibility transport for the Settings sample. The runner
/// publishes an open modal with the dialog title and its copied frame, and
/// revokes it when the model closes the dialog.
pub struct NativeDialogAXPort {
  publish : NativeDialogAXPublish
  revoke : NativeDialogAXRevoke
}

///|
pub fn NativeDialogAXPort::new(
  publish : NativeDialogAXPublish,
  revoke : NativeDialogAXRevoke,
) -> NativeDialogAXPort {
  { publish, revoke, }
}

///|
/// The Wayland text route rejects a zero-size caret rectangle before it starts
/// a native session. An unlaid-out first frame can carry that empty rect, so
/// substitute the documented 1x18 fallback while keeping its origin.
fn settings_caret(caret : @primitives.Rect) -> @primitives.Rect {
  let size = caret.size()
  if size.width() > 0.0 && size.height() > 0.0 {
    caret
  } else {
    match @primitives.Rect::new(caret.left(), caret.top(), 1.0, 18.0) {
      Ok(value) => value
      Err(_) => caret
    }
  }
}

///|
fn settings_window_size() -> (Double, Double) {
  (640.0, 480.0)
}

///|
fn settings_status(settings : @shared_settings.Model) -> String {
  if settings.saving() {
    "saving"
  } else if settings.saved() {
    "saved"
  } else {
    "editing"
  }
}

///|
priv struct SettingsTextRoute {
  key_path_armed : Bool
  transport_failed : Bool
}

///|
/// Text-input fallback when the host has no portable session (for example
/// Weston without text-input-v1). Arms the direct keyboard-text route so typed
/// characters reach the field as committed text, and reports the transport as
/// unavailable only when no route exists at all. Markers are emitted on state
/// transitions so the log shows which route carried the text.
fn settings_key_path_fallback(
  direct_text : NativeDirectText?,
  window : @platform.WindowId,
  route : SettingsTextRoute,
) -> SettingsTextRoute {
  match direct_text {
    Some(arm) =>
      match (arm)(window, true) {
        Ok(_) => {
          if !route.key_path_armed {
            emit_native_marker(
              "YAMI_NATIVE_UI_SETTINGS {\"phase\":\"text\",\"status\":\"key-path\",\"route\":\"direct-keyboard\"}",
            )
          }
          { ..route, key_path_armed: true }
        }
        Err(_) => {
          if !route.key_path_armed && !route.transport_failed {
            emit_native_marker(
              "YAMI_NATIVE_UI_SETTINGS {\"phase\":\"text\",\"status\":\"unavailable\",\"route\":\"none\"}",
            )
          }
          { key_path_armed: route.key_path_armed, transport_failed: true }
        }
      }
    None => {
      if !route.transport_failed {
        emit_native_marker(
          "YAMI_NATIVE_UI_SETTINGS {\"phase\":\"text\",\"status\":\"unavailable\",\"route\":\"none\"}",
        )
      }
      { key_path_armed: route.key_path_armed, transport_failed: true }
    }
  }
}

///|
/// Drive the Shared Settings model on a host that exposes portable text input.
/// The same model source is used by the DOM entry; this runner only delivers
/// host events, the committed text transport and the simulated-save tick.
pub fn run_native_settings_sample(
  host : &@platform.Backend,
  platform : NativeSamplePlatform,
  measure : @components.TextMeasure,
  text_port~ : NativeTextInputPort? = None,
  accessibility_port~ : NativeTextAXPort? = None,
  dialog_port~ : NativeDialogAXPort? = None,
  next_platform_event~ : NativePlatformNext? = None,
  direct_text~ : NativeDirectText? = None,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let port = match text_port {
    Some(value) => value
    None =>
      return Err(
        runner_error(
          "run_native_settings_sample",
          "the selected host does not implement portable text input",
        ),
      )
  }
  let (width, height) = settings_window_size()
  let window = match host.create_window("Yami-kumo Shared Settings", width, height) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let mounted = @ui.Mounted::new(window)
  let mut settings = @shared_settings.Model::new()
  let mut session : TextSession? = None
  let mut ax_token : Int64 = 0
  let mut dialog_token : Int64 = 0
  let mut last_document = ""
  let mut last_caret = @primitives.Rect::new(0.0, 0.0, 0.0, 0.0).unwrap()
  let mut saving_frames = 0
  let mut dirty = true
  let mut focus_initialized = false
  let mut text_suspended = false
  let mut text_transport_failed = false
  let mut key_path_armed = false
  let mut ticks = 0
  let mut destroyed = false
  let mut last_sequence : Int64 = 0
  // Windows keeps the lane alive longer than any driver wait so a failed
  // assertion is reported by the driver, not by a truncated sample loop.
  let tick_limit = if platform is Macos {
    20000
  } else if platform is Windows {
    12000
  } else {
    6000
  }
  while !destroyed && ticks < tick_limit {
    ticks += 1
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
        // Keep the transport visible in the retained log: `commit` comes from
        // the portable text route, while `key` with `character` means WM_CHAR
        // reached the ordinary key path.
        emit_native_marker(
          "YAMI_NATIVE_UI_SETTINGS {\"phase\":\"\{text_event_phase(event.kind())}\",\{text_event_json(event.kind())},\"epoch\":\{current.epoch}}",
        )
        dirty = true
        while mounted.next_action() is Some(action) {
          let next = settings.update(@shared_settings.Ui(action))
          if next != settings {
            settings = next
            dirty = true
          }
        }
      }
      match event.kind() {
        @text_host.FocusLost | @text_host.Cancel => {
          match end_text_session(port, current) {
            Err(error) => return Err(error)
            Ok(_) => ()
          }
          session = None
          text_suspended = true
          last_document = ""
        }
        _ => ()
      }
    }
    let event = match next_platform_event {
      Some(next) =>
        match next(16) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
      None =>
        match host.next_event(timeout_ms=16) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
    }
    match event {
      None => ()
      Some(value) if value.window() == window => {
        if value.sequence() <= last_sequence {
          return Err(
            runner_error(
              "run_native_settings_sample",
              "host event sequence did not advance",
            ),
          )
        }
        last_sequence = value.sequence()
        match value.kind() {
          @platform.Destroyed | @platform.CloseRequested | @platform.ExitRequested => {
            destroyed = true
            dirty = false
          }
          @platform.Resized(..) | @platform.ScaleChanged => {
            // Invalidation clears the commit-ready state; without a new frame
            // the next text observation would be rejected before it reaches the
            // focused field.
            mounted.invalidate_layout()
            dirty = true
          }
          @platform.FocusChanged(focused) => {
            ignore(mounted.handle_event(value))
            text_suspended = !focused
            if !focused {
              focus_initialized = false
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
              if key_path_armed {
                key_path_armed = false
                match direct_text {
                  Some(arm) => ignore(arm(window, false))
                  None => ()
                }
              }
            }
            dirty = true
          }
          @platform.Input(input) => {
            match input {
              @primitives.KeyPressed(key~, ..) => {
                let name = match key {
                  @primitives.Tab => "tab"
                  @primitives.Enter => "enter"
                  @primitives.Escape => "escape"
                  @primitives.Space => "space"
                  @primitives.Backspace => "backspace"
                  @primitives.Character(_) => "character"
                  _ => "other"
                }
                emit_native_marker(
                  "YAMI_NATIVE_UI_SETTINGS {\"phase\":\"key\",\"key\":\"\{name}\"}",
                )
              }
              _ => ()
            }
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
      // Drain queued actions before rendering: a TextChanged enqueued by the
      // previous dispatch must update the model first, or the committed view
      // rebuilds the field with a stale value and resets its caret.
      while mounted.next_action() is Some(action) {
        let next = settings.update(@shared_settings.Ui(action))
        if next != settings {
          settings = next
        }
      }
      let frame = match
        mounted.commit(settings.view(), width, height, 1.0, measure) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      dirty = false
      while mounted.next_action() is Some(action) {
        let next = settings.update(@shared_settings.Ui(action))
        if next != settings {
          settings = next
          dirty = true
        }
      }
      // The simulated save completes after three committed frames so the
      // loading state is observable without a host timer.
      if settings.saving() {
        saving_frames += 1
        dirty = true
        if saving_frames >= 3 {
          saving_frames = 0
          settings = settings.update(@shared_settings.SaveFinished)
        }
      } else {
        saving_frames = 0
      }
      let focused = frame.focused(@shared_settings.settings_name())
      if !focus_initialized {
        if focused {
          focus_initialized = true
        } else if mounted.focus(@shared_settings.settings_name()) {
          dirty = true
        }
      }
      // A rejected focus request (for example while the host reports the
      // window unfocused) is retried on the next commit rather than giving
      // the lane a permanently unfocused field.
      match session {
        None =>
          if focused && !text_suspended && !text_transport_failed && !key_path_armed {
            match mounted.focused_text() {
              Some(state) => {
                match (port.begin)(window, state.binding_id()) {
                  Err(error) => {
                    emit_native_marker(
                      "YAMI_NATIVE_UI_SETTINGS {\"phase\":\"text\",\"status\":\"unavailable\",\"operation\":\"begin_text_input\",\"error\":\"\{json_escape(format_framework_error(error))}\"}",
                    )
                    let route = settings_key_path_fallback(direct_text, window, {
                      key_path_armed,
                      transport_failed: text_transport_failed,
                    })
                    key_path_armed = route.key_path_armed
                    text_transport_failed = route.transport_failed
                  }
                  Ok(epoch) =>
                    match
                      (port.update)(
                        epoch,
                        @text_host.TextInputState::new(
                          state.document(),
                          settings_caret(state.caret()),
                        ),
                      ) {
                      Err(error) => {
                        ignore((port.end)(epoch))
                        emit_native_marker(
                          "YAMI_NATIVE_UI_SETTINGS {\"phase\":\"text\",\"status\":\"unavailable\",\"operation\":\"update_text_input\",\"error\":\"\{json_escape(format_framework_error(error))}\"}",
                        )
                        let route = settings_key_path_fallback(
                          direct_text,
                          window,
                          {
                            key_path_armed,
                            transport_failed: text_transport_failed,
                          },
                        )
                        key_path_armed = route.key_path_armed
                        text_transport_failed = route.transport_failed
                      }
                      Ok(epoch) => {
                        session = Some({ epoch, binding: state.binding_id(), })
                        last_document = state.document().text()
                        last_caret = settings_caret(state.caret())
                        let transport = if platform is Windows { "imm32" } else { "text-input-v1" }
                        emit_native_marker(
                          "YAMI_NATIVE_UI_SETTINGS {\"phase\":\"text\",\"status\":\"started\",\"transport\":\"\{transport}\",\"epoch\":\{epoch}}",
                        )
                      }
                    }
                }
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
              Some(state) => {
                if state.document().text() != last_document ||
                  settings_caret(state.caret()) != last_caret {
                  let epoch = match
                    (port.update)(
                      current.epoch,
                      @text_host.TextInputState::new(
                        state.document(),
                        settings_caret(state.caret()),
                      ),
                    ) {
                    Err(error) => return Err(error)
                    Ok(value) => value
                  }
                  session = Some({ epoch, binding: current.binding, })
                  last_document = state.document().text()
                  last_caret = settings_caret(state.caret())
                }
              }
              None => ()
            }
          }
      }
      match accessibility_port {
        Some(ax) =>
          match
            (frame.bounds(@shared_settings.settings_name()),
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
      match dialog_port {
        Some(port) =>
          if settings.dialog_open() {
            match frame.bounds(@shared_settings.settings_dialog()) {
              Some(bounds) =>
                dialog_token = match
                  (port.publish)(window, dialog_token, "Save changes?", bounds) {
                  Err(error) => return Err(error)
                  Ok(value) => value
                }
              None =>
                if dialog_token != 0 {
                  match (port.revoke)(window, dialog_token) {
                    Err(error) => return Err(error)
                    Ok(_) => ()
                  }
                  dialog_token = 0
                }
            }
          } else if dialog_token != 0 {
            match (port.revoke)(window, dialog_token) {
              Err(error) => return Err(error)
              Ok(_) => ()
            }
            dialog_token = 0
          }
        None => ()
      }
      let error_text = match settings.error() {
        Some(value) => value
        None => ""
      }
      let focus = if frame.focused(@shared_settings.settings_name()) {
        "name"
      } else if frame.focused(@shared_settings.settings_confirm()) {
        "confirm"
      } else if frame.focused(@shared_settings.settings_cancel()) {
        "cancel"
      } else if frame.focused(@shared_settings.settings_save()) {
        "save"
      } else {
        "other"
      }
      emit_native_marker(
        "YAMI_NATIVE_UI_SETTINGS {\"phase\":\"frame\",\"name\":\"\{json_escape(settings.name())}\",\"status\":\"\{settings_status(settings)}\",\"dialog\":\{settings.dialog_open()},\"focus\":\"\{focus}\",\"error\":\"\{json_escape(error_text)}\"}",
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
  if key_path_armed {
    match direct_text {
      Some(arm) => ignore(arm(window, false))
      None => ()
    }
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
  }
  if dialog_token != 0 {
    match dialog_port {
      Some(port) =>
        match (port.revoke)(window, dialog_token) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      None => ()
    }
  }
  mounted.dispose()
  let reason = if destroyed { "window-closed" } else { "tick-limit" }
  emit_native_marker(
    "YAMI_NATIVE_UI_SETTINGS {\"phase\":\"exit\",\"reason\":\"\{reason}\",\"ticks\":\{ticks}}",
  )
  if destroyed || ticks >= tick_limit {
    Ok(())
  } else {
    Err(
      runner_error("run_native_settings_sample", "settings sample loop ended early"),
    )
  }
}
