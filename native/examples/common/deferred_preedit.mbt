///|
/// True only for a retained intent that must wait for the original IME
/// composition to resolve. This does not authorize reordering any other key.
fn is_deferred_preedit_intent(event : @platform.Event) -> Bool {
  match event.kind() {
    @platform.Input(
      @primitives.KeyPressed(key=@primitives.Tab, modifiers~, repeat=false)
    ) => !modifiers.control() && !modifiers.alt() && !modifiers.meta()
    @platform.FocusChanged(false) => true
    _ => false
  }
}

///|
fn same_deferred_preedit_intent(
  a : @platform.Event,
  b : @platform.Event,
) -> Bool {
  if a.window() != b.window() ||
    a.sequence() != b.sequence() ||
    a.scale() != b.scale() {
    return false
  }
  match (a.kind(), b.kind()) {
    (
      @platform.Input(
        @primitives.KeyPressed(key=@primitives.Tab, modifiers=x, repeat=false)
      ),
      @platform.Input(
        @primitives.KeyPressed(key=@primitives.Tab, modifiers=y, repeat=false)
      ),
    ) => x == y
    (@platform.FocusChanged(false), @platform.FocusChanged(false)) => true
    _ => false
  }
}

///|
/// The original admitted intent and its acknowledged native receipt remain
/// owned throughout this operation. Focus, scene, native cutoff and host
/// lifetime are not resolved by this check.
fn SettingsRunOwner::deferred_preedit_owner(self : SettingsRunOwner) -> Bool {
  if !self.suspended ||
    self.running ||
    self.cutoff_done ||
    self.pending_dirty_stage is Some(_) ||
    self.held_tab is Some(_) ||
    !self.held_platform.is_empty() ||
    self.pending_direct is Some(_) ||
    self.receipt_pre_dispatch is Some(_) ||
    !self.host_epoch_verified ||
    self.entered_target is None {
    return false
  }
  let event = match self.inflight {
    Some(OrderedPlatform(value)) if is_deferred_preedit_intent(value) &&
      value.window() == self.window => value
    _ => return false
  }
  // The earlier intent remains the last platform event consumed by this
  // owner. Later FrameCompleted or other platform records must remain queued;
  // otherwise retrying the old intent would be stale and ordering is lost.
  if self.last_sequence != event.sequence() {
    return false
  }
  let session = match self.session {
    Some(value) => value
    None => return false
  }
  let owner = match self.terminal_owner {
    Some(value) => value
    None => return false
  }
  if self.host_epoch != Some(session.epoch) ||
    !owner.matches_session(self.window, session.epoch, session.binding) {
    return false
  }
  let mut matches = 0
  for entry in self.acknowledged_receipts {
    let receipt = entry.receipt
    match receipt.event {
      Some(OrderedPlatform(candidate)) if receipt.window == self.window &&
        receipt.root == session.binding &&
        receipt.epoch == session.epoch &&
        receipt.sequence.to_int64() == event.sequence() &&
        same_deferred_preedit_intent(candidate, event) &&
        entry.stage is ReceiptAcknowledgedOnly => matches += 1
      _ => ()
    }
  }
  matches == 1
}

///|
/// Poll at most once (timeout zero) behind a retained Tab/blur. Only the next
/// original-owner text observation may be taken. A non-text or unsupported
/// native head stays at the host; it is not skipped. The one local slot and
/// bounded receipt ledger are reserved before ACK. A failed ACK keeps both
/// the slot and native receipt for explicit RetryReceiptAck reconciliation.
/// This deliberately postpones the earlier focus intent only to observe an
/// IME preedit update, Commit or Cancel for that same owner. The intent is not
/// applied or retired here. Queue cutoff, scene and finite close remain open.
pub fn SettingsRunOwner::poll_deferred_preedit(
  self : SettingsRunOwner,
) -> Result[SettingsTerminalProgress, @diagnostics.FrameworkError] {
  if !self.deferred_preedit_owner() ||
    self.pending_host_receipt is Some(_) ||
    self.owned_delivery is Some(_) ||
    !self.buffered.is_empty() ||
    self.acknowledged_receipts.length() >= 64 {
    return Err(
      runner_error(
        "deferred_preedit", "owner, bounded slot or receipt ledger unavailable",
      ),
    )
  }
  let owner = match self.terminal_owner {
    Some(value) => value
    None =>
      return Err(runner_error("deferred_preedit", "original owner unavailable"))
  }
  if !self.mounted.terminal_owner_is_current(owner) ||
    !(self.mounted.focused_text() is Some(field) && field.composing()) {
    return Err(runner_error("deferred_preedit", "original preedit unavailable"))
  }
  let ordered = match self.ordered_text {
    Some(value) => value
    None =>
      return Err(runner_error("deferred_preedit", "retained host unavailable"))
  }
  let peek = match ordered.peek {
    Some(value) => value
    None =>
      return Err(runner_error("deferred_preedit", "retained peek unavailable"))
  }
  self.running = true
  let observed = peek(0)
  self.running = false
  let receipt = match observed {
    Err(error) => return Err(error)
    Ok(None) => return Ok(NoRecord)
    Ok(Some(value)) => value
  }
  if !self.deferred_preedit_owner() ||
    self.pending_host_receipt is Some(_) ||
    !self.buffered.is_empty() ||
    self.acknowledged_receipts.length() >= 64 ||
    !self.mounted.terminal_owner_is_current(owner) {
    return Err(runner_error("deferred_preedit", "owner changed during peek"))
  }
  let session = match self.session {
    Some(value) => value
    None => return Err(runner_error("deferred_preedit", "session unavailable"))
  }
  let (_, _, text_sequence) = owner.observed_progress()
  let native_sequence = match self.acknowledged_receipts.last() {
    Some(value) => value.receipt.sequence
    None =>
      return Err(
        runner_error("deferred_preedit", "original receipt unavailable"),
      )
  }
  let event = match receipt.event {
    Some(OrderedText(value)) if receipt.window == self.window &&
      receipt.root == session.binding &&
      receipt.epoch == session.epoch &&
      receipt.entered is None &&
      receipt.direct is None &&
      receipt.edit_key_epoch is None &&
      native_sequence.to_int64() < 2147483647L &&
      receipt.sequence.to_int64() == native_sequence.to_int64() + 1L &&
      text_sequence < 9223372036854775807L &&
      value.window() == self.window &&
      value.epoch() == session.epoch &&
      value.sequence() == text_sequence + 1L &&
      (
        value.kind() is @text_host.Preedit(..) ||
        value.kind() is @text_host.Commit(..) ||
        value.kind() is @text_host.Cancel
      ) => value
    _ =>
      return Err(
        runner_error(
          "deferred_preedit", "next host head is not eligible original text",
        ),
      )
  }
  self.buffered.push(OrderedText(event))
  self.pending_host_receipt = Some(receipt)
  self.running = true
  let ack = self.ack_owned_receipt()
  self.running = false
  match ack {
    Err(error) => Err(error)
    Ok(_) => Ok(RecordBuffered)
  }
}

///|
/// Apply the one already-ACKed observation with the original owned delivery.
/// A measurement/action/model failure keeps the buffered observation and the
/// receipt; applied text is reconciled, never submitted a second time.
pub fn SettingsRunOwner::apply_deferred_preedit(
  self : SettingsRunOwner,
) -> Result[SettingsTerminalProgress, @diagnostics.FrameworkError] {
  if !self.deferred_preedit_owner() ||
    self.pending_host_receipt is Some(_) ||
    self.buffered.length() != 1 {
    return Err(
      runner_error("deferred_preedit", "acknowledged text unavailable"),
    )
  }
  let event = match self.buffered[0] {
    OrderedText(value) => value
    _ =>
      return Err(
        runner_error("deferred_preedit", "nontext prefix remains owned"),
      )
  }
  let session = match self.session {
    Some(value) => value
    None => return Err(runner_error("deferred_preedit", "session unavailable"))
  }
  let owner = match self.terminal_owner {
    Some(value) => value
    None =>
      return Err(runner_error("deferred_preedit", "original owner unavailable"))
  }
  let mut matches = 0
  for entry in self.acknowledged_receipts {
    let receipt = entry.receipt
    match receipt.event {
      Some(OrderedText(value)) if receipt.window == self.window &&
        receipt.root == session.binding &&
        receipt.epoch == session.epoch &&
        value.window() == event.window() &&
        value.epoch() == event.epoch() &&
        value.sequence() == event.sequence() &&
        same_text_observation_kind(value.kind(), event.kind()) => matches += 1
      _ => ()
    }
  }
  if matches != 1 {
    return Err(
      runner_error("deferred_preedit", "original ACK evidence unavailable"),
    )
  }
  let before = self.settings.name()
  self.running = true
  let result = match self.owned_delivery {
    None => self.deliver_owned_observation(event)
    Some(delivery) => {
      let (window, epoch, binding, _, sequence) = delivery.identity()
      let same = window == self.window &&
        epoch == session.epoch &&
        binding == session.binding &&
        sequence == event.sequence() &&
        same_text_observation_kind(delivery.event().kind(), event.kind())
      if !same {
        Err(runner_error("deferred_preedit", "original delivery changed"))
      } else if delivery.applied() {
        self.complete_owned_delivery(delivery, event)
      } else {
        let unchanged = match
          (self.owned_model_before, self.owned_model_fence) {
          (Some(before), Some(fence)) =>
            fence.live &&
            self.settings == before &&
            before.name() == delivery.before_document()
          _ => false
        }
        if !unchanged ||
          !self.mounted.terminal_owner_is_current(owner) ||
          self.mounted.has_pending_actions() {
          Err(runner_error("deferred_preedit", "unapplied owner changed"))
        } else {
          match self.mounted.apply_owned_text(delivery) {
            Err(error) => Err(error)
            Ok(_) => self.complete_owned_delivery(delivery, event)
          }
        }
      }
    }
  }
  self.running = false
  match result {
    Err(error) => Err(error)
    Ok(_) => {
      ignore(self.buffered.remove(0))
      self.dirty = true
      if event.kind() is @text_host.Commit(_) {
        Ok(ModelApplied(event.sequence(), self.settings.name() != before))
      } else {
        Ok(FieldApplied(event.sequence()))
      }
    }
  }
}
