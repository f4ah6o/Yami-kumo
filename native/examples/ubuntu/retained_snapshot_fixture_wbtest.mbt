///|
/// FIXTURE ONLY: production native FIFO with mocked Wayland callbacks. This
/// does not run a live compositor or IME and never ships fixture helpers.
fn snapshot_fixture_route() -> @ubuntu_host.RetainedOrderedRoute {
  let state = @text_host.TextInputState::new(
    @text.TextDocument::new("").unwrap(),
    @primitives.Rect::new(1.0, 2.0, 1.0, 18.0).unwrap(),
  )
  @ubuntu_host.fixture_intent_route(state, @platform.WindowId::new(51L), 9UL)
}

///|
test "native head inspection preserves text, ordering, and explicit failure" {
  let route = snapshot_fixture_route()
  assert_eq(inspect_retained_head(route, false).unwrap(), 0L)
  @ubuntu_host.fixture_intent_preedit()
  let first = route.peek().unwrap().unwrap()
  assert_eq(first.native_sequence(), 2)
  assert_true(first.event() is @ubuntu_host.Text(_))
  assert_eq(inspect_retained_head(route, false).unwrap(), 2L)
  assert_eq(inspect_retained_head(route, false).unwrap(), 2L)
  let calls = Ref(0)
  assert_true(inspect_retained_head_from(route, false, fn() {
    calls.val += 1
    Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "fixture_peek_failed"))
  }) is Err(_))
  assert_eq(calls.val, 1)
  let unchanged = route.peek().unwrap().unwrap()
  assert_eq(unchanged.native_sequence(), first.native_sequence())
  assert_eq(unchanged.epoch(), first.epoch())
  assert_eq(unchanged.root(), first.root())
  assert_false(unchanged.is_native_stale())
  unchanged.ack().unwrap()
  @ubuntu_host.fixture_intent_commit()
  let commit = route.peek().unwrap().unwrap()
  assert_eq(commit.native_sequence(), 3)
  assert_true(commit.event() is @ubuntu_host.Text(_))
  assert_eq(inspect_retained_head(route, false).unwrap(), 3L)
  assert_eq(route.peek().unwrap().unwrap().native_sequence(), 3)
  commit.ack().unwrap()
  assert_eq(inspect_retained_head(route, false).unwrap(), 0L)
  @ubuntu_host.fixture_intent_finish()
}

///|
test "native head inspection preserves queued nontext and geometry intent" {
  let route = snapshot_fixture_route()
  @ubuntu_host.fixture_intent_nontext()
  let first = route.peek().unwrap().unwrap()
  assert_true(first.native_event() is Some(@ubuntu_host.Platform(_)))
  let state = @text_host.TextInputState::new(
    @text.TextDocument::new("").unwrap(),
    @primitives.Rect::new(2.0, 3.0, 1.0, 18.0).unwrap(),
  )
  let intent = route.reserve_geometry_intent(route.binding_epoch().unwrap(), state).unwrap()
  assert_true(route.geometry_intent_stage(intent) is Some(@ubuntu_host.GeometryIntentNotSubmitted))
  assert_eq(inspect_retained_head(route, false).unwrap(), first.native_sequence().to_int64())
  assert_eq(inspect_retained_head(route, false).unwrap(), first.native_sequence().to_int64())
  assert_eq(route.peek().unwrap().unwrap().native_sequence(), first.native_sequence())
  assert_true(route.geometry_intent_stage(intent) is Some(@ubuntu_host.GeometryIntentNotSubmitted))
  assert_true(first.ack() is Err(_))
  @ubuntu_host.fixture_intent_finish()
}

///|
test "native head inspection preserves stale text for its original route" {
  let route = snapshot_fixture_route()
  @ubuntu_host.fixture_intent_preedit()
  @ubuntu_host.fixture_intent_stale_epoch()
  let stale = route.peek().unwrap().unwrap()
  assert_true(stale.is_native_stale())
  assert_true(stale.event() is @ubuntu_host.Unhandled(_))
  assert_eq(inspect_retained_head(route, false).unwrap(), stale.native_sequence().to_int64())
  assert_eq(inspect_retained_head(route, false).unwrap(), stale.native_sequence().to_int64())
  let unchanged = route.peek().unwrap().unwrap()
  assert_true(unchanged.is_native_stale())
  assert_eq(unchanged.native_sequence(), stale.native_sequence())
  assert_eq(unchanged.root(), stale.root())
  assert_eq(unchanged.epoch(), stale.epoch())
  @ubuntu_host.fixture_intent_finish()
}
