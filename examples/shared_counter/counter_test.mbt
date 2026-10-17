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

///|
test "Card consumer shares unchanged model children keys and actions" {
  let runtime = @runtime.Runtime::new()
  let mut model = @shared_counter.Model::new()
  assert_true(!model.view().is_card())
  assert_eq(model.card_view().children(), model.view().children())
  assert_eq(model.card_view().key(), model.view().key())
  assert_eq(runtime.commit(model.view()), Ok(()))
  let root = runtime.token(@core.NodeKey::new("counter")).unwrap()
  let increment = runtime.token(@core.NodeKey::new("increment")).unwrap()
  assert_eq(runtime.commit(model.card_view()), Ok(()))
  assert_true(runtime.token(model.card_view().key()) == Some(root))
  assert_true(!runtime.enqueue_activate(root))
  assert_true(runtime.request_focus(root) is Err(_))
  for _ in 0..<2 {
    assert_true(runtime.enqueue_activate(increment))
    model = model.update(runtime.next_action().unwrap())
    assert_eq(runtime.commit(model.card_view()), Ok(()))
  }
  assert_eq(model.value(), 2)
  assert_eq(runtime.commit(model.view()), Ok(()))
  assert_true(runtime.token(@core.NodeKey::new("increment")) == Some(increment))
}
