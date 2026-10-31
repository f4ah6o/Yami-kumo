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
  peek : ((Int32) -> Result[NativeRetainedReceipt?, @diagnostics.FrameworkError])?
}

///|
pub fn NativeOrderedTextPort::new(
  next : (Int32) -> Result[NativeOrderedEvent?, @diagnostics.FrameworkError],
  end_when_drained : (UInt64) -> Result[Unit, @diagnostics.FrameworkError],
) -> NativeOrderedTextPort {
  { next, end_when_drained, peek: None }
}

///|
/// The callback captures the original host receipt, including its lifetime.
/// An unsupported observation has no portable event and remains unacknowledged.
pub struct NativeRetainedReceipt {
  event : NativeOrderedEvent?
  entered : (Int32, Int64, Int32)?
  direct : (Int32, Int64)?
  edit_key_epoch : Int32?
  window : @platform.WindowId
  sequence : Int32
  root : UInt64
  epoch : UInt64
  ack : () -> Result[Unit, @diagnostics.FrameworkError]
}

///|
/// Highest positively observed text stage for an ACKed native receipt. These
/// stages do not certify geometry publication, terminal resolution or stop.
pub(all) enum NativeReceiptStage {
  ReceiptAcknowledgedOnly
  ReceiptOwnerEntered
  ReceiptPlatformHandled
  ReceiptPointerMovedHandled
  ReceiptUnsupportedAcknowledged
  ReceiptSessionApplied
  ReceiptNoModelAction
  ReceiptActionRequired
  ReceiptModelApplied
  ReceiptTerminalResolved
}

///|
struct NativeReceiptEntry {
  receipt : NativeRetainedReceipt
  mut stage : NativeReceiptStage
}

///|
/// One immutable scene/owner snapshot and the native prefix already applied
/// before its present call. This is observational: it never retires a record.
pub struct SettingsFramePublication {
  priv frame : @ui.Frame
  priv window : @platform.WindowId
  priv binding : UInt64
  priv epoch : UInt64
  priv entered : (Int32, Int64, Int32)
  priv field_progress : (UInt64, Int32, Int64)
  priv caret : @primitives.Rect
  priv watermark : Int32
  priv base_watermark : Int32
  priv prefix : Array[(NativeRetainedReceipt, NativeReceiptStage)]
  priv mut presented : Bool
  priv mut frame_completed : Bool
}

///|
/// Compact, monotonic evidence that a contiguous prefix was reflected by its
/// original owner and included in a completed observed frame. It is scoped to
/// this exact window/text lease and cannot authorize host shutdown.
priv struct RetiredReceiptPrefix {
  window : @platform.WindowId
  binding : UInt64
  epoch : UInt64
  entered : (Int32, Int64, Int32)
  field_generation : UInt64
  watermark : Int32
  scene_revision : UInt64
}

///|
pub fn SettingsFramePublication::watermark(self : SettingsFramePublication) -> Int32 { self.watermark }

///|
pub fn SettingsFramePublication::scene_revision(self : SettingsFramePublication) -> UInt64 { self.frame.revision() }

///|
pub fn SettingsFramePublication::presented(self : SettingsFramePublication) -> Bool { self.presented }

///|
pub fn SettingsFramePublication::frame_completed(self : SettingsFramePublication) -> Bool { self.frame_completed }

///|
pub fn SettingsFramePublication::native_entered_identity(
  self : SettingsFramePublication,
) -> (Int32, Int64, Int32) { self.entered }

///|
pub fn SettingsFramePublication::owner_identity(
  self : SettingsFramePublication,
) -> (@platform.WindowId, UInt64, UInt64, UInt64, Int32, Int64) {
  let (generation, revision, sequence) = self.field_progress
  (self.window, self.binding, self.epoch, generation, revision, sequence)
}

///|
fn receipt_stage_rank(stage : NativeReceiptStage) -> Int {
  match stage {
    ReceiptAcknowledgedOnly => 0
    ReceiptOwnerEntered | ReceiptPlatformHandled | ReceiptPointerMovedHandled | ReceiptUnsupportedAcknowledged => 1
    ReceiptSessionApplied => 1
    ReceiptNoModelAction => 2
    ReceiptActionRequired => 2
    ReceiptModelApplied => 3
    ReceiptTerminalResolved => 4
  }
}

///|
fn same_text_observation_kind(
  left : @text_host.TextInputEventKind, right : @text_host.TextInputEventKind,
) -> Bool {
  match (left, right) {
    (@text_host.Commit(text=a), @text_host.Commit(text=b)) => a == b
    (@text_host.Preedit(text=a, cursor=x), @text_host.Preedit(text=b, cursor=y)) => a == b && x == y
    (@text_host.Cancel, @text_host.Cancel) | (@text_host.FocusLost, @text_host.FocusLost) => true
    _ => false
  }
}

///|
fn same_publication_stage(a : NativeReceiptStage, b : NativeReceiptStage) -> Bool {
  match (a, b) {
    (ReceiptOwnerEntered, ReceiptOwnerEntered)
    | (ReceiptPlatformHandled, ReceiptPlatformHandled)
    | (ReceiptPointerMovedHandled, ReceiptPointerMovedHandled)
    | (ReceiptUnsupportedAcknowledged, ReceiptUnsupportedAcknowledged)
    | (ReceiptNoModelAction, ReceiptNoModelAction)
    | (ReceiptModelApplied, ReceiptModelApplied) => true
    _ => false
  }
}

///|
fn same_publication_receipt(a : NativeRetainedReceipt, b : NativeRetainedReceipt) -> Bool {
  if a.window != b.window || a.sequence != b.sequence || a.root != b.root ||
    a.epoch != b.epoch || a.entered != b.entered || a.direct != b.direct || a.edit_key_epoch != b.edit_key_epoch {
    return false
  }
  match (a.event, b.event) {
    (None, None) => true
    (Some(OrderedPlatform(x)), Some(OrderedPlatform(y))) =>
      x.window() == y.window() && x.sequence() == y.sequence() &&
      x.scale() == y.scale() && same_handled_platform_kind(x.kind(), y.kind())
    (Some(OrderedText(x)), Some(OrderedText(y))) =>
      x.window() == y.window() && x.sequence() == y.sequence() && x.epoch() == y.epoch() &&
      same_text_observation_kind(x.kind(), y.kind())
    _ => false
  }
}

///|
/// Only the explicitly handled non-input events and an independently checked
/// pointer move qualify; this does not certify scene or host geometry.
fn same_handled_platform_kind(left : @platform.EventKind, right : @platform.EventKind) -> Bool {
  match (left, right) {
    (@platform.Resized(width=a, height=b), @platform.Resized(width=x, height=y)) => a == x && b == y
    (@platform.ScaleChanged, @platform.ScaleChanged) | (@platform.FrameCompleted, @platform.FrameCompleted) => true
    (@platform.FocusChanged(true), @platform.FocusChanged(true)) => true
    (@platform.Input(@primitives.PointerMoved(position=a)), @platform.Input(@primitives.PointerMoved(position=b))) =>
      a.x() == b.x() && a.y() == b.y()
    _ => false
  }
}

///|
fn same_direct_event(left : @platform.Event, right : @platform.Event) -> Bool {
  if left.window() != right.window() || left.sequence() != right.sequence() || left.scale() != right.scale() {
    return false
  }
  match (left.kind(), right.kind()) {
    (@platform.Input(@primitives.TextInput(text=a)), @platform.Input(@primitives.TextInput(text=b))) => a == b
    (@platform.Input(@primitives.KeyPressed(key=a, modifiers=b, repeat=c)),
     @platform.Input(@primitives.KeyPressed(key=x, modifiers=y, repeat=z))) => a == x && b == y && c == z
    _ => false
  }
}

///|
fn same_prefix_stage(a : NativeReceiptStage, b : NativeReceiptStage) -> Bool {
  match (a, b) {
    (ReceiptOwnerEntered, ReceiptOwnerEntered)
    | (ReceiptPlatformHandled, ReceiptPlatformHandled)
    | (ReceiptPointerMovedHandled, ReceiptPointerMovedHandled)
    | (ReceiptUnsupportedAcknowledged, ReceiptUnsupportedAcknowledged)
    | (ReceiptNoModelAction, ReceiptNoModelAction)
    | (ReceiptModelApplied, ReceiptModelApplied) => true
    _ => false
  }
}

///|
fn same_prefix_receipt(a : NativeRetainedReceipt, b : NativeRetainedReceipt) -> Bool {
  if a.window != b.window || a.sequence != b.sequence || a.root != b.root ||
    a.epoch != b.epoch || a.entered != b.entered || a.direct != b.direct || a.edit_key_epoch != b.edit_key_epoch {
    return false
  }
  match (a.event, b.event) {
    (None, None) => true
    (Some(OrderedPlatform(x)), Some(OrderedPlatform(y))) =>
      x.window() == y.window() && x.sequence() == y.sequence() &&
      x.scale() == y.scale() && same_handled_platform_kind(x.kind(), y.kind())
    (Some(OrderedText(x)), Some(OrderedText(y))) =>
      x.window() == y.window() && x.sequence() == y.sequence() && x.epoch() == y.epoch() &&
      same_text_observation_kind(x.kind(), y.kind())
    _ => false
  }
}

///|
pub fn NativeRetainedReceipt::new(
  event : NativeOrderedEvent?, window : @platform.WindowId, sequence : Int32,
  root : UInt64, epoch : UInt64,
  ack : () -> Result[Unit, @diagnostics.FrameworkError],
) -> NativeRetainedReceipt {
  { event, entered: None, direct: None, edit_key_epoch: None, window, sequence, root, epoch, ack }
}

///|
/// An Entered receipt has already been decoded by the native route; its
/// native epoch is compared with that route's bound epoch by the adapter.
pub fn NativeRetainedReceipt::entered(
  window : @platform.WindowId, sequence : Int32, root : UInt64, epoch : UInt64,
  native_epoch : Int32, seat : Int64, proxy : Int32,
  ack : () -> Result[Unit, @diagnostics.FrameworkError],
) -> NativeRetainedReceipt {
  { event: None, entered: Some((native_epoch, seat, proxy)), direct: None, edit_key_epoch: None, window, sequence, root, epoch, ack }
}

///|
/// Trusted native adapter only: retain its exact original direct head and
/// validate its host-specific provenance before constructing this receipt.
pub fn NativeRetainedReceipt::direct(
  event : @platform.Event, sequence : Int32, root : UInt64, epoch : UInt64,
  native_epoch : Int32, ordinal : Int64,
  ack : () -> Result[Unit, @diagnostics.FrameworkError],
) -> NativeRetainedReceipt {
  { event: Some(OrderedPlatform(event)), entered: None, edit_key_epoch: None,
    direct: Some((native_epoch, ordinal)), window: event.window(), sequence, root, epoch, ack }
}

///|
/// Trusted native adapter constructs this only for an exact owned key head.
pub fn NativeRetainedReceipt::edit_key(
  event : @platform.Event, sequence : Int32, root : UInt64, epoch : UInt64,
  native_epoch : Int32, ack : () -> Result[Unit, @diagnostics.FrameworkError],
) -> NativeRetainedReceipt {
  { event: Some(OrderedPlatform(event)), entered: None, direct: None,
    edit_key_epoch: Some(native_epoch), window: event.window(), sequence, root, epoch, ack }
}

///|
pub fn NativeOrderedTextPort::with_retained_receipts(
  peek : (Int32) -> Result[NativeRetainedReceipt?, @diagnostics.FrameworkError],
  end_when_drained : (UInt64) -> Result[Unit, @diagnostics.FrameworkError],
) -> NativeOrderedTextPort {
  { next: fn(_) { Ok(None) }, end_when_drained, peek: Some(peek) }
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
fn settings_transport_label(
  platform : NativeSamplePlatform, port : NativeTextInputPort,
) -> String {
  match platform {
    Windows => "imm32"
    Macos => "appkit"
    Linux => match port.linux_transport {
      Some(probe) => match probe() {
        WaylandIme => "text-input-v1"
        DirectKeyboard => "direct-keyboard"
        UnknownLinuxTransport => "unknown"
      }
      None => "unknown"
    }
  }
}

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
/// The original stop reason stays available to the caller during recovery.
pub fn SettingsEntryController::error(
  self : SettingsEntryController,
) -> @diagnostics.FrameworkError? {
  match self.outcome {
    Suspended(_, error) | NotStarted(error) => Some(error)
    Completed => None
  }
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
/// Apply only the named buffered text observation. A repeated request for a
/// completed sequence cannot advance the next record after a lost response.
pub fn SettingsEntryController::apply_sequence(
  self : SettingsEntryController,
  sequence : Int64,
) -> Result[SettingsTerminalProgress, @diagnostics.FrameworkError] {
  let owner = match self.outcome {
    Suspended(value, _) => value
    _ => return Err(runner_error("settings_entry", "no suspended owner"))
  }
  if sequence <= 0L || owner.buffered.is_empty() ||
    !(owner.buffered[0] is OrderedText(event) && event.sequence() == sequence) {
    return Err(runner_error("settings_entry", "text sequence is no longer pending"))
  }
  owner.terminal_step(ApplyNext)
}

///|
/// Retry only the currently retained native receipt, never the next receipt.
pub fn SettingsEntryController::retry_receipt_sequence(
  self : SettingsEntryController, sequence : Int64,
) -> Result[SettingsTerminalProgress, @diagnostics.FrameworkError] {
  let owner = match self.outcome {
    Suspended(value, _) => value
    _ => return Err(runner_error("settings_entry", "no suspended owner"))
  }
  match owner.pending_receipt_identity() {
    Some((_, current, _, _)) if sequence > 0L && sequence == current.to_int64() =>
      owner.terminal_step(RetryReceiptAck)
    _ => Err(runner_error("settings_entry", "receipt sequence is no longer pending"))
  }
}

///|
/// Resume only the acknowledged pre-dispatch record named by native sequence.
pub fn SettingsEntryController::resume_receipt_sequence(
  self : SettingsEntryController, sequence : Int64,
) -> Result[SettingsTerminalProgress, @diagnostics.FrameworkError] {
  let owner = match self.outcome {
    Suspended(value, _) => value
    _ => return Err(runner_error("settings_entry", "no suspended owner"))
  }
  match owner.resumable_receipt_identity() {
    Some((_, current, _, _)) if sequence > 0L && sequence == current.to_int64() =>
      match owner.resume_after_receipt_ack() {
        Ok(_) => Ok(ReceiptDispatched)
        Err(error) => Err(error)
      }
    _ => Err(runner_error("settings_entry", "receipt sequence is no longer resumable"))
  }
}

///|
pub fn SettingsEntryController::advance_generation(
  self : SettingsEntryController,
) -> Int64? {
  match self.outcome {
    Suspended(owner, _) => owner.advance_generation()
    _ => None
  }
}

///|
/// Exactly one bounded continuation per generation, even when no record arrives.
pub fn SettingsEntryController::advance_once(
  self : SettingsEntryController, generation : Int64,
) -> Result[SettingsTerminalProgress, @diagnostics.FrameworkError] {
  match self.outcome {
    Suspended(owner, _) => owner.advance_once(generation)
    _ => Err(runner_error("settings_entry", "no suspended owner"))
  }
}

///|
pub fn SettingsEntryController::owned_delivery_sequence(
  self : SettingsEntryController,
) -> Int64? {
  match self.outcome {
    Suspended(owner, _) => owner.owned_delivery_native_sequence()
    _ => None
  }
}

///|
/// Observe the latest completed local frame's candidate watermark. This is not
/// a guarantee that the candidate satisfies retirement or a host cutoff.
pub fn SettingsEntryController::completed_publication_watermark(
  self : SettingsEntryController,
) -> Int64? {
  match self.outcome {
    Suspended(owner, _) => {
      let count = owner.completed_publication_count()
      if count == 0 { None }
      else { owner.completed_publication(count - 1).map(value => value.watermark().to_int64()) }
    }
    _ => None
  }
}

///|
/// Compact exactly the named latest completed prefix, at most once. A lost
/// reply cannot retire a different later publication on retry.
pub fn SettingsEntryController::retire_publication_watermark(
  self : SettingsEntryController, sequence : Int64,
) -> Result[Int32, @diagnostics.FrameworkError] {
  match self.outcome {
    Suspended(owner, _) if sequence > 0L && self.completed_publication_watermark() == Some(sequence) =>
      owner.retire_completed_publication(owner.completed_publication_count() - 1)
    _ => Err(runner_error("settings_entry", "publication watermark is stale or unavailable"))
  }
}

///|
pub fn SettingsEntryController::reconcile_owned_sequence(
  self : SettingsEntryController, sequence : Int64,
) -> Result[Unit, @diagnostics.FrameworkError] {
  match self.outcome {
    Suspended(owner, _) if sequence > 0L && owner.owned_delivery_native_sequence() == Some(sequence) =>
      owner.reconcile_owned_delivery()
    _ => Err(runner_error("settings_entry", "owned delivery sequence is unavailable"))
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
  // An error from a host update does not prove the old native state survived.
  priv mut host_epoch_verified : Bool
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
  priv mut pending_publication : SettingsFramePublication?
  priv completed_publications : Array[SettingsFramePublication]
  priv mut dirty : Bool
  // Staging is local only; no host update or scene present has occurred.
  priv mut pending_dirty_stage : SettingsDirtyStage?
  // One bounded, original-owner arrival. It stays here across any ACK result;
  // no application, scene or cutoff is implied by the host handoff.
  priv mut geometry_arrival : SettingsGeometryArrival?
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
  priv mut owned_delivery : @ui.OwnedTextDelivery?
  priv mut pending_direct : @ui.OwnedDirectDelivery?
  priv mut pending_direct_model : @shared_settings.Model?
  priv mut pending_direct_fence : SettingsModelFence?
  // Kept together with the bounded native ledger until a direct-specific
  // publication/retirement contract exists.
  priv direct_receipts : Array[(NativeRetainedReceipt, @ui.OwnedDirectDelivery)]
  // Immutable model observed when the owned delivery was reserved. This is
  // held with the receipt through all retries; it is not a scene proof.
  priv mut owned_model_before : @shared_settings.Model?
  priv mut owned_model_fence : SettingsModelFence?
  priv mut model_fence : SettingsModelFence
  // The receipt is installed before ACK, alongside its locally owned event.
  priv mut pending_host_receipt : NativeRetainedReceipt?
  // Retain native identities even after host ACK until an explicit per-stage
  // retirement policy exists. This ledger is bounded and fails closed.
  priv acknowledged_receipts : Array[NativeReceiptEntry]
  priv mut retired_prefix : RetiredReceiptPrefix?
  // Set only when retained polling is refused before peeking a full ledger.
  priv mut ledger_backpressure : Bool
  priv mut entered_target : (Int32, Int64, Int32)?
  // Number of locally buffered observations admitted before a retained
  // Destroyed record. Later observations remain owned but are not delivered
  // to a destroyed target without separate host admission proof.
  priv mut retained_destroyed_prefix : Int?
  // Exact ACKed native Destroyed receipt after explicit terminal validation.
  priv mut terminal_destroyed_sequence : Int32?
  // The exact receipt paired with an observation not yet dispatched.
  priv mut receipt_pre_dispatch : NativeRetainedReceipt?
  priv mut resume_pre_dispatch : Bool
  priv mut bounded_resume : Bool
  priv mut live_step_ready : Bool
  priv mut live_step_generation : Int64
  priv mut cutoff_done : Bool
  priv mut completed : Bool
  priv mut running : Bool
  priv mut suspended : Bool
}

///|
priv struct SettingsDirtyStage {
  prepared : @ui.Prepared
  model : @shared_settings.Model
  fence : SettingsModelFence
  window : @platform.WindowId
  epoch : UInt64
  binding : UInt64
  metrics : (Double, Double, Double)
  // A host attempt may have changed native state. Even if the adapter reports
  // success, only a future publication transaction may release this stage.
  mut host_attempted : Bool
  mut callback_returned_success : Bool
}

///|
priv enum SettingsGeometryArrivalState {
  GeometryArrivalReserved
  GeometryArrivalAttempted
  GeometryArrivalCallbackSucceeded
}

///|
priv struct SettingsGeometryArrival {
  receipt : NativeRetainedReceipt
  native_target : (Int32, Int64, Int32)
  owner_progress : (UInt64, Int32, Int64)
  mut state : SettingsGeometryArrivalState
}

///|
/// An owner-thread fence invalidated by every Settings model transition,
/// including a transition whose resulting value happens to equal an old one.
priv struct SettingsModelFence {
  mut live : Bool
}

///|
fn SettingsRunOwner::replace_settings(
  self : SettingsRunOwner, next : @shared_settings.Model,
) -> Unit {
  self.model_fence.live = false
  self.settings = next
  self.model_fence = { live: true }
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
/// Stage one dirty scene for the same text owner. This performs no host text
/// update, runtime publication, presentation or native queue operation.
pub fn SettingsRunOwner::stage_dirty_scene(
  self : SettingsRunOwner,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if !self.suspended || self.running || !self.dirty || self.pending_dirty_stage is Some(_) ||
    self.cutoff_done || self.pending_host_receipt is Some(_) || self.receipt_pre_dispatch is Some(_) ||
    self.inflight is Some(_) || self.owned_delivery is Some(_) || self.pending_direct is Some(_) ||
    self.held_tab is Some(_) || !self.buffered.is_empty() || !self.held_platform.is_empty() ||
    self.pending_frame is Some(_) || self.pending_publication is Some(_) || self.mounted.has_pending_actions() ||
    !self.host_epoch_verified {
    return Err(runner_error("dirty_scene", "original owner is not ready to stage"))
  }
  self.running = true
  let result = self.stage_dirty_scene_inner()
  self.running = false
  result
}

///|
fn SettingsRunOwner::stage_dirty_scene_inner(
  self : SettingsRunOwner,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let session = match self.session { Some(value) => value; None => return Err(runner_error("dirty_scene", "original session is unavailable")) }
  let owner = match self.terminal_owner { Some(value) => value; None => return Err(runner_error("dirty_scene", "original field is unavailable")) }
  if self.host_epoch != Some(session.epoch) || !owner.matches_session(self.window, session.epoch, session.binding) {
    return Err(runner_error("dirty_scene", "original host owner changed"))
  }
  let metrics = match self.host.window_metrics(self.window) { Ok(value) => value; Err(error) => return Err(error) }
  let (width, height, scale) = metrics
  let model = self.settings
  let fence = self.model_fence
  let prepared = match self.mounted.stage_owned_text_geometry(owner, model.view(), width, height, scale, self.measure) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let geometry = match self.mounted.inspect_staged_text_geometry(owner, prepared) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let (window, epoch, binding, _) = geometry.identity()
  if !fence.live || self.settings != model || window != self.window || epoch != session.epoch ||
    binding != session.binding || geometry.committed().text() != model.name() {
    return Err(runner_error("dirty_scene", "staged model or owner changed"))
  }
  let current_metrics = match self.host.window_metrics(self.window) { Ok(value) => value; Err(error) => return Err(error) }
  if current_metrics != metrics || !fence.live || self.settings != model ||
    self.host_epoch != Some(session.epoch) || !self.host_epoch_verified {
    return Err(runner_error("dirty_scene", "window metrics or owner changed during staging"))
  }
  match self.mounted.inspect_staged_text_geometry(owner, prepared) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  self.pending_dirty_stage = Some({ prepared, model, fence, window, epoch, binding, metrics, host_attempted: false, callback_returned_success: false })
  Ok(())
}

///|
/// Inspect a still-current local candidate. No publication is implied.
pub fn SettingsRunOwner::staged_dirty_geometry(
  self : SettingsRunOwner,
) -> Result[@ui.StagedTextGeometry, @diagnostics.FrameworkError] {
  if !self.suspended || self.running || self.cutoff_done {
    return Err(runner_error("dirty_scene", "staged inspection unavailable"))
  }
  self.running = true
  let result = self.staged_dirty_geometry_inner(true)
  self.running = false
  result
}

///|
fn SettingsRunOwner::staged_dirty_geometry_inner(
  self : SettingsRunOwner,
  require_verified : Bool,
) -> Result[@ui.StagedTextGeometry, @diagnostics.FrameworkError] {
  let staged = match self.pending_dirty_stage { Some(value) => value; None => return Err(runner_error("dirty_scene", "no staged candidate")) }
  let owner = match self.terminal_owner { Some(value) => value; None => return Err(runner_error("dirty_scene", "original field is unavailable")) }
  let session = match self.session { Some(value) => value; None => return Err(runner_error("dirty_scene", "original session is unavailable")) }
  if !staged.fence.live || self.settings != staged.model || self.window != staged.window ||
    session.epoch != staged.epoch || session.binding != staged.binding ||
    self.host_epoch != Some(staged.epoch) || (require_verified && !self.host_epoch_verified) {
    return Err(runner_error("dirty_scene", "staged model or host owner changed"))
  }
  let metrics = match self.host.window_metrics(self.window) { Ok(value) => value; Err(error) => return Err(error) }
  if metrics != staged.metrics || !staged.fence.live || self.settings != staged.model ||
    self.host_epoch != Some(staged.epoch) || (require_verified && !self.host_epoch_verified) {
    return Err(runner_error("dirty_scene", "window metrics or owner changed"))
  }
  self.mounted.inspect_staged_text_geometry(owner, staged.prepared)
}

///|
/// Run a bounded host attempt while retaining the original local candidate.
/// The callback is an adapter seam, not evidence of native acceptance. A
/// platform adapter must validate its own exact opaque receipt synchronously.
/// Even after success, discard, cutoff and publication remain blocked until a
/// separate cross-layer transaction can resolve this candidate.
pub fn SettingsRunOwner::attempt_staged_host_geometry(
  self : SettingsRunOwner,
  attempt : (Bool, @text_host.TextInputState) -> Result[Unit, @diagnostics.FrameworkError],
) -> Result[Unit, @diagnostics.FrameworkError] {
  if !self.suspended || self.running || self.cutoff_done {
    return Err(runner_error("dirty_scene", "staged host attempt unavailable"))
  }
  match self.geometry_arrival {
    Some(held) if !(held.state is GeometryArrivalCallbackSucceeded) =>
      return Err(runner_error("dirty_scene", "arrival handoff outcome is unresolved"))
    Some(held) => {
      let owner = match self.terminal_owner {
        Some(value) => value
        None => return Err(runner_error("dirty_scene", "arrival owner unavailable"))
      }
      if self.entered_target != Some(held.native_target) ||
        !self.mounted.terminal_owner_is_current(owner) || owner.observed_progress() != held.owner_progress {
        return Err(runner_error("dirty_scene", "arrival owner or native target changed"))
      }
    }
    _ => ()
  }
  let staged = match self.pending_dirty_stage {
    Some(value) => value
    None => return Err(runner_error("dirty_scene", "no staged candidate"))
  }
  if staged.callback_returned_success {
    return Err(runner_error("dirty_scene", "staged host callback already returned success"))
  }
  self.running = true
  let result = self.attempt_staged_host_geometry_inner(staged, attempt)
  self.running = false
  result
}

///|
fn SettingsRunOwner::attempt_staged_host_geometry_inner(
  self : SettingsRunOwner,
  staged : SettingsDirtyStage,
  attempt : (Bool, @text_host.TextInputState) -> Result[Unit, @diagnostics.FrameworkError],
) -> Result[Unit, @diagnostics.FrameworkError] {
  let geometry = match self.staged_dirty_geometry_inner(!staged.host_attempted) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let retry = staged.host_attempted
  let state = @text_host.TextInputState::new(geometry.committed(), settings_caret(geometry.caret()))
  staged.host_attempted = true
  self.host_epoch_verified = false
  match attempt(retry, state) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  // The callback may have reentered a host or invalidated the original mount.
  // A local recheck cannot itself prove what happened inside the host.
  match self.staged_dirty_geometry_inner(false) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  // An arbitrary callback's return is not a native receipt. Keep host epoch
  // uncertain even on success, until a platform-owned receipt can be checked.
  staged.callback_returned_success = true
  Ok(())
}

///|
/// Reserve exactly one supported later text receipt before asking the trusted
/// host route to hand it off. No input is applied and the host has not yet
/// acknowledged the record. The native adapter must supply an exact-head
/// handoff callback; a generic callback's result is not native evidence.
pub fn SettingsRunOwner::reserve_geometry_arrival(
  self : SettingsRunOwner, receipt : NativeRetainedReceipt, native_target : (Int32, Int64, Int32),
) -> Result[Unit, @diagnostics.FrameworkError] {
  if !self.suspended || self.running || self.cutoff_done || self.geometry_arrival is Some(_) ||
    self.host_epoch_verified || self.acknowledged_receipts.length() >= 64 ||
    self.pending_host_receipt is Some(_) || self.receipt_pre_dispatch is Some(_) || self.inflight is Some(_) ||
    self.owned_delivery is Some(_) || self.pending_direct is Some(_) || self.held_tab is Some(_) ||
    !self.buffered.is_empty() || !self.held_platform.is_empty() || self.mounted.has_pending_actions() {
    return Err(runner_error("geometry_handoff", "arrival slot unavailable"))
  }
  let staged = match self.pending_dirty_stage {
    Some(value) if value.host_attempted => value
    _ => return Err(runner_error("geometry_handoff", "original stage unavailable"))
  }
  let owner = match self.terminal_owner { Some(value) => value; None => return Err(runner_error("geometry_handoff", "original owner unavailable")) }
  let session = match self.session { Some(value) => value; None => return Err(runner_error("geometry_handoff", "original session unavailable")) }
  if !staged.fence.live || self.settings != staged.model || self.window != staged.window ||
    self.host_epoch != Some(staged.epoch) || session.epoch != staged.epoch || session.binding != staged.binding ||
    self.entered_target != Some(native_target) || native_target.0 <= 0 ||
    !owner.matches_session(staged.window, staged.epoch, staged.binding) || !self.mounted.terminal_owner_is_current(owner) ||
    receipt.window != staged.window || receipt.root != staged.binding || receipt.epoch != staged.epoch ||
    receipt.direct is Some(_) || receipt.edit_key_epoch is Some(_) || receipt.entered is Some(_) {
    return Err(runner_error("geometry_handoff", "arrival owner changed"))
  }
  match receipt.event {
    Some(OrderedText(event)) if event.window() == receipt.window && event.epoch() == receipt.epoch &&
      event.sequence() == receipt.sequence.to_int64() &&
      (event.kind() is @text_host.Preedit(..) || event.kind() is @text_host.Commit(..) || event.kind() is @text_host.Cancel) => ()
    _ => return Err(runner_error("geometry_handoff", "unsupported arrival remains at host"))
  }
  let base = match self.retired_prefix { Some(prefix) => prefix.watermark; None => 0 }
  for i = 0; i < self.acknowledged_receipts.length(); i = i + 1 {
    if self.acknowledged_receipts[i].receipt.sequence.to_int64() != base.to_int64() + i.to_int64() + 1L {
      return Err(runner_error("geometry_handoff", "earlier receipt prefix is not contiguous"))
    }
  }
  if receipt.sequence.to_int64() != base.to_int64() + self.acknowledged_receipts.length().to_int64() + 1L {
    return Err(runner_error("geometry_handoff", "arrival is not next in sequence"))
  }
  self.geometry_arrival = Some({ receipt, native_target, owner_progress: owner.observed_progress(), state: GeometryArrivalReserved })
  Ok(())
}

///|
/// Ask the route to transfer only the reserved head. After any error the
/// result is uncertain and must be reconciled against the same native route;
/// this seam never automatically calls it twice. A successful callback is not
/// a scene, model, native acceptance or cutoff proof.
pub fn SettingsRunOwner::transfer_geometry_arrival(
  self : SettingsRunOwner,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if !self.suspended || self.running || self.cutoff_done || self.host_epoch_verified {
    return Err(runner_error("geometry_handoff", "arrival transfer unavailable"))
  }
  let staged = match self.pending_dirty_stage { Some(value) if value.host_attempted => value; _ => return Err(runner_error("geometry_handoff", "original stage unavailable")) }
  let held = match self.geometry_arrival { Some(value) if value.state is GeometryArrivalReserved => value; _ => return Err(runner_error("geometry_handoff", "arrival transfer already attempted")) }
  let owner = match self.terminal_owner { Some(value) => value; None => return Err(runner_error("geometry_handoff", "original owner unavailable")) }
  let session = match self.session { Some(value) => value; None => return Err(runner_error("geometry_handoff", "original session unavailable")) }
  if !staged.fence.live || self.settings != staged.model || self.window != staged.window ||
    self.host_epoch != Some(staged.epoch) || session.epoch != staged.epoch || session.binding != staged.binding ||
    self.pending_host_receipt is Some(_) || self.receipt_pre_dispatch is Some(_) || self.inflight is Some(_) ||
    self.owned_delivery is Some(_) || self.pending_direct is Some(_) || self.held_tab is Some(_) ||
    !self.buffered.is_empty() || !self.held_platform.is_empty() || self.mounted.has_pending_actions() ||
    self.entered_target != Some(held.native_target) ||
    !owner.matches_session(staged.window, staged.epoch, staged.binding) || !self.mounted.terminal_owner_is_current(owner) ||
    owner.observed_progress() != held.owner_progress {
    return Err(runner_error("geometry_handoff", "original owner changed"))
  }
  held.state = GeometryArrivalAttempted
  self.running = true
  let result = (held.receipt.ack)()
  self.running = false
  match result {
    Err(error) => Err(error)
    Ok(_) => { held.state = GeometryArrivalCallbackSucceeded; Ok(()) }
  }
}

///|
/// Reinspect a transfer whose callback returned an uncertain result. The
/// trusted platform adapter must perform a read-only, exact-route slot check;
/// this callback's return is not itself a native receipt or authority to
/// apply the record. The original receipt and local candidate stay retained.
pub fn SettingsRunOwner::reconcile_geometry_arrival(
  self : SettingsRunOwner,
  inspect : () -> Result[Unit, @diagnostics.FrameworkError],
) -> Result[Unit, @diagnostics.FrameworkError] {
  if !self.suspended || self.running || self.cutoff_done || self.host_epoch_verified {
    return Err(runner_error("geometry_handoff", "arrival reconciliation unavailable"))
  }
  let staged = match self.pending_dirty_stage { Some(value) if value.host_attempted => value; _ => return Err(runner_error("geometry_handoff", "original stage unavailable")) }
  let held = match self.geometry_arrival { Some(value) if value.state is GeometryArrivalAttempted => value; _ => return Err(runner_error("geometry_handoff", "no uncertain arrival")) }
  if !self.geometry_arrival_owner_current(staged, held) {
    return Err(runner_error("geometry_handoff", "original owner changed"))
  }
  self.running = true
  let observed = inspect()
  self.running = false
  match observed { Err(error) => return Err(error); Ok(_) => () }
  if !self.geometry_arrival_owner_current(staged, held) {
    return Err(runner_error("geometry_handoff", "original owner changed during inspection"))
  }
  held.state = GeometryArrivalCallbackSucceeded
  Ok(())
}

///|
fn SettingsRunOwner::geometry_arrival_owner_current(
  self : SettingsRunOwner, staged : SettingsDirtyStage, held : SettingsGeometryArrival,
) -> Bool {
  let owner = match self.terminal_owner { Some(value) => value; None => return false }
  let session = match self.session { Some(value) => value; None => return false }
  self.suspended && !self.running && !self.cutoff_done && !self.host_epoch_verified &&
    staged.fence.live && self.settings == staged.model && self.window == staged.window &&
    self.host_epoch == Some(staged.epoch) && session.epoch == staged.epoch && session.binding == staged.binding &&
    self.entered_target == Some(held.native_target) &&
    self.pending_host_receipt is None && self.receipt_pre_dispatch is None && self.inflight is None &&
    self.owned_delivery is None && self.pending_direct is None && self.held_tab is None &&
    self.buffered.is_empty() && self.held_platform.is_empty() && !self.mounted.has_pending_actions() &&
    owner.matches_session(staged.window, staged.epoch, staged.binding) &&
    self.mounted.terminal_owner_is_current(owner) && owner.observed_progress() == held.owner_progress
}

///|
/// Inspect local transfer bookkeeping, not native ACK or application proof.
pub fn SettingsRunOwner::geometry_arrival_state(self : SettingsRunOwner) -> (Int32, Int)? {
  match self.geometry_arrival {
    None => None
    Some(held) => Some((held.receipt.sequence, match held.state {
      GeometryArrivalReserved => 0
      GeometryArrivalAttempted => 1
      GeometryArrivalCallbackSucceeded => 2
    }))
  }
}

///|
/// Discard only the unpublished derived scene candidate. The original field,
/// preedit, model, host and accepted records are not discarded or ended.
pub fn SettingsRunOwner::discard_staged_dirty_scene(
  self : SettingsRunOwner,
) -> Result[Unit, @diagnostics.FrameworkError] {
  // An uncertain host update must not lose the exact local candidate needed
  // to reconcile that attempt. This guard does not itself provide a host
  // receipt or a way to restore host_epoch_verified.
  if !self.suspended || self.running || !self.host_epoch_verified || self.pending_dirty_stage is None {
    return Err(runner_error("dirty_scene", "no discardable local candidate"))
  }
  let staged = match self.pending_dirty_stage {
    Some(value) => value
    None => return Err(runner_error("dirty_scene", "no discardable local candidate"))
  }
  if staged.host_attempted || self.host_epoch != Some(staged.epoch) {
    return Err(runner_error("dirty_scene", "staged host owner changed"))
  }
  self.pending_dirty_stage = None
  Ok(())
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
  if !self.suspended || self.running || self.pending_dirty_stage is Some(_) || self.cutoff_done || self.held_tab is Some(_) ||
    !self.held_platform.is_empty() ||
    self.pending_host_receipt is Some(_) || self.receipt_pre_dispatch is Some(_) || self.owned_delivery is Some(_) || self.pending_direct is Some(_) {
    return Err(runner_error("terminal_recovery", "terminal owner is unavailable"))
  }
  self.running = true
  let result = self.reconcile_terminal_observation_inner()
  self.running = false
  result
}

///|
fn SettingsRunOwner::reconcile_terminal_observation_inner(
  self : SettingsRunOwner,
) -> Result[Unit, @diagnostics.FrameworkError] {
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
  if self.retained_destroyed_prefix is Some(0) {
    return Err(runner_error("terminal_recovery", "post-destroy record requires admission proof"))
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
      self.note_text_receipt_stage(event, if changed { ReceiptActionRequired } else { ReceiptSessionApplied })
      changed
    }
  }
  if action_required {
    let action = match self.mounted.next_terminal_text_action(owner) {
      Ok(Some(value)) => value
      Ok(None) => return Err(runner_error("terminal_recovery", "the model action is unavailable"))
      Err(error) => return Err(error)
    }
    self.replace_settings(self.settings.update(@shared_settings.Ui(action)))
    self.note_text_receipt_stage(event, ReceiptModelApplied)
  }
  if event.kind() is @text_host.Commit(_) {
    self.terminal_model_sequence = event.sequence()
  }
  self.terminal_applied = None
  ignore(self.buffered.remove(0))
  match self.retained_destroyed_prefix {
    Some(count) if count > 0 => self.retained_destroyed_prefix = Some(count - 1)
    _ => ()
  }
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
  RetryReceiptAck
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
  ReceiptAcknowledged
  ReceiptDispatched
  ContinuationStepped
}

///|
/// Metadata is observable while the opaque host receipt remains owned here.
pub fn SettingsRunOwner::pending_receipt_identity(
  self : SettingsRunOwner,
) -> (@platform.WindowId, Int32, UInt64, UInt64)? {
  match self.pending_host_receipt {
    None => None
    Some(receipt) => Some((receipt.window, receipt.sequence, receipt.root, receipt.epoch))
  }
}

///|
/// Exposes an ACKed receipt only while its exact pre-dispatch step remains.
pub fn SettingsRunOwner::resumable_receipt_identity(
  self : SettingsRunOwner,
) -> (@platform.WindowId, Int32, UInt64, UInt64)? {
  if !self.suspended || self.pending_host_receipt is Some(_) {
    return None
  }
  match self.receipt_pre_dispatch {
    Some(receipt) => Some((receipt.window, receipt.sequence, receipt.root, receipt.epoch))
    None => None
  }
}

///|
pub fn SettingsRunOwner::acknowledged_receipt_count(self : SettingsRunOwner) -> Int {
  self.acknowledged_receipts.length()
}

///|
pub fn SettingsRunOwner::acknowledged_receipt_identity(
  self : SettingsRunOwner, index : Int,
) -> (@platform.WindowId, Int32, UInt64, UInt64)? {
  if index < 0 || index >= self.acknowledged_receipts.length() { return None }
  let receipt = self.acknowledged_receipts[index].receipt
  Some((receipt.window, receipt.sequence, receipt.root, receipt.epoch))
}

///|
pub fn SettingsRunOwner::acknowledged_receipt_stage(
  self : SettingsRunOwner, index : Int,
) -> NativeReceiptStage? {
  if index < 0 || index >= self.acknowledged_receipts.length() { return None }
  let entry = self.acknowledged_receipts[index]
  match entry.receipt.event {
    Some(OrderedText(event)) =>
      for i = 0; i < self.acknowledged_receipts.length(); i = i + 1 {
        if i == index { continue }
        match self.acknowledged_receipts[i].receipt.event {
          Some(OrderedText(other)) if other.window() == event.window() &&
            other.epoch() == event.epoch() && other.sequence() == event.sequence() => return None
          _ => ()
        }
      }
    _ => ()
  }
  Some(entry.stage)
}

///|
/// Resolve a native sequence only when it identifies one retained receipt.
pub fn SettingsRunOwner::receipt_stage_for_sequence(
  self : SettingsRunOwner, sequence : Int64,
) -> NativeReceiptStage? {
  if sequence <= 0L { return None }
  let mut found = -1
  for i = 0; i < self.acknowledged_receipts.length(); i = i + 1 {
    if self.acknowledged_receipts[i].receipt.sequence.to_int64() == sequence {
      if found >= 0 { return None }
      found = i
    }
  }
  if found < 0 { None } else { self.acknowledged_receipt_stage(found) }
}

///|
/// A negative result means that a retired prefix belongs to another lease.
fn SettingsRunOwner::retired_watermark_for(
  self : SettingsRunOwner, binding : UInt64, epoch : UInt64,
  owner : @ui.TerminalTextOwner,
) -> Int32 {
  match self.retired_prefix {
    None => 0
    Some(prefix) => {
      let (generation, _, _) = owner.observed_progress()
      if prefix.watermark <= 0 || prefix.window != self.window ||
        prefix.binding != binding || prefix.epoch != epoch ||
        Some(prefix.entered) != self.entered_target ||
        prefix.field_generation != generation {
        -1
      } else { prefix.watermark }
    }
  }
}

///|
/// A read-only snapshot of the locally recorded prefix before an unsupported
/// receipt. It is not native key provenance, a scene/geometry receipt, an ACK
/// capability, or a guarantee about another consumer or an earlier focus.
/// Callers must not use it alone to discard or acknowledge an event.
pub fn SettingsRunOwner::unsupported_prefix_has_observed_stages(
  self : SettingsRunOwner,
) -> Bool {
  self.unsupported_prefix_matches_running(false)
}

///|
fn SettingsRunOwner::unsupported_prefix_matches_running(
  self : SettingsRunOwner, running : Bool,
) -> Bool {
  if !self.suspended || self.running != running || self.destroyed || self.cutoff_done ||
    !self.host_epoch_verified || !self.buffered.is_empty() ||
    !self.held_platform.is_empty() || self.held_tab is Some(_) ||
    self.inflight is Some(_) || self.owned_delivery is Some(_) || self.pending_direct is Some(_) ||
    self.mounted.has_pending_actions() {
    return false
  }
  let receipt = match self.pending_host_receipt {
    Some(value) if value.event is None && value.entered is None => value
    _ => return false
  }
  let pre_dispatch = match self.receipt_pre_dispatch {
    Some(value) => value
    None => return false
  }
  let current = match self.session { Some(value) => value; None => return false }
  let owner = match self.terminal_owner { Some(value) => value; None => return false }
  let field = match self.mounted.focused_text() { Some(value) => value; None => return false }
  let retired = self.retired_watermark_for(current.binding, current.epoch, owner)
  if retired < 0 { return false }
  if receipt.sequence <= 0 || receipt.window != self.window ||
    receipt.root != current.binding || receipt.epoch != current.epoch ||
    pre_dispatch.sequence != receipt.sequence || pre_dispatch.window != receipt.window ||
    pre_dispatch.root != receipt.root || pre_dispatch.epoch != receipt.epoch ||
    self.host_epoch != Some(current.epoch) || field.binding_id() != current.binding ||
    !owner.matches_session(self.window, current.epoch, current.binding) ||
    !self.mounted.terminal_owner_is_current(owner) ||
    self.entered_target is None ||
    receipt.sequence.to_int64() != retired.to_int64() + self.acknowledged_receipts.length().to_int64() + 1L {
    return false
  }
  let mut entered = retired > 0
  for i = 0; i < self.acknowledged_receipts.length(); i = i + 1 {
    let entry = self.acknowledged_receipts[i]
    if entry.receipt.window != self.window || entry.receipt.sequence.to_int64() != retired.to_int64() + i.to_int64() + 1L {
      return false
    }
    match (entry.receipt.event, entry.stage) {
      (None, ReceiptOwnerEntered) if !entered && entry.receipt.entered == self.entered_target &&
        entry.receipt.root == current.binding && entry.receipt.epoch == current.epoch => entered = true
      (None, ReceiptUnsupportedAcknowledged) if entered && entry.receipt.entered is None &&
        entry.receipt.root == current.binding && entry.receipt.epoch == current.epoch => ()
      (Some(OrderedPlatform(event)), ReceiptPlatformHandled | ReceiptPointerMovedHandled) if
        event.window() == self.window && event.sequence() == entry.receipt.sequence.to_int64() &&
        (if entered {
          entry.receipt.root == current.binding && entry.receipt.epoch == current.epoch
        } else { entry.receipt.root == 0UL && entry.receipt.epoch == 0UL }) => ()
      (Some(OrderedText(event)), ReceiptNoModelAction | ReceiptModelApplied) if entered &&
        entry.receipt.root == current.binding && entry.receipt.epoch == current.epoch &&
        event.window() == self.window && event.epoch() == current.epoch => ()
      _ => return false
    }
  }
  entered
}

///|
/// Prepare an observation only from the exact current field lease and
/// contiguous, locally applied receipt prefix. It is deliberately optional:
/// inability to prove this observation does not imply input was discarded.
fn SettingsRunOwner::prepare_frame_publication(
  self : SettingsRunOwner, frame : @ui.Frame,
) -> SettingsFramePublication? {
  if self.pending_publication is Some(_) || self.completed_publications.length() >= 64 ||
    self.destroyed || self.dirty || !self.host_epoch_verified ||
    self.pending_host_receipt is Some(_) || self.receipt_pre_dispatch is Some(_) ||
    self.inflight is Some(_) || self.owned_delivery is Some(_) || self.pending_direct is Some(_) || self.held_tab is Some(_) ||
    !self.buffered.is_empty() || !self.held_platform.is_empty() ||
    self.mounted.has_pending_actions() {
    return None
  }
  let current = match self.session { Some(value) => value; None => return None }
  let owner = match self.terminal_owner { Some(value) => value; None => return None }
  let field = match self.mounted.focused_text() { Some(value) => value; None => return None }
  let entered_target = match self.entered_target { Some(value) => value; None => return None }
  if self.host_epoch != Some(current.epoch) ||
    !owner.matches_session(self.window, current.epoch, current.binding) ||
    !self.mounted.terminal_owner_is_current(owner) ||
    frame.binding_id(@shared_settings.settings_name()) != Some(current.binding) ||
    !frame.focused(@shared_settings.settings_name()) ||
    field.binding_id() != current.binding || field.document().text() != self.last_document ||
    settings_caret(field.caret()) != self.last_caret {
    return None
  }
  let retired = self.retired_watermark_for(current.binding, current.epoch, owner)
  if retired < 0 { return None }
  let mut watermark = retired
  let mut entered = retired > 0
  let prefix : Array[(NativeRetainedReceipt, NativeReceiptStage)] = []
  for entry in self.acknowledged_receipts {
    if entry.receipt.window != self.window || entry.receipt.sequence != watermark + 1 { break }
    let stage = match self.receipt_stage_for_sequence(entry.receipt.sequence.to_int64()) {
      Some(value) => value
      None => break
    }
    let valid = match (entry.receipt.event, stage) {
      (None, ReceiptOwnerEntered) if !entered && entry.receipt.entered == Some(entered_target) &&
        entry.receipt.root == current.binding && entry.receipt.epoch == current.epoch => {
          entered = true
          true
        }
      (None, ReceiptUnsupportedAcknowledged) => entered && entry.receipt.entered is None &&
        entry.receipt.root == current.binding && entry.receipt.epoch == current.epoch
      (Some(OrderedPlatform(event)), ReceiptPlatformHandled | ReceiptPointerMovedHandled) =>
        event.window() == self.window && event.sequence() == entry.receipt.sequence.to_int64() &&
        (if entered { entry.receipt.root == current.binding && entry.receipt.epoch == current.epoch }
         else { entry.receipt.root == 0UL && entry.receipt.epoch == 0UL })
      (Some(OrderedText(event)), ReceiptNoModelAction | ReceiptModelApplied) =>
        entered && entry.receipt.root == current.binding && entry.receipt.epoch == current.epoch &&
        event.window() == self.window && event.epoch() == current.epoch
      _ => false
    }
    if !valid { break }
    prefix.push((entry.receipt, stage))
    watermark += 1
  }
  if !entered || watermark == 0 || prefix.is_empty() { return None }
  Some({
    frame, window: self.window, binding: current.binding, epoch: current.epoch, entered: entered_target,
    field_progress: owner.observed_progress(), caret: self.last_caret, watermark,
    base_watermark: retired, prefix,
    presented: false, frame_completed: false,
  })
}

///|
/// Attempt presentation without upgrading the candidate on an error. If a
/// backend fails after side effects the original candidate remains available,
/// but neither presentation nor completion is asserted.
fn SettingsRunOwner::present_with_frame_publication(
  self : SettingsRunOwner, frame : @ui.Frame,
  present : (@platform.WindowId, @scene.SceneSnapshot) -> Result[Unit, @diagnostics.FrameworkError],
) -> Result[Unit, @diagnostics.FrameworkError] {
  if self.pending_publication is Some(_) {
    return Err(runner_error("ordered_text", "previous frame publication remains unresolved"))
  }
  self.pending_publication = self.prepare_frame_publication(frame)
  match present(self.window, frame.snapshot()) {
    Err(error) => Err(error)
    Ok(_) => {
      match self.pending_publication { Some(candidate) => candidate.presented = true; None => () }
      Ok(())
    }
  }
}

///|
/// Complete only the captured prefix, never any record received after the
/// present. A later owner/field/scene change invalidates this observation.
fn SettingsRunOwner::complete_frame_publication(self : SettingsRunOwner) -> Unit {
  let candidate = match self.pending_publication { Some(value) => value; None => return }
  if self.destroyed || self.cutoff_done { return }
  let current = match self.session { Some(value) => value; None => return }
  let owner = match self.terminal_owner { Some(value) => value; None => return }
  let field = match self.mounted.focused_text() { Some(value) => value; None => return }
  let frame = match self.mounted.frame() { Some(value) => value; None => return }
  if self.retired_watermark_for(current.binding, current.epoch, owner) != candidate.base_watermark { return }
  if self.acknowledged_receipts.length() < candidate.prefix.length() { return }
  for i = 0; i < candidate.prefix.length(); i = i + 1 {
    let (receipt, stage) = candidate.prefix[i]
    let now = self.acknowledged_receipts[i]
    let observed = match self.receipt_stage_for_sequence(receipt.sequence.to_int64()) {
      Some(value) => value
      None => return
    }
    if !same_publication_receipt(receipt, now.receipt) || !same_publication_stage(stage, observed) { return }
  }
  if candidate.presented && candidate.window == self.window &&
    candidate.binding == current.binding && candidate.epoch == current.epoch &&
    self.entered_target == Some(candidate.entered) &&
    self.host_epoch_verified && self.host_epoch == Some(current.epoch) &&
    owner.matches_session(self.window, current.epoch, current.binding) &&
    self.mounted.terminal_owner_is_current(owner) &&
    owner.observed_progress() == candidate.field_progress &&
    frame.revision() == candidate.frame.revision() &&
    settings_caret(field.caret()) == candidate.caret &&
    self.last_caret == candidate.caret {
    candidate.frame_completed = true
    self.completed_publications.push(candidate)
    self.pending_publication = None
  }
}

///|
pub fn SettingsRunOwner::completed_publication_count(self : SettingsRunOwner) -> Int {
  self.completed_publications.length()
}

///|
/// An in-flight, failed or invalidated present remains retained here. It is
/// not a completed publication or permission to stop.
pub fn SettingsRunOwner::pending_frame_publication(
  self : SettingsRunOwner,
) -> SettingsFramePublication? {
  self.pending_publication
}

///|
pub fn SettingsRunOwner::completed_publication(
  self : SettingsRunOwner, index : Int,
) -> SettingsFramePublication? {
  if index < 0 || index >= self.completed_publications.length() { None }
  else { Some(self.completed_publications[index]) }
}

///|
/// The last native sequence whose fully reflected, frame-observed prefix was
/// compacted for this owner. A positive value is not a host cutoff or stop.
pub fn SettingsRunOwner::retired_native_watermark(self : SettingsRunOwner) -> Int32 {
  match self.retired_prefix { Some(value) => value.watermark; None => 0 }
}

///|
/// Compact only the latest complete publication's entire contiguous prefix.
/// Unsupported records and any unresolved model/owner/geometry stage stay
/// owned. The compact summary preserves the original lease and a monotonic
/// native sequence fence; it neither ends IME nor stops the host.
fn SettingsRunOwner::retire_completed_publication(
  self : SettingsRunOwner, index : Int,
) -> Result[Int32, @diagnostics.FrameworkError] {
  if !self.suspended || self.running || self.pending_dirty_stage is Some(_) || self.destroyed || self.cutoff_done ||
    self.pending_publication is Some(_) || self.inflight is Some(_) ||
    self.owned_delivery is Some(_) || self.held_tab is Some(_) ||
    !self.buffered.is_empty() || !self.held_platform.is_empty() ||
    self.mounted.has_pending_actions() || !self.host_epoch_verified ||
    index < 0 || index != self.completed_publications.length() - 1 {
    return Err(runner_error("ordered_text", "publication retirement prerequisites are unresolved"))
  }
  let candidate = self.completed_publications[index]
  let current = match self.session { Some(value) => value; None => return Err(runner_error("ordered_text", "retirement session unavailable")) }
  let owner = match self.terminal_owner { Some(value) => value; None => return Err(runner_error("ordered_text", "retirement owner unavailable")) }
  let frame = match self.mounted.frame() { Some(value) => value; None => return Err(runner_error("ordered_text", "retirement frame unavailable")) }
  let entered = match self.entered_target { Some(value) => value; None => return Err(runner_error("ordered_text", "retirement entered target unavailable")) }
  let base = self.retired_watermark_for(current.binding, current.epoch, owner)
  let (generation, _, _) = owner.observed_progress()
  if base < 0 || candidate.base_watermark != base || !candidate.presented || !candidate.frame_completed ||
    candidate.window != self.window || candidate.binding != current.binding || candidate.epoch != current.epoch ||
    candidate.entered != entered ||
    self.host_epoch != Some(current.epoch) || !self.mounted.terminal_owner_is_current(owner) ||
    candidate.field_progress != owner.observed_progress() || candidate.frame.revision() != frame.revision() ||
    candidate.caret != self.last_caret || candidate.prefix.is_empty() ||
    candidate.watermark.to_int64() != base.to_int64() + candidate.prefix.length().to_int64() ||
    candidate.prefix.length() > self.acknowledged_receipts.length() {
    return Err(runner_error("ordered_text", "publication or original owner changed"))
  }
  match self.retired_prefix {
    Some(previous) if candidate.frame.revision() <= previous.scene_revision =>
      return Err(runner_error("ordered_text", "publication revision did not advance"))
    _ => ()
  }
  for i = 0; i < candidate.prefix.length(); i = i + 1 {
    let (receipt, stage) = candidate.prefix[i]
    let entry = self.acknowledged_receipts[i]
    let observed = match self.receipt_stage_for_sequence(receipt.sequence.to_int64()) {
      Some(value) => value
      None => return Err(runner_error("ordered_text", "ambiguous retirement sequence"))
    }
    // An unsupported ACK by itself is not retained native proof. Keep it and
    // its suffix until a separate, reviewed retirement policy exists.
    if stage is ReceiptUnsupportedAcknowledged ||
      !same_publication_stage(stage, observed) ||
      !same_publication_receipt(receipt, entry.receipt) ||
      receipt.sequence.to_int64() != base.to_int64() + i.to_int64() + 1L {
      return Err(runner_error("ordered_text", "publication prefix is not retireable"))
    }
  }
  for prior in self.completed_publications {
    if prior.watermark > candidate.watermark {
      return Err(runner_error("ordered_text", "newer publication would be discarded"))
    }
  }
  for i = 0; i < candidate.prefix.length(); i = i + 1 {
    ignore(self.acknowledged_receipts.remove(0))
  }
  self.retired_prefix = Some({
    window: self.window, binding: current.binding, epoch: current.epoch,
    entered, field_generation: generation, watermark: candidate.watermark,
    scene_revision: candidate.frame.revision(),
  })
  while !self.completed_publications.is_empty() { ignore(self.completed_publications.remove(0)) }
  // Only a prior full-ledger refusal, made before native peek, permits one
  // fresh bounded continuation. Other failures still require their own policy.
  if self.ledger_backpressure && self.acknowledged_receipts.length() < 64 &&
    self.pending_host_receipt is None && self.receipt_pre_dispatch is None {
    self.ledger_backpressure = false
    self.live_step_ready = true
    if self.live_step_generation == 0L { self.live_step_generation = 1L }
  }
  Ok(candidate.watermark)
}

///|
/// Opaque observation tied to one suspended owner and one exact unsupported
/// receipt. It is not native input provenance and cannot acknowledge a record.
pub struct UnsupportedPrefixSnapshot {
  priv owner : SettingsRunOwner
  priv pending : NativeRetainedReceipt
  priv entered : (Int32, Int64, Int32)
  priv field_progress : (UInt64, Int32, Int64)
  priv retired_watermark : Int32
  priv prefix : Array[(NativeRetainedReceipt, NativeReceiptStage)]
}

///|
/// Capture the original owner's local prefix, without accepting an external
/// boolean as proof and without changing the native queue or pending record.
pub fn SettingsRunOwner::capture_unsupported_prefix(
  self : SettingsRunOwner, sequence : Int64,
) -> Result[UnsupportedPrefixSnapshot, @diagnostics.FrameworkError] {
  if !self.unsupported_prefix_has_observed_stages() {
    return Err(runner_error("ordered_text", "unsupported prefix is not locally observable"))
  }
  let pending = self.pending_host_receipt.unwrap()
  if sequence <= 0L || pending.sequence.to_int64() != sequence {
    return Err(runner_error("ordered_text", "unsupported receipt identity changed"))
  }
  let owner = self.terminal_owner.unwrap()
  let prefix : Array[(NativeRetainedReceipt, NativeReceiptStage)] = []
  for i = 0; i < self.acknowledged_receipts.length(); i = i + 1 {
    let entry = self.acknowledged_receipts[i]
    let stage = match self.receipt_stage_for_sequence(entry.receipt.sequence.to_int64()) {
      Some(value) => value
      None => return Err(runner_error("ordered_text", "ambiguous prefix receipt"))
    }
    prefix.push((entry.receipt, stage))
  }
  let current = self.session.unwrap()
  let retired_watermark = self.retired_watermark_for(current.binding, current.epoch, owner)
  if retired_watermark < 0 { return Err(runner_error("ordered_text", "retired prefix owner changed")) }
  Ok({ owner: self, pending, entered: self.entered_target.unwrap(), field_progress: owner.observed_progress(), retired_watermark, prefix })
}

///|
/// Identity observed at this owner's original native Entered receipt.
/// This is not a physical key proof or permission to acknowledge anything.
pub fn UnsupportedPrefixSnapshot::native_entered_identity(
  self : UnsupportedPrefixSnapshot,
) -> (Int32, Int64, Int32) {
  self.entered
}

///|
/// Recheck immediately before using an observation. This remains only a
/// local owner/prefix check; native proof and the FIFO ACK must be performed
/// by the backend adapter against the original opaque native receipt.
pub fn UnsupportedPrefixSnapshot::is_current(self : UnsupportedPrefixSnapshot) -> Bool {
  self.is_current_with_running(false)
}

///|
fn UnsupportedPrefixSnapshot::is_current_with_running(
  self : UnsupportedPrefixSnapshot, running : Bool,
) -> Bool {
  let owner = self.owner
  if !owner.unsupported_prefix_matches_running(running) ||
    owner.acknowledged_receipts.length() != self.prefix.length() {
    return false
  }
  let pending = match owner.pending_host_receipt { Some(value) => value; None => return false }
  let field_owner = match owner.terminal_owner { Some(value) => value; None => return false }
  let current = match owner.session { Some(value) => value; None => return false }
  if !same_prefix_receipt(self.pending, pending) ||
    owner.entered_target != Some(self.entered) ||
    owner.retired_watermark_for(current.binding, current.epoch, field_owner) != self.retired_watermark ||
    field_owner.observed_progress() != self.field_progress {
    return false
  }
  for i = 0; i < self.prefix.length(); i = i + 1 {
    let (receipt, stage) = self.prefix[i]
    let current = owner.acknowledged_receipts[i]
    let current_stage = match owner.receipt_stage_for_sequence(receipt.sequence.to_int64()) {
      Some(value) => value
      None => return false
    }
    if !same_prefix_receipt(receipt, current.receipt) || !same_prefix_stage(stage, current_stage) {
      return false
    }
  }
  true
}

///|
/// Execute a synchronous native-adapter policy while the original owner is
/// guarded against reentry. The policy must verify platform provenance on the
/// exact opaque native receipt before invoking the provided one-shot ACK.
/// The local snapshot alone is not that proof. The callback cannot be saved
/// for later, retried within this operation, or used after owner state moves.
///
/// The ordered port is a trusted host adapter: its ACK must dequeue exactly
/// this original receipt on success and leave it owned on error. An arbitrary
/// application callback that merely calls the continuation is not evidence
/// that an unsupported event is safe. A failed/unused policy preserves the
/// owner; a success followed by policy failure remains recorded as ACKed.
pub fn SettingsRunOwner::with_unsupported_native_policy(
  self : SettingsRunOwner, sequence : Int64,
  policy : ((Int32, Int64, Int32), () -> Result[Unit, @diagnostics.FrameworkError]) -> Result[Unit, @diagnostics.FrameworkError],
) -> Result[Unit, @diagnostics.FrameworkError] {
  // A diagnostic snapshot may be saved across an ABA change. Never accept
  // one as authority: capture a new observation inside this synchronous step.
  let snapshot = match self.capture_unsupported_prefix(sequence) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let owner = self
  if owner.acknowledged_receipts.length() >= 64 {
    return Err(runner_error("ordered_text", "unsupported owner snapshot is stale or full"))
  }
  owner.running = true
  let active = Ref(true)
  let attempted = Ref(false)
  let acknowledged = Ref(false)
  let result = policy(snapshot.entered, fn() {
    if !active.val || attempted.val || !snapshot.is_current_with_running(true) {
      return Err(runner_error("ordered_text", "unsupported ACK capability is stale or consumed"))
    }
    attempted.val = true
    let pending = match owner.pending_host_receipt {
      Some(value) => value
      None => return Err(runner_error("ordered_text", "unsupported receipt is no longer held"))
    }
    match (pending.ack)() {
      Err(error) => Err(error)
      Ok(_) => {
        owner.acknowledged_receipts.push({ receipt: pending, stage: ReceiptUnsupportedAcknowledged })
        owner.pending_host_receipt = None
        owner.receipt_pre_dispatch = None
        owner.inflight = None
        owner.live_step_ready = true
        if owner.live_step_generation == 0L { owner.live_step_generation = 1L }
        acknowledged.val = true
        Ok(())
      }
    }
  })
  active.val = false
  owner.running = false
  match result {
    Err(error) => Err(error)
    Ok(_) if !acknowledged.val => Err(runner_error("ordered_text", "native policy did not acknowledge its receipt"))
    Ok(_) => Ok(())
  }
}

///|
/// Resolve only an already ACKed Destroyed observation for the original
/// field. This is a terminal policy, not a host cutoff or permission to stop.
pub fn SettingsRunOwner::resolve_destroyed_receipt(
  self : SettingsRunOwner, sequence : Int64,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if !self.suspended || self.running || self.pending_dirty_stage is Some(_) || self.cutoff_done || sequence <= 0L ||
    self.pending_host_receipt is Some(_) || self.receipt_pre_dispatch is Some(_) || self.owned_delivery is Some(_) || self.pending_direct is Some(_) ||
    self.terminal_destroyed_sequence is Some(_) || self.terminal_applied is Some(_) ||
    !self.held_platform.is_empty() || self.held_tab is Some(_) ||
    !(self.retained_destroyed_prefix is Some(0)) {
    return Err(runner_error("terminal_destroyed", "terminal owner or prefix is unresolved"))
  }
  let session = match self.session { Some(value) => value; None => return Err(runner_error("terminal_destroyed", "session unavailable")) }
  let owner = match self.terminal_owner { Some(value) => value; None => return Err(runner_error("terminal_destroyed", "owner unavailable")) }
  if !owner.matches_session(self.window, session.epoch, session.binding) ||
    !self.mounted.terminal_field_can_cutoff(owner) {
    return Err(runner_error("terminal_destroyed", "field, preedit or action remains unresolved"))
  }
  let event = match self.inflight {
    Some(OrderedPlatform(value)) if value.window() == self.window && value.kind() is @platform.Destroyed => value
    _ => return Err(runner_error("terminal_destroyed", "destroyed event is unavailable"))
  }
  if !(self.receipt_stage_for_sequence(sequence) is Some(ReceiptAcknowledgedOnly)) {
    return Err(runner_error("terminal_destroyed", "native receipt is missing or ambiguous"))
  }
  let mut found = -1
  for i = 0; i < self.acknowledged_receipts.length(); i = i + 1 {
    let receipt = self.acknowledged_receipts[i].receipt
    match receipt.event {
      Some(OrderedPlatform(candidate)) if receipt.sequence.to_int64() == sequence &&
        receipt.window == self.window && receipt.root == session.binding &&
        receipt.epoch == session.epoch && candidate.window() == event.window() &&
        candidate.sequence() == sequence && candidate.sequence() == event.sequence() &&
        candidate.kind() is @platform.Destroyed => {
          if found >= 0 { return Err(runner_error("terminal_destroyed", "ambiguous native receipt")) }
          found = i
        }
      _ => ()
    }
  }
  if found < 0 { return Err(runner_error("terminal_destroyed", "original receipt unavailable")) }
  self.terminal_destroyed_sequence = Some(self.acknowledged_receipts[found].receipt.sequence)
  self.acknowledged_receipts[found].stage = ReceiptTerminalResolved
  self.destroyed = true
  self.gate.invalidate_layout(self.pending_frame is Some(_))
  self.mounted.invalidate_layout()
  Ok(())
}

///|
/// Retire one committed receipt only after model reflection and a validated
/// later native Destroyed receipt. Later input, terminal receipt and host stay
/// owned; no scene, cutoff or successful shutdown is implied.
pub fn SettingsRunOwner::retire_destroyed_model_receipt(
  self : SettingsRunOwner, sequence : Int64,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if !self.suspended || self.running || self.pending_dirty_stage is Some(_) || self.cutoff_done || sequence <= 0L ||
    self.pending_host_receipt is Some(_) || self.receipt_pre_dispatch is Some(_) || self.owned_delivery is Some(_) || self.pending_direct is Some(_) ||
    self.terminal_applied is Some(_) || !self.held_platform.is_empty() ||
    self.held_tab is Some(_) || !(self.retained_destroyed_prefix is Some(0)) {
    return Err(runner_error("terminal_retire", "terminal stages are unresolved"))
  }
  let terminal = match self.terminal_destroyed_sequence {
    Some(value) if sequence < value.to_int64() => value
    _ => return Err(runner_error("terminal_retire", "earlier model receipt required"))
  }
  ignore(terminal)
  let session = match self.session { Some(value) => value; None => return Err(runner_error("terminal_retire", "session unavailable")) }
  let owner = match self.terminal_owner { Some(value) => value; None => return Err(runner_error("terminal_retire", "owner unavailable")) }
  if !owner.matches_session(self.window, session.epoch, session.binding) ||
    !self.mounted.terminal_field_can_cutoff(owner) {
    return Err(runner_error("terminal_retire", "field, preedit or action remains unresolved"))
  }
  let mut found = -1
  for i = 0; i < self.acknowledged_receipts.length(); i = i + 1 {
    if self.acknowledged_receipts[i].receipt.sequence.to_int64() == sequence {
      if found >= 0 { return Err(runner_error("terminal_retire", "ambiguous native receipt")) }
      found = i
    }
  }
  if found < 0 || !(self.acknowledged_receipt_stage(found) is Some(ReceiptModelApplied)) {
    return Err(runner_error("terminal_retire", "model reflection is not proven"))
  }
  let receipt = self.acknowledged_receipts[found].receipt
  match receipt.event {
    Some(OrderedText(value)) if receipt.window == self.window && receipt.root == session.binding &&
      receipt.epoch == session.epoch && value.window() == self.window && value.epoch() == session.epoch &&
      value.sequence() <= self.terminal_model_sequence && value.kind() is @text_host.Commit(_) => ()
    _ => return Err(runner_error("terminal_retire", "original commit owner does not match"))
  }
  ignore(self.acknowledged_receipts.remove(found))
  Ok(())
}

///|
/// Associate a text stage only when one retained native receipt uniquely owns
/// the exact portable window, epoch and sequence. Missing/ambiguous evidence
/// stays unclassified rather than attributing another record's effects.
fn SettingsRunOwner::note_text_receipt_stage(
  self : SettingsRunOwner, event : @text_host.TextInputEvent, stage : NativeReceiptStage,
) -> Unit {
  let session = match self.session { Some(value) => value; None => return }
  let owner = match self.terminal_owner { Some(value) => value; None => return }
  if !owner.matches_session(self.window, session.epoch, session.binding) { return }
  let mut found = -1
  for i = 0; i < self.acknowledged_receipts.length(); i = i + 1 {
    let receipt = self.acknowledged_receipts[i].receipt
    match receipt.event {
      Some(OrderedText(value)) if receipt.window == self.window &&
        receipt.root == session.binding && receipt.epoch == session.epoch &&
        value.window() == event.window() &&
        value.epoch() == event.epoch() && value.sequence() == event.sequence() => {
          if found >= 0 { return }
          found = i
        }
      _ => ()
    }
  }
  if found >= 0 {
    let entry = self.acknowledged_receipts[found]
    match entry.receipt.event {
      Some(OrderedText(value)) if same_text_observation_kind(value.kind(), event.kind()) &&
        receipt_stage_rank(stage) > receipt_stage_rank(entry.stage) => entry.stage = stage
      _ => ()
    }
  }
}

///|
fn SettingsRunOwner::note_handled_platform(
  self : SettingsRunOwner, event : @platform.Event,
) -> Unit {
  let mut found = -1
  for i = 0; i < self.acknowledged_receipts.length(); i = i + 1 {
    let receipt = self.acknowledged_receipts[i].receipt
    if receipt.sequence.to_int64() == event.sequence() {
      if found >= 0 { return }
      found = i
    }
  }
  if found < 0 { return }
  let entry = self.acknowledged_receipts[found]
  match entry.receipt.event {
    Some(OrderedPlatform(value)) if entry.receipt.window == event.window() &&
      value.window() == event.window() && value.sequence() == event.sequence() &&
      value.scale() == event.scale() &&
      same_handled_platform_kind(value.kind(), event.kind()) &&
      entry.stage is ReceiptAcknowledgedOnly => entry.stage = match value.kind() {
        @platform.Input(@primitives.PointerMoved(..)) => ReceiptPointerMovedHandled
        _ => ReceiptPlatformHandled
      }
    _ => ()
  }
}

///|
/// Dispatch only the record interrupted by a failed ACK, without publishing a
/// scene or consuming a later record. Other failures remain suspended.
pub fn SettingsRunOwner::resume_after_receipt_ack(
  self : SettingsRunOwner,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if !self.suspended || self.running || self.pending_dirty_stage is Some(_) || self.owned_delivery is Some(_) || self.pending_direct is Some(_) || self.receipt_pre_dispatch is None ||
    self.pending_host_receipt is Some(_) || self.cutoff_done {
    return Err(runner_error("ordered_text", "no acknowledged pre-dispatch interruption"))
  }
  self.suspended = false
  self.resume_pre_dispatch = true
  self.bounded_resume = true
  let result = self.drive()
  self.bounded_resume = false
  self.suspended = true
  if result is Ok(_) {
    self.live_step_ready = true
    if self.live_step_generation == 0L { self.live_step_generation = 1L }
  }
  result
}

///|
/// A generation changes before every admitted step, including an empty poll.
pub fn SettingsRunOwner::advance_generation(self : SettingsRunOwner) -> Int64? {
  if self.suspended && !self.running && self.pending_dirty_stage is None && self.live_step_ready &&
    self.pending_host_receipt is None && self.inflight is None && self.owned_delivery is None && self.pending_direct is None &&
    self.held_tab is None && self.receipt_pre_dispatch is None && !self.cutoff_done {
    Some(self.live_step_generation)
  } else {
    None
  }
}

///|
pub fn SettingsRunOwner::advance_once(
  self : SettingsRunOwner, generation : Int64,
) -> Result[SettingsTerminalProgress, @diagnostics.FrameworkError] {
  if self.advance_generation() != Some(generation) || generation <= 0L ||
    generation == 9223372036854775807L {
    return Err(runner_error("ordered_text", "continuation generation is stale or unavailable"))
  }
  self.live_step_generation += 1L
  self.live_step_ready = false
  self.suspended = false
  self.bounded_resume = true
  let result = self.drive()
  self.bounded_resume = false
  self.suspended = true
  match result {
    Ok(_) => {
      self.live_step_ready = true
      Ok(ContinuationStepped)
    }
    Err(error) => Err(error)
  }
}

///|
fn SettingsRunOwner::ack_owned_receipt(
  self : SettingsRunOwner,
) -> Result[Unit, @diagnostics.FrameworkError] {
  match self.pending_host_receipt {
    None => Err(runner_error("ordered_text", "no retained receipt"))
    Some(receipt) if receipt.event is None && receipt.entered is None =>
      Err(runner_error("ordered_text", "unsupported receipt requires an explicit policy"))
    Some(receipt) if receipt.entered is Some(_) && receipt.entered != self.entered_target =>
      Err(runner_error("ordered_text", "entered owner was not validated"))
    Some(receipt) if self.retired_prefix is Some(prefix) && receipt.sequence <= prefix.watermark =>
      Err(runner_error("ordered_text", "native sequence was already retired"))
    Some(receipt) if self.retired_prefix is Some(prefix) &&
      receipt.sequence.to_int64() != prefix.watermark.to_int64() + self.acknowledged_receipts.length().to_int64() + 1L =>
      Err(runner_error("ordered_text", "native sequence skipped the retained prefix"))
    Some(_) if self.acknowledged_receipts.length() >= 64 =>
      Err(runner_error("ordered_text", "receipt ledger is full"))
    Some(receipt) if self.pending_direct is Some(_) && receipt.direct is None && receipt.edit_key_epoch is None =>
      Err(runner_error("ordered_text", "a different direct receipt is pending"))
    Some(receipt) => {
      if receipt.direct is Some(_) || receipt.edit_key_epoch is Some(_) {
        let direct = match self.pending_direct {
          Some(value) => value
          None => return Err(runner_error("ordered_text", "direct receipt has not been reserved"))
        }
        let (window, epoch, binding, _, _) = direct.identity()
        let matches = match (receipt.direct, receipt.edit_key_epoch, receipt.event) {
          (Some((native_epoch, ordinal)), None, Some(OrderedPlatform(event))) =>
            native_epoch > 0 && !direct.is_edit_key() && ordinal == direct.ordinal() && same_direct_event(event, direct.event())
          (None, Some(native_epoch), Some(OrderedPlatform(event))) =>
            native_epoch > 0 && direct.is_edit_key() && same_direct_event(event, direct.event())
          _ => false
        }
        if !matches || window != receipt.window || epoch != receipt.epoch || binding != receipt.root ||
          direct.native_sequence() != receipt.sequence || direct.attempted() ||
          !(self.inflight is Some(OrderedPlatform(event)) && same_direct_event(event, direct.event())) {
          return Err(runner_error("ordered_text", "direct receipt reservation changed"))
        }
        match (self.pending_direct_model, self.pending_direct_fence, self.terminal_owner) {
          (Some(before), Some(fence), Some(owner)) if fence.live && before == self.settings &&
            self.mounted.terminal_owner_is_current(owner) => ()
          _ => return Err(runner_error("ordered_text", "direct model proof is stale"))
        }
      }
      if receipt.entered is Some(_) {
        match self.validate_entered(receipt) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      }
      match (receipt.ack)() {
        Err(error) => Err(error)
        Ok(_) => {
          self.acknowledged_receipts.push({
            receipt,
            stage: if receipt.entered is Some(_) { ReceiptOwnerEntered } else { ReceiptAcknowledgedOnly },
          })
          match (receipt.direct is Some(_) || receipt.edit_key_epoch is Some(_), self.pending_direct) {
            (true, Some(direct)) => {
              self.direct_receipts.push((receipt, direct))
            }
            _ => ()
          }
          self.pending_host_receipt = None
          Ok(())
        }
      }
    }
  }
}

///|
/// Reserve the exact direct head while the native receipt is still held.
/// The trusted Ubuntu adapter validates opaque native provenance; ACK checks
/// the current native head before the reserved event may mutate the field.
fn SettingsRunOwner::reserve_pending_direct(
  self : SettingsRunOwner, receipt : NativeRetainedReceipt,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if self.pending_direct is Some(_) || self.owned_delivery is Some(_) ||
    self.acknowledged_receipts.length() >= 64 {
    return Err(runner_error("ordered_text", "direct owner is blocked"))
  }
  let native_epoch = match (receipt.direct, receipt.edit_key_epoch) {
    (Some((value, _)), None) | (None, Some(value)) => value
    _ => return Err(runner_error("ordered_text", "not a single owned input receipt"))
  }
  let event = match receipt.event {
    Some(OrderedPlatform(value)) => value
    _ => return Err(runner_error("ordered_text", "owned input event is unavailable"))
  }
  let session = match self.session {
    Some(value) => value
    None => return Err(runner_error("ordered_text", "direct original session is unavailable"))
  }
  let owner = match self.terminal_owner {
    Some(value) => value
    None => return Err(runner_error("ordered_text", "direct original field owner is unavailable"))
  }
  if native_epoch <= 0 || receipt.window != self.window || receipt.root != session.binding ||
    receipt.epoch != session.epoch || self.host_epoch != Some(session.epoch) ||
    !self.host_epoch_verified || !owner.matches_session(self.window, session.epoch, session.binding) {
    return Err(runner_error("ordered_text", "direct native owner changed"))
  }
  let before = self.settings
  let fence = self.model_fence
  let candidate = match receipt.direct {
    Some((_, ordinal)) => self.mounted.reserve_owned_direct_text(owner, event, receipt.sequence, ordinal)
    None => self.mounted.reserve_owned_edit_key(owner, event, receipt.sequence)
  }
  let direct = match candidate {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if direct.before_document() != before.name() {
    return Err(runner_error("ordered_text", "direct field and model differ"))
  }
  self.pending_direct = Some(direct)
  self.pending_direct_model = Some(before)
  self.pending_direct_fence = Some(fence)
  Ok(())
}

///|
fn direct_delivery_marker(delivery : @ui.OwnedDirectDelivery) -> String? {
  if delivery.is_edit_key() { None }
  else { Some("YAMI_NATIVE_UI_SETTINGS {\"phase\":\"direct-insert\",\"sequence\":\{delivery.native_sequence()}}") }
}

///|
/// Apply only an already-ACKed original receipt. Any failure retains the
/// original event, owner, model fence and application/action stage.
fn SettingsRunOwner::complete_pending_direct(
  self : SettingsRunOwner,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if self.pending_host_receipt is Some(_) { return Err(runner_error("ordered_text", "direct head is not acknowledged")) }
  let direct = match self.pending_direct { Some(value) => value; None => return Err(runner_error("ordered_text", "direct reservation is missing")) }
  let (native, owned) = match self.direct_receipts.last() {
    Some(value) => value
    None => return Err(runner_error("ordered_text", "acknowledged direct receipt is missing"))
  }
  if owned.native_sequence() != direct.native_sequence() || owned.ordinal() != direct.ordinal() ||
    owned.identity() != direct.identity() || !same_direct_event(owned.event(), direct.event()) ||
    native.sequence != direct.native_sequence() ||
    !(native.event is Some(OrderedPlatform(event)) && same_direct_event(event, direct.event())) ||
    !(self.inflight is Some(OrderedPlatform(event)) && same_direct_event(event, direct.event())) {
    return Err(runner_error("ordered_text", "acknowledged direct owner changed"))
  }
  let before = match self.pending_direct_model { Some(value) => value; None => return Err(runner_error("ordered_text", "direct model is missing")) }
  let fence = match self.pending_direct_fence { Some(value) => value; None => return Err(runner_error("ordered_text", "direct model fence is missing")) }
  if !fence.live || self.settings != before {
    return Err(runner_error("ordered_text", "direct model changed before application"))
  }
  if !direct.applied() {
    if direct.attempted() { return Err(runner_error("ordered_text", "direct application outcome is uncertain")) }
    match self.mounted.apply_owned_direct_text(direct) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  } else if !direct.owner_noted() {
    match self.mounted.complete_owned_direct_text(direct) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  if !fence.live || self.settings != before {
    return Err(runner_error("ordered_text", "direct model changed during application"))
  }
  match direct.action_required() {
    Some(false) => ()
    Some(true) => {
      let action = match self.mounted.owned_direct_text_action(direct) {
        Ok(Some(value)) => value
        Ok(None) => return Err(runner_error("ordered_text", "direct model action missing"))
        Err(error) => return Err(error)
      }
      let next = before.update(@shared_settings.Ui(action))
      match action {
        @view.TextChanged(key, value) if key == @shared_settings.settings_name() && next.name() == value => ()
        _ => return Err(runner_error("ordered_text", "direct action targets a different model"))
      }
      match self.mounted.mark_owned_direct_text_model_applied(direct) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      self.replace_settings(next)
    }
    None => return Err(runner_error("ordered_text", "direct model requirement is unknown"))
  }
  match direct_delivery_marker(direct) { Some(marker) => emit_native_marker(marker); None => () }
  self.pending_direct = None
  self.pending_direct_model = None
  self.pending_direct_fence = None
  self.inflight = None
  self.receipt_pre_dispatch = None
  if self.suspended {
    self.live_step_ready = true
    if self.live_step_generation == 0L { self.live_step_generation = 1L }
  }
  Ok(())
}

///|
/// Record the original session and native seat/proxy before acknowledging an
/// Entered notification. No preedit, cancel, model action or scene is implied.
fn SettingsRunOwner::own_entered(
  self : SettingsRunOwner, receipt : NativeRetainedReceipt,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if self.entered_target is Some(_) {
    return Err(runner_error("ordered_text", "entered target already owned"))
  }
  let target = match self.validate_entered(receipt) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.entered_target = Some(target)
  Ok(())
}

///|
fn SettingsRunOwner::validate_entered(
  self : SettingsRunOwner, receipt : NativeRetainedReceipt,
) -> Result[(Int32, Int64, Int32), @diagnostics.FrameworkError] {
  let target = match receipt.entered {
    Some((native_epoch, seat, proxy)) if native_epoch > 0 && seat > 0L && proxy > 0 =>
      (native_epoch, seat, proxy)
    _ => return Err(runner_error("ordered_text", "invalid entered target"))
  }
  let session = match self.session {
    Some(value) => value
    None => return Err(runner_error("ordered_text", "entered session unavailable"))
  }
  let owner = match self.terminal_owner {
    Some(value) => value
    None => return Err(runner_error("ordered_text", "entered owner unavailable"))
  }
  let focused = match self.mounted.focused_text() {
    Some(value) => value
    None => return Err(runner_error("ordered_text", "entered focus unavailable"))
  }
  if !self.host_epoch_verified ||
    self.host_epoch != Some(session.epoch) || receipt.window != self.window ||
    receipt.root != session.binding || receipt.epoch != session.epoch ||
    focused.binding_id() != session.binding ||
    !owner.matches_session(self.window, session.epoch, session.binding) {
    return Err(runner_error("ordered_text", "entered owner mismatch"))
  }
  Ok(target)
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
  if !self.suspended || self.running || self.pending_dirty_stage is Some(_) || self.cutoff_done {
    return Err(runner_error("terminal_step", "owner is not suspended or is busy"))
  }
  if self.pending_host_receipt is Some(_) && !(command is RetryReceiptAck) {
    return Err(runner_error("terminal_step", "receipt acknowledgement is pending"))
  }
  if self.owned_delivery is Some(_) {
    return Err(runner_error("terminal_step", "owned text delivery requires resolution"))
  }
  if self.receipt_pre_dispatch is Some(_) && !(command is RetryReceiptAck) {
    return Err(runner_error("terminal_step", "pre-dispatch receipt requires resolution"))
  }
  match command {
    RetryReceiptAck => {
      self.running = true
      let result = match self.ack_owned_receipt() {
        Ok(_) if self.pending_direct is Some(_) => self.complete_pending_direct()
        result => result
      }
      self.running = false
      match result {
        Ok(_) => Ok(ReceiptAcknowledged)
        Err(error) => Err(error)
      }
    }
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
      if self.acknowledged_receipts.length() >= 64 {
        return Err(runner_error("terminal_step", "receipt ledger is full"))
      }
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
      let before_count = self.buffered.length()
      let result = match ordered.peek {
        None => (ordered.next)(0)
        Some(peek) =>
          match peek(0) {
            Err(error) => Err(error)
            Ok(None) => Ok(None)
            Ok(Some(receipt)) => {
              self.pending_host_receipt = Some(receipt)
              match receipt.event {
                None => Err(runner_error("ordered_text", "unsupported receipt requires an explicit policy"))
                Some(record) => {
                  self.buffered.push(record)
                  match self.ack_owned_receipt() {
                    Err(error) => Err(error)
                    Ok(_) => Ok(None)
                  }
                }
              }
            }
          }
      }
      self.running = false
      match result {
        Err(error) => Err(error)
        Ok(None) => if self.buffered.length() > before_count {
          Ok(RecordBuffered)
        } else { Ok(NoRecord) }
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
/// Retry only the post-ACK direct stage on the same retained owner; an
/// uncertain field application is never invoked again.
pub fn SettingsRunOwner::reconcile_direct_delivery(
  self : SettingsRunOwner,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if !self.suspended || self.running || self.pending_dirty_stage is Some(_) || self.pending_host_receipt is Some(_) ||
    self.pending_direct is None || self.cutoff_done {
    return Err(runner_error("ordered_text", "direct recovery is unavailable"))
  }
  self.running = true
  let result = self.complete_pending_direct()
  self.running = false
  result
}

///|
/// Attempt only the text-session native cutoff, without consuming the retained
/// terminal event or stopping the host. Busy leaves the original owner intact.
/// Success is not an ACK for other native events or permission to stop.
pub fn SettingsRunOwner::try_terminal_text_cutoff(
  self : SettingsRunOwner,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if !self.suspended || self.running || self.pending_dirty_stage is Some(_) || self.cutoff_done ||
    self.held_tab is Some(_) || self.owned_delivery is Some(_) || self.pending_direct is Some(_) || self.pending_host_receipt is Some(_) ||
    self.receipt_pre_dispatch is Some(_) || !self.buffered.is_empty() ||
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
  if !self.host_epoch_verified ||
    !owner.matches_session(self.window, session.epoch, session.binding) ||
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
/// False means a fallible host update did not return a current epoch.
pub fn SettingsRunOwner::host_epoch_verified(self : SettingsRunOwner) -> Bool {
  self.host_epoch_verified
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
/// The original applied delivery and any extracted action remain inspectable
/// after an interruption; this is not a model or geometry completion proof.
pub fn SettingsRunOwner::owned_text_delivery(
  self : SettingsRunOwner,
) -> @ui.OwnedTextDelivery? {
  self.owned_delivery
}

///|
/// Find the unique native receipt for this exact applied delivery. Missing or
/// ambiguous associations cannot authorize a sequence-bound recovery step.
pub fn SettingsRunOwner::owned_delivery_native_sequence(
  self : SettingsRunOwner,
) -> Int64? {
  let receipt = match self.owned_delivery { Some(value) => value; None => return None }
  let event = receipt.event()
  let (window, epoch, binding, _, sequence) = receipt.identity()
  match self.inflight {
    Some(OrderedText(value)) if value.window() == window && value.epoch() == epoch &&
      value.sequence() == sequence && same_text_observation_kind(value.kind(), event.kind()) => ()
    _ => return None
  }
  let mut found = -1
  for i = 0; i < self.acknowledged_receipts.length(); i = i + 1 {
    let native = self.acknowledged_receipts[i].receipt
    match native.event {
      Some(OrderedText(value)) if native.window == window && native.root == binding &&
        native.epoch == epoch && value.window() == window && value.epoch() == epoch &&
        value.sequence() == sequence && same_text_observation_kind(value.kind(), event.kind()) => {
          if found >= 0 { return None }
          found = i
        }
      _ => ()
    }
  }
  if found < 0 || self.acknowledged_receipt_stage(found) is None { return None }
  let native_sequence = self.acknowledged_receipts[found].receipt.sequence.to_int64()
  if self.receipt_stage_for_sequence(native_sequence) is None { None } else { Some(native_sequence) }
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
    host_epoch_verified: false,
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
    pending_publication: None,
    completed_publications: [],
    dirty: true,
    pending_dirty_stage: None,
    geometry_arrival: None,
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
    owned_delivery: None,
    pending_direct: None,
    pending_direct_model: None,
    pending_direct_fence: None,
    direct_receipts: [],
    owned_model_before: None,
    owned_model_fence: None,
    model_fence: { live: true },
    pending_host_receipt: None,
    acknowledged_receipts: [],
    retired_prefix: None,
    ledger_backpressure: false,
    entered_target: None,
    retained_destroyed_prefix: None,
    terminal_destroyed_sequence: None,
    receipt_pre_dispatch: None,
    resume_pre_dispatch: false,
    bounded_resume: false,
    live_step_ready: false,
    live_step_generation: 0L,
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
  if self.running || self.pending_dirty_stage is Some(_) ||
    self.completed ||
    self.suspended ||
    (self.inflight is Some(_) && !self.resume_pre_dispatch) || self.owned_delivery is Some(_) || self.pending_direct is Some(_) || self.pending_host_receipt is Some(_) ||
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
/// Apply a text record only after reserving its original action ownership.
/// Every fallible step leaves either the untouched inflight record or its
/// applied delivery and extracted action on this owner.
fn SettingsRunOwner::deliver_owned_observation(
  self : SettingsRunOwner, event : @text_host.TextInputEvent,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if self.owned_delivery is Some(_) {
    return Err(runner_error("ordered_text", "another owned delivery is unresolved"))
  }
  let owner = match self.terminal_owner {
    Some(value) => value
    None => return Err(runner_error("ordered_text", "original owner unavailable"))
  }
  let receipt = match self.mounted.reserve_owned_text(owner, event) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if receipt.before_document() != self.settings.name() {
    return Err(runner_error("ordered_text", "field and model do not share the original value"))
  }
  self.owned_model_before = Some(self.settings)
  self.owned_model_fence = Some(self.model_fence)
  self.owned_delivery = Some(receipt)
  match self.mounted.apply_owned_text(receipt) {
    Err(error) => {
      if receipt.applied() {
        self.note_text_receipt_stage(event, ReceiptSessionApplied)
        if receipt.action_required() is Some(true) {
          self.note_text_receipt_stage(event, ReceiptActionRequired)
        }
      }
      return Err(error)
    }
    Ok(_) => ()
  }
  self.complete_owned_delivery(receipt, event)
}

///|
fn SettingsRunOwner::complete_owned_delivery(
  self : SettingsRunOwner, receipt : @ui.OwnedTextDelivery, event : @text_host.TextInputEvent,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if !receipt.applied() {
    return Err(runner_error("ordered_text", "unapplied delivery needs separate policy"))
  }
  match (self.owned_model_before, self.owned_model_fence) {
    (Some(before), Some(fence)) if fence.live && before == self.settings && before.name() == receipt.before_document() => ()
    _ => return Err(runner_error("ordered_text", "original model changed during owned delivery"))
  }
  if receipt.action_required() is None {
    match self.mounted.complete_owned_text_evidence(receipt) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  self.note_text_receipt_stage(event, ReceiptSessionApplied)
  if receipt.action_required() is Some(true) {
    self.note_text_receipt_stage(event, ReceiptActionRequired)
  }
  if !receipt.owner_noted() {
    match self.mounted.note_owned_text(receipt) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  if receipt.action_required() is Some(false) {
    self.note_text_receipt_stage(event, ReceiptNoModelAction)
  }
  if receipt.action_required() is Some(true) && !receipt.model_applied() {
    let action = match self.mounted.owned_text_action(receipt) {
      Ok(Some(value)) => value
      Ok(None) => return Err(runner_error("ordered_text", "owned model action unavailable"))
      Err(error) => return Err(error)
    }
    let next = self.settings.update(@shared_settings.Ui(action))
    match action {
      @view.TextChanged(key, value) if key == @shared_settings.settings_name() && next.name() == value => ()
      _ => return Err(runner_error("ordered_text", "owned action does not update the original model field"))
    }
    match self.mounted.mark_owned_text_model_applied(receipt) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    self.replace_settings(next)
    self.note_text_receipt_stage(event, ReceiptModelApplied)
  }
  self.owned_delivery = None
  self.owned_model_before = None
  self.owned_model_fence = None
  Ok(())
}

///|
/// Complete an already-applied owned record at most once. This bounded step
/// publishes no scene or host geometry and never stops the host.
pub fn SettingsRunOwner::reconcile_owned_delivery(
  self : SettingsRunOwner,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if !self.suspended || self.running || self.pending_dirty_stage is Some(_) || self.cutoff_done ||
    self.pending_host_receipt is Some(_) || self.receipt_pre_dispatch is Some(_) {
    return Err(runner_error("ordered_text", "owned delivery is unavailable"))
  }
  let receipt = match self.owned_delivery {
    Some(value) => value
    None => return Err(runner_error("ordered_text", "no owned delivery"))
  }
  let event = match self.inflight {
    Some(OrderedText(value)) => value
    _ => return Err(runner_error("ordered_text", "original inflight text is unavailable"))
  }
  let (window, epoch, binding, _, sequence) = receipt.identity()
  let original = receipt.event()
  let session = match self.session { Some(value) => value; None => return Err(runner_error("ordered_text", "original session is unavailable")) }
  if window != self.window || epoch != session.epoch || binding != session.binding ||
    event.window() != window || event.epoch() != epoch || event.sequence() != sequence ||
    original.window() != window || original.epoch() != epoch || original.sequence() != sequence ||
    !same_text_observation_kind(event.kind(), original.kind()) {
    return Err(runner_error("ordered_text", "owned delivery identity changed"))
  }
  self.running = true
  let result = self.complete_owned_delivery(receipt, event)
  self.running = false
  match result {
    Err(error) => Err(error)
    Ok(_) => {
      self.inflight = None
      self.dirty = true
      Ok(())
    }
  }
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
            self.replace_settings(next)
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
        if !self.resume_pre_dispatch { match (self.held_tab, self.session) {
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
        } }
        if event is None {
          let ingress = if self.resume_pre_dispatch {
            self.resume_pre_dispatch = false
            self.receipt_pre_dispatch = None
            self.inflight
          } else if self.held_tab is None &&
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
            if ordered.peek is Some(_) && self.acknowledged_receipts.length() >= 64 {
              self.ledger_backpressure = true
              return Err(runner_error("ordered_text", "receipt ledger is full"))
            }
            match ordered.peek {
              None => match (ordered.next)(16) {
                Err(error) => return Err(error)
                Ok(value) => value
              }
              Some(peek) => match peek(16) {
                Err(error) => return Err(error)
                Ok(None) => None
                Ok(Some(receipt)) => {
                  let receipt = if receipt.edit_key_epoch is Some(_) && self.session is None {
                    { ..receipt, edit_key_epoch: None }
                  } else { receipt }
                  self.pending_host_receipt = Some(receipt)
                  self.inflight = receipt.event
                  self.receipt_pre_dispatch = Some(receipt)
                  if receipt.direct is Some(_) || receipt.edit_key_epoch is Some(_) {
                    if !gate.input_ready() || self.held_tab is Some(_) ||
                      !self.buffered.is_empty() || !self.held_platform.is_empty() {
                      return Err(runner_error("ordered_text", "direct head awaits the original presented prefix"))
                    }
                    match self.reserve_pending_direct(receipt) {
                      Err(error) => return Err(error)
                      Ok(_) => self.dirty = true
                    }
                  }
                  if self.retained_destroyed_prefix is None &&
                    receipt.event is Some(OrderedPlatform(value)) && value.kind() is @platform.Destroyed {
                    self.retained_destroyed_prefix = Some(self.buffered.length())
                  }
                  match receipt.event {
                    None if receipt.entered is Some(_) =>
                      match self.own_entered(receipt) {
                        Ok(_) => ()
                        Err(error) => return Err(error)
                      }
                    None => return Err(runner_error("ordered_text", "unsupported receipt requires an explicit policy"))
                    Some(_) => ()
                  }
                  match self.ack_owned_receipt() {
                    Err(error) => return Err(error)
                    Ok(_) => {
                      self.receipt_pre_dispatch = None
                      if receipt.direct is Some(_) || receipt.edit_key_epoch is Some(_) {
                        match self.complete_pending_direct() {
                          Err(error) => return Err(error)
                          Ok(_) => None
                        }
                      } else { receipt.event }
                    }
                  }
                }
              }
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
                    if self.held_tab is Some(_) {
                      match mounted.held_text_input(current.epoch, observation) {
                        Err(error) => return Err(error)
                        Ok(false) => return Err(runner_error("ordered_text", "held observation was not applied"))
                        Ok(true) => self.note_text_receipt_stage(observation, ReceiptSessionApplied)
                      }
                      while mounted.next_action() is Some(action) {
                        self.replace_settings(self.settings.update(@shared_settings.Ui(action)))
                      }
                    } else {
                      match self.deliver_owned_observation(observation) {
                        Err(error) => return Err(error)
                        Ok(_) => ()
                      }
                    }
                    emit_native_marker(
                      "YAMI_NATIVE_UI_SETTINGS {\"phase\":\"\{text_event_phase(observation.kind())}\",\{text_event_json(observation.kind())},\"epoch\":\{current.epoch}}",
                    )
                    self.dirty = true
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
            if ordered_text is Some(_) && mounted.has_pending_actions() {
              return Err(runner_error("ordered_text", "terminal event cannot discard a pending action"))
            }
            self.destroyed = true
            self.dirty = false
            if ordered_text is Some(_) {
              gate.invalidate_layout(self.pending_frame is Some(_))
              mounted.invalidate_layout()
            }
          }
          @platform.Resized(..) | @platform.ScaleChanged => {
            if ordered_text is Some(_) && mounted.has_pending_actions() {
              return Err(runner_error("ordered_text", "layout invalidation cannot discard a pending action"))
            }
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
                  self.complete_frame_publication()
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
            if !focused && ordered_text is Some(_) && mounted.has_pending_actions() {
              return Err(runner_error("ordered_text", "focus loss cannot discard a pending action"))
            }
            let handled = mounted.handle_event(value)
            if ordered_text is Some(_) {
              match handled {
                Err(error) => return Err(error)
                Ok(false) => return Err(runner_error("ordered_text", "focus event was not accepted"))
                Ok(true) => ()
              }
            }
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
            if ordered_text is Some(_) && self.session is Some(_) && input is @primitives.TextInput(..) {
              // A platform TextInput is not an IME commit. The regular
              // Mounted path changes the field without advancing the captured
              // TextSession lease, and may reject it during preedit. Keep the
              // original in-flight receipt until an owner-bound direct Insert
              // delivery exists; never synthesize a commit or cancel here.
              return Err(runner_error("ordered_text", "direct text requires owned Insert delivery"))
            }
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
              if self.bounded_resume { return Ok(()) }
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
            let pointer_move = input is @primitives.PointerMoved(..)
            let prior_input_sequence = mounted.last_dispatched_input_sequence()
            if ordered_text is Some(_) && pointer_move && mounted.has_pending_actions() {
              return Err(runner_error("ordered_text", "pointer move cannot overtake a pending action"))
            }
            let handled = mounted.handle_event(value)
            if ordered_text is Some(_) && pointer_move {
              match handled {
                Err(error) => return Err(error)
                Ok(_) => ()
              }
              if prior_input_sequence >= value.sequence() ||
                mounted.last_dispatched_input_sequence() != value.sequence() ||
                mounted.has_pending_actions() {
                return Err(runner_error("ordered_text", "pointer move dispatch is unresolved"))
              }
            }
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
    match event {
      Some(value) if value.window() == window => self.note_handled_platform(value)
      _ => ()
    }
    if ordered_text is Some(_) && self.destroyed {
      return Err(runner_error("ordered_text", "terminal event requires retained cleanup"))
    }
    self.inflight = None
    if self.bounded_resume { return Ok(()) }
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
          self.replace_settings(next)
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
          self.replace_settings(next)
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
                match (match port.begin_with_state {
                  None => (port.begin)(window, state.binding_id())
                  Some(begin) => begin(window, state.binding_id(), @text_host.TextInputState::new(
                    state.document(), settings_caret(state.caret()),
                  ))
                }) {
                  Err(error) => {
                    // A retained begin may have installed a native binding even
                    // when it reports failure; fallback would abandon that owner.
                    if port.begin_with_state is Some(_) { return Err(error) }
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
                      self.host_epoch_verified = true
                      self.terminal_owner = Some(match mounted.capture_terminal_text_owner(epoch) {
                        Err(error) => return Err(error)
                        Ok(value) => value
                      })
                      self.host_epoch_verified = false
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
                          self.host_epoch_verified = true
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
                        let transport = settings_transport_label(platform, port)
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
                  if ordered_text is Some(_) {
                    self.host_epoch_verified = false
                  }
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
                    self.host_epoch_verified = true
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
      let presentation = match ordered_text {
        Some(ordered) if ordered.peek is Some(_) && platform is Linux =>
          self.present_with_frame_publication(frame, fn(w, snapshot) { host.present(w, snapshot) })
        _ => host.present(window, frame.snapshot())
      }
      match presentation {
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
          self.replace_settings(self.settings.update(@shared_settings.SaveFinished))
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
