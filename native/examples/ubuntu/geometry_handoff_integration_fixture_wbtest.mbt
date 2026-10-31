///|
/// Fixture-only GPUI shim drives its route state machine with a synthetic ACK;
/// no native host token, native FIFO or compositor is involved.
test "original adapter recognizes only the exact route-owned handoff" {
  ignore(@linux_text.require_grayscale_raster())
  let state = @text_host.TextInputState::new(
    @text.TextDocument::new("").unwrap(),
    @primitives.Rect::new(4.0, 2.0, 1.0, 18.0).unwrap(),
  )
  let (route, receipt) = @ubuntu_host.fixture_handoff_receipt(state, @platform.WindowId::new(51L), 9UL)
  let adapter = SettingsGeometryArrivalAdapter::new(route, receipt).unwrap()
  assert_eq(receipt.native_sequence(), 21)
  assert_eq(adapter.portable.sequence(), 1L)
  assert_true(adapter.inspect_owned() is Err(_))
  @ubuntu_host.fixture_handoff_transfer(route, receipt).unwrap()
  adapter.inspect_owned().unwrap()
  let owned = route.owned_geometry_text().unwrap()
  assert_true(adapter.matches_owned(owned))
  let wrong_serial = { ..adapter.target, serial: adapter.target.serial + 1 }
  let wrong_owner : SettingsGeometryArrivalAdapter = { ..adapter, target: wrong_serial }
  assert_false(wrong_owner.matches_owned(owned))
  assert_true(wrong_owner.inspect_owned() is Err(_))
  let wrong_generation : SettingsGeometryArrivalAdapter = { ..adapter, geometry_generation: adapter.geometry_generation + 1UL }
  assert_false(wrong_generation.matches_owned(owned))
  assert_true(wrong_generation.inspect_owned() is Err(_))
  assert_true(route.owned_geometry_text() is Some(_))
  assert_true(route.pending_geometry() is Some(_))
}

///|
/// Local owner -> exact adapter -> GPUI route state machine with synthetic ACK;
/// this is not a native FIFO, scene, model-application or IME live run.
test "owner reservation precedes the exact route handoff" {
  let (owner, root) = @common.fixture_handoff_owner()
  let state = @text_host.TextInputState::new(
    @text.TextDocument::new("").unwrap(),
    @primitives.Rect::new(4.0, 2.0, 1.0, 18.0).unwrap(),
  )
  let (route, receipt) = @ubuntu_host.fixture_handoff_receipt(state, owner.window(), root)
  let adapter = SettingsGeometryArrivalAdapter::new(route, receipt).unwrap()
  let portable = @common.NativeRetainedReceipt::new(
    Some(@common.OrderedText(adapter.portable)), receipt.native_window(), receipt.native_sequence(),
    receipt.root(), receipt.epoch(), fn() {
      match @ubuntu_host.fixture_handoff_transfer(route, receipt) {
        Err(error) => Err(error)
        Ok(_) => adapter.inspect_owned()
      }
    },
  )
  owner.reserve_geometry_arrival(portable, (adapter.target.epoch, adapter.target.seat, adapter.target.proxy_generation)).unwrap()
  assert_true(route.owned_geometry_text() is None)
  owner.transfer_geometry_arrival().unwrap()
  assert_true(owner.geometry_arrival_state() is Some((21, 2)))
  assert_true(route.owned_geometry_text() is Some(_))
  assert_true(owner.transfer_geometry_arrival() is Err(_))
  assert_true(owner.try_terminal_text_cutoff() is Err(_))
  assert_false(owner.can_stop())
}
