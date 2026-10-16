///|
test "counter model and view are deterministic and ignore unrelated actions" {
  let initial = @shared_counter.Model::new()
  assert_eq(initial.value(), 0)
  assert_eq(initial.view(), @shared_counter.Model::new().view())
  let action = @core.Activate(@core.NodeKey::new("increment"))
  let one = initial.update(action)
  assert_eq(one.value(), 1)
  assert_eq(initial.value(), 0)
  assert_eq(one, initial.update(action))
  assert_eq(one.view(), initial.update(action).view())
  assert_eq(one.update(@core.Activate(@core.NodeKey::new("heading"))), one)
  assert_eq(one.update(@core.Activate(@core.NodeKey::new("unknown"))), one)
  assert_eq(one.update(action).value(), 2)
  assert_eq(one.view().children()[1].label(), "Count: 1")
}

///|
test "one model owner drains runtime actions before rendering next view" {
  let runtime = @runtime.Runtime::new()
  let mut model = @shared_counter.Model::new()
  assert_eq(runtime.commit(model.view()), Ok(()))
  let increment = runtime.token(@core.NodeKey::new("increment")).unwrap()
  let trace = []
  for _ in 0..<3 {
    assert_true(runtime.enqueue_activate(increment))
    assert_eq(model.value(), trace.length())
    let action = runtime.next_action().unwrap()
    model = model.update(action)
    assert_eq(runtime.commit(model.view()), Ok(()))
    trace.push(model.value())
  }
  assert_eq(trace, [1, 2, 3])
  assert_true(
    runtime.token(@core.NodeKey::new("increment")).unwrap() == increment,
  )
  assert_eq(runtime.view(), Some(model.view()))
  runtime.dispose()
  assert_true(!runtime.enqueue_activate(increment))
  assert_eq(model.value(), 3)
}
