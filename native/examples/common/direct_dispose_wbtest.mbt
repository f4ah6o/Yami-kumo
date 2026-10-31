///|
test "owned direct disposal during measurement retains the attempted receipt" {
  let (owner, _) = publication_fixture()
  let trigger = Ref(false)
  let measure : @components.TextMeasure = fn(value, size) {
    if trigger.val { owner.mounted.dispose() }
    text_runner_measure(value, size)
  }
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, measure).unwrap())
  let event = @platform.Event::new(owner.window, 1L, 1.0,
    @platform.Input(@primitives.TextInput(text="a")))
  let receipt = owner.mounted.reserve_owned_direct_text(owner.terminal_owner.unwrap(), event, 1, 1L).unwrap()
  trigger.val = true
  assert_true(owner.mounted.apply_owned_direct_text(receipt) is Err(_))
  assert_true(receipt.attempted())
  assert_false(receipt.applied())
  assert_true(owner.mounted.apply_owned_direct_text(receipt) is Err(_))
  assert_eq(owner.model().name(), "")
}

///|
test "owned direct layout invalidation during measurement rejects the old owner" {
  let (owner, _) = publication_fixture()
  let trigger = Ref(false)
  let measure : @components.TextMeasure = fn(value, size) {
    if trigger.val { owner.mounted.invalidate_layout() }
    text_runner_measure(value, size)
  }
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, measure).unwrap())
  let event = @platform.Event::new(owner.window, 1L, 1.0,
    @platform.Input(@primitives.TextInput(text="a")))
  let receipt = owner.mounted.reserve_owned_direct_text(owner.terminal_owner.unwrap(), event, 1, 1L).unwrap()
  trigger.val = true
  assert_true(owner.mounted.apply_owned_direct_text(receipt) is Err(_))
  assert_true(receipt.attempted())
  assert_false(receipt.applied())
  assert_false(receipt.owner_noted())
  assert_true(receipt.pending_action() is None)
  assert_true(owner.mounted.apply_owned_direct_text(receipt) is Err(_))
  assert_eq(owner.model().name(), "")
}
