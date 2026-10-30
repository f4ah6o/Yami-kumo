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
fn ubuntu_text_caret(
  caret : @primitives.Rect,
) -> Result[@primitives.Rect, @diagnostics.FrameworkError] {
  // text-input-v1 takes signed integral surface-logical endpoints, while
  // Pango may return fractional logical geometry. Preserve the entire caret;
  // do not multiply by output scale or truncate a negative coordinate.
  let left = caret.left().floor()
  let top = caret.top().floor()
  let right = caret.right().ceil()
  let bottom = caret.bottom().ceil()
  let error = @diagnostics.FrameworkError::new(
    @diagnostics.InvalidInput,
    "ubuntu_text_caret",
    subsystem="native-sample-ubuntu",
    message="caret is outside the integral Wayland rectangle range",
  )
  for value in [left, top, right, bottom] {
    if value.is_nan() ||
      value.is_inf() ||
      value < -2147483648.0 ||
      value > 2147483647.0 {
      return Err(error)
    }
  }
  let width = right - left
  let height = bottom - top
  if caret.size().width() <= 0.0 ||
    caret.size().height() <= 0.0 ||
    width < 1.0 ||
    height < 1.0 ||
    width > 2147483647.0 ||
    height > 2147483647.0 {
    return Err(error)
  }
  match @primitives.Rect::new(left, top, width, height) {
    Ok(value) => Ok(value)
    Err(_) => Err(error)
  }
}

///|
fn ubuntu_text_state(
  state : @text_host.TextInputState,
) -> Result[@text_host.TextInputState, @diagnostics.FrameworkError] {
  let caret = match ubuntu_text_caret(state.caret()) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok(
    @text_host.TextInputState::new(state.document(), caret).with_preedit(
      state.preedit(),
    ),
  )
}

///|
extern "C" fn control_open() -> Int = "gpui_settings_control_open"

///|
extern "C" fn control_next(timeout_ms : Int) -> Int = "gpui_settings_control_next"

///|
extern "C" fn control_reply(code : Int) = "gpui_settings_control_reply"

///|
extern "C" fn control_sequence() -> Int64 = "gpui_settings_control_sequence"

///|
extern "C" fn control_reply_sequence(code : Int, sequence : Int64) = "gpui_settings_control_reply_sequence"

///|
extern "C" fn control_close() = "gpui_settings_control_close"

///|
extern "C" fn control_backoff() = "gpui_settings_control_backoff"

///|
fn control_step_error(error : @diagnostics.FrameworkError, code : Int) -> Unit {
  println("YAMI_SETTINGS_CONTROL step: " + @common.format_framework_error(error))
  control_reply(code)
}

///|
fn control_pending_sequence(entry : @common.SettingsEntryController) -> Int64 {
  match entry.owner() {
    Some(owner) => {
      let records = owner.pending_records()
      if !records.is_empty() {
        match records[0] {
          @common.OrderedText(event) => return event.sequence()
          _ => ()
        }
      }
      0L
    }
    None => 0L
  }
}

///|
fn control_receipt_sequence(entry : @common.SettingsEntryController) -> Int64 {
  match entry.owner() {
    Some(owner) => match owner.pending_receipt_identity() {
      Some((_, sequence, _, _)) => sequence.to_int64()
      None => match owner.resumable_receipt_identity() {
        Some((_, sequence, _, _)) => sequence.to_int64()
        None => 0L
      }
    }
    None => 0L
  }
}

///|
/// Each request is bounded. Idle or a disconnected client never releases an
/// unresolved owner; this experimental service does not claim completion.
fn run_settings_control(entry : @common.SettingsEntryController) -> Unit {
  println("YAMI_SETTINGS_CONTROL {\"state\":\"active\",\"scene_published\":false}")
  match entry.error() {
    Some(error) => println("YAMI_SETTINGS_CONTROL reason: " + @common.format_framework_error(error))
    None => ()
  }
  let mut listener_error_reported = false
  while true {
    let command = control_next(30000)
    if command < 0 {
      if !listener_error_reported {
        println("YAMI_SETTINGS_CONTROL {\"state\":\"listener_error_owner_retained\"}")
        listener_error_reported = true
      }
      control_backoff()
      continue
    }
    listener_error_reported = false
    match command {
      0 => ()
      // s: status; report suspended separately from other unresolved states.
      115 => control_reply_sequence(if entry.suspended() { 83 } else { 78 }, control_pending_sequence(entry))
      // t: inspect the exact native receipt sequence, without ACK.
      116 => control_reply_sequence(if entry.suspended() { 83 } else { 78 }, control_receipt_sequence(entry))
      // r: retry ACK only for the inspected native sequence.
      114 => match entry.retry_receipt_sequence(control_sequence()) {
        Ok(@common.ReceiptAcknowledged) => control_reply(65)
        Err(error) => control_step_error(error, 69)
        Ok(_) => control_reply(69)
      }
      // u: dispatch only the named ACKed record; do not publish a scene.
      117 => match entry.resume_receipt_sequence(control_sequence()) {
        Ok(@common.ReceiptDispatched) => control_reply(85)
        Err(error) => control_step_error(error, 69)
        Ok(_) => control_reply(69)
      }
      // n/g: inspect and consume a single continuation generation.
      110 => control_reply_sequence(if entry.suspended() { 83 } else { 78 }, entry.advance_generation().unwrap_or(0L))
      103 => match entry.advance_once(control_sequence()) {
        Ok(@common.ContinuationStepped) => control_reply(86)
        Err(error) => control_step_error(error, 69)
        Ok(_) => control_reply(69)
      }
      // j: report only a unique, positively observed receipt stage.
      106 => {
        let stage = match entry.owner() {
          Some(owner) => owner.receipt_stage_for_sequence(control_sequence())
          None => None
        }
        match stage {
          Some(@common.ReceiptAcknowledgedOnly) => control_reply(75)
          Some(@common.ReceiptSessionApplied) => control_reply(74)
          Some(@common.ReceiptActionRequired) => control_reply(76)
          Some(@common.ReceiptModelApplied) => control_reply(77)
          None => control_reply(69)
        }
      }
      // p: one nonblocking host poll; a blank poll proves no cutoff.
      112 =>
        match entry.terminal_step(@common.PollOnce) {
          Ok(@common.RecordBuffered) => control_reply(66)
          Ok(@common.NoRecord) => control_reply(73)
          Err(error) => control_step_error(error, 69)
          Ok(_) => control_reply(69)
        }
      // a: apply one retained record; model and scene are distinct stages.
      97 =>
        match entry.apply_sequence(control_sequence()) {
          Ok(@common.ModelApplied(sequence, changed)) => {
            println("YAMI_SETTINGS_CONTROL {\"state\":\"model_applied\",\"sequence\":\{sequence},\"changed\":\{changed},\"scene_published\":false}")
            control_reply(77)
          }
          Ok(@common.FieldApplied(sequence)) => {
            println("YAMI_SETTINGS_CONTROL {\"state\":\"field_applied\",\"sequence\":\{sequence},\"scene_published\":false}")
            control_reply(70)
          }
          Err(error) => control_step_error(error, 69)
          Ok(_) => control_reply(69)
        }
      // c: attempt the native text cutoff only; it does not allow shutdown.
      99 =>
        match entry.terminal_step(@common.TryTextCutoff) {
          Ok(@common.TextCutoffCompleted) => control_reply(67)
          Err(error) => control_step_error(error, 69)
          Ok(_) => control_reply(69)
        }
      // q: explicit stop request; rejected until controller proves completion.
      113 =>
        match entry.try_stop() {
          Ok(_) => {
            control_reply(68)
            control_close()
            return
          }
          Err(error) => control_step_error(error, 82)
        }
      _ => control_reply(69)
    }
  }
}

///|
fn main {
  let controlled = @env.args().contains("--settings-retained-control")
  if controlled && control_open() != 0 {
    abort("could not open private Settings control socket")
  }
  let host = match @ubuntu_host.Host::start() {
    Err(error) => {
      if controlled { control_close() }
      abort(
        "Ubuntu native Host startup failed: " +
        @common.format_framework_error(error),
      )
    }
    Ok(value) => value
  }
  let capture : @common.NativeFrameCapture = fn(window) {
    @testing.capture_frame(host, window)
  }
  if controlled {
    let retained = match @ubuntu_host.RetainedOrderedRoute::new(host) {
      Ok(value) => value
      Err(error) => abort(@common.format_framework_error(error))
    }
    let first_update = Ref(false)
    let retained_port = @common.NativeTextInputPort::with_initial_state(
      fn(window, root, state) {
        let normalized = match ubuntu_text_state(state) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        match retained.begin(window, root, normalized) {
          Err(error) => Err(error)
          Ok(epoch) => { first_update.val = true; Ok(epoch) }
        }
      },
      fn(epoch, state) {
        if first_update.val {
          first_update.val = false
          return Ok(epoch)
        }
        let normalized = match ubuntu_text_state(state) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        match retained.update(epoch, normalized) {
          Ok(_) => Ok(epoch)
          Err(error) => Err(error)
        }
      },
      fn(_) { Err(@diagnostics.FrameworkError::new(@diagnostics.InvalidInput, "retained_cancel_policy")) },
      fn(_) { Err(@diagnostics.FrameworkError::new(@diagnostics.InvalidInput, "retained_end_policy")) },
      fn(_) { Ok(None) },
    )
    let retained_ordered = @common.NativeOrderedTextPort::with_retained_receipts(
      fn(timeout) {
        let observed = match retained.peek() {
          Ok(None) => match host.dispatch_retained(timeout) {
            Ok(_) => retained.peek()
            Err(error) => Err(error)
          }
          result => result
        }
        match observed {
          Err(error) => Err(error)
          Ok(None) => Ok(None)
          Ok(Some(receipt)) => {
            match receipt.event() {
              @ubuntu_host.Lifecycle(target, @ubuntu_host.Entered) if
                target.window == receipt.native_window() &&
                target.sequence == receipt.native_sequence().to_int64() &&
                retained.native_epoch() == Some(target.epoch) => {
                println("YAMI_SETTINGS_IME {\"stage\":\"entered_peek\",\"native_sequence\":\{receipt.native_sequence()},\"portable_epoch\":\{receipt.epoch()},\"native_epoch\":\{target.epoch},\"seat\":\{target.seat},\"proxy\":\{target.proxy_generation}}")
                return Ok(Some(@common.NativeRetainedReceipt::entered(
                  receipt.native_window(), receipt.native_sequence(), receipt.root(),
                  receipt.epoch(), target.epoch, target.seat, target.proxy_generation,
                  fn() {
                    match receipt.ack() {
                      Ok(_) => {
                        println("YAMI_SETTINGS_IME {\"stage\":\"entered_ack\",\"native_sequence\":\{receipt.native_sequence()}}")
                        Ok(())
                      }
                      Err(error) => Err(error)
                    }
                  },
                )))
              }
              _ => ()
            }
            let event = match receipt.event() {
              @ubuntu_host.Text(value) => Some(@common.OrderedText(value))
              @ubuntu_host.Platform(value) => Some(@common.OrderedPlatform(value))
              // Preserve other lifecycle and unsupported records without ACK;
              // neither is an observed cancel.
              _ => None
            }
            Ok(Some(@common.NativeRetainedReceipt::new(
              event, receipt.native_window(), receipt.native_sequence(),
              receipt.root(), receipt.epoch(), fn() { receipt.ack() },
            )))
          }
        }
      },
      fn(epoch) { retained.try_end_when_drained(epoch) },
    )
    let entry = @common.SettingsEntryController::start(
      host, @common.Linux, ubuntu_measure, text_port=Some(retained_port),
      direct_text=Some(fn(window, enabled) { host.set_direct_keyboard_text(window, enabled) }),
      ordered_text=Some(retained_ordered),
    )
    run_settings_control(entry)
    return
  }
  let legacy = @ubuntu_host.TextHostRoute::new(host)
  let route = @ubuntu_host.OrderedTextHostRoute::new(host)
  let legacy_text_port = @common.NativeTextInputPort::new(
    fn(window, root) { legacy.begin_text_input(window, root) },
    fn(epoch, state) {
      match ubuntu_text_state(state) {
        Ok(value) => legacy.update_text_input(epoch, value)
        Err(error) => Err(error)
      }
    },
    fn(epoch) { legacy.cancel_text_input(epoch) },
    fn(epoch) { legacy.end_text_input(epoch) },
    fn(timeout) { legacy.next_text_input(timeout_ms=timeout) },
  )
  let text_begin : @common.NativeTextBegin = fn(window, root) {
    route.begin_text_input(window, root)
  }
  let text_update : @common.NativeTextUpdate = fn(epoch, state) {
    let normalized = match ubuntu_text_state(state) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    route.update_text_input(epoch, normalized)
  }
  let text_cancel : @common.NativeTextCancel = fn(epoch) {
    route.cancel_text_input(epoch)
  }
  let text_end : @common.NativeTextEnd = fn(epoch) {
    route.end_text_input(epoch)
  }
  let text_next : @common.NativeTextNext = fn(_) { Ok(None) }
  let text_port = @common.NativeTextInputPort::new(
    text_begin, text_update, text_cancel, text_end, text_next,
  )
  let ordered_next = fn(timeout) {
    match route.next_ordered_event(timeout_ms=timeout) {
      Ok(Some(@ubuntu_host.Text(value))) => Ok(Some(@common.OrderedText(value)))
      Ok(Some(@ubuntu_host.Platform(value))) =>
        Ok(Some(@common.OrderedPlatform(value)))
      Ok(None) => Ok(None)
      Err(error) => Err(error)
    }
  }
  let ordered_text = @common.NativeOrderedTextPort::new(ordered_next, fn(
    epoch,
  ) {
    route.try_end_when_drained(epoch)
  })
  // Weston installs no text-input-v1 manager, so the settings lane falls
  // back to the compositor key path armed through the host's direct
  // keyboard-text mode.
  let direct_text : @common.NativeDirectText = fn(window, enabled) {
    host.set_direct_keyboard_text(window, enabled)
  }
  let result = @common.run_native_entry(
    host,
    @common.Linux,
    ubuntu_measure,
    capture,
    text_port=Some(legacy_text_port),
    settings_text_port=Some(text_port),
    settings_ordered_text=Some(ordered_text),
    settings_direct_text=Some(direct_text),
  )
  let stopped = host.stop()
  match result {
    Err(error) => abort(@common.format_framework_error(error))
    Ok(_) => ()
  }
  match stopped {
    Err(error) => abort(@common.format_framework_error(error))
    Ok(_) => ()
  }
}
