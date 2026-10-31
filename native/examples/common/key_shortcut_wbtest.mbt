///|
test "owned edit key rejects Meta Y without Control" {
  let (owner, _) = publication_fixture()
  let lease = owner.terminal_owner.unwrap()
  let modifiers = @primitives.Modifiers::new(shift=false, control=false, alt=false, meta=true)
  let event = @platform.Event::new(owner.window, 2L, 1.0,
    @platform.Input(@primitives.KeyPressed(key=@primitives.Character("y"), repeat=false, modifiers~)))
  assert_true(owner.mounted.reserve_owned_edit_key(lease, event, 2) is Err(_))
  assert_true(owner.mounted.terminal_owner_is_current(lease))
  assert_eq(owner.model().name(), "")
}
