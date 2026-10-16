///|
/// One copied sample Button binding. The Windows projection owns copied
/// semantics only; it does not register a UI Automation provider.
struct WindowsButtonAccessibilityState {
  model : @accessibility.AccessibilityModel?
  projection : @windows_host.AccessibilityProjection?
  source_snapshot : @sample.NativeButtonAccessibilitySnapshot?
  export_id : @windows_host.AccessibilityExportId?
  transport_token : Int64
  next_token : Int64
  closed : Bool
}

///|
struct WindowsButtonAccessibilitySession {
  state : Ref[WindowsButtonAccessibilityState]
}

///|
fn windows_button_accessibility_error(
  operation : String,
  message : String,
) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    @diagnostics.NativeFailure,
    operation,
    subsystem="native-sample-windows-accessibility",
    message~,
  )
}

///|
fn WindowsButtonAccessibilitySession::new() -> WindowsButtonAccessibilitySession {
  {
    state: Ref({
      model: None,
      projection: None,
      source_snapshot: None,
      export_id: None,
      transport_token: 0L,
      next_token: 0L,
      closed: false,
    }),
  }
}

///|
fn WindowsButtonAccessibilitySession::open_projection(
  self : WindowsButtonAccessibilitySession,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let state = self.state.val
  if state.closed {
    return Err(
      windows_button_accessibility_error(
        "windows_button_accessibility", "session is closed",
      ),
    )
  }
  if state.model is Some(_) && state.projection is Some(_) {
    return Ok(())
  }
  let model = match @accessibility.AccessibilityModel::new() {
    Err(_) =>
      return Err(
        windows_button_accessibility_error(
          "windows_button_accessibility", "could not create the sample owner model",
        ),
      )
    Ok(value) => value
  }
  let projection = match @windows_host.AccessibilityProjection::new() {
    Err(_) => {
      model.close()
      return Err(
        windows_button_accessibility_error(
          "windows_button_accessibility", "could not create the Windows copy projection",
        ),
      )
    }
    Ok(value) => value
  }
  self.state.val = { ..state, model: Some(model), projection: Some(projection), }
  Ok(())
}

///|
fn WindowsButtonAccessibilitySession::publish(
  self : WindowsButtonAccessibilitySession,
  existing_token : Int64,
  source : @sample.NativeButtonAccessibilitySnapshot,
) -> Result[Int64, @diagnostics.FrameworkError] {
  match self.open_projection() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let state = self.state.val
  let model = match state.model {
    None =>
      return Err(
        windows_button_accessibility_error(
          "windows_button_accessibility", "sample owner model is unavailable",
        ),
      )
    Some(value) => value
  }
  let projection = match state.projection {
    None =>
      return Err(
        windows_button_accessibility_error(
          "windows_button_accessibility", "Windows copy projection is unavailable",
        ),
      )
    Some(value) => value
  }
  let actions : Array[@accessibility.AccessibilityAction] = if source.enabled() {
    [@accessibility.Invoke]
  } else {
    []
  }
  let spec = @accessibility.NodeSpec::new(
    source.id(),
    None,
    @accessibility.Button,
    source.name(),
    source.bounds(),
  ).with_enabled(source.enabled()).with_loading(source.loading()).with_focused(
    source.focused(),
  )
  let spec = match spec.with_actions(actions) {
    Err(_) =>
      return Err(
        windows_button_accessibility_error(
          "windows_button_accessibility", "sample Button actions were rejected",
        ),
      )
    Ok(value) => value
  }
  let semantic_snapshot = match model.publish([spec]) {
    Err(_) =>
      return Err(
        windows_button_accessibility_error(
          "windows_button_accessibility", "sample Button semantics could not be committed",
        ),
      )
    Ok(value) => value
  }
  let copied = match projection.publish(model, semantic_snapshot) {
    Err(_) =>
      return Err(
        windows_button_accessibility_error(
          "windows_button_accessibility", "sample Button copy could not be published",
        ),
      )
    Ok(value) => value
  }
  let mut copied_button : @windows_host.AccessibilityExportId? = None
  for node in copied.nodes() {
    if node.role() == @accessibility.Button &&
      node.name() == source.name() &&
      node.bounds() == source.bounds() {
      copied_button = Some(node.id())
    }
  }
  let export_id = match copied_button {
    None =>
      return Err(
        windows_button_accessibility_error(
          "windows_button_accessibility", "copied Button was absent from the projection",
        ),
      )
    Some(value) => value
  }
  let token = if existing_token > 0L && state.transport_token == existing_token {
    existing_token
  } else {
    if state.next_token >= 0x7fff_ffff_ffff_fffeL {
      return Err(
        windows_button_accessibility_error(
          "windows_button_accessibility", "sample Button token space is exhausted",
        ),
      )
    }
    state.next_token + 1L
  }
  self.state.val = {
    ..state,
    source_snapshot: Some(source),
    export_id: Some(export_id),
    transport_token: token,
    next_token: if token > state.next_token { token } else { state.next_token },
  }
  Ok(token)
}

///|
fn windows_button_snapshots_match(
  left : @sample.NativeButtonAccessibilitySnapshot,
  right : @sample.NativeButtonAccessibilitySnapshot,
) -> Bool {
  left.id() == right.id() &&
  left.name() == right.name() &&
  left.bounds() == right.bounds() &&
  left.enabled() == right.enabled() &&
  left.loading() == right.loading() &&
  left.focused() == right.focused() &&
  left.activations() == right.activations() &&
  left.same_revision(right)
}

///|
fn WindowsButtonAccessibilitySession::snapshot(
  self : WindowsButtonAccessibilitySession,
) -> Result[@windows_host.AccessibilityProjectionSnapshot, @diagnostics.FrameworkError] {
  match self.state.val.projection {
    None =>
      Err(
        windows_button_accessibility_error(
          "windows_button_accessibility", "Windows copy projection is unavailable",
        ),
      )
    Some(projection) =>
      match projection.snapshot() {
        Err(_) =>
          Err(
            windows_button_accessibility_error(
              "windows_button_accessibility", "Windows copy snapshot is unavailable",
            ),
          )
        Ok(snapshot) => Ok(snapshot)
      }
  }
}

///|
/// Validate an exported Invoke through the current projection. The caller
/// still dispatches the effect through NativeSample's App Entity owner.
fn WindowsButtonAccessibilitySession::resolve_invoke(
  self : WindowsButtonAccessibilitySession,
  token : Int64,
  expected : @sample.NativeButtonAccessibilitySnapshot,
) -> Result[Bool, @diagnostics.FrameworkError] {
  let state = self.state.val
  if state.closed || state.transport_token != token || token <= 0L {
    return Ok(false)
  }
  match state.source_snapshot {
    None => return Ok(false)
    Some(current) if !windows_button_snapshots_match(current, expected) =>
      return Ok(false)
    Some(_) => ()
  }
  let projection = match state.projection {
    None => return Ok(false)
    Some(value) => value
  }
  let export_id = match state.export_id {
    None => return Ok(false)
    Some(value) => value
  }
  match projection.resolve_action(export_id, @accessibility.Invoke) {
    Err(_) => Ok(false)
    Ok(intent) =>
      Ok(
        intent.action() == @accessibility.Invoke &&
        intent.node_id().key() == expected.id(),
      )
  }
}

///|
/// Resolve copied semantics, then hand the unchanged owner snapshot back to
/// NativeSample. The sample performs the final live owner/layout check and
/// dispatches the effect through its App Entity.
fn WindowsButtonAccessibilitySession::dispatch_invoke(
  self : WindowsButtonAccessibilitySession,
  sample : @sample.NativeSample,
  token : Int64,
  expected : @sample.NativeButtonAccessibilitySnapshot,
) -> Result[Bool, @diagnostics.FrameworkError] {
  match self.resolve_invoke(token, expected) {
    Err(error) => Err(error)
    Ok(false) => Ok(false)
    Ok(true) => sample.activate_accessibility_button(expected)
  }
}

///|
fn WindowsButtonAccessibilitySession::revoke(
  self : WindowsButtonAccessibilitySession,
  token : Int64,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let state = self.state.val
  if token > 0L && token == state.transport_token {
    match state.projection {
      None => ()
      Some(projection) => projection.close()
    }
    match state.model {
      None => ()
      Some(model) => model.close()
    }
    self.state.val = {
      ..state,
      model: None,
      projection: None,
      source_snapshot: None,
      export_id: None,
      transport_token: 0L,
    }
  }
  Ok(())
}

///|
fn WindowsButtonAccessibilitySession::port(
  self : WindowsButtonAccessibilitySession,
) -> @common.NativeButtonAXPort {
  let publish : @common.NativeButtonAXPublish = fn(
    _window,
    existing_token,
    snapshot,
  ) {
    self.publish(existing_token, snapshot)
  }
  let revoke : @common.NativeButtonAXRevoke = fn(_window, token) {
    self.revoke(token)
  }
  // UI Automation transport is not implemented, so the host cannot issue
  // accessibility requests on Windows yet.
  let take_request : @common.NativeButtonAXTakeRequest = fn(_window) {
    Ok(None)
  }
  @common.NativeButtonAXPort::new(publish, revoke, take_request)
}

///|
fn WindowsButtonAccessibilitySession::close(
  self : WindowsButtonAccessibilitySession,
) -> Unit {
  let state = self.state.val
  match state.projection {
    None => ()
    Some(projection) => projection.close()
  }
  match state.model {
    None => ()
    Some(model) => model.close()
  }
  self.state.val = {
    ..state,
    model: None,
    projection: None,
    source_snapshot: None,
    export_id: None,
    transport_token: 0L,
    closed: true,
  }
}

///|
fn windows_button_accessibility_sample(
  disabled? : Bool = false,
) -> @sample.NativeSample raise {
  match @sample.NativeSample::new(disabled~) {
    Err(_) => fail("Windows sample should initialize")
    Ok(sample) =>
      match sample.render(800.0, 600.0, 1.0, windows_measure) {
        Err(_) => fail("Windows sample should render")
        Ok(_) => sample
      }
  }
}

///|
test "Windows Button copy resolves only its current sample owner and generation" {
  let sample = windows_button_accessibility_sample()
  let source = match sample.button_accessibility_snapshot() {
    Err(_) => fail("rendered Windows Button should expose its snapshot")
    Ok(None) => fail("rendered Windows Button should remain available")
    Ok(Some(value)) => value
  }
  let session = WindowsButtonAccessibilitySession::new()
  let token = match session.publish(0L, source) {
    Err(_) => fail("Windows Button snapshot should copy into the projection")
    Ok(value) => value
  }
  assert_true(token > 0L)
  let copied = match session.snapshot() {
    Err(_) => fail("Windows projection should expose its copied snapshot")
    Ok(value) => value
  }
  assert_eq(copied.nodes().length(), 1)
  let copied_button = copied.nodes()[0]
  assert_true(copied_button.role() == @accessibility.Button)
  assert_eq(copied_button.name(), source.name())
  assert_true(copied_button.bounds() == source.bounds())
  assert_true(copied_button.is_enabled())
  assert_true(!copied_button.is_loading())
  let copied_actions = copied_button.supported_actions()
  assert_true(copied_actions.length() == 1)
  assert_true(copied_actions[0] == @accessibility.Invoke)
  let foreign_sample = windows_button_accessibility_sample()
  let foreign_source = match foreign_sample.button_accessibility_snapshot() {
    Err(_) => fail("other sample should expose its independent Button owner")
    Ok(None) => fail("other sample Button should remain available")
    Ok(Some(value)) => value
  }
  assert_true(session.dispatch_invoke(foreign_sample, token, foreign_source) is Ok(false))
  assert_true(foreign_sample.count() is Ok(0))
  assert_true(session.dispatch_invoke(sample, token, source) is Ok(true))
  assert_true(sample.count() is Ok(1))

  let updated = match sample.button_accessibility_snapshot() {
    Err(_) => fail("updated Windows Button should expose its snapshot")
    Ok(None) => fail("updated Windows Button should remain available")
    Ok(Some(value)) => value
  }
  match session.publish(token, updated) {
    Err(_) => fail("updated sample Button should keep its current binding")
    Ok(updated_token) => assert_true(updated_token == token)
  }
  assert_true(session.dispatch_invoke(sample, token, source) is Ok(false))
  assert_true(session.dispatch_invoke(sample, token, updated) is Ok(true))
  assert_true(sample.count() is Ok(2))

  sample.invalidate_layout()
  // Even if the copied projection has not yet been revoked, the original
  // sample owner rejects its now-stale layout generation before the effect.
  assert_true(session.dispatch_invoke(sample, token, updated) is Ok(false))
  assert_true(sample.count() is Ok(2))
  assert_true(session.revoke(token) is Ok(_))
  assert_true(session.resolve_invoke(token, updated) is Ok(false))

  match sample.render(800.0, 600.0, 1.0, windows_measure) {
    Err(_) => fail("sample should render a fresh post-invalidation layout")
    Ok(_) => ()
  }
  let current = match sample.button_accessibility_snapshot() {
    Err(_) => fail("fresh Windows Button should expose its snapshot")
    Ok(None) => fail("fresh Windows Button should remain available")
    Ok(Some(value)) => value
  }
  let fresh_token = match session.publish(0L, current) {
    Err(_) => fail("session should republish after revocation")
    Ok(value) => value
  }
  assert_true(fresh_token > token)
  assert_true(session.resolve_invoke(token, current) is Ok(false))
  assert_true(session.dispatch_invoke(sample, fresh_token, current) is Ok(true))
  assert_true(sample.count() is Ok(3))
  session.close()
  assert_true(session.resolve_invoke(fresh_token, current) is Ok(false))
  match session.publish(0L, current) {
    Err(_) => ()
    Ok(_) => fail("closed Windows Button session must reject republish")
  }
}

///|
test "disabled Windows Button projection omits Invoke and keeps the sample owner unchanged" {
  let sample = windows_button_accessibility_sample(disabled=true)
  let source = match sample.button_accessibility_snapshot() {
    Err(_) => fail("disabled Windows Button should expose its snapshot")
    Ok(None) => fail("disabled Windows Button should remain projectable")
    Ok(Some(value)) => value
  }
  let session = WindowsButtonAccessibilitySession::new()
  let token = match session.publish(0L, source) {
    Err(_) => fail("disabled Windows Button should copy into the projection")
    Ok(value) => value
  }
  assert_true(!source.enabled())
  let copied = match session.snapshot() {
    Err(_) => fail("disabled Windows projection should expose its snapshot")
    Ok(value) => value
  }
  let copied_button = copied.nodes()[0]
  assert_true(!copied_button.is_enabled())
  assert_true(copied_button.supported_actions().length() == 0)
  assert_true(session.resolve_invoke(token, source) is Ok(false))
  assert_true(session.dispatch_invoke(sample, token, source) is Ok(false))
  assert_true(sample.activate_accessibility_button(source) is Ok(false))
  assert_true(sample.count() is Ok(0))
  session.close()
}

///|
test "Windows projection preserves loading and rejects removed or closed nodes" {
  let model = match @accessibility.AccessibilityModel::new() {
    Err(_) => fail("Windows test accessibility model should initialize")
    Ok(value) => value
  }
  let projection = match @windows_host.AccessibilityProjection::new() {
    Err(_) => fail("Windows copied projection should initialize")
    Ok(value) => value
  }
  let bounds = match @primitives.Rect::new(10.0, 12.0, 80.0, 24.0) {
    Err(_) => fail("loading Button bounds should be valid")
    Ok(value) => value
  }
  let root_spec = @accessibility.NodeSpec::new(
    1UL,
    None,
    @accessibility.Window,
    "Window",
    bounds,
  )
  let loading_spec = @accessibility.NodeSpec::new(
    2UL,
    Some(1UL),
    @accessibility.Button,
    "Loading",
    bounds,
  ).with_loading(true)
  let loading_spec = match loading_spec.with_actions([@accessibility.Invoke]) {
    Err(_) => fail("loading Button should accept its Invoke action")
    Ok(value) => value
  }
  let loading_source = match model.publish([root_spec, loading_spec]) {
    Err(_) => fail("loading Button semantics should publish")
    Ok(value) => value
  }
  let loading_copy = match projection.publish(model, loading_source) {
    Err(_) => fail("loading Button should copy to Windows projection")
    Ok(value) => value
  }
  let loading_nodes = loading_copy.nodes()
  assert_true(loading_nodes.length() == 2)
  let loading_node = loading_nodes[1]
  let removed_id = loading_node.id()
  assert_true(loading_node.is_loading())
  assert_true(loading_node.is_enabled())
  assert_true(loading_node.supported_actions() == [@accessibility.Invoke])
  assert_true(projection.resolve_action(removed_id, @accessibility.Invoke) is Err(_))

  let removed_source = match model.publish([root_spec]) {
    Err(_) => fail("removing the loading Button should publish")
    Ok(value) => value
  }
  let removed_copy = match projection.publish(model, removed_source) {
    Err(_) => fail("Windows projection should publish the removed Button")
    Ok(value) => value
  }
  assert_true(removed_copy.nodes().length() == 1)
  assert_true(projection.resolve_action(removed_id, @accessibility.Invoke) is Err(_))
  projection.close()
  assert_true(projection.snapshot() is Err(_))
  assert_true(projection.resolve_action(removed_id, @accessibility.Invoke) is Err(_))
  model.close()
}
