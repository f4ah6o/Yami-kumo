///|
/// These callbacks are implemented by the retained native adapter. A successful
/// seal must atomically close admission after the exact Destroyed ACK; an empty
/// peek or a text cutoff alone is not a seal.
pub struct NativeDirectLifecyclePort {
  release : (UInt64) -> Result[Unit, @diagnostics.FrameworkError]
  rebind : (@platform.WindowId, UInt64, UInt64, Int32) -> Result[
    UInt64,
    @diagnostics.FrameworkError,
  ]
  seal_destroyed : (@platform.WindowId, Int32) -> Result[
    Unit,
    @diagnostics.FrameworkError,
  ]
}

///|
pub fn NativeOrderedTextPort::with_direct_lifecycle(
  self : NativeOrderedTextPort,
  release : (UInt64) -> Result[Unit, @diagnostics.FrameworkError],
  rebind : (@platform.WindowId, UInt64, UInt64, Int32) -> Result[
    UInt64,
    @diagnostics.FrameworkError,
  ],
  seal_destroyed : (@platform.WindowId, Int32) -> Result[
    Unit,
    @diagnostics.FrameworkError,
  ],
) -> NativeOrderedTextPort {
  { ..self, direct_lifecycle: Some({ release, rebind, seal_destroyed, }), }
}

///|
priv enum DirectRecordResolution {
  DirectPassive
  DirectEdit(
    @ui.OwnedDirectDelivery,
    @shared_settings.Model,
    @shared_settings.Model
  )
  DirectPlatform(
    @shared_settings.Model,
    Array[@view.SemanticAction],
    @shared_settings.Model
  )
  DirectSaveFinished(@shared_settings.Model, @shared_settings.Model)
  DirectBoundary
  DirectDeferredRelease
}

///|
priv struct DirectRecordProof {
  receipt : NativeRetainedReceipt
  mut resolution : DirectRecordResolution
}

///|
priv struct DirectPendingAdmission {
  receipt : NativeRetainedReceipt
  before : @shared_settings.Model
  delivery : @ui.OwnedDirectDelivery?
  mut proof : DirectRecordProof?
  mut platform_attempted : Bool
}

///|
priv struct DirectLeaseProof {
  owner : @ui.TerminalTextOwner
  session : TextSession
  document : String
  progress : (UInt64, Int32, Int64)
  direct_progress : (Int64, Int32)
  mut native_epoch : Int32?
}

///|
priv struct DirectSceneProof {
  frame : @ui.Frame
  model : @shared_settings.Model
  fence : SettingsModelFence
  owner : (@ui.TerminalTextOwner, (UInt64, Int32, Int64), (Int64, Int32))?
  mut completed : Bool
}

///|
priv struct SettingsDirectRun {
  port : NativeDirectLifecyclePort
  records : Array[DirectRecordProof]
  pressed : Array[@primitives.Key]
  mut retired : Int32
  mut prefix_model : @shared_settings.Model
  mut unbound_epoch : UInt64
  mut lease : DirectLeaseProof?
  mut scene : DirectSceneProof?
  mut boundary : NativeRetainedReceipt?
  mut pending : DirectPendingAdmission?
  mut checkpoint : Bool
  mut release_attempted : Bool
  mut rebind_attempted : Bool
  mut close_requested : Bool
  mut destroy_attempted : Bool
  mut destroyed_sequence : Int32?
  mut admission_sealed : Bool
}

///|
fn direct_lifecycle_error(detail : String) -> @diagnostics.FrameworkError {
  runner_error("direct_lifecycle", detail)
}

///|
fn direct_printable_press(event : @platform.Event) -> Bool {
  match event.kind() {
    @platform.Input(
      @primitives.KeyPressed(
        key=@primitives.Character(_)
        | @primitives.Space,
        modifiers~,
        ..
      )
    ) => !modifiers.control() && !modifiers.meta() && !modifiers.alt()
    _ => false
  }
}

///|
fn same_direct_platform(a : @platform.Event, b : @platform.Event) -> Bool {
  if a.window() != b.window() ||
    a.sequence() != b.sequence() ||
    a.scale() != b.scale() {
    return false
  }
  match (a.kind(), b.kind()) {
    (@platform.Input(x), @platform.Input(y)) => x == y
    (@platform.FocusChanged(x), @platform.FocusChanged(y)) => x == y
    (@platform.Resized(width=a, height=b), @platform.Resized(width=x, height=y)) =>
      a == x && b == y
    (@platform.Created, @platform.Created)
    | (@platform.FrameCompleted, @platform.FrameCompleted)
    | (@platform.ScaleChanged, @platform.ScaleChanged)
    | (@platform.CloseRequested, @platform.CloseRequested)
    | (@platform.ExitRequested, @platform.ExitRequested)
    | (@platform.Destroyed, @platform.Destroyed)
    | (@platform.Wake, @platform.Wake) => true
    _ => false
  }
}

///|
fn same_direct_native(
  a : NativeRetainedReceipt,
  b : NativeRetainedReceipt,
) -> Bool {
  a.window == b.window &&
  a.sequence == b.sequence &&
  a.root == b.root &&
  a.epoch == b.epoch &&
  a.direct == b.direct &&
  a.edit_key_epoch == b.edit_key_epoch &&
  a.entered == b.entered &&
  (match (a.event, b.event) {
    (Some(OrderedPlatform(x)), Some(OrderedPlatform(y))) =>
      same_direct_platform(x, y)
    _ => false
  })
}

///|
fn SettingsRunOwner::can_start_direct_lifecycle(
  self : SettingsRunOwner,
) -> Bool {
  self.platform is Linux &&
  self.session is Some(_) &&
  !self.dirty &&
  !self.mounted.has_pending_actions() &&
  self.buffered.is_empty() &&
  self.held_platform.is_empty() &&
  self.inflight is None &&
  self.pending_host_receipt is None &&
  self.receipt_pre_dispatch is None &&
  self.pending_direct is None &&
  (
    self.ordered_text is Some(port) &&
    port.peek is Some(_) &&
    port.direct_lifecycle is Some(_)
  ) &&
  self.port.linux_transport is Some(probe) &&
  probe() is DirectKeyboard
}

///|
fn SettingsRunOwner::capture_direct_scene(
  self : SettingsRunOwner,
  frame : @ui.Frame,
) -> Result[DirectSceneProof, @diagnostics.FrameworkError] {
  if self.mounted.has_pending_actions() ||
    self.dirty ||
    self.pending_direct is Some(_) ||
    self.owned_delivery is Some(_) {
    return Err(direct_lifecycle_error("scene has unresolved model work"))
  }
  let owner = match (self.session, self.terminal_owner) {
    (Some(session), Some(owner)) => {
      let field = match self.mounted.focused_text() {
        Some(value) => value
        None => return Err(direct_lifecycle_error("scene field is unavailable"))
      }
      if !self.host_epoch_verified ||
        self.host_epoch != Some(session.epoch) ||
        !owner.matches_session(self.window, session.epoch, session.binding) ||
        !self.mounted.terminal_owner_is_current(owner) ||
        field.document().text() != self.settings.name() ||
        field.binding_id() != session.binding ||
        !frame.focused(@shared_settings.settings_name()) ||
        frame.binding_id(@shared_settings.settings_name()) !=
        Some(session.binding) {
        return Err(
          direct_lifecycle_error("scene does not represent the original owner"),
        )
      }
      Some((owner, owner.observed_progress(), owner.direct_progress()))
    }
    (None, None) => None
    _ => return Err(direct_lifecycle_error("scene lease is incomplete"))
  }
  Ok({
    frame,
    model: self.settings,
    fence: self.model_fence,
    owner,
    completed: false,
  })
}

///|
fn SettingsRunOwner::direct_scene_is_current(
  self : SettingsRunOwner,
  run : SettingsDirectRun,
) -> Bool {
  let scene = match run.scene {
    Some(value) => value
    None => return false
  }
  let frame = match self.mounted.frame() {
    Some(value) => value
    None => return false
  }
  if !scene.completed ||
    !scene.fence.live ||
    scene.model != self.settings ||
    self.dirty ||
    self.pending_frame is Some(_) ||
    frame.revision() != scene.frame.revision() ||
    self.mounted.has_pending_actions() {
    return false
  }
  match (scene.owner, self.session, self.terminal_owner) {
    (Some((owner, progress, direct_progress)), Some(session), Some(current)) =>
      owner.matches_session(self.window, session.epoch, session.binding) &&
      current.matches_session(self.window, session.epoch, session.binding) &&
      self.mounted.terminal_owner_is_current(owner) &&
      self.mounted.terminal_owner_is_current(current) &&
      owner.observed_progress() == progress &&
      owner.direct_progress() == direct_progress &&
      self.host_epoch_verified &&
      self.host_epoch == Some(session.epoch)
    (None, None, None) => true
    _ => false
  }
}

///|
fn SettingsRunOwner::start_direct_run(
  self : SettingsRunOwner,
) -> Result[SettingsDirectRun, @diagnostics.FrameworkError] {
  let ordered = self.ordered_text.unwrap()
  let session = self.session.unwrap()
  let owner = match self.terminal_owner {
    Some(value) => value
    None => return Err(direct_lifecycle_error("initial owner is unavailable"))
  }
  if self.pending_host_receipt is Some(_) ||
    self.receipt_pre_dispatch is Some(_) ||
    self.inflight is Some(_) ||
    self.pending_direct is Some(_) ||
    self.owned_delivery is Some(_) ||
    self.held_tab is Some(_) ||
    !self.buffered.is_empty() ||
    !self.held_platform.is_empty() ||
    !self.direct_receipts.is_empty() ||
    self.retired_prefix is Some(_) ||
    self.accessibility_port is Some(_) ||
    self.dialog_port is Some(_) {
    return Err(direct_lifecycle_error("initial ownership is unresolved"))
  }
  let records : Array[DirectRecordProof] = []
  for i = 0; i < self.acknowledged_receipts.length(); i = i + 1 {
    let entry = self.acknowledged_receipts[i]
    let created = entry.receipt.event is Some(OrderedPlatform(event)) &&
      event.kind() is @platform.Created &&
      event.window() == self.window &&
      event.sequence() == entry.receipt.sequence.to_int64() &&
      entry.receipt.root == 0UL &&
      entry.receipt.epoch == 0UL &&
      entry.stage is ReceiptAcknowledgedOnly
    if entry.receipt.sequence != i + 1 ||
      (
        !created &&
        (
          !(entry.stage is (ReceiptPlatformHandled | ReceiptPointerMovedHandled)) ||
          !(entry.receipt.event is Some(OrderedPlatform(event)) &&
          same_handled_platform_kind(event.kind(), event.kind()))
        )
      ) {
      return Err(
        direct_lifecycle_error(
          "bootstrap native prefix is unproven at sequence \{entry.receipt.sequence}",
        ),
      )
    }
    records.push({ receipt: entry.receipt, resolution: DirectPassive, })
  }
  let scene = match self.mounted.frame() {
    Some(frame) if self.pending_frame is Some(_) =>
      match self.capture_direct_scene(frame) {
        Ok(value) => Some(value)
        Err(error) => return Err(error)
      }
    _ => {
      self.dirty = true
      None
    }
  }
  Ok({
    port: ordered.direct_lifecycle.unwrap(),
    records,
    pressed: [],
    retired: 0,
    prefix_model: self.settings,
    unbound_epoch: 0UL,
    lease: Some({
      owner,
      session,
      document: self.settings.name(),
      progress: owner.observed_progress(),
      direct_progress: owner.direct_progress(),
      native_epoch: None,
    }),
    scene,
    boundary: None,
    pending: None,
    checkpoint: false,
    release_attempted: false,
    rebind_attempted: false,
    close_requested: false,
    destroy_attempted: false,
    destroyed_sequence: None,
    admission_sealed: false,
  })
}

///|
fn SettingsRunOwner::verify_direct_prefix(
  self : SettingsRunOwner,
  run : SettingsDirectRun,
  count : Int32,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if count < 0 ||
    run.rebind_attempted ||
    count > run.records.length() ||
    run.records.length() != self.acknowledged_receipts.length() ||
    self.pending_host_receipt is Some(_) ||
    self.receipt_pre_dispatch is Some(_) ||
    self.pending_direct is Some(_) ||
    self.owned_delivery is Some(_) ||
    run.pending is Some(_) ||
    self.mounted.has_pending_actions() ||
    !self.direct_scene_is_current(run) {
    return Err(
      direct_lifecycle_error(
        "retirement requires an exact completed scene and resolved actions",
      ),
    )
  }
  let mut document = run.lease
    .map(value => value.document)
    .unwrap_or(self.settings.name())
  let mut progress = run.lease
    .map(value => value.progress)
    .unwrap_or((0UL, 0, 0L))
  let mut direct_progress = run.lease
    .map(value => value.direct_progress)
    .unwrap_or((0L, 0))
  let mut direct_count = 0
  let mut expected_model = run.prefix_model
  for i = 0; i < count; i = i + 1 {
    let proof = run.records[i]
    let entry = self.acknowledged_receipts[i]
    if proof.receipt.sequence.to_int64() !=
      run.retired.to_int64() + i.to_int64() + 1L ||
      !same_direct_native(proof.receipt, entry.receipt) {
      return Err(direct_lifecycle_error("native prefix identity changed"))
    }
    match proof.resolution {
      DirectPassive => ()
      DirectBoundary | DirectDeferredRelease =>
        return Err(
          direct_lifecycle_error("boundary action has not been dispatched"),
        )
      DirectPlatform(before, actions, after) => {
        if before != expected_model {
          return Err(direct_lifecycle_error("platform model prefix changed"))
        }
        let mut expected = before
        for action in actions {
          expected = expected.update(@shared_settings.Ui(action))
        }
        if expected != after {
          return Err(
            direct_lifecycle_error("platform model action chain changed"),
          )
        }
        expected_model = after
      }
      DirectSaveFinished(before, after) => {
        if before != expected_model ||
          before.update(@shared_settings.SaveFinished) != after ||
          !(proof.receipt.event is Some(OrderedPlatform(event)) &&
          event.kind() is @platform.FrameCompleted) {
          return Err(direct_lifecycle_error("save completion model prefix changed"))
        }
        expected_model = after
      }
      DirectEdit(delivery, before, after) => {
        let lease = match run.lease {
          Some(value) => value
          None =>
            return Err(
              direct_lifecycle_error("direct receipt has no original lease"),
            )
        }
        let (ordinal, native_sequence) = direct_progress
        let (window, epoch, binding, generation, sequence) = delivery.identity()
        if !delivery.matches_owner(lease.owner) ||
          !delivery.applied() ||
          !delivery.owner_noted() ||
          delivery.before_document() != document ||
          delivery.before_progress() != progress ||
          before != expected_model ||
          before.name() != document ||
          delivery.after_document() != Some(after.name()) ||
          window != proof.receipt.window ||
          epoch != proof.receipt.epoch ||
          binding != proof.receipt.root ||
          generation != progress.0 ||
          sequence != proof.receipt.sequence.to_int64() ||
          delivery.native_sequence() != proof.receipt.sequence ||
          delivery.native_sequence() <= native_sequence ||
          !(proof.receipt.event is Some(OrderedPlatform(event)) &&
          same_direct_event(delivery.event(), event)) ||
          (if delivery.is_edit_key() {
            delivery.ordinal() != ordinal ||
            proof.receipt.edit_key_epoch != lease.native_epoch
          } else {
            ordinal == 9223372036854775807L ||
            delivery.ordinal() != ordinal + 1L ||
            proof.receipt.direct !=
            lease.native_epoch.map(value => (value, delivery.ordinal()))
          }) {
          return Err(
            direct_lifecycle_error("direct operation or original owner changed"),
          )
        }
        match delivery.action_required() {
          Some(true) if delivery.model_applied() &&
            delivery.pending_action() is None &&
            before.update(
              @shared_settings.Ui(
                @view.TextChanged(
                  @shared_settings.settings_name(),
                  after.name(),
                ),
              ),
            ) ==
            after => ()
          Some(false) if before == after && delivery.pending_action() is None =>
            ()
          _ =>
            return Err(
              direct_lifecycle_error("direct model effect is unresolved"),
            )
        }
        let after_progress = match delivery.after_progress() {
          Some(value) => value
          None =>
            return Err(
              direct_lifecycle_error("direct field effect is unresolved"),
            )
        }
        if after_progress.0 != progress.0 ||
          after_progress.1 < progress.1 ||
          after_progress.2 != progress.2 {
          return Err(direct_lifecycle_error("direct field progress changed"))
        }
        if direct_count >= self.direct_receipts.length() ||
          !same_direct_native(
            self.direct_receipts[direct_count].0,
            proof.receipt,
          ) ||
          self.direct_receipts[direct_count].1.identity() != delivery.identity() {
          return Err(
            direct_lifecycle_error("direct ledger association changed"),
          )
        }
        direct_count += 1
        document = after.name()
        progress = after_progress
        direct_progress = (delivery.ordinal(), delivery.native_sequence())
        expected_model = after
      }
    }
  }
  if direct_count != self.direct_receipts.length() {
    return Err(direct_lifecycle_error("direct suffix is still owned"))
  }
  if expected_model != self.settings {
    return Err(direct_lifecycle_error("completed scene differs from the model prefix"))
  }
  match run.lease {
    Some(lease) if lease.owner.observed_progress() != progress ||
      lease.owner.direct_progress() != direct_progress ||
      self.settings.name() != document ||
      !self.mounted.terminal_field_can_cutoff(lease.owner) =>
      Err(
        direct_lifecycle_error(
          "original field no longer matches the model chain",
        ),
      )
    _ => Ok(())
  }
}

///|
fn SettingsRunOwner::compact_direct_prefix(
  self : SettingsRunOwner,
  run : SettingsDirectRun,
  count : Int32,
) -> Unit {
  for _ in 0..<count {
    let proof = run.records.remove(0)
    match proof.resolution {
      DirectEdit(_, _, after) | DirectPlatform(_, _, after) |
      DirectSaveFinished(_, after) => run.prefix_model = after
      _ => ()
    }
    run.retired = proof.receipt.sequence
    ignore(self.acknowledged_receipts.remove(0))
  }
  self.direct_receipts.clear()
}

///|
fn SettingsRunOwner::release_direct_lease(
  self : SettingsRunOwner,
  run : SettingsDirectRun,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let lease = match run.lease {
    Some(value) => value
    None => return Ok(())
  }
  let count = match run.boundary {
    Some(boundary) => boundary.sequence.to_int64() - run.retired.to_int64() - 1L
    None => run.records.length().to_int64()
  }
  match self.verify_direct_prefix(run, count.to_int()) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if !self.cutoff_done ||
    run.release_attempted ||
    !(self.session is Some(current) &&
    current.epoch == lease.session.epoch &&
    current.binding == lease.session.binding) {
    return Err(
      direct_lifecycle_error("host cutoff or release state is unresolved"),
    )
  }
  // An error may follow native side effects. Keeping the attempt prevents an
  // implicit retry from treating an uncertain release as successful.
  run.release_attempted = true
  match (run.port.release)(lease.session.epoch) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match self.mounted.release_terminal_text_owner(lease.owner) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  self.compact_direct_prefix(run, count.to_int())
  emit_native_marker(
    "YAMI_NATIVE_UI_SETTINGS {\"phase\":\"direct-retired\",\"sequence\":\{run.retired},\"epoch\":\{lease.session.epoch}}",
  )
  self.session = None
  self.terminal_owner = None
  self.host_epoch = None
  self.host_epoch_verified = false
  run.unbound_epoch = lease.session.epoch
  self.last_document = ""
  run.lease = None
  // Releasing a host lease changes no pixels. Preserve the completed model
  // scene, removing only the now-revoked live-owner reference.
  run.scene = run.scene.map(scene => { ..scene, owner: None, })
  self.cutoff_done = false
  run.release_attempted = false
  run.checkpoint = false
  Ok(())
}

///|
fn SettingsRunOwner::direct_render(
  self : SettingsRunOwner,
  run : SettingsDirectRun,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if self.mounted.has_pending_actions() ||
    self.pending_host_receipt is Some(_) ||
    self.pending_direct is Some(_) {
    return Err(direct_lifecycle_error("render cannot discard unresolved input"))
  }
  let (width, height, scale) = match self.host.window_metrics(self.window) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let frame = match
    self.mounted.commit(
      self.settings.view(),
      width,
      height,
      scale,
      self.measure,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if self.mounted.has_pending_actions() {
    return Err(direct_lifecycle_error("commit produced an unresolved action"))
  }
  self.dirty = false
  if !self.text_suspended && !self.focus_initialized {
    if frame.focused(@shared_settings.settings_name()) {
      self.focus_initialized = true
    } else if self.mounted.focus(@shared_settings.settings_name()) {
      self.dirty = true
    }
  }
  if self.dirty {
    return Ok(())
  }
  match self.session {
    Some(session) => {
      let field = match self.mounted.focused_text() {
        Some(value) => value
        None => return Err(direct_lifecycle_error("render lost original focus"))
      }
      self.host_epoch_verified = false
      let epoch = match
        (self.port.update)(
          session.epoch,
          @text_host.TextInputState::new(
            field.document(),
            settings_caret(field.caret()),
          ),
        ) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      self.host_epoch = Some(epoch)
      self.host_epoch_verified = true
      if epoch != session.epoch {
        return Err(direct_lifecycle_error("render replaced the host epoch"))
      }
      self.last_document = field.document().text()
      self.last_caret = settings_caret(field.caret())
    }
    None => ()
  }
  let scene = match self.capture_direct_scene(frame) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  run.scene = Some(scene)
  match self.host.present(self.window, frame.snapshot()) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  self.gate.mark_presented()
  let focus = if frame.focused(@shared_settings.settings_name()) {
    "name"
  } else if frame.focused(@shared_settings.settings_save()) {
    "save"
  } else if frame.focused(@shared_settings.settings_confirm()) {
    "confirm"
  } else if frame.focused(@shared_settings.settings_cancel()) {
    "cancel"
  } else {
    "other"
  }
  let error_text = self.settings.error().unwrap_or("")
  self.pending_frame = Some(
    "YAMI_NATIVE_UI_SETTINGS {\"phase\":\"frame\",\"name\":\"\{json_escape(self.settings.name())}\",\"status\":\"\{settings_status(self.settings)}\",\"dialog\":\{self.settings.dialog_open()},\"focus\":\"\{focus}\",\"error\":\"\{json_escape(error_text)}\"}",
  )
  Ok(())
}

///|
fn SettingsRunOwner::direct_dispatch_platform(
  self : SettingsRunOwner,
  run : SettingsDirectRun,
  proof : DirectRecordProof,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let event = match proof.receipt.event {
    Some(OrderedPlatform(value)) => value
    _ => return Err(direct_lifecycle_error("platform record is unavailable"))
  }
  if self.mounted.has_pending_actions() {
    return Err(
      direct_lifecycle_error("platform input cannot overtake an action"),
    )
  }
  let before = self.settings
  let unchanged_owner = if direct_printable_press(event) ||
    event.kind() is @platform.Input(@primitives.KeyReleased(..)) {
    match (self.terminal_owner, self.mounted.focused_text(), self.mounted.frame()) {
      (Some(owner), Some(field), Some(frame)) =>
        Some((owner, owner.observed_progress(), owner.direct_progress(), field,
          frame.revision(), self.model_fence))
      _ => None
    }
  } else {
    None
  }
  match event.kind() {
    @platform.FrameCompleted => {
      match (run.scene, self.pending_frame) {
        (Some(scene), Some(marker)) => {
          scene.completed = true
          self.pending_frame = None
          emit_native_marker(marker)
        }
        _ => ()
      }
      proof.resolution = DirectPassive
      if self.settings.saving() {
        self.saving_frames += 1
        if self.saving_frames >= 3 {
          self.replace_settings(
            self.settings.update(@shared_settings.SaveFinished),
          )
          self.saving_frames = 0
          proof.resolution = DirectSaveFinished(before, self.settings)
        }
        self.dirty = true
      }
      return Ok(())
    }
    @platform.Created | @platform.Wake => {
      proof.resolution = DirectPassive
      return Ok(())
    }
    @platform.CloseRequested | @platform.ExitRequested => {
      if self.session is Some(_) || run.destroy_attempted {
        return Err(direct_lifecycle_error("close still owns a text lease"))
      }
      proof.resolution = DirectPlatform(before, [], before)
      run.close_requested = true
      return Ok(())
    }
    @platform.Destroyed => {
      run.destroyed_sequence = Some(proof.receipt.sequence)
      proof.resolution = DirectPassive
      return Ok(())
    }
    @platform.Composition(_) | @platform.Input(@primitives.TextInput(_)) =>
      return Err(
        direct_lifecycle_error("unowned text cannot enter the platform path"),
      )
    _ => ()
  }
  match event.kind() {
    @platform.Input(@primitives.KeyPressed(key~, ..)) => {
      let name = match key {
        @primitives.Tab => "tab"
        @primitives.Enter => "enter"
        @primitives.Escape => "escape"
        @primitives.Backspace => "backspace"
        _ => "other"
      }
      emit_native_marker(
        "YAMI_NATIVE_UI_SETTINGS {\"phase\":\"key\",\"key\":\"\{name}\"}",
      )
    }
    _ => ()
  }
  let handled = match self.mounted.handle_event(event) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let observed_input = match event.kind() {
    @platform.Input(@primitives.PointerMoved(..) | @primitives.KeyReleased(..)) =>
      self.mounted.last_dispatched_input_sequence() == event.sequence()
    _ if unchanged_owner is Some(_) =>
      self.mounted.last_dispatched_input_sequence() == event.sequence()
    _ => false
  }
  if !handled && !observed_input {
    return Err(direct_lifecycle_error("platform dispatch was not accepted"))
  }
  let actions : Array[@view.SemanticAction] = []
  while self.mounted.next_action() is Some(action) {
    actions.push(action)
    self.replace_settings(self.settings.update(@shared_settings.Ui(action)))
  }
  match unchanged_owner {
    Some((owner, progress, direct_progress, field, revision, fence)) =>
      if !actions.is_empty() ||
        self.settings != before ||
        !fence.live ||
        !self.mounted.terminal_owner_is_current(owner) ||
        owner.observed_progress() != progress ||
        owner.direct_progress() != direct_progress ||
        !(self.mounted.frame() is Some(current) &&
        current.revision() == revision) ||
        !(self.mounted.focused_text() is Some(current) &&
        current.key() == field.key() &&
        current.binding_id() == field.binding_id() &&
        current.document() == field.document() &&
        current.document().text() == before.name() &&
        current.caret() == field.caret() &&
        current.composing() == field.composing()) {
        return Err(
          direct_lifecycle_error(
            "passive key edge changed the original field",
          ),
        )
      }
    None => ()
  }
  proof.resolution = DirectPlatform(before, actions, self.settings)
  match event.kind() {
    @platform.FocusChanged(focused) => {
      self.text_suspended = !focused
      if !focused {
        self.focus_initialized = false
      }
    }
    _ => ()
  }
  // A proven passive key edge changes no scene state. Preserve any existing
  // dirty edit, but do not keep a completed scene perpetually in flight merely
  // because its physical press/release was also acknowledged.
  if unchanged_owner is None {
    self.dirty = true
  }
  Ok(())
}

///|
fn SettingsRunOwner::direct_admit(
  self : SettingsRunOwner,
  run : SettingsDirectRun,
  receipt : NativeRetainedReceipt,
) -> Result[Unit, @diagnostics.FrameworkError] {
  self.pending_host_receipt = Some(receipt)
  self.receipt_pre_dispatch = Some(receipt)
  self.inflight = receipt.event
  let event = match receipt.event {
    Some(OrderedPlatform(value)) => value
    _ =>
      return Err(
        direct_lifecycle_error(
          "unsupported native record remains unacknowledged",
        ),
      )
  }
  if receipt.window != self.window ||
    event.window() != self.window ||
    receipt.sequence <= 0 ||
    event.sequence() != receipt.sequence.to_int64() ||
    receipt.sequence.to_int64() !=
    run.retired.to_int64() + self.acknowledged_receipts.length().to_int64() + 1L ||
    self.mounted.has_pending_actions() {
    return Err(
      direct_lifecycle_error(
        "native identity, sequence or pending action is unresolved",
      ),
    )
  }
  match self.session {
    Some(session) if receipt.root != session.binding ||
      receipt.epoch != session.epoch =>
      return Err(
        direct_lifecycle_error("native lease differs from original owner"),
      )
    None if receipt.root != 0UL || receipt.epoch != run.unbound_epoch =>
      return Err(
        direct_lifecycle_error("record belongs to a different released lease"),
      )
    _ => ()
  }
  if self.session is None && direct_printable_press(event) &&
    (self.mounted.focused_text() is Some(field) &&
    field.key() == @shared_settings.settings_name()) {
    // While native rearm is pending, this physical press has no corresponding
    // direct TextInput record. It cannot be acknowledged as a harmless no-op
    // or reconstructed as an edit belonging to a not-yet-created owner.
    return Err(direct_lifecycle_error("printable key arrived before direct owner rebind"))
  }
  let direct = receipt.direct is Some(_) || receipt.edit_key_epoch is Some(_)
  if run.close_requested {
    match event.kind() {
      @platform.FrameCompleted
      | @platform.Destroyed
      | @platform.Input(@primitives.KeyReleased(..)) => ()
      _ => return Err(direct_lifecycle_error("input after close remains owned"))
    }
  }
  if run.boundary is Some(_) {
    match event.kind() {
      @platform.FrameCompleted | @platform.Input(@primitives.KeyReleased(..)) =>
        ()
      _ =>
        return Err(
          direct_lifecycle_error(
            "later input cannot overtake the retained boundary",
          ),
        )
    }
  }
  let before = self.settings
  if direct {
    let lease = match run.lease {
      Some(value) => value
      None =>
        return Err(
          direct_lifecycle_error("direct record has no original owner"),
        )
    }
    let epoch = match (receipt.direct, receipt.edit_key_epoch) {
      (Some((value, _)), None) | (None, Some(value)) => value
      _ => return Err(direct_lifecycle_error("ambiguous direct kind"))
    }
    if lease.native_epoch is Some(previous) && previous != epoch {
      return Err(direct_lifecycle_error("native direct epoch changed"))
    }
    lease.native_epoch = Some(epoch)
    match self.reserve_pending_direct(receipt) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  run.pending = Some({
    receipt,
    before,
    delivery: self.pending_direct,
    proof: None,
    platform_attempted: false,
  })
  match self.ack_owned_receipt() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  self.complete_direct_admission(run)
}

///|
fn SettingsRunOwner::complete_direct_admission(
  self : SettingsRunOwner,
  run : SettingsDirectRun,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let pending = match run.pending {
    Some(value) => value
    None => return Err(direct_lifecycle_error("admission proof is unavailable"))
  }
  let receipt = pending.receipt
  let event = match receipt.event {
    Some(OrderedPlatform(value)) => value
    _ => return Err(direct_lifecycle_error("admission event is unavailable"))
  }
  if self.pending_host_receipt is Some(_) ||
    !(self.acknowledged_receipts.last() is Some(entry) &&
    same_direct_native(entry.receipt, receipt)) {
    return Err(direct_lifecycle_error("original admission is not acknowledged"))
  }
  self.receipt_pre_dispatch = None
  let proof = match pending.proof {
    Some(value) => value
    None => {
      let value : DirectRecordProof = { receipt, resolution: DirectBoundary, }
      pending.proof = Some(value)
      run.records.push(value)
      match event.kind() {
        @platform.Input(@primitives.KeyPressed(key~, ..)) =>
          if !run.pressed.contains(key) {
            run.pressed.push(key)
          }
        @platform.Input(@primitives.KeyReleased(key~, ..)) =>
          for i = 0; i < run.pressed.length(); i = i + 1 {
            if run.pressed[i] == key {
              ignore(run.pressed.remove(i))
              break
            }
          }
        _ => ()
      }
      value
    }
  }
  if pending.delivery is Some(delivery) {
    match self.complete_pending_direct() {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    proof.resolution = DirectEdit(delivery, pending.before, self.settings)
    self.dirty = true
  } else {
    if pending.platform_attempted {
      return Err(direct_lifecycle_error("platform effect is uncertain"))
    }
    pending.platform_attempted = true
    let boundary = self.session is Some(_) &&
      !direct_printable_press(event) &&
      (match event.kind() {
        @platform.FrameCompleted
        | @platform.Created
        | @platform.Wake
        | @platform.Input(@primitives.KeyReleased(..))
        | @platform.Input(@primitives.PointerMoved(..)) => false
        _ => true
      })
    if boundary {
      if run.boundary is Some(_) {
        return Err(direct_lifecycle_error("another boundary is retained"))
      }
      run.boundary = Some(receipt)
    } else if run.boundary is Some(_) &&
      event.kind() is @platform.Input(@primitives.KeyReleased(..)) {
      proof.resolution = DirectDeferredRelease
    } else {
      match self.direct_dispatch_platform(run, proof) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    }
  }
  self.inflight = None
  self.last_sequence = event.sequence()
  run.pending = None
  if self.suspended {
    self.live_step_ready = true
    if self.live_step_generation == 0L {
      self.live_step_generation = 1L
    }
  }
  Ok(())
}

///|
fn SettingsRunOwner::direct_begin_again(
  self : SettingsRunOwner,
  run : SettingsDirectRun,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if self.session is Some(_) ||
    !run.pressed.is_empty() ||
    self.text_suspended ||
    run.close_requested ||
    run.destroy_attempted ||
    run.destroyed_sequence is Some(_) ||
    run.boundary is Some(_) ||
    self.dirty ||
    self.pending_frame is Some(_) {
    return Ok(())
  }
  let frame = match self.mounted.frame() {
    Some(value) => value
    None => return Ok(())
  }
  if !frame.focused(@shared_settings.settings_name()) {
    return Ok(())
  }
  if run.rebind_attempted {
    return Err(direct_lifecycle_error("previous host rebind is unresolved"))
  }
  match self.verify_direct_prefix(run, run.records.length()) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let field = self.mounted.focused_text().unwrap()
  let state = @text_host.TextInputState::new(
    field.document(),
    settings_caret(field.caret()),
  )
  let watermark = if run.records.is_empty() {
    run.retired
  } else {
    run.records[run.records.length() - 1].receipt.sequence
  }
  run.rebind_attempted = true
  let epoch = match (run.port.rebind)(self.window, field.binding_id(),
    run.unbound_epoch, watermark) {
    Ok(value) => value
    Err(error) if error.code() is @diagnostics.Busy => {
      // The native rebind contract guarantees Busy has no side effects. Drain
      // the still-owned suffix before retrying; other failures remain retained.
      run.rebind_attempted = false
      return Ok(())
    }
    Err(error) => return Err(error)
  }
  self.compact_direct_prefix(run, run.records.length())
  self.session = Some({ epoch, binding: field.binding_id(), })
  self.host_epoch = Some(epoch)
  self.host_epoch_verified = false
  let owner = match self.mounted.capture_terminal_text_owner(epoch) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.terminal_owner = Some(owner)
  if !(self.port.linux_transport is Some(probe) && probe() is DirectKeyboard) {
    return Err(
      direct_lifecycle_error("reopened transport is not direct keyboard"),
    )
  }
  let updated = match (self.port.update)(epoch, state) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.host_epoch = Some(updated)
  self.host_epoch_verified = true
  if updated != epoch {
    return Err(direct_lifecycle_error("reopened host epoch changed"))
  }
  self.last_document = field.document().text()
  self.last_caret = settings_caret(field.caret())
  run.lease = Some({
    owner,
    session: self.session.unwrap(),
    document: self.settings.name(),
    progress: owner.observed_progress(),
    direct_progress: owner.direct_progress(),
    native_epoch: None,
  })
  run.rebind_attempted = false
  self.dirty = true
  Ok(())
}

///|
fn SettingsRunOwner::drive_direct_lifecycle(
  self : SettingsRunOwner,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let run = match self.direct_run {
    Some(value) => value
    None =>
      match self.start_direct_run() {
        Err(error) => return Err(error)
        Ok(value) => {
          self.direct_run = Some(value)
          value
        }
      }
  }
  let ordered = self.ordered_text.unwrap()
  let peek = ordered.peek.unwrap()
  while self.ticks < 6000 {
    self.ticks += 1
    if self.pending_host_receipt is Some(_) ||
      self.receipt_pre_dispatch is Some(_) ||
      self.pending_direct is Some(_) ||
      self.owned_delivery is Some(_) {
      return Err(direct_lifecycle_error("previous receipt remains unresolved"))
    }
    if self.dirty &&
      self.pending_frame is None &&
      !run.destroy_attempted &&
      run.destroyed_sequence is None {
      match self.direct_render(run) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    }
    if run.close_requested && run.pressed.is_empty() &&
      !run.destroy_attempted &&
      self.session is None &&
      run.boundary is None &&
      self.direct_scene_is_current(run) {
      match self.verify_direct_prefix(run, run.records.length()) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      run.destroy_attempted = true
      match self.host.destroy_window(self.window) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    }
    if run.destroyed_sequence is Some(sequence) {
      if self.session is Some(_) ||
        run.boundary is Some(_) ||
        self.mounted.has_pending_actions() ||
        self.pending_frame is Some(_) ||
        self.dirty {
        return Err(
          direct_lifecycle_error("destroyed window still has unpublished work"),
        )
      }
      // The final Destroyed observation closes admission, so no empty-poll
      // inference or caller-provided boolean can substitute for this callback.
      match self.verify_direct_prefix(run, run.records.length()) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      match (run.port.seal_destroyed)(self.window, sequence) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      self.compact_direct_prefix(run, run.records.length())
      run.admission_sealed = true
      self.mounted.dispose()
      self.destroyed = true
      self.completed = true
      emit_native_marker(
        "YAMI_NATIVE_UI_SETTINGS {\"phase\":\"exit\",\"reason\":\"sealed-destroyed\",\"sequence\":\{sequence}}",
      )
      return Ok(())
    }
    if self.acknowledged_receipts.length() >= 48 &&
      self.session is Some(_) &&
      run.boundary is None {
      run.checkpoint = true
    }
    if (run.boundary is Some(_) || run.checkpoint) &&
      self.direct_scene_is_current(run) {
      if !self.cutoff_done {
        let session = self.session.unwrap()
        match (ordered.end_when_drained)(session.epoch) {
          Ok(_) => self.cutoff_done = true
          Err(error) if error.code() is @diagnostics.Busy => ()
          Err(error) => return Err(error)
        }
      }
      if self.cutoff_done {
        match self.release_direct_lease(run) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
        match run.boundary {
          Some(receipt) => {
            let proof = run.records[0]
            if !same_direct_native(proof.receipt, receipt) {
              return Err(direct_lifecycle_error("boundary identity changed"))
            }
            run.boundary = None
            match self.direct_dispatch_platform(run, proof) {
              Err(error) => return Err(error)
              Ok(_) => ()
            }
            for suffix in run.records {
              if suffix.resolution is DirectDeferredRelease {
                match self.direct_dispatch_platform(run, suffix) {
                  Err(error) => return Err(error)
                  Ok(_) => ()
                }
              }
            }
          }
          // A checkpoint changes ownership but no pixels. Rebind immediately
          // against this already-completed scene; the new owner then requires
          // its own publication before any subsequent retirement.
          None => ()
        }
      }
    }
    if self.session is None &&
      !self.dirty &&
      self.pending_frame is None &&
      !run.destroy_attempted &&
      run.destroyed_sequence is None {
      match self.direct_begin_again(run) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    }
    if self.session is None && run.lease is None &&
      run.boundary is None && run.pressed.is_empty() &&
      !run.close_requested && !run.destroy_attempted &&
      run.destroyed_sequence is None &&
      run.records.length() >= 48 && self.direct_scene_is_current(run) {
      // The old native lease is already cut off and released. Dialog/button
      // actions still require their own exact ACK, model and completed scene
      // proofs, even while focus stays outside the text field indefinitely.
      match self.verify_direct_prefix(run, run.records.length()) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      self.compact_direct_prefix(run, run.records.length())
    }
    if self.acknowledged_receipts.length() >= 64 {
      return Err(direct_lifecycle_error("receipt ledger is full"))
    }
    match peek(16) {
      Err(error) => return Err(error)
      Ok(None) => ()
      Ok(Some(receipt)) =>
        match self.direct_admit(run, receipt) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
    }
    if self.bounded_resume {
      return Ok(())
    }
  }
  Err(direct_lifecycle_error("bounded drive ended with retained ownership"))
}
