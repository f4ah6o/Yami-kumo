///|
/// GPUI fixture-only shim provides a real native FIFO and mocked Wayland
/// requests. It is not a real compositor, live IME or product dependency.
test "closed adapter keeps exact intent across native FIFO handoff" {
  ignore(@linux_text.require_grayscale_raster())
  let initial = @text_host.TextInputState::new(
    @text.TextDocument::new("old").unwrap(),
    @primitives.Rect::new(1.0, 2.0, 1.0, 18.0).unwrap(),
  )
  let route = @ubuntu_host.fixture_intent_route(initial)
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
