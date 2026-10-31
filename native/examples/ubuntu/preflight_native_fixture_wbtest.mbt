///|
/// Fixture only: GPUI's retained FIFO is real, Wayland requests are mocked.
fn preflight_native_fixture() -> (@ubuntu_host.RetainedOrderedRoute, SettingsPreflightAdapter, @text_host.TextInputState) {
  ignore(@linux_text.require_grayscale_raster())
  let initial = @text_host.TextInputState::new(
    @text.TextDocument::new("").unwrap(),
    @primitives.Rect::new(1.0, 2.0, 1.0, 18.0).unwrap(),
  )
  let route = @ubuntu_host.fixture_intent_route(initial, @platform.WindowId::new(51L), 9UL)
  let adapter : SettingsPreflightAdapter = { route, proof: None, accepted: None, uncertain: false }
  let state = @text_host.TextInputState::new(
    @text.TextDocument::new("").unwrap(),
    @primitives.Rect::new(5.0, 2.0, 1.0, 18.0).unwrap(),
  )
  (route, adapter, state)
}

///|
test "native preflight Busy preserves head and same geometry until explicit retry" {
  let (route, adapter, state) = preflight_native_fixture()
  let epoch = route.binding_epoch().unwrap()
  @ubuntu_host.fixture_intent_preedit()
  let head = route.peek().unwrap().unwrap()
  assert_eq(head.native_sequence(), 2)
  let before = @ubuntu_host.fixture_intent_wayland_calls()
  assert_true(adapter.attempt(epoch, state) is Err(_))
  assert_true(adapter.proof is Some(_))
  assert_true(route.pending_geometry() is None)
  assert_eq(@ubuntu_host.fixture_intent_wayland_calls(), before)
  assert_true(adapter.retry(@platform.WindowId::new(51L), 8UL, epoch, state) is Err(_))
  assert_true(adapter.retry(@platform.WindowId::new(51L), 9UL, epoch, state) is Err(_))
  assert_true(adapter.proof is Some(_))
  assert_eq(route.peek().unwrap().unwrap().native_sequence(), head.native_sequence())
  assert_eq(@ubuntu_host.fixture_intent_wayland_calls(), before)
  // Explicit fixture ACK: not a policy for a production IME record.
  head.ack().unwrap()
  assert_eq(adapter.retry(@platform.WindowId::new(51L), 9UL, epoch, state).unwrap(), epoch)
  assert_true(adapter.accepted is Some(_))
  let after = @ubuntu_host.fixture_intent_wayland_calls()
  assert_true(after > before)
  assert_eq(adapter.retry(@platform.WindowId::new(51L), 9UL, epoch, state).unwrap(), epoch)
  assert_eq(@ubuntu_host.fixture_intent_wayland_calls(), after)
  assert_true(route.peek().unwrap() is None)
  @ubuntu_host.fixture_intent_finish()
}

///|
test "native-entered Busy is uncertain and cannot replay a preflight proof" {
  let (route, adapter, state) = preflight_native_fixture()
  let epoch = route.binding_epoch().unwrap()
  @ubuntu_host.fixture_intent_preedit()
  assert_true(adapter.attempt(epoch, state) is Err(_))
  let original = route.peek().unwrap().unwrap()
  original.ack().unwrap() // Fixture only; not an IME release policy.
  @ubuntu_host.fixture_intent_fail_after_update()
  let before = @ubuntu_host.fixture_intent_wayland_calls()
  assert_true(adapter.retry(@platform.WindowId::new(51L), 9UL, epoch, state) is Err(_))
  let after = @ubuntu_host.fixture_intent_wayland_calls()
  assert_true(after > before)
  assert_true(adapter.uncertain)
  assert_true(adapter.proof is None)
  assert_true(route.pending_geometry() is Some(_))
  assert_true(adapter.retry(@platform.WindowId::new(51L), 9UL, epoch, state) is Err(_))
  assert_eq(@ubuntu_host.fixture_intent_wayland_calls(), after)
  assert_true(route.pending_geometry() is Some(_))
  @ubuntu_host.fixture_intent_finish()
}
