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

///|
test "held owner does not publish a commit after reentrant layout invalidation" {
  let mounted = Mounted::new(@platform.WindowId::new(1L))
  let invalidate = Ref(false)
  let measure : @components.TextMeasure = fn(value, size) {
    if invalidate.val {
      mounted.invalidate_layout()
    }
    let document = @text.TextDocument::new(value).unwrap()
    let bounds = @primitives.Rect::new(
      0.0,
      0.0,
      (value.length() + 1).to_double() * size,
      size,
    ).unwrap()
    let carets = []
    let mut offset = 0
    carets.push(
      @text_layout.CaretGeometry::new(
        0,
        true,
        @primitives.Rect::new(0.0, 0.0, 1.0, size).unwrap(),
        @primitives.Rect::new(0.0, 0.0, 1.0, size).unwrap(),
      ).unwrap(),
    )
    for scalar in value.iter() {
      offset += if scalar.to_int() > 0xFFFF { 2 } else { 1 }
      let caret = @primitives.Rect::new(
        offset.to_double() * size,
        0.0,
        1.0,
        size,
      ).unwrap()
      carets.push(
        @text_layout.CaretGeometry::new(offset, true, caret, caret).unwrap(),
      )
    }
    Ok(
      @text_layout.TextMeasurement::new(
        document,
        bounds,
        bounds,
        size * 0.8,
        1,
        0,
        carets,
      ).unwrap(),
    )
  }
  let key = @view.NodeKey::new("name")
  let view = @view.column(@view.NodeKey::new("root"), [
    @view.text_field(key, @view.TextFieldProps::new("", "Name")),
  ])
  ignore(mounted.commit(view, 640.0, 480.0, 1.0, measure).unwrap())
  assert_true(mounted.focus(key))
  assert_true(mounted.begin_held_text(7UL).unwrap())
  let before = mounted.held_text.unwrap().session.snapshot()
  invalidate.val = true
  let observed = @text_host.TextInputEvent::new(
    @platform.WindowId::new(1L),
    1L,
    7UL,
    @text_host.Commit(text="日本"),
  )
  assert_true(mounted.held_text_input(7UL, observed) is Err(_))
  let after = mounted.held_text.unwrap().session.snapshot()
  assert_eq(after.delivery_watermark(), before.delivery_watermark())
  assert_eq(
    after.field().committed_document().text(),
    before.field().committed_document().text(),
  )
  assert_true(mounted.held_text.unwrap().poisoned)
  assert_true(mounted.held_text_input(7UL, observed) is Err(_))
  mounted.dispose()
}

///|
test "exploratory held composition prepare cannot publish the session" {
  let mounted = Mounted::new(@platform.WindowId::new(1L))
  let measure : @components.TextMeasure = fn(value, size) {
    let document = @text.TextDocument::new(value).unwrap()
    let bounds = @primitives.Rect::new(
      0.0, 0.0, (value.length() + 1).to_double() * size, size,
    ).unwrap()
    let carets = []
    let mut offset = 0
    let caret = @primitives.Rect::new(0.0, 0.0, 1.0, size).unwrap()
    carets.push(@text_layout.CaretGeometry::new(0, true, caret, caret).unwrap())
    for scalar in value.iter() {
      offset += if scalar.to_int() > 0xFFFF { 2 } else { 1 }
      let caret = @primitives.Rect::new(offset.to_double() * size, 0.0, 1.0, size).unwrap()
      carets.push(@text_layout.CaretGeometry::new(offset, true, caret, caret).unwrap())
    }
    Ok(@text_layout.TextMeasurement::new(document, bounds, bounds, size * 0.8, 1, 0, carets).unwrap())
  }
  let key = @view.NodeKey::new("name")
  let view = @view.column(@view.NodeKey::new("root"), [
    @view.text_field(key, @view.TextFieldProps::new("", "Name")),
  ])
  ignore(mounted.commit(view, 640.0, 480.0, 1.0, measure).unwrap())
  assert_true(mounted.focus(key))
  assert_true(mounted.begin_held_text(7UL).unwrap())
  assert_true(mounted.held_text_input(7UL, @text_host.TextInputEvent::new(
    @platform.WindowId::new(1L), 1L, 7UL, @text_host.Preedit(text="に", cursor=1),
  )).unwrap())
  let before = mounted.held_text.unwrap().session.snapshot()
  mounted.invalidate_layout()
  // Private-only probe: public stage intentionally rejects held owners. This
  // prepares a scene without authorizing publication or changing the session.
  assert_true(mounted.stage(view, 800.0, 480.0, 1.0, measure) is Err(_))
  let shifted = @view.column(@view.NodeKey::new("root"), [
    @view.button(@view.NodeKey::new("preceding"), "Before"),
    @view.text_field(key, @view.TextFieldProps::new("", "Name")),
  ])
  let candidate = mounted.prepare(shifted, 800.0, 480.0, 1.0, measure).unwrap()
  let staged = binding_for(candidate.bindings, key).unwrap().field.unwrap()
  let after = mounted.held_text.unwrap().session.snapshot()
  assert_true(staged.is_composing())
  assert_true(staged.bounds() != before.field().bounds())
  assert_eq(staged.document().text(), before.field().document().text())
  assert_eq(after.published_revision(), before.published_revision())
  assert_true(after.field().bounds() == before.field().bounds())
  assert_true(after.field().is_composing())
  mounted.dispose()
}
