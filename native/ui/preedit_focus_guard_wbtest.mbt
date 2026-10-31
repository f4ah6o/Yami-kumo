///|
test "active preedit is not cancelled by requested focus on another field" {
  let window = @platform.WindowId::new(1L)
  let mounted = Mounted::new(window)
  let key = @view.NodeKey::new("name")
  let next = @view.NodeKey::new("next")
  let view = @view.column(@view.NodeKey::new("root"), [
    @view.text_field(key, @view.TextFieldProps::new("", "Name")),
    @view.button(next, "Next"),
  ])
  ignore(mounted.commit(view, 640.0, 480.0, 1.0, owner_focus_measure).unwrap())
  assert_true(mounted.focus(key))
  let owner = mounted.capture_terminal_text_owner(7UL).unwrap()
  let preedit = @text_host.TextInputEvent::new(
    window,
    1L,
    7UL,
    @text_host.Preedit(text="にほん", cursor=3),
  )
  let first = mounted.reserve_owned_text(owner, preedit).unwrap()
  mounted.apply_owned_text(first).unwrap()
  mounted.note_owned_text(first).unwrap()
  assert_false(mounted.focus(next))
  let retained = binding_for(mounted.bindings, key).unwrap().field.unwrap()
  assert_true(retained.is_composing())
  assert_eq(retained.document().text(), "にほん")
  assert_eq(retained.committed_document().text(), "")
  assert_true(mounted.terminal_owner_is_current(owner))
  let commit = @text_host.TextInputEvent::new(
    window,
    2L,
    7UL,
    @text_host.Commit(text="日本"),
  )
  let delivery = mounted.reserve_owned_text(owner, commit).unwrap()
  mounted.apply_owned_text(delivery).unwrap()
  mounted.note_owned_text(delivery).unwrap()
  assert_true(
    mounted.owned_text_action(delivery).unwrap()
    is Some(@view.TextChanged(_, "日本")),
  )
  assert_eq(mounted.focused_text().unwrap().document().text(), "日本")
  assert_true(mounted.apply_owned_text(delivery) is Err(_))
}

///|
test "preedit defers ordered Tab blur and close until observed cancel" {
  let window = @platform.WindowId::new(1L)
  let mounted = Mounted::new(window)
  let key = @view.NodeKey::new("name")
  let view = @view.column(@view.NodeKey::new("root"), [
    @view.text_field(key, @view.TextFieldProps::new("", "Name")),
    @view.button(@view.NodeKey::new("next"), "Next"),
  ])
  ignore(mounted.commit(view, 640.0, 480.0, 1.0, owner_focus_measure).unwrap())
  assert_true(mounted.focus(key))
  let owner = mounted.capture_terminal_text_owner(7UL).unwrap()
  let preedit = @text_host.TextInputEvent::new(
    window,
    1L,
    7UL,
    @text_host.Preedit(text="にほん", cursor=3),
  )
  let first = mounted.reserve_owned_text(owner, preedit).unwrap()
  mounted.apply_owned_text(first).unwrap()
  mounted.note_owned_text(first).unwrap()
  let tab = @platform.Event::new(
    window,
    1L,
    1.0,
    @platform.Input(
      @primitives.KeyPressed(
        key=@primitives.Tab,
        modifiers=@primitives.Modifiers::none(),
        repeat=false,
      ),
    ),
  )
  let blur = @platform.Event::new(
    window,
    2L,
    1.0,
    @platform.FocusChanged(false),
  )
  let close = @platform.Event::new(window, 3L, 1.0, @platform.CloseRequested)
  let destroyed = @platform.Event::new(window, 4L, 1.0, @platform.Destroyed)
  let shift_tab = @platform.Event::new(
    window,
    1L,
    1.0,
    @platform.Input(
      @primitives.KeyPressed(
        key=@primitives.Tab,
        modifiers=@primitives.Modifiers::new(
          shift=true,
          control=false,
          alt=false,
          meta=false,
        ),
        repeat=false,
      ),
    ),
  )
  // These are independent possible next events, not one admitted FIFO.
  for event in [tab, shift_tab, blur, close, destroyed] {
    assert_true(mounted.handle_event(event) is Err(_))
    assert_eq(mounted.last_sequence, 0L)
    assert_true(mounted.terminal_owner_is_current(owner))
    assert_true(
      binding_for(mounted.bindings, key).unwrap().field.unwrap().is_composing(),
    )
  }
  assert_eq(tab.sequence(), 1L)
  assert_eq(blur.sequence(), 2L)
  assert_false(mounted.is_disposed())
  let cancel = @text_host.TextInputEvent::new(
    window,
    2L,
    7UL,
    @text_host.Cancel,
  )
  let second = mounted.reserve_owned_text(owner, cancel).unwrap()
  mounted.apply_owned_text(second).unwrap()
  mounted.note_owned_text(second).unwrap()
  assert_false(
    binding_for(mounted.bindings, key).unwrap().field.unwrap().is_composing(),
  )
  assert_eq(mounted.focused_text().unwrap().document().text(), "")
  assert_false(mounted.has_pending_actions())
  // The retained event may now be retried by the original caller. This test
  // carries the exact event locally; it does not establish host FIFO policy.
  assert_true(mounted.handle_event(tab) is Ok(true))
  assert_eq(mounted.last_sequence, 1L)
  assert_true(mounted.handle_event(blur) is Ok(true))
  assert_eq(mounted.last_sequence, 2L)
}
