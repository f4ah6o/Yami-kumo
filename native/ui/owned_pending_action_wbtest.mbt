///|
test "raw committed action survives deferred blur and close until caller takes it" {
  for close in [false, true] {
    let window = @platform.WindowId::new(1L)
    let mounted = Mounted::new(window)
    let key = @view.NodeKey::new("name")
    let view = @view.column(@view.NodeKey::new("root"), [
      @view.text_field(key, @view.TextFieldProps::new("", "Name")),
    ])
    ignore(
      mounted.commit(view, 640.0, 480.0, 1.0, owner_focus_measure).unwrap(),
    )
    assert_true(mounted.focus(key))
    let owner = mounted.capture_terminal_text_owner(7UL).unwrap()
    let preedit = @text_host.TextInputEvent::new(
      window,
      1L,
      7UL,
      @text_host.Preedit(text="にほん", cursor=3),
    )
    assert_true(mounted.text_input(7UL, preedit).unwrap())
    mounted.note_terminal_text_delivery(owner, preedit).unwrap()
    let boundary = @platform.Event::new(
      window,
      1L,
      1.0,
      if close {
        @platform.CloseRequested
      } else {
        @platform.FocusChanged(false)
      },
    )
    assert_true(mounted.handle_event(boundary) is Err(_))
    let commit = @text_host.TextInputEvent::new(
      window,
      2L,
      7UL,
      @text_host.Commit(text="日本"),
    )
    assert_true(mounted.text_input(7UL, commit).unwrap())
    mounted.note_terminal_text_delivery(owner, commit).unwrap()
    assert_true(mounted.has_pending_actions())
    assert_true(mounted.handle_event(boundary) is Err(_))
    assert_eq(mounted.last_sequence, 0L)
    assert_false(mounted.is_disposed())
    assert_true(mounted.has_pending_actions())
    let action = mounted.next_action()
    assert_true(action is Some(@view.TextChanged(_, "日本")))
    assert_false(mounted.has_pending_actions())
    // The action is now caller-owned. This test does not assert model apply.
    assert_true(mounted.handle_event(boundary) is Ok(true))
  }
}

///|
test "extracted owned action remains valid until original model acknowledgment" {
  let window = @platform.WindowId::new(1L)
  let mounted = Mounted::new(window)
  let key = @view.NodeKey::new("name")
  let view = @view.column(@view.NodeKey::new("root"), [
    @view.text_field(key, @view.TextFieldProps::new("", "Name")),
  ])
  ignore(mounted.commit(view, 640.0, 480.0, 1.0, owner_focus_measure).unwrap())
  assert_true(mounted.focus(key))
  let owner = mounted.capture_terminal_text_owner(7UL).unwrap()
  let event = @text_host.TextInputEvent::new(
    window,
    1L,
    7UL,
    @text_host.Commit(text="日本"),
  )
  let receipt = mounted.reserve_owned_text(owner, event).unwrap()
  mounted.apply_owned_text(receipt).unwrap()
  mounted.note_owned_text(receipt).unwrap()
  let action = mounted.owned_text_action(receipt).unwrap().unwrap()
  let model_name = match action {
    @view.TextChanged(_, value) => value
    _ => abort("unexpected model action")
  }
  assert_eq(model_name, "日本")
  assert_false(mounted.has_pending_actions())
  let close = @platform.Event::new(window, 1L, 1.0, @platform.CloseRequested)
  assert_true(mounted.handle_event(close) is Err(_))
  assert_eq(mounted.last_sequence, 0L)
  assert_false(mounted.is_disposed())
  assert_false(receipt.model_applied())
  let next = @text_host.TextInputEvent::new(
    window,
    2L,
    7UL,
    @text_host.Commit(text="語"),
  )
  assert_true(mounted.reserve_owned_text(owner, next) is Err(_))
  assert_true(mounted.text_input(7UL, next) is Err(_))
  // The caller's model has accepted the extracted action above.
  mounted.mark_owned_text_model_applied(receipt).unwrap()
  assert_true(mounted.handle_event(close) is Ok(true))
}

///|
test "failed preapply retains original delivery and blocks raw bypass or close" {
  let window = @platform.WindowId::new(1L)
  let mounted = Mounted::new(window)
  let key = @view.NodeKey::new("name")
  let fail = Ref(false)
  let measure = fn(value, size) {
    if fail.val && value == "日本" {
      Err(adapter_error("fixture measurement failure"))
    } else {
      owner_focus_measure(value, size)
    }
  }
  let view = @view.column(@view.NodeKey::new("root"), [
    @view.text_field(key, @view.TextFieldProps::new("", "Name")),
  ])
  ignore(mounted.commit(view, 640.0, 480.0, 1.0, measure).unwrap())
  assert_true(mounted.focus(key))
  let owner = mounted.capture_terminal_text_owner(7UL).unwrap()
  let event = @text_host.TextInputEvent::new(
    window,
    1L,
    7UL,
    @text_host.Commit(text="日本"),
  )
  let receipt = mounted.reserve_owned_text(owner, event).unwrap()
  fail.val = true
  assert_true(mounted.apply_owned_text(receipt) is Err(_))
  assert_false(receipt.applied())
  assert_true(mounted.text_input(7UL, event) is Err(_))
  let close = @platform.Event::new(window, 1L, 1.0, @platform.CloseRequested)
  assert_true(mounted.handle_event(close) is Err(_))
  assert_false(mounted.is_disposed())
  assert_eq(mounted.focused_text().unwrap().document().text(), "")
  fail.val = false
  mounted.apply_owned_text(receipt).unwrap()
  mounted.note_owned_text(receipt).unwrap()
  let action = mounted.owned_text_action(receipt).unwrap().unwrap()
  let model_name = match action {
    @view.TextChanged(_, value) => value
    _ => abort("unexpected action")
  }
  assert_eq(model_name, "日本")
  mounted.mark_owned_text_model_applied(receipt).unwrap()
  assert_true(mounted.handle_event(close) is Ok(true))
}
