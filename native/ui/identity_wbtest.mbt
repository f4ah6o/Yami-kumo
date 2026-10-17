///|
test "native epoch probes preserve markers and liveness for aliases and distinct cells" {
  for left_live in [false, true] {
    for right_live in [false, true] {
      for left_marker in [false, true] {
        for right_marker in [false, true] {
          let left = fresh_epoch()
          let right = fresh_epoch()
          left.live = left_live
          right.live = right_live
          left.marker = left_marker
          right.marker = right_marker
          let copied = left
          for _ in 0..<3 {
            assert_true(same_epoch(left, left))
            assert_true(same_epoch(left, copied))
            assert_true(same_epoch(copied, left))
            assert_true(same_epoch(right, right))
            assert_eq(left.marker, left_marker)
            assert_eq(right.marker, right_marker)
            assert_eq(copied.marker, left_marker)
            assert_eq(left.live, left_live)
            assert_eq(right.live, right_live)
            assert_true(!same_epoch(left, right))
            assert_eq(left.marker, left_marker)
            assert_eq(right.marker, right_marker)
            assert_eq(left.live, left_live)
            assert_eq(right.live, right_live)
            assert_true(!same_epoch(right, copied))
            assert_eq(left.marker, left_marker)
            assert_eq(right.marker, right_marker)
            assert_eq(copied.live, left_live)
            assert_eq(right.live, right_live)
          }
        }
      }
    }
  }
}

///|
test "same-key Column Card transitions retain native binding and runtime token" {
  let mount = Mounted::new(@platform.WindowId::new(1L))
  let key = @view.NodeKey::new("surface")
  let no_text : @components.TextMeasure = fn(_, _) {
    Err(adapter_error("empty containers must not measure text"))
  }
  ignore(
    mount.commit(@view.column(key, []), 800.0, 600.0, 1.0, no_text).unwrap(),
  )
  let before = binding_for(mount.bindings, key).unwrap()
  for card in [true, false, true] {
    let view = if card { @view.card(key, []) } else { @view.column(key, []) }
    let frame = mount.commit(view, 800.0, 600.0, 1.0, no_text).unwrap()
    let after = binding_for(mount.bindings, key).unwrap()
    assert_eq(after.id, before.id)
    assert_true(after.token == before.token)
    assert_true(!mount.focus(key))
    if card {
      assert_eq(frame.snapshot().items().length(), 3)
      assert_eq(frame.snapshot().items()[1].id(), before.id + 1UL)
      assert_eq(frame.snapshot().items()[2].id(), before.id + 2UL)
    } else {
      assert_eq(frame.snapshot().items().length(), 1)
    }
  }
}
