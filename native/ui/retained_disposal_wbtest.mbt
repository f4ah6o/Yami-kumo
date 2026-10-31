///|
test "direct dispose retains owned action until model acknowledgment" {
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
  mounted.dispose()
  assert_false(mounted.is_disposed())
  assert_true(receipt.pending_action() is Some(@view.TextChanged(_, "日本")))
  let model_name = match action {
    @view.TextChanged(_, value) => value
    _ => abort("unexpected action")
  }
  assert_eq(model_name, "日本")
  mounted.mark_owned_text_model_applied(receipt).unwrap()
  // Model reflection alone is not a native cutoff or owner release receipt.
  assert_true(mounted.try_dispose() is Err(_))
  assert_false(mounted.is_disposed())
}

///|
test "active owner without local action is still insufficient for disposal" {
  let window = @platform.WindowId::new(1L)
  let mounted = Mounted::new(window)
  let key = @view.NodeKey::new("name")
  let view = @view.column(@view.NodeKey::new("root"), [
    @view.text_field(key, @view.TextFieldProps::new("", "Name")),
  ])
  ignore(mounted.commit(view, 640.0, 480.0, 1.0, owner_focus_measure).unwrap())
  assert_true(mounted.focus(key))
  let owner = mounted.capture_terminal_text_owner(7UL).unwrap()
  assert_false(mounted.has_pending_actions())
  assert_true(mounted.try_dispose() is Err(_))
  assert_false(mounted.is_disposed())
  let destroyed = @platform.Event::new(window, 1L, 1.0, @platform.Destroyed)
  assert_true(mounted.handle_event(destroyed) is Err(_))
  assert_true(mounted.deferred_platform_event is Some(_))
  assert_eq(mounted.last_sequence, 0L)
  assert_true(mounted.terminal_owner_is_current(owner))
  assert_true(mounted.try_dispose() is Err(_))
  assert_false(mounted.is_disposed())
}
