///|
test "later platform event cannot overtake deferred Tab while preedit resolves" {
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
        repeat=false,
        modifiers=@primitives.Modifiers::none(),
      ),
    ),
  )
  let frame = @platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted)
  assert_true(mounted.handle_event(tab) is Err(_))
  assert_true(mounted.handle_event(frame) is Err(_))
  let colliding = @platform.Event::new(
    window,
    1L,
    1.0,
    @platform.Input(
      @primitives.KeyPressed(
        key=@primitives.Tab,
        repeat=false,
        modifiers=@primitives.Modifiers::new(
          shift=true,
          control=false,
          alt=false,
          meta=false,
        ),
      ),
    ),
  )
  assert_true(mounted.handle_event(colliding) is Err(_))
  assert_eq(mounted.last_sequence, 0L)
  let cancel = @text_host.TextInputEvent::new(
    window,
    2L,
    7UL,
    @text_host.Cancel,
  )
  let second = mounted.reserve_owned_text(owner, cancel).unwrap()
  mounted.apply_owned_text(second).unwrap()
  mounted.note_owned_text(second).unwrap()
  assert_true(mounted.handle_event(frame) is Err(_))
  assert_false(mounted.focus(@view.NodeKey::new("next")))
  assert_true(mounted.handle_event(tab) is Ok(true))
  assert_eq(mounted.last_sequence, 1L)
  assert_true(mounted.handle_event(frame) is Ok(false))
  assert_eq(mounted.last_sequence, 2L)
}

///|
test "deferred blur waits for committed model action and cannot be overtaken" {
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
  assert_true(mounted.text_input(7UL, preedit).unwrap())
  mounted.note_terminal_text_delivery(owner, preedit).unwrap()
  let blur = @platform.Event::new(
    window,
    1L,
    1.0,
    @platform.FocusChanged(false),
  )
  let frame = @platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted)
  assert_true(mounted.handle_event(blur) is Err(_))
  let commit = @text_host.TextInputEvent::new(
    window,
    2L,
    7UL,
    @text_host.Commit(text="日本"),
  )
  assert_true(mounted.text_input(7UL, commit).unwrap())
  mounted.note_terminal_text_delivery(owner, commit).unwrap()
  assert_true(mounted.has_pending_actions())
  assert_true(mounted.handle_event(blur) is Err(_))
  assert_true(mounted.handle_event(frame) is Err(_))
  assert_eq(mounted.last_sequence, 0L)
  assert_true(mounted.next_action() is Some(@view.TextChanged(_, "日本")))
  assert_true(mounted.handle_event(blur) is Ok(true))
  assert_true(mounted.handle_event(frame) is Ok(false))
  assert_eq(mounted.last_sequence, 2L)
}

///|
test "stale deferred intent is not reported as a successfully handled event" {
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
  assert_true(mounted.text_input(7UL, preedit).unwrap())
  mounted.note_terminal_text_delivery(owner, preedit).unwrap()
  let tab = @platform.Event::new(
    window,
    1L,
    1.0,
    @platform.Input(
      @primitives.KeyPressed(
        key=@primitives.Tab,
        repeat=false,
        modifiers=@primitives.Modifiers::none(),
      ),
    ),
  )
  assert_true(mounted.handle_event(tab) is Err(_))
  let cancel = @text_host.TextInputEvent::new(
    window,
    2L,
    7UL,
    @text_host.Cancel,
  )
  assert_true(mounted.text_input(7UL, cancel).unwrap())
  mounted.note_terminal_text_delivery(owner, cancel).unwrap()
  // Fault injection models an earlier partial dispatch which advanced the
  // watermark. The stale intent remains pending and later events stay fenced.
  mounted.last_sequence = 1L
  assert_true(mounted.handle_event(tab) is Err(_))
  assert_true(
    mounted.handle_event(
      @platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted),
    )
    is Err(_),
  )
  assert_true(mounted.deferred_platform_event is Some(_))
}
