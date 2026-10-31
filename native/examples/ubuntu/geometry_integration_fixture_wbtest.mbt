///|
/// Synthetic test-only GPUI shim generates opaque receipts through the real
/// route state machine. Its native token is invalid: no live host is exercised.
fn fixture_geometry_adapter(
  route : @ubuntu_host.RetainedOrderedRoute,
  state : @text_host.TextInputState,
  window : @platform.WindowId,
  root : UInt64,
  epoch : UInt64,
  native_epoch : Int32,
  generation : UInt64?,
) -> SettingsGeometryAdapter {
  { route, window, root, epoch, native_epoch, state,
    pending_generation: generation, receipt: None }
}

///|
test "opaque receipt candidate rejects foreign owner and altered payload" {
  let state = @text_host.TextInputState::new(
    @text.TextDocument::new("日本").unwrap(),
    @primitives.Rect::new(4.0, 2.0, 1.0, 18.0).unwrap(),
  )
  let (route, receipt) = @ubuntu_host.fixture_geometry_receipt(state)
  let pending = receipt.pending()
  let window = @platform.WindowId::new(51L)
  let other_window = @platform.WindowId::new(52L)
  assert_true(fixture_geometry_adapter(route, state, window, 9UL, 3UL, 7, None).matches(pending))
  assert_false(fixture_geometry_adapter(route, state, other_window, 9UL, 3UL, 7, None).matches(pending))
  assert_false(fixture_geometry_adapter(route, state, window, 10UL, 3UL, 7, None).matches(pending))
  assert_false(fixture_geometry_adapter(route, state, window, 9UL, 4UL, 7, None).matches(pending))
  assert_false(fixture_geometry_adapter(route, state, window, 9UL, 3UL, 8, None).matches(pending))
  let different = @text_host.TextInputState::new(@text.TextDocument::new("日本語").unwrap(), state.caret())
  assert_false(fixture_geometry_adapter(route, different, window, 9UL, 3UL, 7, None).matches(pending))
  assert_false(route.geometry_receipt_is_current(receipt))
}

///|
test "changed retry generation retains the opaque pending candidate" {
  let state = @text_host.TextInputState::new(
    @text.TextDocument::new("日本").unwrap(),
    @primitives.Rect::new(4.0, 2.0, 1.0, 18.0).unwrap(),
  )
  let route = @ubuntu_host.fixture_geometry_pending(state)
  let adapter = fixture_geometry_adapter(route, state, @platform.WindowId::new(51L), 9UL, 3UL, 7, Some(2UL))
  assert_true(adapter.attempt(true, state) is Err(_))
  let pending = route.pending_geometry().unwrap()
  assert_eq(pending.generation(), 1UL)
  assert_true(pending.state().document() == state.document())
  assert_true(pending.state().caret() == state.caret())
  assert_true(adapter.receipt is None)
}
