///|
/// Optional platform-record source while a host text route owns the queue.
/// Route-backed hosts park ordinary records in their own ordered queue, so the
/// runner must not read `Host::next_event` directly.
pub type NativePlatformNext = (Int32) -> Result[
  @platform.Event?,
  @diagnostics.FrameworkError,
]

///|
/// One ordered observation from a host route. This keeps the common runner
/// independent of any particular native backend.
pub(all) enum NativeOrderedEvent {
  OrderedText(@text_host.TextInputEvent)
  OrderedPlatform(@platform.Event)
}

///|
pub struct NativeOrderedTextPort {
  next : (Int32) -> Result[NativeOrderedEvent?, @diagnostics.FrameworkError]
  end_when_drained : (UInt64) -> Result[Unit, @diagnostics.FrameworkError]
}

///|
pub fn NativeOrderedTextPort::new(
  next : (Int32) -> Result[NativeOrderedEvent?, @diagnostics.FrameworkError],
  end_when_drained : (UInt64) -> Result[Unit, @diagnostics.FrameworkError],
) -> NativeOrderedTextPort {
  { next, end_when_drained, }
}

///|
/// Optional direct-keyboard text transport used when the host has no portable
/// text-input session (for example Weston without text-input-v1). Arming it
/// keeps typed characters on the compositor key path as committed text input;
/// disarming it on focus loss keeps stale epochs from being delivered.
pub type NativeDirectText = (@platform.WindowId, Bool) -> Result[
  Unit,
  @diagnostics.FrameworkError,
]

///|
pub type NativeDialogAXPublish = (
  @platform.WindowId,
  Int64,
  String,
  @primitives.Rect,
) -> Result[Int64, @diagnostics.FrameworkError]

///|
pub type NativeDialogAXRevoke = (@platform.WindowId, Int64) -> Result[
  Unit,
  @diagnostics.FrameworkError,
]

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
      match arm(window, true) {
        Ok(_) => {
          if !route.key_path_armed {
            emit_native_marker(
              "YAMI_NATIVE_UI_SETTINGS {\"phase\":\"text\",\"status\":\"key-path\",\"route\":\"direct-keyboard\"}",
            )
          }
          { ..route, key_path_armed: true, }
        }
        Err(_) => {
          if !route.key_path_armed && !route.transport_failed {
            emit_native_marker(
              "YAMI_NATIVE_UI_SETTINGS {\"phase\":\"text\",\"status\":\"unavailable\",\"route\":\"none\"}",
            )
          }
          { key_path_armed: route.key_path_armed, transport_failed: true, }
        }
      }
    None => {
      if !route.transport_failed {
        emit_native_marker(
          "YAMI_NATIVE_UI_SETTINGS {\"phase\":\"text\",\"status\":\"unavailable\",\"route\":\"none\"}",
        )
      }
      { key_path_armed: route.key_path_armed, transport_failed: true, }
    }
  }
}

///|
/// Legacy one-shot entry. Ordered callers needing retention must keep an
/// explicit SettingsRunOwner instead of discarding it on error.
pub fn run_native_settings_sample(
  host : &@platform.Backend,
  platform : NativeSamplePlatform,
  measure : @components.TextMeasure,
  text_port~ : NativeTextInputPort? = None,
  accessibility_port~ : NativeTextAXPort? = None,
  dialog_port~ : NativeDialogAXPort? = None,
  next_platform_event~ : NativePlatformNext? = None,
  direct_text~ : NativeDirectText? = None,
  ordered_text~ : NativeOrderedTextPort? = None,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if ordered_text is Some(_) {
    // A one-shot Result cannot transfer the owner to the caller on failure.
    // Refuse before creating a window or fetching any ordered input.
    return Err(
      runner_error("ordered_text", "ordered input requires a retained owner"),
    )
  }
  let owner = match
    SettingsRunOwner::new(
      host,
      platform,
      measure,
      text_port~,
      accessibility_port~,
      dialog_port~,
      next_platform_event~,
      direct_text~,
      ordered_text~,
    ) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  owner.drive()
}

///|
/// A caller must retain the owner and its host after `Suspended`; this outcome
/// is neither a model acknowledgement nor permission to stop the backend.
pub(all) enum SettingsRunOutcome {
  Completed
  NotStarted(@diagnostics.FrameworkError)
  Suspended(SettingsRunOwner, @diagnostics.FrameworkError)
}

///|
/// Start a run while transferring the original owner back on interruption.
/// A successful drive without an established terminal receipt remains
/// suspended: the owner must not be discarded or the host stopped.
pub fn run_native_settings_retained(
  host : &@platform.Backend,
  platform : NativeSamplePlatform,
  measure : @components.TextMeasure,
  text_port~ : NativeTextInputPort? = None,
  accessibility_port~ : NativeTextAXPort? = None,
  dialog_port~ : NativeDialogAXPort? = None,
  next_platform_event~ : NativePlatformNext? = None,
  direct_text~ : NativeDirectText? = None,
  ordered_text~ : NativeOrderedTextPort? = None,
) -> SettingsRunOutcome {
  if ordered_text is None {
    return NotStarted(
      runner_error("ordered_text", "retained entry currently requires ordered input"),
    )
  }
  let owner = match SettingsRunOwner::new(
    host, platform, measure, text_port~, accessibility_port~, dialog_port~,
    next_platform_event~, direct_text~, ordered_text~,
  ) {
    Err(error) => return NotStarted(error)
    Ok(value) => value
  }
  match owner.drive() {
    Err(error) => Suspended(owner, error)
    Ok(_) if owner.can_stop() => Completed
    Ok(_) => Suspended(
      owner,
      runner_error("ordered_text", "terminal queue receipt is unavailable"),
    )
  }
}

///|
/// Entry-level owner for a retained Settings run. The entrypoint must keep this
/// controller and its host alive whenever `suspended()` is true.
pub struct SettingsEntryController {
  priv host : &@platform.Backend
  priv outcome : SettingsRunOutcome
  priv mut stop_attempted : Bool
  priv mut stopped : Bool
}

///|
/// Start once and retain the outcome. This does not stop the host.
pub fn SettingsEntryController::start(
  host : &@platform.Backend,
  platform : NativeSamplePlatform,
  measure : @components.TextMeasure,
  text_port~ : NativeTextInputPort? = None,
  direct_text~ : NativeDirectText? = None,
  ordered_text~ : NativeOrderedTextPort? = None,
) -> SettingsEntryController {
  {
    host,
    outcome: run_native_settings_retained(host, platform, measure, text_port~, direct_text~, ordered_text~),
    stop_attempted: false,
    stopped: false,
  }
}

///|
pub fn SettingsEntryController::suspended(self : SettingsEntryController) -> Bool {
  self.outcome is Suspended(_, _)
}

///|
/// Observe the retained owner without transferring or recreating its host.
pub fn SettingsEntryController::owner(self : SettingsEntryController) -> SettingsRunOwner? {
  match self.outcome {
    Suspended(owner, _) => Some(owner)
    _ => None
  }
}

///|
/// Run one bounded explicit operation; no error permits implicit host stop.
pub fn SettingsEntryController::terminal_step(
  self : SettingsEntryController,
  command : SettingsTerminalCommand,
) -> Result[SettingsTerminalProgress, @diagnostics.FrameworkError] {
  match self.outcome {
    Suspended(owner, _) => owner.terminal_step(command)
    _ => Err(runner_error("settings_entry", "no suspended owner"))
  }
}

///|
/// Stop only after an outcome that already proved complete owner cleanup.
/// NotStarted and Suspended are conservative failures, leaving the host alive.
pub fn SettingsEntryController::try_stop(
  self : SettingsEntryController,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if self.stop_attempted || self.stopped || !(self.outcome is Completed) {
    return Err(runner_error("settings_entry", "host ownership is unresolved"))
  }
  // A host error need not mean that stop had no side effects. Do not retry it
  // implicitly, including from a reentrant host callback.
  self.stop_attempted = true
  match self.host.stop() {
    Err(error) => Err(error)
    Ok(_) => {
      self.stopped = true
      Ok(())
    }
  }
}

///|
/// Retains one Settings run and its owner state when drive returns an error.
/// The caller must retain the host and owner; an error is not permission to
/// stop it or to replay an observation already applied by the TextSession.
pub struct SettingsRunOwner {
  priv host : &@platform.Backend
  priv platform : NativeSamplePlatform
  priv measure : @components.TextMeasure
  priv port : NativeTextInputPort
  priv accessibility_port : NativeTextAXPort?
  priv dialog_port : NativeDialogAXPort?
  priv next_platform_event : NativePlatformNext?
  priv direct_text : NativeDirectText?
  priv ordered_text : NativeOrderedTextPort?
  priv window : @platform.WindowId
  priv mounted : @ui.Mounted
  priv mut settings : @shared_settings.Model
  priv mut session : TextSession?
  // Host's most recently returned epoch, distinct from the original field
  // owner if an update unexpectedly replaces it.
  priv mut host_epoch : UInt64?
  priv mut terminal_owner : @ui.TerminalTextOwner?
  priv mut terminal_applied : (Int64, Bool)?
  priv mut terminal_model_sequence : Int64
  priv mut ax_token : Int64
  priv mut dialog_token : Int64
  priv mut last_document : String
  priv mut last_caret : @primitives.Rect
  priv mut saving_frames : Int32
  priv gate : PresentationGate
  priv mut pending_frame : String?
  priv mut dirty : Bool
  priv mut focus_initialized : Bool
  priv mut text_suspended : Bool
  priv mut text_transport_failed : Bool
  priv mut key_path_armed : Bool
  priv mut ticks : Int32
  priv mut destroyed : Bool
  priv mut last_sequence : Int64
  priv mut held_tab : @platform.Event?
  priv buffered : Array[NativeOrderedEvent]
  priv held_platform : Array[@platform.Event]
  priv mut inflight : NativeOrderedEvent?
  priv mut cutoff_done : Bool
  priv mut completed : Bool
  priv mut running : Bool
  priv mut suspended : Bool
}

///|
/// The model and pending records are observations, not a host or model ACK.
/// The caller must retain the owner and its host while either is unresolved.
pub fn SettingsRunOwner::model(
  self : SettingsRunOwner,
) -> @shared_settings.Model {
  self.settings
}

///|
pub fn SettingsRunOwner::pending_records(
  self : SettingsRunOwner,
) -> Array[NativeOrderedEvent] {
  self.buffered.copy()
}

///|
pub fn SettingsRunOwner::held_platform_records(
  self : SettingsRunOwner,
) -> Array[@platform.Event] {
  self.held_platform.copy()
}

///|
pub fn SettingsRunOwner::held_tab(self : SettingsRunOwner) -> @platform.Event? {
  self.held_tab
}

///|
/// True means the host cutoff returned successfully, even if completing the
/// held TextSession subsequently failed. It is not an IME quiescence proof.
pub fn SettingsRunOwner::cutoff_completed(self : SettingsRunOwner) -> Bool {
  self.cutoff_done
}

///|
pub fn SettingsRunOwner::last_platform_sequence(self : SettingsRunOwner) -> Int64 {
  self.last_sequence
}

///|
/// Apply one original buffered commit to its still-owned field after a
/// terminal window event. This deliberately does not publish a scene, finish
/// the host session, consume the terminal record, or permit host shutdown.
/// Any non-text prefix, held TextSession or stale identity remains suspended.
pub fn SettingsRunOwner::reconcile_terminal_commit(
  self : SettingsRunOwner,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if self.buffered.is_empty() || !(self.buffered[0] is OrderedText(event) && event.kind() is @text_host.Commit(_)) {
    return Err(runner_error("terminal_recovery", "the next retained record is not a commit"))
  }
  self.reconcile_terminal_observation()
}

///|
/// Reconcile one ordered preedit, commit, or observed cancel without changing
/// the terminal event or publishing geometry.
pub fn SettingsRunOwner::reconcile_terminal_observation(
  self : SettingsRunOwner,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if !self.suspended || self.running || self.held_tab is Some(_) {
    return Err(runner_error("terminal_recovery", "terminal owner is unavailable"))
  }
  match self.inflight {
    Some(OrderedPlatform(event)) if event.window() == self.window &&
      (event.kind() is @platform.Destroyed || event.kind() is @platform.CloseRequested ||
       event.kind() is @platform.ExitRequested) => ()
    _ => return Err(runner_error("terminal_recovery", "terminal event is not retained"))
  }
  let owner = match self.terminal_owner {
    Some(value) => value
    None => return Err(runner_error("terminal_recovery", "original field owner is unavailable"))
  }
  if self.buffered.is_empty() {
    return Err(runner_error("terminal_recovery", "no retained record"))
  }
  let event = match self.buffered[0] {
    OrderedText(value) if value.kind() is @text_host.Commit(_) ||
      value.kind() is @text_host.Preedit(..) || value.kind() is @text_host.Cancel => value
    _ => return Err(runner_error("terminal_recovery", "the next retained record is unsupported"))
  }
  let action_required = match self.terminal_applied {
    Some((sequence, required)) if sequence == event.sequence() => required
    Some(_) => return Err(runner_error("terminal_recovery", "another applied record is unresolved"))
    None => {
      let changed = match self.mounted.apply_terminal_observation(owner, event) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      self.terminal_applied = Some((event.sequence(), changed))
      changed
    }
  }
  if action_required {
    let action = match self.mounted.next_terminal_text_action(owner) {
      Ok(Some(value)) => value
      Ok(None) => return Err(runner_error("terminal_recovery", "the model action is unavailable"))
      Err(error) => return Err(error)
    }
    self.settings = self.settings.update(@shared_settings.Ui(action))
  }
  if event.kind() is @text_host.Commit(_) {
    self.terminal_model_sequence = event.sequence()
  }
  self.terminal_applied = None
  ignore(self.buffered.remove(0))
  Ok(())
}

///|
/// Last terminal commit reflected into the shared model; no scene or host
/// geometry publication is implied.
pub fn SettingsRunOwner::terminal_model_sequence(self : SettingsRunOwner) -> Int64 {
  self.terminal_model_sequence
}

///|
/// One explicitly requested, bounded terminal-control operation.
pub(all) enum SettingsTerminalCommand {
  ApplyNext
  PollOnce
  TryTextCutoff
}

///|
/// A step is an observation, never permission to stop the host. No result
/// publishes a scene or caret geometry.
pub(all) enum SettingsTerminalProgress {
  FieldApplied(Int64)
  ModelApplied(Int64, Bool)
  RecordBuffered
  NoRecord
  TextCutoffCompleted
}

///|
/// Terminal steps never publish a scene, even after a model action is applied.
pub fn SettingsTerminalProgress::scene_published(
  self : SettingsTerminalProgress,
) -> Bool {
  ignore(self)
  false
}

///|
/// Perform at most one terminal operation while retaining this owner. A failed
/// step leaves the caller responsible for the owner and host. Polling consumes
/// at most one record exposed by the port; it is not a host quiescence proof.
pub fn SettingsRunOwner::terminal_step(
  self : SettingsRunOwner,
  command : SettingsTerminalCommand,
) -> Result[SettingsTerminalProgress, @diagnostics.FrameworkError] {
  if !self.suspended || self.running {
    return Err(runner_error("terminal_step", "owner is not suspended or is busy"))
  }
  match command {
    ApplyNext => {
      if self.buffered.is_empty() {
        return Err(runner_error("terminal_step", "no buffered record"))
      }
      let event = match self.buffered[0] {
        OrderedText(value) => value
        _ => return Err(runner_error("terminal_step", "non-text prefix requires a terminal policy"))
      }
      let before = self.settings.name()
      match self.reconcile_terminal_observation() {
        Err(error) => Err(error)
        Ok(_) =>
          if event.kind() is @text_host.Commit(_) {
            Ok(ModelApplied(event.sequence(), self.settings.name() != before))
          } else {
            Ok(FieldApplied(event.sequence()))
          }
      }
    }
    PollOnce => {
      if self.buffered.length() + self.held_platform.length() >= 64 {
        return Err(runner_error("terminal_step", "local buffer is full"))
      }
      match self.inflight {
        Some(OrderedPlatform(event)) if event.window() == self.window &&
          (event.kind() is @platform.Destroyed || event.kind() is @platform.CloseRequested ||
           event.kind() is @platform.ExitRequested) => ()
        _ => return Err(runner_error("terminal_step", "terminal event is not retained"))
      }
      let ordered = match self.ordered_text {
        Some(value) => value
        None => return Err(runner_error("terminal_step", "ordered host is unavailable"))
      }
      self.running = true
      let result = (ordered.next)(0)
      self.running = false
      match result {
        Err(error) => Err(error)
        Ok(None) => Ok(NoRecord)
        Ok(Some(record)) => {
          self.buffered.push(record)
          Ok(RecordBuffered)
        }
      }
    }
    TryTextCutoff =>
      match self.try_terminal_text_cutoff() {
        Err(error) => Err(error)
        Ok(_) => Ok(TextCutoffCompleted)
      }
  }
}

///|
/// Attempt only the text-session native cutoff, without consuming the retained
/// terminal event or stopping the host. Busy leaves the original owner intact.
/// Success is not an ACK for other native events or permission to stop.
pub fn SettingsRunOwner::try_terminal_text_cutoff(
  self : SettingsRunOwner,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if !self.suspended || self.running || self.cutoff_done ||
    self.held_tab is Some(_) || !self.buffered.is_empty() ||
    !self.held_platform.is_empty() || self.terminal_applied is Some(_) {
    return Err(runner_error("terminal_cutoff", "local records or actions remain unresolved"))
  }
  match self.inflight {
    Some(OrderedPlatform(event)) if event.window() == self.window &&
      (event.kind() is @platform.Destroyed || event.kind() is @platform.CloseRequested ||
       event.kind() is @platform.ExitRequested) => ()
    _ => return Err(runner_error("terminal_cutoff", "terminal event is not retained"))
  }
  let owner = match self.terminal_owner {
    Some(value) => value
    None => return Err(runner_error("terminal_cutoff", "original field owner is unavailable"))
  }
  if !self.mounted.terminal_field_can_cutoff(owner) {
    return Err(runner_error("terminal_cutoff", "field or pending action is unresolved"))
  }
  let session = match self.session {
    Some(value) => value
    None => return Err(runner_error("terminal_cutoff", "original session is unavailable"))
  }
  if !owner.matches_session(self.window, session.epoch, session.binding) ||
    self.host_epoch != Some(session.epoch) {
    return Err(runner_error("terminal_cutoff", "host session differs from field owner"))
  }
  let ordered = match self.ordered_text {
    Some(value) => value
    None => return Err(runner_error("terminal_cutoff", "ordered host is unavailable"))
  }
  // A port is caller-provided code: it may try to reenter this owner. Hold the
  // same mutation guard used by drive and reconciliation during the callback.
  self.running = true
  let result = (ordered.end_when_drained)(session.epoch)
  self.running = false
  match result {
    Err(error) => Err(error)
    Ok(_) => {
      self.cutoff_done = true
      Ok(())
    }
  }
}

///|
pub fn SettingsRunOwner::inflight_record(
  self : SettingsRunOwner,
) -> NativeOrderedEvent? {
  self.inflight
}

///|
pub fn SettingsRunOwner::window(self : SettingsRunOwner) -> @platform.WindowId {
  self.window
}

///|
pub fn SettingsRunOwner::text_owner(
  self : SettingsRunOwner,
) -> (UInt64, UInt64)? {
  self.session.map(value => (value.epoch, value.binding))
}

///|
/// Most recent epoch returned by the host, including an unresolved replacement.
pub fn SettingsRunOwner::host_epoch(self : SettingsRunOwner) -> UInt64? {
  self.host_epoch
}

///|
/// A copied receipt may prove that an inflight held record was applied even
/// if its action could not be enqueued. It does not prove model publication.
pub fn SettingsRunOwner::inflight_receipt(
  self : SettingsRunOwner,
) -> @ui.HeldTextReceipt? {
  match (self.inflight, self.session) {
    (Some(OrderedText(event)), Some(current)) =>
      self.mounted.held_text_receipt(current.epoch, event.sequence())
    _ => None
  }
}

///|
/// Only successful, fully resolved cleanup permits the host to stop. This is
/// not evidence of IME quiescence or an ACK for callbacks not yet delivered.
pub fn SettingsRunOwner::can_stop(self : SettingsRunOwner) -> Bool {
  // Neither route currently supplies an explicit host-queue terminal receipt.
  // Simply observing a destroyed window does not establish that receipt.
  ignore(self)
  false
}

///|
/// Construct a run before polling any input.
pub fn SettingsRunOwner::new(
  host : &@platform.Backend,
  platform : NativeSamplePlatform,
  measure : @components.TextMeasure,
  text_port~ : NativeTextInputPort? = None,
  accessibility_port~ : NativeTextAXPort? = None,
  dialog_port~ : NativeDialogAXPort? = None,
  next_platform_event~ : NativePlatformNext? = None,
  direct_text~ : NativeDirectText? = None,
  ordered_text~ : NativeOrderedTextPort? = None,
) -> Result[SettingsRunOwner, @diagnostics.FrameworkError] {
  let port = match text_port {
    Some(value) => value
    None =>
      return Err(
        runner_error(
          "run_native_settings_sample", "the selected host does not implement portable text input",
        ),
      )
  }
  let (width, height) = settings_window_size()
  let window = match
    host.create_window("Yami-kumo Shared Settings", width, height) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  Ok({
    host,
    platform,
    measure,
    port,
    accessibility_port,
    dialog_port,
    next_platform_event,
    direct_text,
    ordered_text,
    window,
    mounted: @ui.Mounted::new(window),
    settings: @shared_settings.Model::new(),
    session: None,
    host_epoch: None,
    terminal_owner: None,
    terminal_applied: None,
    terminal_model_sequence: 0L,
    ax_token: 0,
    dialog_token: 0,
    last_document: "",
    last_caret: @primitives.Rect::new(0.0, 0.0, 0.0, 0.0).unwrap(),
    saving_frames: 0,
    gate: PresentationGate::{ rendered: false, pending_stale: false, },
    pending_frame: None,
    dirty: true,
    focus_initialized: false,
    text_suspended: false,
    text_transport_failed: false,
    key_path_armed: false,
    ticks: 0,
    destroyed: false,
    last_sequence: 0L,
    held_tab: None,
    buffered: [],
    held_platform: [],
    inflight: None,
    cutoff_done: false,
    completed: false,
    running: false,
    suspended: false,
  })
}

///|
/// Drive the retained run. An error does not dispose this owner or its host.
pub fn SettingsRunOwner::drive(
  self : SettingsRunOwner,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if self.running ||
    self.completed ||
    self.suspended ||
    self.inflight is Some(_) ||
    self.cutoff_done {
    return Err(
      runner_error("ordered_text", "retained state requires explicit recovery"),
    )
  }
  self.running = true
  let result = self.drive_inner()
  self.running = false
  if result is Err(_) {
    // A failure can occur after an effect even with no inflight event.
    // Never silently restart at a different program point.
    self.suspended = true
  }
  result
}

///|
fn SettingsRunOwner::drive_inner(
  self : SettingsRunOwner,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let host = self.host
  let platform = self.platform
  let measure = self.measure
  let port = self.port
  let accessibility_port = self.accessibility_port
  let dialog_port = self.dialog_port
  let next_platform_event = self.next_platform_event
  let direct_text = self.direct_text
  let ordered_text = self.ordered_text
  let window = self.window
  let mounted = self.mounted
  let gate = self.gate
  let buffered = self.buffered
  let held_platform = self.held_platform
  // Windows keeps the lane alive longer than any driver wait so a failed
  // assertion is reported by the driver, not by a truncated sample loop.
  let tick_limit = if platform is Macos {
    20000
  } else if platform is Windows {
    12000
  } else {
    6000
  }
  while !self.destroyed && self.ticks < tick_limit {
    self.ticks += 1
    let mut drained = 0
    while ordered_text is None && drained < 32 && gate.input_ready() {
      let current = match self.session {
        Some(value) => value
        None => break
      }
      if !text_session_has_focus(mounted, current) {
        match end_text_session(port, current) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
        self.session = None
        self.last_document = ""
        self.dirty = true
        break
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
      let handled = match deliver_text_observation(mounted, current, event) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      if handled {
        match self.terminal_owner {
          Some(owner) =>
            match mounted.note_terminal_text_delivery(owner, event) {
              Err(error) => return Err(error)
              Ok(_) => ()
            }
          None => ()
        }
        // Keep the transport visible in the retained log: `commit` comes from
        // the portable text route, while `key` with `character` means WM_CHAR
        // reached the ordinary key path.
        emit_native_marker(
          "YAMI_NATIVE_UI_SETTINGS {\"phase\":\"\{text_event_phase(event.kind())}\",\{text_event_json(event.kind())},\"epoch\":\{current.epoch}}",
        )
        self.dirty = true
        while mounted.next_action() is Some(action) {
          let next = self.settings.update(@shared_settings.Ui(action))
          if next != self.settings {
            self.settings = next
            self.dirty = true
          }
        }
      }
      match event.kind() {
        @text_host.FocusLost | @text_host.Cancel => {
          match end_text_session(port, current) {
            Err(error) => return Err(error)
            Ok(_) => ()
          }
          self.session = None
          self.text_suspended = true
          self.last_document = ""
        }
        _ => ()
      }
    }
    let mut event : @platform.Event? = None
    let mut released_tab = false
    let mut reordered_frame = false
    match ordered_text {
      None =>
        event = match next_platform_event {
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
      Some(ordered) => {
        match (self.held_tab, self.session) {
          (Some(tab), Some(current)) => {
            let composing = match mounted.focused_text() {
              Some(value) => value.composing()
              None =>
                return Err(
                  runner_error("ordered_text", "held text owner is unavailable"),
                )
            }
            if !composing && buffered.is_empty() {
              match (ordered.end_when_drained)(current.epoch) {
                Ok(_) => {
                  self.cutoff_done = true
                  match mounted.finish_held_text(current.epoch) {
                    Err(error) => return Err(error)
                    Ok(_) => ()
                  }
                  self.held_tab = None
                  self.session = None
                  self.cutoff_done = false
                  self.last_document = ""
                  event = Some(tab)
                  released_tab = true
                }
                Err(error) if error.code() is @diagnostics.Busy => ()
                Err(error) => return Err(error)
              }
            }
          }
          (Some(_), None) =>
            return Err(runner_error("ordered_text", "held session disappeared"))
          _ => ()
        }
        if event is None {
          let ingress = if self.held_tab is None &&
            gate.input_ready() &&
            !held_platform.is_empty() {
            Some(OrderedPlatform(held_platform.remove(0)))
          } else if gate.input_ready() && !buffered.is_empty() {
            Some(buffered.remove(0))
          } else if buffered.length() + held_platform.length() >= 64 {
            return Err(
              runner_error("ordered_text", "deferred input buffer is full"),
            )
          } else {
            match (ordered.next)(16) {
              Err(error) => return Err(error)
              Ok(value) => value
            }
          }
          self.inflight = ingress
          match ingress {
            Some(OrderedText(observation)) =>
              if self.held_tab is None && !gate.input_ready() {
                if buffered.length() + held_platform.length() >= 64 {
                  return Err(
                    runner_error(
                      "ordered_text", "deferred input buffer is full",
                    ),
                  )
                }
                buffered.push(OrderedText(observation))
              } else {
                match self.session {
                  Some(current) if observation.epoch() == current.epoch => {
                    if self.held_tab is None {
                      match self.terminal_owner {
                        Some(owner) =>
                          match mounted.validate_terminal_text_delivery(owner, observation) {
                            Err(error) => return Err(error)
                            Ok(_) => ()
                          }
                        None => return Err(runner_error("ordered_text", "original owner unavailable"))
                      }
                    }
                    let handled = if self.held_tab is Some(_) {
                      mounted.held_text_input(current.epoch, observation)
                    } else {
                      deliver_text_observation(mounted, current, observation)
                    }
                    match handled {
                      Err(error) => return Err(error)
                      Ok(true) => {
                        if self.held_tab is None {
                          match self.terminal_owner {
                            Some(owner) =>
                              match mounted.note_terminal_text_delivery(owner, observation) {
                                Err(error) => return Err(error)
                                Ok(_) => ()
                              }
                            None => ()
                          }
                        }
                        emit_native_marker(
                          "YAMI_NATIVE_UI_SETTINGS {\"phase\":\"\{text_event_phase(observation.kind())}\",\{text_event_json(observation.kind())},\"epoch\":\{current.epoch}}",
                        )
                        self.dirty = true
                        while mounted.next_action() is Some(action) {
                          self.settings = self.settings.update(
                            @shared_settings.Ui(action),
                          )
                        }
                      }
                      Ok(false) =>
                        return Err(
                          runner_error("ordered_text", "accepted observation was not applied to its owner"),
                        )
                    }
                  }
                  _ =>
                    return Err(
                      runner_error("ordered_text", "accepted observation has no matching owner"),
                    )
                }
              }
            Some(OrderedPlatform(value)) =>
              if self.held_tab is Some(_) {
                match value.kind() {
                  @platform.Resized(..)
                  | @platform.ScaleChanged
                  | @platform.Destroyed
                  | @platform.CloseRequested
                  | @platform.ExitRequested =>
                    return Err(
                      runner_error(
                        "ordered_text", "structural event during deferred input requires recovery",
                      ),
                    )
                  _ => ()
                }
                if held_platform.length() + buffered.length() >= 64 {
                  return Err(
                    runner_error(
                      "ordered_text", "deferred input buffer is full",
                    ),
                  )
                }
                held_platform.push(value)
              } else if !gate.input_ready() &&
                !(value.kind() is @platform.FrameCompleted) {
                match value.kind() {
                  @platform.Resized(..)
                  | @platform.ScaleChanged
                  | @platform.Destroyed
                  | @platform.CloseRequested
                  | @platform.ExitRequested =>
                    if buffered.is_empty() {
                      event = Some(value)
                    } else {
                      return Err(
                        runner_error(
                          "ordered_text", "structural event behind deferred input requires recovery",
                        ),
                      )
                    }
                  _ => {
                    if held_platform.length() + buffered.length() >= 64 {
                      return Err(
                        runner_error(
                          "ordered_text", "deferred input buffer is full",
                        ),
                      )
                    }
                    buffered.push(OrderedPlatform(value))
                  }
                }
              } else {
                event = Some(value)
                reordered_frame = !gate.input_ready() &&
                  !buffered.is_empty() &&
                  value.kind() is @platform.FrameCompleted
              }
            None => ()
          }
        }
      }
    }
    if event is None {
      self.inflight = None
    }
    match event {
      None => ()
      Some(value) if value.window() == window => {
        if !released_tab &&
          !reordered_frame &&
          value.sequence() <= self.last_sequence {
          return Err(
            runner_error(
              "run_native_settings_sample", "host event sequence did not advance",
            ),
          )
        }
        if !released_tab && !reordered_frame {
          self.last_sequence = value.sequence()
        }
        match value.kind() {
          @platform.Destroyed
          | @platform.CloseRequested
          | @platform.ExitRequested => {
            self.destroyed = true
            self.dirty = false
          }
          @platform.Resized(..) | @platform.ScaleChanged => {
            // Invalidation clears the commit-ready state; without a new frame
            // the next text observation would be rejected before it reaches the
            // focused field.
            gate.invalidate_layout(self.pending_frame is Some(_))
            mounted.invalidate_layout()
            self.dirty = true
          }
          @platform.FrameCompleted =>
            match self.pending_frame {
              Some(marker) => {
                self.pending_frame = None
                if gate.completed_frame_is_current() {
                  emit_native_marker(marker)
                }
              }
              None => ()
            }
          @platform.FocusChanged(focused) => {
            if !focused && ordered_text is Some(_) && self.session is Some(_) {
              // An observed blur does not resolve an active preview or the
              // accepted text prefix. Retain the event and original owner.
              return Err(
                runner_error("ordered_text", "focus loss requires ordered owner recovery"),
              )
            }
            ignore(mounted.handle_event(value))
            self.text_suspended = !focused
            if !focused {
              self.focus_initialized = false
              match self.session {
                Some(current) => {
                  match end_text_session(port, current) {
                    Err(error) => return Err(error)
                    Ok(_) => ()
                  }
                  self.session = None
                  self.last_document = ""
                }
                None => ()
              }
              if self.key_path_armed {
                self.key_path_armed = false
                match direct_text {
                  Some(arm) => ignore(arm(window, false))
                  None => ()
                }
              }
            }
            self.dirty = true
          }
          @platform.Input(input) => {
            let hold = match (ordered_text, self.session, input) {
              (
                Some(_),
                Some(current),
                @primitives.KeyPressed(
                  key=@primitives.Tab,
                  repeat=false,
                  modifiers~
                ),
              ) if !modifiers.control() && !modifiers.meta() && !modifiers.alt() =>
                match mounted.focused_text() {
                  Some(state) if state.composing() =>
                    return Err(
                      runner_error(
                        "ordered_text", "Tab during active preedit requires observed resolution",
                      ),
                    )
                  Some(_) =>
                    match mounted.begin_held_text(current.epoch) {
                      Err(error) => return Err(error)
                      Ok(value) => value
                    }
                  None => false
                }
              _ => false
            }
            if hold {
              self.held_tab = Some(value)
              self.inflight = None
              continue
            }
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
            self.dirty = true
          }
          @platform.Composition(_) => {
            ignore(mounted.handle_event(value))
            self.dirty = true
          }
          _ => ()
        }
      }
      Some(_) => ()
    }
    self.inflight = None
    if self.dirty &&
      self.pending_frame is None &&
      !self.destroyed &&
      self.held_tab is None {
      // Drain queued actions before rendering: a TextChanged enqueued by the
      // previous dispatch must update the model first, or the committed view
      // rebuilds the field with a stale value and resets its caret.
      while mounted.next_action() is Some(action) {
        let next = self.settings.update(@shared_settings.Ui(action))
        if next != self.settings {
          self.settings = next
        }
      }
      let (width, height, scale) = match host.window_metrics(window) {
        Err(error) => return Err(error)
        Ok(metrics) => metrics
      }
      let frame = match
        mounted.commit(self.settings.view(), width, height, scale, measure) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      self.dirty = false
      while mounted.next_action() is Some(action) {
        let next = self.settings.update(@shared_settings.Ui(action))
        if next != self.settings {
          self.settings = next
          self.dirty = true
        }
      }
      let focused = frame.focused(@shared_settings.settings_name())
      if !self.focus_initialized {
        if focused {
          self.focus_initialized = true
        } else if mounted.focus(@shared_settings.settings_name()) {
          self.dirty = true
        }
      }
      // A rejected focus request (for example while the host reports the
      // window unfocused) is retried on the next commit rather than giving
      // the lane a permanently unfocused field.
      match self.session {
        None =>
          if focused &&
            !self.text_suspended &&
            !self.text_transport_failed &&
            !self.key_path_armed {
            match mounted.focused_text() {
              Some(state) =>
                match (port.begin)(window, state.binding_id()) {
                  Err(error) => {
                    emit_native_marker(
                      "YAMI_NATIVE_UI_SETTINGS {\"phase\":\"text\",\"status\":\"unavailable\",\"operation\":\"begin_text_input\",\"error\":\"\{json_escape(format_framework_error(error))}\"}",
                    )
                    let route = settings_key_path_fallback(
                      direct_text,
                      window,
                      {
                        key_path_armed: self.key_path_armed,
                        transport_failed: self.text_transport_failed,
                      },
                    )
                    self.key_path_armed = route.key_path_armed
                    self.text_transport_failed = route.transport_failed
                  }
                  Ok(epoch) => {
                    if ordered_text is Some(_) {
                      // Begin may already admit records. Capture its exact
                      // owner before any fallible update or host cleanup.
                      self.session = Some({ epoch, binding: state.binding_id(), })
                      self.host_epoch = Some(epoch)
                      self.terminal_owner = Some(match mounted.capture_terminal_text_owner(epoch) {
                        Err(error) => return Err(error)
                        Ok(value) => value
                      })
                    }
                    match
                      (port.update)(
                        epoch,
                        @text_host.TextInputState::new(
                          state.document(),
                          settings_caret(state.caret()),
                        ),
                      ) {
                      Err(error) => {
                        if ordered_text is Some(_) {
                          return Err(error)
                        }
                        ignore((port.end)(epoch))
                        emit_native_marker(
                          "YAMI_NATIVE_UI_SETTINGS {\"phase\":\"text\",\"status\":\"unavailable\",\"operation\":\"update_text_input\",\"error\":\"\{json_escape(format_framework_error(error))}\"}",
                        )
                        let route = settings_key_path_fallback(
                          direct_text,
                          window,
                          {
                            key_path_armed: self.key_path_armed,
                            transport_failed: self.text_transport_failed,
                          },
                        )
                        self.key_path_armed = route.key_path_armed
                        self.text_transport_failed = route.transport_failed
                      }
                      Ok(updated_epoch) => {
                        if ordered_text is Some(_) {
                          self.host_epoch = Some(updated_epoch)
                          if updated_epoch != epoch {
                            return Err(runner_error("ordered_text", "host replaced an unresolved owner epoch"))
                          }
                        }
                        self.session = Some({
                          epoch: updated_epoch,
                          binding: state.binding_id(),
                        })
                        self.last_document = state.document().text()
                        self.last_caret = settings_caret(state.caret())
                        let transport = match platform {
                          Windows => "imm32"
                          Linux => "text-input-v1"
                          Macos => "appkit"
                        }
                        emit_native_marker(
                          "YAMI_NATIVE_UI_SETTINGS {\"phase\":\"text\",\"status\":\"started\",\"transport\":\"\{transport}\",\"epoch\":\{updated_epoch}}",
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
            if ordered_text is Some(_) {
              return Err(runner_error("ordered_text", "field focus changed before ordered cutoff"))
            }
            match end_text_session(port, current) {
              Err(error) => return Err(error)
              Ok(_) => ()
            }
            self.session = None
            self.last_document = ""
          } else {
            match mounted.focused_text() {
              Some(state) =>
                if state.document().text() != self.last_document ||
                  settings_caret(state.caret()) != self.last_caret {
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
                  if ordered_text is Some(_) {
                    self.host_epoch = Some(epoch)
                    if epoch != current.epoch {
                      return Err(runner_error("ordered_text", "host replaced an unresolved owner epoch"))
                    }
                  }
                  self.session = Some({ epoch, binding: current.binding, })
                  self.last_document = state.document().text()
                  self.last_caret = settings_caret(state.caret())
                }
              None => ()
            }
          }
      }
      match accessibility_port {
        Some(ax) =>
          match
            (
              frame.bounds(@shared_settings.settings_name()),
              mounted.focused_text(),
            ) {
            (Some(bounds), Some(state)) => {
              let snapshot : NativeTextAXSnapshot = {
                value: state.document().text(),
                bounds,
                focused: true,
                editable: true,
              }
              self.ax_token = match
                (ax.publish)(window, self.ax_token, snapshot) {
                Err(error) => return Err(error)
                Ok(value) => value
              }
            }
            _ =>
              if self.ax_token != 0 {
                match (ax.revoke)(window, self.ax_token) {
                  Err(error) => return Err(error)
                  Ok(_) => ()
                }
                self.ax_token = 0
              }
          }
        None => ()
      }
      match dialog_port {
        Some(port) =>
          if self.settings.dialog_open() {
            match frame.bounds(@shared_settings.settings_dialog()) {
              Some(bounds) =>
                self.dialog_token = match
                  (port.publish)(
                    window,
                    self.dialog_token,
                    "Save changes?",
                    bounds,
                  ) {
                  Err(error) => return Err(error)
                  Ok(value) => value
                }
              None =>
                if self.dialog_token != 0 {
                  match (port.revoke)(window, self.dialog_token) {
                    Err(error) => return Err(error)
                    Ok(_) => ()
                  }
                  self.dialog_token = 0
                }
            }
          } else if self.dialog_token != 0 {
            match (port.revoke)(window, self.dialog_token) {
              Err(error) => return Err(error)
              Ok(_) => ()
            }
            self.dialog_token = 0
          }
        None => ()
      }
      let error_text = match self.settings.error() {
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
      let marker = "YAMI_NATIVE_UI_SETTINGS {\"phase\":\"frame\",\"name\":\"\{json_escape(self.settings.name())}\",\"status\":\"\{settings_status(self.settings)}\",\"dialog\":\{self.settings.dialog_open()},\"focus\":\"\{focus}\",\"error\":\"\{json_escape(error_text)}\"}"
      match host.present(window, frame.snapshot()) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      gate.mark_presented()
      if platform is Macos {
        emit_native_marker(marker)
      } else {
        self.pending_frame = Some(marker)
      }
      // The simulated save completes after three committed frames so the
      // loading state is observable without a host timer.
      if self.settings.saving() {
        self.saving_frames += 1
        self.dirty = true
        if self.saving_frames >= 3 {
          self.saving_frames = 0
          self.settings = self.settings.update(@shared_settings.SaveFinished)
        }
      } else {
        self.saving_frames = 0
      }
    }
  }
  // An ordered lease is not resolved by the sample timeout. In particular,
  // cancellation/end here would silently abandon a live preview or an
  // admitted prefix while cutoff remains Busy. The outer entrypoint still
  // stops its host on error: this guard prevents false success but does not
  // provide event retention or safe production shutdown.
  if ordered_text is Some(_) &&
    (
      !self.destroyed ||
      self.held_tab is Some(_) ||
      !buffered.is_empty() ||
      !held_platform.is_empty() ||
      self.session is Some(_)
    ) {
    return Err(
      runner_error(
        "ordered_text", "ordered shutdown requires a resolved owner and drained ingress",
      ),
    )
  }
  if ordered_text is Some(_) {
    // No API currently proves that terminal ingress was fully drained. Keep
    // the original owner live rather than dispose it on an unproven success.
    return Err(
      runner_error("ordered_text", "terminal queue receipt is unavailable"),
    )
  }
  match self.session {
    Some(current) =>
      match end_text_session(port, current) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    None => ()
  }
  if self.key_path_armed {
    match direct_text {
      Some(arm) => ignore(arm(window, false))
      None => ()
    }
  }
  if self.ax_token != 0 {
    match accessibility_port {
      Some(ax) =>
        match (ax.revoke)(window, self.ax_token) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      None => ()
    }
  }
  if self.dialog_token != 0 {
    match dialog_port {
      Some(port) =>
        match (port.revoke)(window, self.dialog_token) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      None => ()
    }
  }
  mounted.dispose()
  let reason = if self.destroyed { "window-closed" } else { "tick-limit" }
  emit_native_marker(
    "YAMI_NATIVE_UI_SETTINGS {\"phase\":\"exit\",\"reason\":\"\{reason}\",\"ticks\":\{self.ticks}}",
  )
  if self.destroyed || self.ticks >= tick_limit {
    self.completed = true
    Ok(())
  } else {
    Err(
      runner_error(
        "run_native_settings_sample", "settings sample loop ended early",
      ),
    )
  }
}
