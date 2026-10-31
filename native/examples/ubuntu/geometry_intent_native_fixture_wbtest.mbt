///|
/// GPUI fixture-only shim provides a real native FIFO and mocked Wayland
/// requests. It is not a real compositor, live IME or product dependency.
test "closed adapter keeps exact intent across native FIFO handoff" {
  ignore(@linux_text.require_grayscale_raster())
  let initial = @text_host.TextInputState::new(
    @text.TextDocument::new("old").unwrap(),
    @primitives.Rect::new(1.0, 2.0, 1.0, 18.0).unwrap(),
  )
  let route = @ubuntu_host.fixture_intent_route(initial, @platform.WindowId::new(51L), 9UL)
  let epoch = route.binding_epoch().unwrap()
  let native_epoch = route.native_epoch().unwrap()
  let state = @text_host.TextInputState::new(
    @text.TextDocument::new("old").unwrap(),
    @primitives.Rect::new(5.0, 2.0, 1.0, 18.0).unwrap(),
  )
  let adapter : SettingsGeometryAdapter = {
    route, window: @platform.WindowId::new(51L), root: 9UL, epoch, native_epoch,
    state, intent: None, reserve_rejected: false, receipt: None,
  }
  @ubuntu_host.fixture_intent_commit()
  assert_true(adapter.attempt(false, state) is Err(_))
  let intent = adapter.intent.unwrap()
  assert_true(route.geometry_intent_stage(intent) is Some(@ubuntu_host.GeometryIntentNotSubmitted))
  let original = route.peek().unwrap().unwrap()
  let arrival = SettingsGeometryArrivalAdapter::new(route, original).unwrap()
  arrival.transfer().unwrap()
  arrival.inspect_owned().unwrap()
  assert_true(route.owned_geometry_text() is Some(_))
  adapter.attempt(true, state).unwrap()
  assert_true(route.geometry_intent_stage(intent) is None)
  assert_true(route.geometry_receipt_is_current(adapter.receipt.unwrap()))
  assert_true(route.owned_geometry_text() is Some(_))
  assert_true(adapter.attempt(true, state) is Err(_))
  assert_true(route.try_end_when_drained(epoch) is Err(_))
  @ubuntu_host.fixture_intent_finish()
}

///|
/// Connects the original synthetic consumer owner to a real native FIFO and
/// route with mocked protocol. Record application and scene are not exercised.
test "original owner reserves before native intent handoff and retry" {
  let (owner, root) = @common.fixture_intent_owner()
  let initial = @text_host.TextInputState::new(
    @text.TextDocument::new("").unwrap(),
    @primitives.Rect::new(1.0, 2.0, 1.0, 18.0).unwrap(),
  )
  let route = @ubuntu_host.fixture_intent_route(initial, owner.window(), root)
  let epoch = route.binding_epoch().unwrap()
  let native_epoch = route.native_epoch().unwrap()
  @common.fixture_prepare_intent_owner(owner, root, epoch, native_epoch)
  let geometry = owner.staged_dirty_geometry().unwrap()
  let state = ubuntu_text_state(@text_host.TextInputState::new(geometry.committed(), geometry.caret())).unwrap()
  let adapter = SettingsGeometryAdapter::new(route, geometry, state).unwrap()
  @ubuntu_host.fixture_intent_commit()
  assert_true(owner.attempt_staged_host_geometry(fn(retry, candidate) { adapter.attempt(retry, candidate) }) is Err(_))
  let intent = adapter.intent.unwrap()
  assert_true(route.geometry_intent_stage(intent) is Some(@ubuntu_host.GeometryIntentNotSubmitted))
  let original = route.peek().unwrap().unwrap()
  assert_eq(original.native_sequence(), 2)
  let arrival = SettingsGeometryArrivalAdapter::new(route, original).unwrap()
  assert_eq(arrival.portable.sequence(), 1L)
  let receipt = @common.NativeRetainedReceipt::new(
    Some(@common.OrderedText(arrival.portable)), original.native_window(), original.native_sequence(),
    original.root(), original.epoch(), fn() { arrival.transfer() },
  )
  owner.reserve_geometry_arrival(receipt, (arrival.target.epoch, arrival.target.seat, arrival.target.proxy_generation)).unwrap()
  assert_true(route.owned_geometry_text() is None)
  owner.transfer_geometry_arrival().unwrap()
  arrival.inspect_owned().unwrap()
  assert_true(owner.geometry_arrival_state() is Some((2, 2)))
  owner.attempt_staged_host_geometry(fn(retry, candidate) { adapter.attempt(retry, candidate) }).unwrap()
  assert_true(route.geometry_receipt_is_current(adapter.receipt.unwrap()))
  assert_true(route.owned_geometry_text() is Some(_))
  assert_false(owner.host_epoch_verified())
  assert_eq(owner.model().name(), "")
  assert_true(owner.try_terminal_text_cutoff() is Err(_))
  assert_false(owner.can_stop())
  @ubuntu_host.fixture_intent_finish()
}

///|
/// Controlled native getter rejects reservation without native update; the
/// exact same original owner/candidate may retry after fake owner restoration.
test "original owner retries an actually rejected native reservation" {
  let (owner, root) = @common.fixture_intent_owner()
  let initial = @text_host.TextInputState::new(
    @text.TextDocument::new("").unwrap(),
    @primitives.Rect::new(1.0, 2.0, 1.0, 18.0).unwrap(),
  )
  let route = @ubuntu_host.fixture_intent_route(initial, owner.window(), root)
  let epoch = route.binding_epoch().unwrap()
  let native_epoch = route.native_epoch().unwrap()
  @common.fixture_prepare_intent_owner(owner, root, epoch, native_epoch)
  let geometry = owner.staged_dirty_geometry().unwrap()
  let state = ubuntu_text_state(@text_host.TextInputState::new(geometry.committed(), geometry.caret())).unwrap()
  let adapter = SettingsGeometryAdapter::new(route, geometry, state).unwrap()
  @ubuntu_host.fixture_intent_set_requested(0)
  assert_true(owner.attempt_staged_host_geometry(fn(retry, candidate) { adapter.attempt(retry, candidate) }) is Err(_))
  assert_true(adapter.reserve_rejected)
  assert_true(adapter.intent is None)
  assert_true(route.pending_geometry() is None)
  assert_false(owner.host_epoch_verified())
  assert_eq(owner.model().name(), "")
  @ubuntu_host.fixture_intent_set_requested(1)
  owner.attempt_staged_host_geometry(fn(retry, candidate) { adapter.attempt(retry, candidate) }).unwrap()
  assert_false(adapter.reserve_rejected)
  assert_true(adapter.intent is Some(_))
  assert_true(route.geometry_receipt_is_current(adapter.receipt.unwrap()))
  assert_true(owner.discard_staged_dirty_scene() is Err(_))
  assert_false(owner.can_stop())
  @ubuntu_host.fixture_intent_finish()
}

///|
/// Characterization: native FIFO + controlled callbacks, not live IME.
/// The handoff succeeds but no published transaction can yet apply its commit.
test "handoff commit after native preedit remains blocked at original owner" {
  let (owner, root) = @common.fixture_intent_owner()
  let initial = @text_host.TextInputState::new(
    @text.TextDocument::new("").unwrap(),
    @primitives.Rect::new(1.0, 2.0, 1.0, 18.0).unwrap(),
  )
  let route = @ubuntu_host.fixture_intent_route(initial, owner.window(), root)
  let epoch = route.binding_epoch().unwrap()
  let native_epoch = route.native_epoch().unwrap()
  @ubuntu_host.fixture_intent_preedit()
  let preview_receipt = route.peek().unwrap().unwrap()
  assert_eq(preview_receipt.native_sequence(), 2)
  let preview = match preview_receipt.event() {
    @ubuntu_host.Text(value) => value
    _ => fail("preedit must be retained text")
  }
  assert_eq(preview.sequence(), 1L)
  assert_true(preview.kind() is @text_host.Preedit(..))
  preview_receipt.ack().unwrap()
  @common.fixture_prepare_intent_owner_with_preedit(owner, root, epoch, native_epoch, preview)
  let geometry = owner.staged_dirty_geometry().unwrap()
  let state = ubuntu_text_state(@text_host.TextInputState::new(geometry.committed(), geometry.caret())).unwrap()
  let adapter = SettingsGeometryAdapter::new(route, geometry, state).unwrap()
  @ubuntu_host.fixture_intent_commit()
  assert_true(owner.attempt_staged_host_geometry(fn(retry, candidate) { adapter.attempt(retry, candidate) }) is Err(_))
  let original = route.peek().unwrap().unwrap()
  assert_eq(original.native_sequence(), 3)
  let arrival = SettingsGeometryArrivalAdapter::new(route, original).unwrap()
  assert_eq(arrival.portable.sequence(), 2L)
  let receipt = @common.NativeRetainedReceipt::new(
    Some(@common.OrderedText(arrival.portable)), original.native_window(), original.native_sequence(),
    original.root(), original.epoch(), fn() { arrival.transfer() },
  )
  owner.reserve_geometry_arrival(receipt, (arrival.target.epoch, arrival.target.seat, arrival.target.proxy_generation)).unwrap()
  owner.transfer_geometry_arrival().unwrap()
  owner.attempt_staged_host_geometry(fn(retry, candidate) { adapter.attempt(retry, candidate) }).unwrap()
  assert_true(route.geometry_receipt_is_current(adapter.receipt.unwrap()))
  assert_true(route.owned_geometry_text() is Some(_))
  assert_true(owner.geometry_arrival_state() is Some((3, 2)))
  assert_true(@common.fixture_intent_preedit_is_retained(owner))
  owner.inspect_geometry_arrival_before_apply().unwrap()
  arrival.inspect_after_geometry_acceptance(adapter).unwrap()
  @ubuntu_host.fixture_intent_commit_next()
  let later = route.peek().unwrap().unwrap()
  assert_eq(later.native_sequence(), 4)
  assert_true(later.ack() is Err(_))
  owner.take_geometry_arrival_to_local_owner(fn() { arrival.take_after_geometry_acceptance(adapter) }).unwrap()
  assert_true(arrival.taken is Some(_))
  arrival.inspect_taken_after_geometry_acceptance(adapter).unwrap()
  assert_true(route.owned_geometry_text() is None)
  assert_eq(owner.geometry_arrival_take_state(), Some(2))
  assert_true(owner.take_geometry_arrival_to_local_owner(fn() { arrival.take_after_geometry_acceptance(adapter) }) is Err(_))
  assert_true(owner.drive() is Err(_))
  assert_true(owner.reconcile_owned_delivery() is Err(_))
  assert_true(owner.discard_staged_dirty_scene() is Err(_))
  assert_true(arrival.taken is Some(_))
  assert_eq(owner.model().name(), "")
  assert_false(owner.can_stop())
  @ubuntu_host.fixture_intent_finish()
}


///| Fixture: lost callback reply cannot drop or re-take native ownership.
test "native slot remains owned when take callback reports failure" {
  let (owner, root) = @common.fixture_intent_owner()
  let initial = @text_host.TextInputState::new(
    @text.TextDocument::new("").unwrap(),
    @primitives.Rect::new(1.0, 2.0, 1.0, 18.0).unwrap(),
  )
  let route = @ubuntu_host.fixture_intent_route(initial, owner.window(), root)
  let epoch = route.binding_epoch().unwrap()
  let native_epoch = route.native_epoch().unwrap()
  @ubuntu_host.fixture_intent_preedit()
  let preview_receipt = route.peek().unwrap().unwrap()
  assert_eq(preview_receipt.native_sequence(), 2)
  let preview = match preview_receipt.event() {
    @ubuntu_host.Text(value) => value
    _ => fail("preedit must be retained text")
  }
  assert_eq(preview.sequence(), 1L)
  assert_true(preview.kind() is @text_host.Preedit(..))
  preview_receipt.ack().unwrap()
  @common.fixture_prepare_intent_owner_with_preedit(owner, root, epoch, native_epoch, preview)
  let geometry = owner.staged_dirty_geometry().unwrap()
  let state = ubuntu_text_state(@text_host.TextInputState::new(geometry.committed(), geometry.caret())).unwrap()
  let adapter = SettingsGeometryAdapter::new(route, geometry, state).unwrap()
  @ubuntu_host.fixture_intent_commit()
  assert_true(owner.attempt_staged_host_geometry(fn(retry, candidate) { adapter.attempt(retry, candidate) }) is Err(_))
  let original = route.peek().unwrap().unwrap()
  assert_eq(original.native_sequence(), 3)
  let arrival = SettingsGeometryArrivalAdapter::new(route, original).unwrap()
  assert_eq(arrival.portable.sequence(), 2L)
  let receipt = @common.NativeRetainedReceipt::new(
    Some(@common.OrderedText(arrival.portable)), original.native_window(), original.native_sequence(),
    original.root(), original.epoch(), fn() { arrival.transfer() },
  )
  owner.reserve_geometry_arrival(receipt, (arrival.target.epoch, arrival.target.seat, arrival.target.proxy_generation)).unwrap()
  owner.transfer_geometry_arrival().unwrap()
  owner.attempt_staged_host_geometry(fn(retry, candidate) { adapter.attempt(retry, candidate) }).unwrap()
  assert_true(route.geometry_receipt_is_current(adapter.receipt.unwrap()))
  assert_true(route.owned_geometry_text() is Some(_))
  assert_true(owner.geometry_arrival_state() is Some((3, 2)))
  assert_true(@common.fixture_intent_preedit_is_retained(owner))
  owner.inspect_geometry_arrival_before_apply().unwrap()
  arrival.inspect_after_geometry_acceptance(adapter).unwrap()
  @ubuntu_host.fixture_intent_commit_next()
  let later = route.peek().unwrap().unwrap()
  assert_eq(later.native_sequence(), 4)
  assert_true(later.ack() is Err(_))
  let calls = Ref(0)
  assert_true(owner.take_geometry_arrival_to_local_owner(fn() {
    calls.val += 1
    match arrival.take_after_geometry_acceptance(adapter) { Err(error) => return Err(error); Ok(_) => () }
    Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "fixture_reply_lost_after_take"))
  }) is Err(_))
  assert_true(arrival.taken is Some(_))
  assert_true(route.owned_geometry_text() is None)
  assert_eq(owner.geometry_arrival_take_state(), Some(1))
  assert_true(owner.take_geometry_arrival_to_local_owner(fn() { calls.val += 1; arrival.take_after_geometry_acceptance(adapter) }) is Err(_))
  owner.reconcile_geometry_arrival_take(fn() { arrival.inspect_taken_after_geometry_acceptance(adapter) }).unwrap()
  assert_eq(owner.geometry_arrival_take_state(), Some(2))
  assert_eq(calls.val, 1)
  assert_true(owner.drive() is Err(_))
  assert_true(owner.reconcile_owned_delivery() is Err(_))
  assert_true(owner.discard_staged_dirty_scene() is Err(_))
  assert_true(arrival.taken is Some(_))
  assert_eq(owner.model().name(), "")
  assert_false(owner.can_stop())
  @ubuntu_host.fixture_intent_finish()
}


///| Controlled native FIFO and mocked Wayland; not a live compositor.
test "taken native FIFO commit reaches original preedit owner once" {
  let (owner, root) = @common.fixture_intent_owner()
  let initial = @text_host.TextInputState::new(
    @text.TextDocument::new("").unwrap(),
    @primitives.Rect::new(1.0, 2.0, 1.0, 18.0).unwrap(),
  )
  let route = @ubuntu_host.fixture_intent_route(initial, owner.window(), root)
  let epoch = route.binding_epoch().unwrap()
  let native_epoch = route.native_epoch().unwrap()
  @ubuntu_host.fixture_intent_preedit()
  let preview_receipt = route.peek().unwrap().unwrap()
  assert_eq(preview_receipt.native_sequence(), 2)
  let preview = match preview_receipt.event() {
    @ubuntu_host.Text(value) => value
    _ => fail("preedit must be retained text")
  }
  assert_eq(preview.sequence(), 1L)
  assert_true(preview.kind() is @text_host.Preedit(..))
  preview_receipt.ack().unwrap()
  @common.fixture_prepare_intent_owner_with_preedit(owner, root, epoch, native_epoch, preview)
  let geometry = owner.staged_dirty_geometry().unwrap()
  let state = ubuntu_text_state(@text_host.TextInputState::new(geometry.committed(), geometry.caret())).unwrap()
  let adapter = SettingsGeometryAdapter::new(route, geometry, state).unwrap()
  @ubuntu_host.fixture_intent_commit()
  assert_true(owner.attempt_staged_host_geometry(fn(retry, candidate) { adapter.attempt(retry, candidate) }) is Err(_))
  let original = route.peek().unwrap().unwrap()
  assert_eq(original.native_sequence(), 3)
  let arrival = SettingsGeometryArrivalAdapter::new(route, original).unwrap()
  assert_eq(arrival.portable.sequence(), 2L)
  let receipt = @common.NativeRetainedReceipt::new(
    Some(@common.OrderedText(arrival.portable)), original.native_window(), original.native_sequence(),
    original.root(), original.epoch(), fn() { arrival.transfer() },
  )
  owner.reserve_geometry_arrival(receipt, (arrival.target.epoch, arrival.target.seat, arrival.target.proxy_generation)).unwrap()
  owner.transfer_geometry_arrival().unwrap()
  owner.attempt_staged_host_geometry(fn(retry, candidate) { adapter.attempt(retry, candidate) }).unwrap()
  assert_true(route.geometry_receipt_is_current(adapter.receipt.unwrap()))
  assert_true(route.owned_geometry_text() is Some(_))
  assert_true(owner.geometry_arrival_state() is Some((3, 2)))
  assert_true(@common.fixture_intent_preedit_is_retained(owner))
  owner.inspect_geometry_arrival_before_apply().unwrap()
  arrival.inspect_after_geometry_acceptance(adapter).unwrap()
  @ubuntu_host.fixture_intent_commit_next()
  let later = route.peek().unwrap().unwrap()
  assert_eq(later.native_sequence(), 4)
  assert_true(later.ack() is Err(_))
  owner.take_geometry_arrival_to_local_owner(fn() { arrival.take_after_geometry_acceptance(adapter) }).unwrap()
  assert_true(arrival.taken is Some(_))
  arrival.inspect_taken_after_geometry_acceptance(adapter).unwrap()
  assert_true(route.owned_geometry_text() is None)
  assert_eq(owner.geometry_arrival_take_state(), Some(2))
  assert_true(owner.take_geometry_arrival_to_local_owner(fn() { arrival.take_after_geometry_acceptance(adapter) }) is Err(_))
  owner.apply_taken_geometry_arrival(3L, fn() { arrival.inspect_taken_after_geometry_acceptance(adapter) }).unwrap()
  assert_eq(owner.model().name(), "日本")
  assert_true(owner.receipt_stage_for_sequence(3L) is Some(@common.ReceiptModelApplied))
  assert_true(owner.apply_taken_geometry_arrival(3L, fn() { arrival.inspect_taken_after_geometry_acceptance(adapter) }) is Err(_))
  assert_true(owner.reconcile_taken_geometry_arrival(3L) is Err(_))
  assert_true(owner.drive() is Err(_))
  assert_true(owner.reconcile_owned_delivery() is Err(_))
  assert_true(owner.discard_staged_dirty_scene() is Err(_))
  assert_true(arrival.taken is Some(_))
  assert_eq(owner.model().name(), "日本")
  assert_false(owner.can_stop())
  @ubuntu_host.fixture_intent_finish()
}
