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
    state, intent: None, receipt: None,
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
