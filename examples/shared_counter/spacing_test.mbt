///|
test "spacing demo composes unchanged counter and toggles its own state" {
  let initial = @shared_counter.SpacingModel::new()
  let increment = @core.Activate(@core.NodeKey::new("increment"))
  let toggle = @core.Activate(@core.NodeKey::new("spacing-toggle"))
  let one = initial.update(increment)
  let expanded = one.update(toggle)
  assert_eq(expanded.value(), 1)
  assert_true(expanded.expanded())
  assert_eq(expanded.counter(), @shared_counter.Model::new().update(increment))
  assert_eq(one.counter().update(toggle), one.counter())
  assert_eq(one.update_counter(toggle), one)
  assert_eq(expanded.update(toggle), one)
  assert_eq(
    expanded.update(@core.Activate(@core.NodeKey::new("unknown"))),
    expanded,
  )
  assert_eq(initial.view().spacing().unwrap().gap(), @core.Zero)
  assert_eq(expanded.view().spacing().unwrap().gap(), @core.Twelve)
  assert_eq(initial.view().key(), expanded.view().key())
  assert_eq(
    initial.view().children()[2].children()[1].key().value(),
    "spacing-toggle",
  )
  assert_true(expanded.view().children()[3].is_card())
  assert_eq(expanded.view().children()[3].spacing(), None)
}
