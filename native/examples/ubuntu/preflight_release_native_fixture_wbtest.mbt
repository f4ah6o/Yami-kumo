///|
/// Controlled native FIFO and mocked Wayland callbacks; not live IME.
fn physical_release_fixture() -> (@common.SettingsEntryController, @ubuntu_host.RetainedOrderedRoute, SettingsPreflightAdapter, @text_host.TextInputState) {
  ignore(@linux_text.require_grayscale_raster())
  let (entry, state) = @common.fixture_preflight_release_entry()
  let owner = entry.owner().unwrap()
  let (_, binding) = owner.text_owner().unwrap()
  let normalized = ubuntu_text_state(state).unwrap()
  let route = @ubuntu_host.fixture_physical_route(normalized, owner.window(), binding)
  @ubuntu_host.fixture_intent_preedit()
  let preedit = route.peek().unwrap().unwrap()
  if preedit.native_sequence() != 3 { abort("unexpected preedit sequence") }
  ignore(preedit.ack().unwrap()) // Fixture synchronizes an already-applied prefix.
  let adapter : SettingsPreflightAdapter = { route, proof: None, accepted: None, uncertain: false }
  (entry, route, adapter, state)
}

///|
test "preflight release preserves owner and retries exact native geometry" {
  let (entry, route, adapter, state) = physical_release_fixture()
  let owner = entry.owner().unwrap()
  let (epoch, _) = owner.text_owner().unwrap()
  @ubuntu_host.fixture_physical_release()
  let head = route.peek().unwrap().unwrap()
  assert_eq(head.native_sequence(), 4)
  let evidence = head.physical_release_evidence().unwrap().unwrap()
  assert_true(evidence.claim_before_any_window())
  assert_eq(evidence.host_window_generation(), Some(1))
  assert_eq(evidence.focus_generation(), 1)
  assert_true(evidence.prior() is @ubuntu_host.NoPressObservedSinceFocus)
  assert_true(adapter.attempt(epoch, ubuntu_text_state(state).unwrap()) is Err(_))
  assert_true(adapter.proof is Some(_))
  let held : Ref[@ubuntu_host.RetainedOrderedReceipt?] = Ref(None)
  assert_true(resolve_preflight_release(entry, route, adapter, held, 5L) is Err(_))
  assert_eq(route.peek().unwrap().unwrap().native_sequence(), 4)
  resolve_preflight_release(entry, route, adapter, held, 4L).unwrap()
  assert_true(route.peek().unwrap() is None)
  assert_true(owner.receipt_stage_for_sequence(4L) is Some(@common.ReceiptUnsupportedAcknowledged))
  assert_false(owner.host_epoch_verified())
  assert_eq(owner.model().name(), "")
  let before = @ubuntu_host.fixture_intent_wayland_calls()
  owner.retry_captured_host_update(fn(window, root, value_epoch, candidate) {
    adapter.retry(window, root, value_epoch, candidate)
  }).unwrap()
  assert_true(owner.host_epoch_verified())
  assert_true(@ubuntu_host.fixture_intent_wayland_calls() > before)
  assert_true(owner.advance_generation() is None)
  assert_false(owner.can_stop())
  assert_eq(owner.model().name(), "")
  @ubuntu_host.fixture_intent_finish()
}

///|
test "preflight release leaves a different native text head untouched" {
  let (entry, route, adapter, state) = physical_release_fixture()
  let owner = entry.owner().unwrap()
  let (epoch, _) = owner.text_owner().unwrap()
  @ubuntu_host.fixture_intent_commit()
  let head = route.peek().unwrap().unwrap()
  assert_true(adapter.attempt(epoch, ubuntu_text_state(state).unwrap()) is Err(_))
  let held : Ref[@ubuntu_host.RetainedOrderedReceipt?] = Ref(None)
  assert_true(resolve_preflight_release(entry, route, adapter, held, head.native_sequence().to_int64()) is Err(_))
  assert_eq(route.peek().unwrap().unwrap().native_sequence(), head.native_sequence())
  assert_true(held.val is None)
  assert_false(owner.host_epoch_verified())
  assert_false(owner.can_stop())
  @ubuntu_host.fixture_intent_finish()
}
