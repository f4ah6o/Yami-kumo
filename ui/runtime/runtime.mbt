///|
/// Private capabilities avoid global counters, overflow and caller-forged IDs.
/// Identity uses observable mutable aliasing, independently of live state.
priv struct Identity {
  mut live : Bool
  mut marker : Bool
}

///|
fn fresh_identity() -> Identity {
  { live: true, marker: false, }
}

///|
/// UI-owner-thread only. No callbacks, suspension or user code can run between
/// these marker accesses. Restore both original markers before returning;
/// comparing either live or disposed capabilities never changes their liveness.
/// physical_equal is only an optimization hint, not a semantic identity test.
fn same_identity(left : Identity, right : Identity) -> Bool {
  let left_marker = left.marker
  let right_marker = right.marker
  left.marker = !right_marker
  let same = right.marker != right_marker
  left.marker = left_marker
  right.marker = right_marker
  same
}

///|
/// An opaque capability for one root and one mount generation. A key alone is
/// never sufficient to submit an event. Tokens can be compared but not forged.
pub struct InstanceToken {
  priv root : Identity
  priv instance : Identity
  priv key : @core.NodeKey
}

///|
pub impl Eq for InstanceToken with fn equal(self, other) {
  same_identity(self.root, other.root) &&
  same_identity(self.instance, other.instance)
}

///|
pub fn InstanceToken::key(self : InstanceToken) -> @core.NodeKey {
  self.key
}

///|
priv struct Entry {
  view : @core.View
  token : InstanceToken
  gate : Identity
}

///|
priv struct PendingAction {
  token : InstanceToken
  gate : Identity
  action : @core.SemanticAction
}

///|
pub(all) enum CommitError {
  EmptyKey
  DuplicateKey(@core.NodeKey)
  Disposed
} derive(Eq, @debug.Debug)

///|
pub(all) enum RequestError {
  Disposed
  StaleToken
  NotFocusable
  Unavailable
} derive(Eq, @debug.Debug)

///|
/// An opaque, single-use focus request. The host must report the actual result
/// using complete_focus, rather than treating this request as success.
pub struct FocusRequest {
  priv target : InstanceToken
  priv gate : Identity
  priv request : Identity
}

///|
pub fn FocusRequest::target(self : FocusRequest) -> InstanceToken {
  self.target
}

///|
pub struct FocusResult {
  priv key : @core.NodeKey
  priv outcome : @core.FocusOutcome
}

///|
pub fn FocusResult::key(self : FocusResult) -> @core.NodeKey {
  self.key
}

///|
pub fn FocusResult::outcome(self : FocusResult) -> @core.FocusOutcome {
  self.outcome
}

///|
priv struct PendingFocusResult {
  request : FocusRequest
  outcome : @core.FocusOutcome
}

///|
/// Bounded keyed lifecycle runtime. It owns instance/request lifetime, not the
/// application's model. Host callbacks only enqueue; the application explicitly
/// drains actions and commits its next view, so callbacks cannot reenter update.
/// All access and token comparisons are confined to the owning UI thread.
pub struct Runtime {
  priv root : Identity
  priv mut tree : @core.View?
  priv mut entries : Array[Entry]
  priv actions : Array[PendingAction]
  priv focus_requests : Array[FocusRequest]
  priv focus_results : Array[PendingFocusResult]
}

///|
pub fn Runtime::new() -> Runtime {
  {
    root: fresh_identity(),
    tree: None,
    entries: [],
    actions: [],
    focus_requests: [],
    focus_results: [],
  }
}

///|
pub fn Runtime::is_disposed(self : Runtime) -> Bool {
  !self.root.live
}

///|
pub fn Runtime::view(self : Runtime) -> @core.View? {
  self.tree
}

///|
fn find_entry(entries : Array[Entry], key : @core.NodeKey) -> Entry? {
  for entry in entries {
    if entry.view.key() == key {
      return Some(entry)
    }
  }
  None
}

///|
fn validate_tree(
  view : @core.View,
  nodes : Array[@core.View],
) -> Result[Unit, CommitError] {
  let key = view.key()
  if key.value().is_empty() {
    return Err(EmptyKey)
  }
  for prior in nodes {
    if prior.key() == key {
      return Err(DuplicateKey(key))
    }
  }
  nodes.push(view)
  for child in view.children() {
    match validate_tree(child, nodes) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
/// Validate the whole tree first, then atomically publish a new snapshot.
/// Every key is root-wide, including nested containers. Same key and kind keep
/// their instance across reorder/reparent/prop edits. Type replacement and
/// removal invalidate the old token permanently, even after reinsertion.
pub fn Runtime::commit(
  self : Runtime,
  view : @core.View,
) -> Result[Unit, CommitError] {
  if self.is_disposed() {
    return Err(CommitError::Disposed)
  }
  let nodes = []
  match validate_tree(view, nodes) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let next : Array[Entry] = []
  for node in nodes {
    match find_entry(self.entries, node.key()) {
      Some(previous) if previous.view.kind() == node.kind() => {
        // A gate change cancels already-queued input, including the sequence
        // enabled -> disabled/loading -> enabled before the queue is drained.
        let same_gate = previous.view.disabled() == node.disabled() &&
          previous.view.loading() == node.loading() &&
          previous.view.text_field_revision() == node.text_field_revision() &&
          previous.view.dialog_open() == node.dialog_open()
        next.push({
          view: node,
          token: previous.token,
          gate: if same_gate {
            previous.gate
          } else {
            fresh_identity()
          },
        })
      }
      _ =>
        next.push({
          view: node,
          token: {
            root: self.root,
            instance: fresh_identity(),
            key: node.key(),
          },
          gate: fresh_identity(),
        })
    }
  }
  for previous in self.entries {
    match find_entry(next, previous.view.key()) {
      Some(current) if current.token == previous.token => ()
      _ => previous.token.instance.live = false
    }
  }
  self.entries = next
  self.tree = Some(view)
  Ok(())
}

///|
pub fn Runtime::token(self : Runtime, key : @core.NodeKey) -> InstanceToken? {
  if self.is_disposed() {
    return None
  }
  find_entry(self.entries, key).map(entry => entry.token)
}

///|
pub fn Runtime::is_current(self : Runtime, token : InstanceToken) -> Bool {
  if self.is_disposed() ||
    !same_identity(self.root, token.root) ||
    !token.instance.live {
    return false
  }
  match find_entry(self.entries, token.key) {
    Some(entry) => entry.token == token
    None => false
  }
}

///|
fn Runtime::active_entry(self : Runtime, token : InstanceToken) -> Entry? {
  if !self.is_current(token) {
    return None
  }
  find_entry(self.entries, token.key)
}

///|
fn available_button(entry : Entry) -> Bool {
  entry.view.kind() == @core.Button &&
  !entry.view.disabled() &&
  !entry.view.loading()
}

///|
fn available_text_field(entry : Entry) -> Bool {
  if entry.view.kind() != @core.TextField || entry.view.disabled() {
    return false
  }
  match entry.view.text_field_props() {
    Some(props) => !props.read_only()
    None => false
  }
}

///|
fn available_dialog(entry : Entry) -> Bool {
  entry.view.kind() == @core.Dialog && entry.view.dialog_open()
}

///|
fn available_action(entry : Entry, action : @core.SemanticAction) -> Bool {
  match action {
    Activate(_) => available_button(entry)
    TextChanged(_, _) | Submitted(_) => available_text_field(entry)
    Dismissed(_) | Confirmed(_) => available_dialog(entry)
  }
}

///|
/// Accept normalized activation only; native controls and real DOM button click
/// are the host's entry points. Disabled/loading is checked again at delivery.
pub fn Runtime::enqueue_activate(self : Runtime, token : InstanceToken) -> Bool {
  match self.active_entry(token) {
    Some(entry) if available_button(entry) => {
      self.actions.push({
        token,
        gate: entry.gate,
        action: @core.Activate(token.key()),
      })
      true
    }
    _ => false
  }
}

///|
/// Queue one committed TextField value. Disabled/read-only is rechecked at
/// delivery; a revision change invalidates the queued action.
pub fn Runtime::enqueue_text_changed(
  self : Runtime,
  token : InstanceToken,
  value : String,
) -> Bool {
  match self.active_entry(token) {
    Some(entry) if available_text_field(entry) => {
      self.actions.push({
        token,
        gate: entry.gate,
        action: @core.TextChanged(token.key(), value),
      })
      true
    }
    _ => false
  }
}

///|
/// Queue a submit request for a TextField. Focus loss does not imply submit.
pub fn Runtime::enqueue_submitted(
  self : Runtime,
  token : InstanceToken,
) -> Bool {
  match self.active_entry(token) {
    Some(entry) if available_text_field(entry) => {
      self.actions.push({
        token,
        gate: entry.gate,
        action: @core.Submitted(token.key()),
      })
      true
    }
    _ => false
  }
}

///|
/// Queue a dismiss request for the current open Dialog. The application still
/// owns the next `open` value.
pub fn Runtime::enqueue_dismissed(self : Runtime, token : InstanceToken) -> Bool {
  match self.active_entry(token) {
    Some(entry) if available_dialog(entry) => {
      self.actions.push({
        token,
        gate: entry.gate,
        action: @core.Dismissed(token.key()),
      })
      true
    }
    _ => false
  }
}

///|
/// Queue a confirm request for the current open Dialog.
pub fn Runtime::enqueue_confirmed(self : Runtime, token : InstanceToken) -> Bool {
  match self.active_entry(token) {
    Some(entry) if available_dialog(entry) => {
      self.actions.push({
        token,
        gate: entry.gate,
        action: @core.Confirmed(token.key()),
      })
      true
    }
    _ => false
  }
}

///|
/// Drain one still-current semantic action in FIFO order, skipping cancelled
/// entries. No application callbacks run inside the runtime. Draining one at a
/// time lets the model owner commit disabled/loading/revision before the next
/// action.
pub fn Runtime::next_action(self : Runtime) -> @core.SemanticAction? {
  while !self.actions.is_empty() {
    let pending = self.actions.remove(0)
    match self.active_entry(pending.token) {
      Some(entry) if available_action(entry, pending.action) &&
        same_identity(entry.gate, pending.gate) => return Some(pending.action)
      _ => ()
    }
  }
  None
}

///|
/// A newer focus request supersedes every older request in this root. The host
/// is responsible for synchronous gesture eligibility before issuing requests.
pub fn Runtime::request_focus(
  self : Runtime,
  token : InstanceToken,
) -> Result[FocusRequest, RequestError] {
  if self.is_disposed() {
    return Err(RequestError::Disposed)
  }
  let entry = match self.active_entry(token) {
    Some(entry) => entry
    None => return Err(StaleToken)
  }
  if entry.view.kind() != @core.Button && entry.view.kind() != @core.TextField {
    return Err(NotFocusable)
  }
  if entry.view.kind() == @core.Button {
    if !available_button(entry) {
      return Err(Unavailable)
    }
  } else if entry.view.disabled() {
    return Err(Unavailable)
  }
  for request in self.focus_requests {
    request.request.live = false
  }
  self.focus_requests.clear()
  self.focus_results.clear()
  let request = { target: token, gate: entry.gate, request: fresh_identity(), }
  self.focus_requests.push(request)
  Ok(request)
}

///|
/// Complete a pending request once. Stale, cross-root, superseded and disposed
/// completions are rejected without producing an observation.
pub fn Runtime::complete_focus(
  self : Runtime,
  request : FocusRequest,
  outcome : @core.FocusOutcome,
) -> Bool {
  if !request.request.live {
    return false
  }
  match self.active_entry(request.target) {
    Some(entry) if available_button(entry) &&
      same_identity(entry.gate, request.gate) => {
      let mut owned = false
      for pending in self.focus_requests {
        if same_identity(pending.request, request.request) {
          owned = true
        }
      }
      if !owned {
        return false
      }
      request.request.live = false
      self.focus_requests.clear()
      self.focus_results.push({ request, outcome, })
      true
    }
    _ => false
  }
}

///|
/// Focus observations are separate from application activation. Pending
/// observations are also checked for stale mount and availability at delivery.
pub fn Runtime::next_focus_result(self : Runtime) -> FocusResult? {
  while !self.focus_results.is_empty() {
    let pending = self.focus_results.remove(0)
    match self.active_entry(pending.request.target) {
      Some(entry) if available_button(entry) &&
        same_identity(entry.gate, pending.request.gate) =>
        return Some({
          key: pending.request.target.key,
          outcome: pending.outcome,
        })
      _ => ()
    }
  }
  None
}

///|
/// Idempotently release all runtime-held trees, queued events and requests.
/// The adapter must also remove its own listeners/timers/observers on disposal.
pub fn Runtime::dispose(self : Runtime) -> Unit {
  if self.is_disposed() {
    return
  }
  self.root.live = false
  for entry in self.entries {
    entry.token.instance.live = false
  }
  for request in self.focus_requests {
    request.request.live = false
  }
  self.tree = None
  self.entries.clear()
  self.actions.clear()
  self.focus_requests.clear()
  self.focus_results.clear()
}

///|
pub extend CommitError with Eq::{equal, not_equal}

///|
pub extend CommitError with @debug.Debug::{to_repr}

///|
pub extend RequestError with Eq::{equal, not_equal}

///|
pub extend RequestError with @debug.Debug::{to_repr}

///|
pub extend InstanceToken with Eq::{equal, not_equal}
