///|
test "old epoch cannot deliver text after injected same key replacement" {
  let mounted = Mounted::new(@platform.WindowId::new(1L))
  let key = @view.NodeKey::new("name")
  let view = fn(value) {
    @view.column(@view.NodeKey::new("root"), [
      @view.text_field(key, @view.TextFieldProps::new(value, "Name")),
    ])
  }
  ignore(
    mounted.commit(view(""), 640.0, 480.0, 1.0, owner_focus_measure).unwrap(),
  )
  assert_true(mounted.focus(key))
  let owner = mounted.capture_terminal_text_owner(7UL).unwrap()
  let focus = mounted.scope.unwrap().snapshot().focus_owner()
  let generation = owner.observed_progress().0
  let replacement = mounted
    .stage(view("replacement"), 640.0, 480.0, 1.0, owner_focus_measure)
    .unwrap()
  assert_true(mounted.publish(replacement) is Err(_))
  // Fault injection: force the once-public replacement state after admission
  // refused it. Raw input must still reject even if another bug bypasses the
  // pre-publication fence.
  let proposed = binding_for(replacement.candidate.bindings, key).unwrap()
  for i = 0; i < mounted.bindings.length(); i = i + 1 {
    if mounted.bindings[i].id == owner.binding {
      mounted.bindings[i] = { ..proposed, token: Some(owner.token), }
    }
  }
  assert_true(mounted.scope.unwrap().snapshot().focus_owner() == focus)
  assert_true(
    binding_for(mounted.bindings, key).unwrap().field_generation != generation,
  )
  assert_false(mounted.terminal_owner_is_current(owner))
  let event = @text_host.TextInputEvent::new(
    @platform.WindowId::new(1L),
    1L,
    7UL,
    @text_host.Commit(text="日本"),
  )
  assert_true(mounted.reserve_owned_text(owner, event) is Err(_))
  assert_true(mounted.text_input(7UL, event) is Err(_))
  assert_true(mounted.begin_held_text(7UL) is Err(_))
  assert_eq(mounted.focused_text().unwrap().document().text(), "replacement")
  assert_false(mounted.has_pending_actions())
  assert_true(mounted.capture_terminal_text_owner(8UL) is Err(_))
  let new_epoch = @text_host.TextInputEvent::new(
    @platform.WindowId::new(1L),
    1L,
    8UL,
    @text_host.Commit(text="日本"),
  )
  assert_true(mounted.text_input(8UL, new_epoch) is Ok(false))
  assert_true(
    owner.matches_session(@platform.WindowId::new(1L), 7UL, owner.binding),
  )
  assert_eq(event.sequence(), 1L)
}

///|
test "matching original field still applies ordered preedit and commit once" {
  let window = @platform.WindowId::new(1L)
  let mounted = Mounted::new(window)
  let key = @view.NodeKey::new("name")
  let view = @view.column(@view.NodeKey::new("root"), [
    @view.text_field(key, @view.TextFieldProps::new("", "Name")),
  ])
  ignore(mounted.commit(view, 640.0, 480.0, 1.0, owner_focus_measure).unwrap())
  assert_true(mounted.focus(key))
  let owner = mounted.capture_terminal_text_owner(7UL).unwrap()
  let preedit = @text_host.TextInputEvent::new(
    window,
    1L,
    7UL,
    @text_host.Preedit(text="に", cursor=1),
  )
  let first = mounted.reserve_owned_text(owner, preedit).unwrap()
  mounted.apply_owned_text(first).unwrap()
  mounted.note_owned_text(first).unwrap()
  assert_true(mounted.focused_text().unwrap().composing())
  assert_eq(mounted.focused_text().unwrap().document().text(), "")
  let commit = @text_host.TextInputEvent::new(
    window,
    2L,
    7UL,
    @text_host.Commit(text="日本"),
  )
  let second = mounted.reserve_owned_text(owner, commit).unwrap()
  mounted.apply_owned_text(second).unwrap()
  mounted.note_owned_text(second).unwrap()
  assert_true(
    mounted.owned_text_action(second).unwrap()
    is Some(@view.TextChanged(_, "日本")),
  )
  assert_eq(mounted.focused_text().unwrap().document().text(), "日本")
  assert_true(mounted.reserve_owned_text(owner, commit) is Err(_))
  assert_true(mounted.apply_owned_text(second) is Err(_))
  assert_true(mounted.text_input(7UL, commit) is Ok(false))
  assert_eq(mounted.focused_text().unwrap().document().text(), "日本")
}
