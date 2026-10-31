///|
test "published model replacement cannot discard an unresolved original field" {
  let window = @platform.WindowId::new(1L)
  let mounted = Mounted::new(window)
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
  let frame = mounted.current_frame.unwrap()
  let token = owner.token
  assert_true(
    mounted.commit(view("replacement"), 640.0, 480.0, 1.0, owner_focus_measure)
    is Err(_),
  )
  assert_true(mounted.terminal_owner_is_current(owner))
  assert_true(mounted.runtime.is_current(token))
  assert_eq(mounted.current_frame.unwrap().revision(), frame.revision())
  assert_eq(mounted.focused_text().unwrap().document().text(), "")
  // An old record remains applicable exactly once to the same owner.
  let event = @text_host.TextInputEvent::new(
    window,
    1L,
    7UL,
    @text_host.Commit(text="日本"),
  )
  let delivery = mounted.reserve_owned_text(owner, event).unwrap()
  mounted.apply_owned_text(delivery).unwrap()
  mounted.note_owned_text(delivery).unwrap()
  assert_true(
    mounted.owned_text_action(delivery).unwrap()
    is Some(@view.TextChanged(_, "日本")),
  )
  assert_true(mounted.apply_owned_text(delivery) is Err(_))
  assert_eq(mounted.focused_text().unwrap().document().text(), "日本")
}

///|
test "active preedit resize remains owned until separately staged geometry resolves" {
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
    @text_host.Preedit(text="にほん", cursor=3),
  )
  let first = mounted.reserve_owned_text(owner, preedit).unwrap()
  mounted.apply_owned_text(first).unwrap()
  mounted.note_owned_text(first).unwrap()
  let old = binding_for(mounted.bindings, key).unwrap().field.unwrap()
  assert_true(old.is_composing())
  assert_eq(old.document().text(), "にほん")
  assert_true(
    mounted.commit(view, 800.0, 480.0, 1.5, owner_focus_measure) is Err(_),
  )
  let retained = binding_for(mounted.bindings, key).unwrap().field.unwrap()
  assert_eq(retained.revision(), old.revision())
  assert_true(retained.document() == old.document())
  assert_true(retained.is_composing())
  assert_true(mounted.terminal_owner_is_current(owner))
  // This separate public step is a local proposal only, not host or scene
  // publication; a later text observation invalidates the derived candidate.
  let proposal = mounted
    .stage_owned_text_geometry(
      owner, view, 800.0, 480.0, 1.5, owner_focus_measure,
    )
    .unwrap()
  assert_eq(
    mounted
    .inspect_staged_text_geometry(owner, proposal)
    .unwrap()
    .preview()
    .text(),
    "にほん",
  )
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
  assert_true(mounted.inspect_staged_text_geometry(owner, proposal) is Err(_))
  assert_eq(mounted.focused_text().unwrap().document().text(), "日本")
}
