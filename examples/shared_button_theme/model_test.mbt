///|
test "theme switch leaves the shared view and keyed incarnation unchanged" {
  let initial = @shared_button_theme.Model::new()
  let runtime = @runtime.Runtime::new()
  assert_true(runtime.commit(initial.view()) is Ok(_))
  let increment = runtime.token(@core.NodeKey::new("increment")).unwrap()
  let toggle = runtime.token(@core.NodeKey::new("theme-toggle")).unwrap()
  let dark = initial.update(@core.Activate(@core.NodeKey::new("theme-toggle")))
  assert_eq(dark.theme(), @theme.Dark)
  assert_eq(dark.view(), initial.view())
  assert_true(runtime.commit(dark.view()) is Ok(_))
  assert_true(runtime.is_current(increment))
  assert_true(runtime.is_current(toggle))
  assert_eq(dark.value(), 0)
  let incremented = dark.update(@core.Activate(@core.NodeKey::new("increment")))
  assert_eq(incremented.value(), 1)
  assert_eq(incremented.theme(), @theme.Dark)
  assert_eq(initial.value(), 0)
}

///|
test "theme changes preserve the common runtime gates and pending activations" {
  let runtime = @runtime.Runtime::new()
  let model = @shared_button_theme.Model::new()
  assert_true(runtime.commit(model.view()) is Ok(_))
  let increment = runtime.token(@core.NodeKey::new("increment")).unwrap()
  let toggle = runtime.token(@core.NodeKey::new("theme-toggle")).unwrap()
  for mode in [@shared_button_theme.Disabled, @shared_button_theme.Loading, @shared_button_theme.DisabledLoading] {
    let gated = model.with_mode(mode).with_theme(@theme.Dark)
    assert_true(runtime.commit(gated.view()) is Ok(_))
    assert_true(runtime.is_current(increment))
    assert_true(!runtime.enqueue_activate(increment))
    assert_true(runtime.next_action() is None)
    assert_true(runtime.enqueue_activate(toggle))
    let light = gated.update(runtime.next_action().unwrap())
    assert_eq(light.theme(), @theme.Light)
    assert_eq(light.mode(), mode)
    assert_eq(light.value(), 0)
  }
  assert_true(runtime.commit(model.view()) is Ok(_))
  assert_true(runtime.enqueue_activate(increment))
  let dark = model.with_theme(@theme.Dark)
  assert_true(runtime.commit(dark.view()) is Ok(_))
  assert_eq(dark.update(runtime.next_action().unwrap()).value(), 1)
  runtime.dispose()
  assert_true(!runtime.enqueue_activate(increment))
}
