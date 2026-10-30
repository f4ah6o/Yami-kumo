///|
/// Tests retain the owner for the duration of each scripted run.
fn run_test_settings(
  host : &@platform.Backend,
  platform : NativeSamplePlatform,
  measure : @components.TextMeasure,
  text_port~ : NativeTextInputPort? = None,
  accessibility_port~ : NativeTextAXPort? = None,
  dialog_port~ : NativeDialogAXPort? = None,
  next_platform_event~ : NativePlatformNext? = None,
  direct_text~ : NativeDirectText? = None,
  ordered_text~ : NativeOrderedTextPort? = None,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let owner = match SettingsRunOwner::new(
    host, platform, measure, text_port~, accessibility_port~, dialog_port~,
    next_platform_event~, direct_text~, ordered_text~,
  ) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  owner.drive()
}

///|
test "settings presents frames and releases a failed portable session before fallback" {
  let host = @testing.ScriptedBackend::new(800.0, 600.0, 1.5).unwrap()
  for _ in 0..<6 {
    ignore(host.enqueue(@platform.FrameCompleted, 1.5))
  }
  ignore(host.enqueue(@platform.Destroyed, 1.5))
  let ended = Ref(false)
  let armed = Ref(false)
  let released_before_fallback = Ref(false)
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) },
    fn(_, _) { Err(runner_error("test_update", "transport unavailable")) },
    fn(epoch) { Ok(epoch) },
    fn(_) {
      ended.val = true
      Ok(())
    },
    fn(_) { Ok(None) },
  )
  let direct : NativeDirectText = fn(_, enabled) {
    if enabled {
      released_before_fallback.val = ended.val
    }
    armed.val = enabled
    Ok(())
  }
  run_test_settings(
    host,
    Linux,
    text_runner_measure,
    text_port=Some(port),
    direct_text=Some(direct),
    next_platform_event=Some(fn(timeout) {
      ignore(host.set_metrics(800.0, 600.0, 1.5))
      host.next_event(timeout_ms=timeout)
    }),
  ).unwrap()
  assert_true(released_before_fallback.val)
  assert_true(ended.val)
  assert_true(!armed.val)
  assert_true(host.present_count() >= 2)
  let snapshot = host.last_present().unwrap()
  assert_eq(snapshot.scale(), 1.5)
  assert_eq(snapshot.viewport().size().width(), 800.0)
  assert_eq(snapshot.viewport().size().height(), 600.0)
}

///|
test "Settings applies an observed commit before a later window blur" {
  let window = @platform.WindowId::new(1L)
  let mounted = @ui.Mounted::new(window)
  let mut settings = @shared_settings.Model::new()
  ignore(
    mounted
    .commit(settings.view(), 640.0, 480.0, 1.0, text_runner_measure)
    .unwrap(),
  )
  assert_true(mounted.focus(@shared_settings.settings_name()))
  let session = {
    epoch: 7UL,
    binding: mounted.focused_text().unwrap().binding_id(),
  }
  let preedit = @text_host.TextInputEvent::new(
    window,
    1L,
    7UL,
    @text_host.Preedit(text="にほん", cursor=3),
  )
  let commit = @text_host.TextInputEvent::new(
    window,
    2L,
    7UL,
    @text_host.Commit(text="日本語"),
  )
  assert_true(deliver_text_observation(mounted, session, preedit).unwrap())
  assert_true(mounted.next_action() is None)
  assert_true(deliver_text_observation(mounted, session, commit).unwrap())
  while mounted.next_action() is Some(action) {
    settings = settings.update(@shared_settings.Ui(action))
  }
  assert_eq(settings.name(), "日本語")
  assert_false(deliver_text_observation(mounted, session, commit).unwrap())
  assert_true(mounted.next_action() is None)
  assert_true(
    mounted
    .handle_event(
      @platform.Event::new(window, 1L, 1.0, @platform.FocusChanged(false)),
    )
    .unwrap(),
  )
  assert_true(mounted.focused_text() is None)
  assert_eq(settings.name(), "日本語")
  mounted.dispose()
}

///|
test "Settings held Tab applies the old-owner direct commit before focus moves" {
  let mounted = @ui.Mounted::new(@platform.WindowId::new(1L))
  let mut settings = @shared_settings.Model::new()
  ignore(
    mounted
    .commit(settings.view(), 640.0, 480.0, 1.0, text_runner_measure)
    .unwrap(),
  )
  assert_true(mounted.focus(@shared_settings.settings_name()))
  let epoch = 11UL
  assert_true(mounted.begin_held_text(epoch).unwrap())
  let commit = @text_host.TextInputEvent::new(
    @platform.WindowId::new(1L),
    1L,
    epoch,
    @text_host.Commit(text="日本"),
  )
  assert_true(mounted.held_text_input(epoch, commit).unwrap())
  while mounted.next_action() is Some(action) {
    settings = settings.update(@shared_settings.Ui(action))
  }
  assert_eq(settings.name(), "日本")
  assert_false(mounted.held_text_input(epoch, commit).unwrap())
  // Simulate a host cutoff only after all already-observed records were
  // applied. The native host cutoff and its Busy cases have separate tests.
  mounted.finish_held_text(epoch).unwrap()
  assert_true(
    mounted
    .handle_event(
      @platform.Event::new(
        @platform.WindowId::new(1L),
        1L,
        1.0,
        @platform.Input(
          @primitives.KeyPressed(
            key=@primitives.Tab,
            repeat=false,
            modifiers=@primitives.Modifiers::none(),
          ),
        ),
      ),
    )
    .unwrap(),
  )
  assert_true(mounted.focused_text() is None)
  assert_eq(settings.name(), "日本")
  mounted.dispose()
}

///|
test "ordered Settings holds Tab until the old-owner commit and cutoff" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let window = @platform.WindowId::new(1L)
  let delivered = Ref(0)
  let cutoff_calls = Ref(0)
  let events : Ref[Array[NativeOrderedEvent]] = Ref([
    OrderedPlatform(
      @platform.Event::new(window, 1L, 1.0, @platform.FrameCompleted),
    ),
    OrderedPlatform(
      @platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted),
    ),
    OrderedPlatform(
      @platform.Event::new(window, 3L, 1.0, @platform.FrameCompleted),
    ),
    OrderedPlatform(
      @platform.Event::new(
        window,
        4L,
        1.0,
        @platform.Input(
          @primitives.KeyPressed(
            key=@primitives.Tab,
            repeat=false,
            modifiers=@primitives.Modifiers::none(),
          ),
        ),
      ),
    ),
    OrderedText(
      @text_host.TextInputEvent::new(
        window,
        1L,
        7UL,
        @text_host.Commit(text="日本"),
      ),
    ),
    OrderedPlatform(
      @platform.Event::new(
        window,
        5L,
        1.0,
        @platform.Input(
          @primitives.KeyReleased(
            key=@primitives.Tab,
            modifiers=@primitives.Modifiers::none(),
          ),
        ),
      ),
    ),
    OrderedPlatform(
      @platform.Event::new(window, 6L, 1.0, @platform.FrameCompleted),
    ),
    OrderedPlatform(
      @platform.Event::new(window, 7L, 1.0, @platform.FrameCompleted),
    ),
    OrderedPlatform(@platform.Event::new(window, 8L, 1.0, @platform.Destroyed)),
  ])
  let ordered = NativeOrderedTextPort::new(
    fn(_) {
      if events.val.is_empty() {
        return Ok(None)
      }
      let next = events.val.remove(0)
      if next is OrderedText(_) {
        delivered.val += 1
      }
      Ok(Some(next))
    },
    fn(epoch) {
      if epoch != 7UL {
        return Err(runner_error("test-cutoff", "wrong epoch"))
      }
      cutoff_calls.val += 1
      if delivered.val == 1 {
        Ok(())
      } else {
        Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "test-cutoff"))
      }
    },
  )
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) },
    fn(epoch, _) { Ok(epoch) },
    fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) },
    fn(_) { Ok(None) },
  )
  // No terminal queue receipt is available, so the run cannot claim success.
  assert_true(run_test_settings(
    host,
    Linux,
    text_runner_measure,
    text_port=Some(port),
    ordered_text=Some(ordered),
  ) is Err(_))
  assert_eq(delivered.val, 1)
  assert_true(cutoff_calls.val >= 2)
  let mut seen = false
  for item in host.last_present().unwrap().items() {
    match item {
      @scene.TextItem(text~, ..) | @scene.TextRunItem(text~, ..) if text ==
        "日本" => seen = true
      _ => ()
    }
  }
  assert_true(seen)
}

///|
test "ordered Settings keeps post-Tab preedit pending until observed commit" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let window = @platform.WindowId::new(1L)
  let stage = Ref(0)
  let cutoff_calls = Ref(0)
  let events : Ref[Array[NativeOrderedEvent]] = Ref([
    OrderedPlatform(
      @platform.Event::new(window, 1L, 1.0, @platform.FrameCompleted),
    ),
    OrderedPlatform(
      @platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted),
    ),
    OrderedPlatform(
      @platform.Event::new(window, 3L, 1.0, @platform.FrameCompleted),
    ),
    OrderedPlatform(
      @platform.Event::new(
        window,
        4L,
        1.0,
        @platform.Input(
          @primitives.KeyPressed(
            key=@primitives.Tab,
            repeat=false,
            modifiers=@primitives.Modifiers::none(),
          ),
        ),
      ),
    ),
    OrderedText(
      @text_host.TextInputEvent::new(
        window,
        1L,
        7UL,
        @text_host.Preedit(text="にほん", cursor=3),
      ),
    ),
    OrderedText(
      @text_host.TextInputEvent::new(
        window,
        2L,
        7UL,
        @text_host.Commit(text="日本"),
      ),
    ),
    OrderedPlatform(
      @platform.Event::new(window, 5L, 1.0, @platform.FrameCompleted),
    ),
    OrderedPlatform(@platform.Event::new(window, 6L, 1.0, @platform.Destroyed)),
  ])
  let ordered = NativeOrderedTextPort::new(
    fn(_) {
      if events.val.is_empty() {
        return Ok(None)
      }
      let next = events.val.remove(0)
      match next {
        OrderedText(event) =>
          match event.kind() {
            @text_host.Preedit(..) => stage.val = 1
            @text_host.Commit(..) => stage.val = 2
            _ => ()
          }
        _ => ()
      }
      Ok(Some(next))
    },
    fn(_) {
      cutoff_calls.val += 1
      if stage.val == 2 {
        Ok(())
      } else {
        Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "test-cutoff"))
      }
    },
  )
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) },
    fn(epoch, _) { Ok(epoch) },
    fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) },
    fn(_) { Ok(None) },
  )
  assert_true(run_test_settings(
    host,
    Linux,
    text_runner_measure,
    text_port=Some(port),
    ordered_text=Some(ordered),
  ) is Err(_))
  // One Busy before preedit, then success after its actual commit. Calling
  // cutoff while composing would add a third attempt and violate the fence.
  assert_eq(cutoff_calls.val, 2)
  assert_eq(stage.val, 2)
}

///|
test "ordered Settings rejects Tab during existing preedit without cancel" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let window = @platform.WindowId::new(1L)
  let cancels = Ref(0)
  let events : Ref[Array[NativeOrderedEvent]] = Ref([
    OrderedPlatform(
      @platform.Event::new(window, 1L, 1.0, @platform.FrameCompleted),
    ),
    OrderedPlatform(
      @platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted),
    ),
    OrderedPlatform(
      @platform.Event::new(window, 3L, 1.0, @platform.FrameCompleted),
    ),
    OrderedText(
      @text_host.TextInputEvent::new(
        window,
        1L,
        7UL,
        @text_host.Preedit(text="に", cursor=1),
      ),
    ),
    OrderedPlatform(
      @platform.Event::new(
        window,
        4L,
        1.0,
        @platform.Input(
          @primitives.KeyPressed(
            key=@primitives.Tab,
            repeat=false,
            modifiers=@primitives.Modifiers::none(),
          ),
        ),
      ),
    ),
  ])
  let ordered = NativeOrderedTextPort::new(
    fn(_) {
      if events.val.is_empty() {
        Ok(None)
      } else {
        Ok(Some(events.val.remove(0)))
      }
    },
    fn(_) { Err(runner_error("test-cutoff", "must not cut active preedit")) },
  )
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) },
    fn(epoch, _) { Ok(epoch) },
    fn(epoch) {
      cancels.val += 1
      Ok(epoch)
    },
    fn(_) { Ok(()) },
    fn(_) { Ok(None) },
  )
  assert_true(
    run_test_settings(
      host,
      Linux,
      text_runner_measure,
      text_port=Some(port),
      ordered_text=Some(ordered),
    )
    is Err(_),
  )
  assert_eq(cancels.val, 0)
}

///|
test "ordered Settings fails closed on resize while Tab is held" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let window = @platform.WindowId::new(1L)
  let cancels = Ref(0)
  let events : Ref[Array[NativeOrderedEvent]] = Ref([
    OrderedPlatform(
      @platform.Event::new(window, 1L, 1.0, @platform.FrameCompleted),
    ),
    OrderedPlatform(
      @platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted),
    ),
    OrderedPlatform(
      @platform.Event::new(window, 3L, 1.0, @platform.FrameCompleted),
    ),
    OrderedPlatform(
      @platform.Event::new(
        window,
        4L,
        1.0,
        @platform.Input(
          @primitives.KeyPressed(
            key=@primitives.Tab,
            repeat=false,
            modifiers=@primitives.Modifiers::none(),
          ),
        ),
      ),
    ),
    OrderedPlatform(
      @platform.Event::new(
        window,
        5L,
        1.0,
        @platform.Resized(width=800.0, height=600.0),
      ),
    ),
    OrderedText(
      @text_host.TextInputEvent::new(
        window,
        1L,
        7UL,
        @text_host.Commit(text="日本"),
      ),
    ),
  ])
  let ordered = NativeOrderedTextPort::new(
    fn(_) {
      if events.val.is_empty() {
        Ok(None)
      } else {
        Ok(Some(events.val.remove(0)))
      }
    },
    fn(_) {
      Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "test-cutoff"))
    },
  )
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) },
    fn(epoch, _) { Ok(epoch) },
    fn(epoch) {
      cancels.val += 1
      Ok(epoch)
    },
    fn(_) { Ok(()) },
    fn(_) { Ok(None) },
  )
  assert_true(
    run_test_settings(
      host,
      Linux,
      text_runner_measure,
      text_port=Some(port),
      ordered_text=Some(ordered),
    )
    is Err(_),
  )
  assert_eq(cancels.val, 0)
  assert_eq(events.val.length(), 1)
  assert_true(events.val[0] is OrderedText(_))
}

///|
test "ordered Settings reports bounded-buffer overflow during a held Tab" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let window = @platform.WindowId::new(1L)
  let cancels = Ref(0)
  let queue : Array[NativeOrderedEvent] = [
    OrderedPlatform(
      @platform.Event::new(window, 1L, 1.0, @platform.FrameCompleted),
    ),
    OrderedPlatform(
      @platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted),
    ),
    OrderedPlatform(
      @platform.Event::new(window, 3L, 1.0, @platform.FrameCompleted),
    ),
    OrderedPlatform(
      @platform.Event::new(
        window,
        4L,
        1.0,
        @platform.Input(
          @primitives.KeyPressed(
            key=@primitives.Tab,
            repeat=false,
            modifiers=@primitives.Modifiers::none(),
          ),
        ),
      ),
    ),
  ]
  for index in 0..<65 {
    queue.push(
      OrderedPlatform(
        @platform.Event::new(
          window,
          (index + 5).to_int64(),
          1.0,
          @platform.Input(
            @primitives.KeyReleased(
              key=@primitives.Character("x"),
              modifiers=@primitives.Modifiers::none(),
            ),
          ),
        ),
      ),
    )
  }
  queue.push(
    OrderedText(
      @text_host.TextInputEvent::new(
        window,
        1L,
        7UL,
        @text_host.Commit(text="日本"),
      ),
    ),
  )
  let events = Ref(queue)
  let ordered = NativeOrderedTextPort::new(
    fn(_) {
      if events.val.is_empty() {
        Ok(None)
      } else {
        Ok(Some(events.val.remove(0)))
      }
    },
    fn(_) {
      Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "test-cutoff"))
    },
  )
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) },
    fn(epoch, _) { Ok(epoch) },
    fn(epoch) {
      cancels.val += 1
      Ok(epoch)
    },
    fn(_) { Ok(()) },
    fn(_) { Ok(None) },
  )
  assert_true(
    run_test_settings(
      host,
      Linux,
      text_runner_measure,
      text_port=Some(port),
      ordered_text=Some(ordered),
    )
    is Err(_),
  )
  assert_eq(cancels.val, 0)
  // Stop polling before fetching the next record once the local buffer is
  // full; both still-live source records remain with the host.
  assert_eq(events.val.length(), 2)
  assert_true(events.val[0] is OrderedPlatform(_))
  assert_true(events.val[1] is OrderedText(_))
}

///|
test "ordered Settings timeout cannot resolve a held owner by cleanup" {
  for preview in [false, true] {
    let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
    let window = @platform.WindowId::new(1L)
    let cancel_count = Ref(0)
    let end_count = Ref(0)
    let cutoff_count = Ref(0)
    let events : Array[NativeOrderedEvent] = [
      OrderedPlatform(
        @platform.Event::new(window, 1L, 1.0, @platform.FrameCompleted),
      ),
      OrderedPlatform(
        @platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted),
      ),
      OrderedPlatform(
        @platform.Event::new(window, 3L, 1.0, @platform.FrameCompleted),
      ),
      OrderedPlatform(
        @platform.Event::new(
          window,
          4L,
          1.0,
          @platform.Input(
            @primitives.KeyPressed(
              key=@primitives.Tab,
              repeat=false,
              modifiers=@primitives.Modifiers::none(),
            ),
          ),
        ),
      ),
    ]
    if preview {
      events.push(
        OrderedText(
          @text_host.TextInputEvent::new(
            window,
            1L,
            7UL,
            @text_host.Preedit(text="に", cursor=1),
          ),
        ),
      )
    }
    let ordered = NativeOrderedTextPort::new(
      fn(_) {
        if events.is_empty() {
          Ok(None)
        } else {
          Ok(Some(events.remove(0)))
        }
      },
      fn(_) {
        cutoff_count.val += 1
        Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "test-cutoff"))
      },
    )
    let port = NativeTextInputPort::new(
      fn(_, _) { Ok(7UL) },
      fn(epoch, _) { Ok(epoch) },
      fn(epoch) {
        cancel_count.val += 1
        Ok(epoch)
      },
      fn(_) {
        end_count.val += 1
        Ok(())
      },
      fn(_) { Ok(None) },
    )
    let result = run_test_settings(
      host,
      Linux,
      text_runner_measure,
      text_port=Some(port),
      ordered_text=Some(ordered),
    )
    assert_true(result is Err(_))
    assert_eq(cancel_count.val, 0)
    assert_eq(end_count.val, 0)
    assert_true(cutoff_count.val > 0)
    if preview {
      assert_eq(cutoff_count.val, 1)
    }
  }
}

///|
test "ordered Settings exposes lost local buffer on close after resize" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let window = @platform.WindowId::new(1L)
  let delivered = Ref(0)
  let events : Array[NativeOrderedEvent] = [
    OrderedPlatform(
      @platform.Event::new(window, 1L, 1.0, @platform.FrameCompleted),
    ),
    OrderedPlatform(
      @platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted),
    ),
    OrderedPlatform(
      @platform.Event::new(
        window,
        3L,
        1.0,
        @platform.Resized(width=800.0, height=600.0),
      ),
    ),
    OrderedText(
      @text_host.TextInputEvent::new(
        window,
        1L,
        7UL,
        @text_host.Commit(text="日本"),
      ),
    ),
    OrderedPlatform(@platform.Event::new(window, 4L, 1.0, @platform.Destroyed)),
  ]
  let ordered = NativeOrderedTextPort::new(
    fn(_) {
      if events.is_empty() {
        return Ok(None)
      }
      let event = events.remove(0)
      if event is OrderedText(_) {
        delivered.val += 1
      }
      Ok(Some(event))
    },
    fn(_) {
      Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "test-cutoff"))
    },
  )
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) },
    fn(epoch, _) { Ok(epoch) },
    fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) },
    fn(_) { Ok(None) },
  )
  let result = run_test_settings(
    host,
    Linux,
    text_runner_measure,
    text_port=Some(port),
    ordered_text=Some(ordered),
  )
  match result {
    Err(error) =>
      assert_eq(
        error.message(),
        Some("structural event behind deferred input requires recovery"),
      )
    Ok(_) => fail("structural event must expose unresolved buffered input")
  }
  assert_eq(delivered.val, 1)
  assert_true(events.is_empty())
  let mut rendered_commit = false
  for item in host.last_present().unwrap().items() {
    match item {
      @scene.TextItem(text~, ..) | @scene.TextRunItem(text~, ..) if text ==
        "日本" => rendered_commit = true
      _ => ()
    }
  }
  assert_false(rendered_commit)
  // The caller gets no returned buffer or owner. This is a known P1, not a
  // preservation or replay test: the outer entry next stops the real host.
}

///|
test "retained Settings owner keeps buffered commit and terminal record on error" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let window = @platform.WindowId::new(1L)
  let events : Array[NativeOrderedEvent] = [
    OrderedPlatform(
      @platform.Event::new(window, 1L, 1.0, @platform.FrameCompleted),
    ),
    OrderedPlatform(
      @platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted),
    ),
    OrderedPlatform(
      @platform.Event::new(
        window,
        3L,
        1.0,
        @platform.Resized(width=800.0, height=600.0),
      ),
    ),
    OrderedText(
      @text_host.TextInputEvent::new(
        window,
        1L,
        7UL,
        @text_host.Commit(text="日本"),
      ),
    ),
    OrderedPlatform(@platform.Event::new(window, 4L, 1.0, @platform.Destroyed)),
  ]
  let ordered = NativeOrderedTextPort::new(
    fn(_) { Ok(if events.is_empty() { None } else { Some(events.remove(0)) }) },
    fn(_) {
      Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "test-cutoff"))
    },
  )
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) },
    fn(epoch, _) { Ok(epoch) },
    fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) },
    fn(_) { Ok(None) },
  )
  let owner = match run_native_settings_retained(
    host,
    Linux,
    text_runner_measure,
    text_port=Some(port),
    ordered_text=Some(ordered),
  ) {
    Suspended(value, _) => value
    _ => fail("the retained owner must be returned to the caller")
  }
  assert_eq(host.stop_count(), 0)
  assert_false(owner.can_stop())
  assert_true(owner.window() == window)
  assert_true(owner.text_owner() is Some((7UL, _)))
  assert_eq(owner.model().name(), "")
  assert_eq(owner.pending_records().length(), 1)
  match owner.pending_records()[0] {
    OrderedText(value) => {
      assert_eq(value.epoch(), 7UL)
      assert_eq(value.sequence(), 1L)
      assert_true(value.kind() is @text_host.Commit(text="日本"))
    }
    _ => fail("the original commit must remain owned")
  }
  assert_true(owner.inflight_record() is Some(OrderedPlatform(_)))
  assert_true(owner.inflight_receipt() is None)
  // Reconcile the original commit into its still-owned model without trying
  // to publish a scene for the destroyed window or stop the backend.
  owner.reconcile_terminal_commit().unwrap()
  assert_eq(owner.model().name(), "日本")
  assert_eq(owner.terminal_model_sequence(), 1L)
  assert_eq(owner.pending_records().length(), 0)
  assert_true(owner.inflight_record() is Some(OrderedPlatform(_)))
  assert_true(owner.reconcile_terminal_commit() is Err(_))
  // The fake native cutoff is Busy; the terminal record and host remain owned.
  assert_true(owner.try_terminal_text_cutoff() is Err(_))
  assert_false(owner.cutoff_completed())
  assert_true(owner.inflight_record() is Some(OrderedPlatform(_)))
  assert_eq(owner.model().name(), "日本")
  assert_false(owner.can_stop())
  assert_eq(host.stop_count(), 0)
  // Automatic replay is deliberately unavailable until owner-preserving
  // geometry/terminal recovery is implemented.
  assert_true(owner.drive() is Err(_))
  assert_eq(owner.pending_records().length(), 0)
  assert_true(owner.inflight_record() is Some(OrderedPlatform(_)))
  assert_eq(host.stop_count(), 0)
}

///|
test "one-shot entry refuses ordered input before fetching any records" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let calls = Ref(0)
  let ordered = NativeOrderedTextPort::new(
    fn(_) {
      calls.val += 1
      Ok(None)
    },
    fn(_) { Ok(()) },
  )
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  assert_true(run_native_settings_sample(
    host, Linux, text_runner_measure, text_port=Some(port), ordered_text=Some(ordered),
  ) is Err(_))
  assert_eq(calls.val, 0)
  assert_eq(host.stop_count(), 0)
}

///|
test "retained owner distinguishes session receipt from model publication" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port)).unwrap()
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, text_runner_measure).unwrap())
  assert_true(owner.mounted.focus(@shared_settings.settings_name()))
  let binding = owner.mounted.focused_text().unwrap().binding_id()
  owner.session = Some({ epoch: 7UL, binding, })
  assert_true(owner.mounted.begin_held_text(7UL).unwrap())
  let event = @text_host.TextInputEvent::new(
    owner.window, 1L, 7UL, @text_host.Commit(text="日本"),
  )
  owner.inflight = Some(OrderedText(event))
  assert_true(owner.mounted.held_text_input(7UL, event).unwrap())
  let receipt = owner.inflight_receipt().unwrap()
  assert_eq(receipt.sequence(), 1L)
  assert_true(receipt.action_required())
  assert_true(receipt.action_enqueued())
  assert_eq(receipt.transaction().snapshot().field().committed_document().text(), "日本")
  // Merely publishing a TextSession receipt has not updated the shared model.
  assert_eq(owner.model().name(), "")
  match owner.mounted.next_action() {
    Some(action) => owner.settings = owner.settings.update(@shared_settings.Ui(action))
    None => fail("model action must remain available")
  }
  assert_eq(owner.model().name(), "日本")
  assert_false(owner.mounted.held_text_input(7UL, event).unwrap())
  assert_true(owner.mounted.next_action() is None)
  assert_false(owner.can_stop())
  assert_eq(host.stop_count(), 0)
}

///|
test "terminal recovery never skips a buffered preedit prefix" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port)).unwrap()
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, text_runner_measure).unwrap())
  assert_true(owner.mounted.focus(@shared_settings.settings_name()))
  let field = owner.mounted.focused_text().unwrap()
  owner.session = Some({ epoch: 7UL, binding: field.binding_id(), })
  owner.host_epoch = Some(7UL)
  owner.terminal_owner = Some(owner.mounted.capture_terminal_text_owner(7UL).unwrap())
  owner.mounted.invalidate_layout()
  owner.suspended = true
  owner.buffered.push(OrderedText(@text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Preedit(text="にほん", cursor=3))))
  owner.buffered.push(OrderedText(@text_host.TextInputEvent::new(owner.window, 2L, 7UL, @text_host.Commit(text="日本"))))
  owner.inflight = Some(OrderedPlatform(@platform.Event::new(owner.window, 3L, 1.0, @platform.Destroyed)))
  assert_true(owner.reconcile_terminal_commit() is Err(_))
  assert_eq(owner.pending_records().length(), 2)
  assert_eq(owner.model().name(), "")
  owner.reconcile_terminal_observation().unwrap()
  assert_eq(owner.pending_records().length(), 1)
  assert_eq(owner.model().name(), "")
  assert_eq(owner.terminal_model_sequence(), 0L)
  owner.reconcile_terminal_commit().unwrap()
  assert_eq(owner.pending_records().length(), 0)
  assert_eq(owner.model().name(), "日本")
  assert_eq(owner.terminal_model_sequence(), 2L)
  assert_true(owner.reconcile_terminal_commit() is Err(_))
  assert_true(owner.inflight_record() is Some(OrderedPlatform(_)))
  assert_eq(host.stop_count(), 0)
}

///|
test "terminal recovery does not steal a held TextSession" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port)).unwrap()
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, text_runner_measure).unwrap())
  assert_true(owner.mounted.focus(@shared_settings.settings_name()))
  let field = owner.mounted.focused_text().unwrap()
  owner.session = Some({ epoch: 7UL, binding: field.binding_id(), })
  owner.terminal_owner = Some(owner.mounted.capture_terminal_text_owner(7UL).unwrap())
  assert_true(owner.mounted.begin_held_text(7UL).unwrap())
  owner.mounted.invalidate_layout()
  owner.suspended = true
  owner.buffered.push(OrderedText(@text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Commit(text="日本"))))
  owner.inflight = Some(OrderedPlatform(@platform.Event::new(owner.window, 3L, 1.0, @platform.Destroyed)))
  assert_true(owner.reconcile_terminal_commit() is Err(_))
  assert_eq(owner.pending_records().length(), 1)
  assert_eq(owner.model().name(), "")
  assert_eq(host.stop_count(), 0)
}

///|
test "terminal observed cancel rolls back preview without changing model" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port)).unwrap()
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, text_runner_measure).unwrap())
  assert_true(owner.mounted.focus(@shared_settings.settings_name()))
  let field = owner.mounted.focused_text().unwrap()
  owner.session = Some({ epoch: 7UL, binding: field.binding_id(), })
  owner.terminal_owner = Some(owner.mounted.capture_terminal_text_owner(7UL).unwrap())
  owner.mounted.invalidate_layout()
  owner.suspended = true
  owner.buffered.push(OrderedText(@text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Preedit(text="にほん", cursor=3))))
  owner.buffered.push(OrderedText(@text_host.TextInputEvent::new(owner.window, 2L, 7UL, @text_host.Cancel)))
  owner.buffered.push(OrderedText(@text_host.TextInputEvent::new(owner.window, 3L, 7UL, @text_host.Commit(text="新"))))
  owner.inflight = Some(OrderedPlatform(@platform.Event::new(owner.window, 4L, 1.0, @platform.Destroyed)))
  owner.reconcile_terminal_observation().unwrap()
  assert_eq(owner.model().name(), "")
  owner.reconcile_terminal_observation().unwrap()
  assert_eq(owner.model().name(), "")
  assert_eq(owner.terminal_model_sequence(), 0L)
  owner.reconcile_terminal_observation().unwrap()
  assert_eq(owner.model().name(), "新")
  assert_eq(owner.terminal_model_sequence(), 3L)
  assert_eq(owner.pending_records().length(), 0)
  assert_true(owner.inflight_record() is Some(OrderedPlatform(_)))
  assert_eq(host.stop_count(), 0)
}

///|
test "ordered foreign epoch remains owned instead of being silently dropped" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let window = @platform.WindowId::new(1L)
  let events : Array[NativeOrderedEvent] = [
    OrderedPlatform(@platform.Event::new(window, 1L, 1.0, @platform.FrameCompleted)),
    OrderedPlatform(@platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted)),
    OrderedText(@text_host.TextInputEvent::new(window, 1L, 8UL, @text_host.Commit(text="日本"))),
  ]
  let ordered = NativeOrderedTextPort::new(
    fn(_) { Ok(if events.is_empty() { None } else { Some(events.remove(0)) }) },
    fn(_) { Ok(()) },
  )
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = match run_native_settings_retained(host, Linux, text_runner_measure, text_port=Some(port), ordered_text=Some(ordered)) {
    Suspended(value, _) => value
    _ => fail("foreign epoch must remain suspended")
  }
  match owner.inflight_record() {
    Some(OrderedText(event)) => {
      assert_eq(event.epoch(), 8UL)
      assert_true(event.kind() is @text_host.Commit(text="日本"))
    }
    _ => fail("the original foreign record must be retained")
  }
  assert_eq(owner.model().name(), "")
  assert_false(owner.can_stop())
  assert_eq(host.stop_count(), 0)
}

///|
test "ordered sequence gap is rejected before field or action publication" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let window = @platform.WindowId::new(1L)
  let events : Array[NativeOrderedEvent] = [
    OrderedPlatform(@platform.Event::new(window, 1L, 1.0, @platform.FrameCompleted)),
    OrderedPlatform(@platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted)),
    OrderedText(@text_host.TextInputEvent::new(window, 2L, 7UL, @text_host.Commit(text="日本"))),
  ]
  let ordered = NativeOrderedTextPort::new(
    fn(_) { Ok(if events.is_empty() { None } else { Some(events.remove(0)) }) },
    fn(_) { Ok(()) },
  )
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = match run_native_settings_retained(host, Linux, text_runner_measure, text_port=Some(port), ordered_text=Some(ordered)) {
    Suspended(value, _) => value
    _ => fail("sequence gap must remain suspended")
  }
  match owner.inflight_record() {
    Some(OrderedText(event)) => {
      assert_eq(event.epoch(), 7UL)
      assert_eq(event.sequence(), 2L)
      assert_true(event.kind() is @text_host.Commit(text="日本"))
    }
    _ => fail("the original gap record must be retained")
  }
  assert_eq(owner.model().name(), "")
  assert_true(owner.mounted.next_action() is None)
  assert_eq(owner.mounted.focused_text().unwrap().document().text(), "")
  assert_false(owner.can_stop())
  assert_eq(host.stop_count(), 0)
}

///|
test "focus lost does not synthesize cancel for an armed preedit" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port)).unwrap()
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, text_runner_measure).unwrap())
  assert_true(owner.mounted.focus(@shared_settings.settings_name()))
  let lease = owner.mounted.capture_terminal_text_owner(7UL).unwrap()
  let preedit = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Preedit(text="にほん", cursor=3))
  owner.mounted.validate_terminal_text_delivery(lease, preedit).unwrap()
  assert_true(owner.mounted.text_input(7UL, preedit).unwrap())
  owner.mounted.note_terminal_text_delivery(lease, preedit).unwrap()
  assert_true(owner.mounted.focused_text().unwrap().composing())
  let lost = @text_host.TextInputEvent::new(owner.window, 2L, 7UL, @text_host.FocusLost)
  assert_true(owner.mounted.text_input(7UL, lost).unwrap())
  owner.mounted.note_terminal_text_delivery(lease, lost).unwrap()
  assert_true(owner.mounted.focused_text().unwrap().composing())
  assert_true(owner.mounted.next_action() is None)
  let cancelled = @text_host.TextInputEvent::new(owner.window, 3L, 7UL, @text_host.Cancel)
  assert_true(owner.mounted.text_input(7UL, cancelled).unwrap())
  owner.mounted.note_terminal_text_delivery(lease, cancelled).unwrap()
  assert_false(owner.mounted.focused_text().unwrap().composing())
  assert_true(owner.mounted.next_action() is None)
  assert_eq(host.stop_count(), 0)
}

///|
test "terminal cutoff needs an empty prefix and retains terminal ownership" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let calls = Ref(0)
  let pending : Array[NativeOrderedEvent] = []
  let ordered = NativeOrderedTextPort::new(
    fn(_) { Ok(if pending.is_empty() { None } else { Some(pending.remove(0)) }) },
    fn(epoch) {
      if epoch != 7UL {
        return Err(runner_error("terminal_cutoff", "unexpected epoch"))
      }
      calls.val += 1
      if !pending.is_empty() {
        return Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "terminal-cutoff"))
      }
      Ok(())
    },
  )
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port), ordered_text=Some(ordered)).unwrap()
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, text_runner_measure).unwrap())
  assert_true(owner.mounted.focus(@shared_settings.settings_name()))
  let field = owner.mounted.focused_text().unwrap()
  owner.session = Some({ epoch: 7UL, binding: field.binding_id(), })
  owner.host_epoch = Some(7UL)
  owner.terminal_owner = Some(owner.mounted.capture_terminal_text_owner(7UL).unwrap())
  owner.mounted.invalidate_layout()
  owner.suspended = true
  owner.buffered.push(OrderedText(@text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Preedit(text="にほん", cursor=3))))
  owner.inflight = Some(OrderedPlatform(@platform.Event::new(owner.window, 2L, 1.0, @platform.Destroyed)))
  assert_true(owner.try_terminal_text_cutoff() is Err(_))
  assert_eq(calls.val, 0)
  owner.reconcile_terminal_observation().unwrap()
  assert_true(owner.try_terminal_text_cutoff() is Err(_))
  assert_eq(calls.val, 0)
  owner.buffered.push(OrderedText(@text_host.TextInputEvent::new(owner.window, 2L, 7UL, @text_host.Cancel)))
  owner.reconcile_terminal_observation().unwrap()
  owner.session = Some({ epoch: 7UL, binding: field.binding_id() + 1UL, })
  assert_true(owner.try_terminal_text_cutoff() is Err(_))
  assert_eq(calls.val, 0)
  owner.session = Some({ epoch: 7UL, binding: field.binding_id(), })
  // A newly admitted commit keeps the native cutoff Busy. Moving it to the
  // local buffer and applying it to the original model precedes retry.
  pending.push(OrderedText(@text_host.TextInputEvent::new(owner.window, 3L, 7UL, @text_host.Commit(text="日本"))))
  assert_true(owner.try_terminal_text_cutoff() is Err(_))
  assert_false(owner.cutoff_completed())
  assert_eq(pending.length(), 1)
  owner.buffered.push((ordered.next)(0).unwrap().unwrap())
  owner.reconcile_terminal_observation().unwrap()
  assert_eq(owner.model().name(), "日本")
  owner.try_terminal_text_cutoff().unwrap()
  assert_eq(calls.val, 2)
  assert_true(owner.cutoff_completed())
  assert_true(owner.try_terminal_text_cutoff() is Err(_))
  assert_true(owner.inflight_record() is Some(OrderedPlatform(_)))
  assert_false(owner.can_stop())
  assert_eq(host.stop_count(), 0)
}

///|
test "begin update failure or replacement retains original admitted epoch" {
  for replaced in [false, true] {
    let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
    let window = @platform.WindowId::new(1L)
    let pending : Array[NativeOrderedEvent] = [
      OrderedPlatform(@platform.Event::new(window, 1L, 1.0, @platform.FrameCompleted)),
      OrderedPlatform(@platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted)),
    ]
    let ends = Ref(0)
    let ordered = NativeOrderedTextPort::new(
      fn(_) { Ok(if pending.is_empty() { None } else { Some(pending.remove(0)) }) },
      fn(_) { Ok(()) },
    )
    let port = NativeTextInputPort::new(
      fn(_, _) { Ok(7UL) },
      fn(_, _) {
        pending.push(OrderedText(@text_host.TextInputEvent::new(window, 1L, 7UL, @text_host.Commit(text="日本"))))
        if replaced { Ok(8UL) } else { Err(runner_error("test", "update failed")) }
      },
      fn(epoch) { Ok(epoch) },
      fn(_) { ends.val += 1; Ok(()) },
      fn(_) { Ok(None) },
    )
    let owner = match run_native_settings_retained(host, Linux, text_runner_measure, text_port=Some(port), ordered_text=Some(ordered)) {
      Suspended(value, _) => value
      _ => fail("update failure or replacement must suspend")
    }
    assert_true(owner.text_owner() is Some((7UL, _)))
    assert_eq(owner.host_epoch(), Some(if replaced { 8UL } else { 7UL }))
    let original = owner.session.unwrap()
    assert_true(owner.terminal_owner.unwrap().matches_session(window, original.epoch, original.binding))
    assert_eq(owner.model().name(), "")
    assert_true(owner.mounted.next_action() is None)
    assert_eq(pending.length(), 1)
    match pending[0] {
      OrderedText(event) => {
        assert_eq(event.epoch(), 7UL)
        assert_true(event.kind() is @text_host.Commit(text="日本"))
      }
      _ => fail("the original admitted commit must remain with the host")
    }
    assert_eq(ends.val, 0)
    assert_eq(host.stop_count(), 0)
    assert_false(owner.can_stop())
  }
}

///|
test "later update epoch replacement retains original owner and admitted record" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let window = @platform.WindowId::new(1L)
  let pending : Array[NativeOrderedEvent] = [
    OrderedPlatform(@platform.Event::new(window, 1L, 1.0, @platform.FrameCompleted)),
    OrderedPlatform(@platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted)),
    OrderedText(@text_host.TextInputEvent::new(window, 1L, 7UL, @text_host.Commit(text="日"))),
    OrderedPlatform(@platform.Event::new(window, 3L, 1.0, @platform.FrameCompleted)),
  ]
  let updates = Ref(0)
  let ends = Ref(0)
  let ordered = NativeOrderedTextPort::new(
    fn(_) { Ok(if pending.is_empty() { None } else { Some(pending.remove(0)) }) },
    fn(_) { Ok(()) },
  )
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) },
    fn(_, _) {
      updates.val += 1
      if updates.val == 1 { return Ok(7UL) }
      pending.push(OrderedText(@text_host.TextInputEvent::new(window, 2L, 7UL, @text_host.Commit(text="本"))))
      Ok(8UL)
    },
    fn(epoch) { Ok(epoch) },
    fn(_) { ends.val += 1; Ok(()) },
    fn(_) { Ok(None) },
  )
  let owner = match run_native_settings_retained(host, Linux, text_runner_measure, text_port=Some(port), ordered_text=Some(ordered)) {
    Suspended(value, _) => value
    _ => fail("replacement must retain its original owner")
  }
  assert_eq(updates.val, 2)
  assert_true(owner.text_owner() is Some((7UL, _)))
  assert_eq(owner.host_epoch(), Some(8UL))
  assert_eq(owner.model().name(), "日")
  assert_eq(pending.length(), 1)
  assert_eq(ends.val, 0)
  assert_eq(host.stop_count(), 0)
}

///|
test "terminal cutoff rejects reentry before a Busy result" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let calls = Ref(0)
  let rejected = Ref(false)
  let captured : Ref[SettingsRunOwner?] = Ref(None)
  let ordered = NativeOrderedTextPort::new(
    fn(_) { Ok(None) },
    fn(_) {
      calls.val += 1
      if calls.val == 1 {
        match captured.val {
          Some(owner) => rejected.val = owner.try_terminal_text_cutoff() is Err(_)
          None => ()
        }
        return Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "terminal-cutoff"))
      }
      Ok(())
    },
  )
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port), ordered_text=Some(ordered)).unwrap()
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, text_runner_measure).unwrap())
  assert_true(owner.mounted.focus(@shared_settings.settings_name()))
  let field = owner.mounted.focused_text().unwrap()
  owner.session = Some({ epoch: 7UL, binding: field.binding_id(), })
  owner.host_epoch = Some(7UL)
  owner.terminal_owner = Some(owner.mounted.capture_terminal_text_owner(7UL).unwrap())
  owner.suspended = true
  owner.inflight = Some(OrderedPlatform(@platform.Event::new(owner.window, 1L, 1.0, @platform.Destroyed)))
  captured.val = Some(owner)
  assert_true(owner.try_terminal_text_cutoff() is Err(_))
  assert_true(rejected.val)
  assert_eq(calls.val, 1)
  assert_false(owner.cutoff_completed())
  assert_true(owner.inflight_record() is Some(OrderedPlatform(_)))
  assert_false(owner.can_stop())
  assert_eq(host.stop_count(), 0)
}
