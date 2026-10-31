///|
test "deferred unhandled pointer release completes after observed cancel" {
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
  let release = @platform.Event::new(
    window,
    1L,
    1.0,
    @platform.Input(
      @primitives.PointerButtonReleased(
        position=@primitives.Point::new(1.0, 1.0).unwrap(),
        button=@primitives.Primary,
        modifiers=@primitives.Modifiers::none(),
      ),
    ),
  )
  assert_true(mounted.handle_event(release) is Err(_))
  let cancel = @text_host.TextInputEvent::new(
    window,
    2L,
    7UL,
    @text_host.Cancel,
  )
  let second = mounted.reserve_owned_text(owner, cancel).unwrap()
  mounted.apply_owned_text(second).unwrap()
  mounted.note_owned_text(second).unwrap()
  assert_true(mounted.handle_event(release) is Ok(false))
  assert_true(mounted.deferred_platform_event is None)
  assert_eq(mounted.last_sequence, 1L)
  assert_true(
    mounted.handle_event(
      @platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted),
    )
    is Ok(false),
  )
}

///|
test "deferred pointer release is not cleared for stale or unavailable dispatch" {
  for stale in [false, true] {
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
      @text_host.Preedit(text="に", cursor=1),
    )
    let first = mounted.reserve_owned_text(owner, preedit).unwrap()
    mounted.apply_owned_text(first).unwrap()
    mounted.note_owned_text(first).unwrap()
    let release = @platform.Event::new(
      window,
      1L,
      1.0,
      @platform.Input(
        @primitives.PointerButtonReleased(
          position=@primitives.Point::new(1.0, 1.0).unwrap(),
          button=@primitives.Primary,
          modifiers=@primitives.Modifiers::none(),
        ),
      ),
    )
    assert_true(mounted.handle_event(release) is Err(_))
    let cancel = @text_host.TextInputEvent::new(
      window,
      2L,
      7UL,
      @text_host.Cancel,
    )
    let second = mounted.reserve_owned_text(owner, cancel).unwrap()
    mounted.apply_owned_text(second).unwrap()
    mounted.note_owned_text(second).unwrap()
    if stale {
      mounted.last_sequence = 1L
    } else {
      mounted.invalidate_layout()
    }
    assert_true(mounted.handle_event(release) is Err(_))
    assert_true(mounted.deferred_platform_event is Some(_))
    assert_eq(mounted.last_sequence, if stale { 1L } else { 0L })
    assert_true(
      mounted.handle_event(
        @platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted),
      )
      is Err(_),
    )
  }
}
