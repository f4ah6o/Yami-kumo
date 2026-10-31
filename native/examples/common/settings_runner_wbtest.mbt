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
  let entry = SettingsEntryController::start(
    host,
    Linux,
    text_runner_measure,
    text_port=Some(port),
    ordered_text=Some(ordered),
  )
  assert_true(entry.suspended())
  assert_true(entry.error() is Some(_))
  let owner = entry.owner().unwrap()
  assert_true(entry.try_stop() is Err(_))
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
  let progress = entry.terminal_step(ApplyNext).unwrap()
  assert_true(progress is ModelApplied(1L, true))
  assert_false(progress.scene_published())
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
  assert_true(entry.try_stop() is Err(_))
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
test "characterization pending unrelated action precedes applied commit" {
  // This characterizes the pre-existing ambiguity. PASS here means that the
  // hazardous ordering was reproduced, not that action ownership is fixed.
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port)).unwrap()
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, text_runner_measure).unwrap())
  assert_true(owner.mounted.focus(@shared_settings.settings_name()))
  let lease = owner.mounted.capture_terminal_text_owner(7UL).unwrap()
  let save = owner.mounted.callback(@shared_settings.settings_save()).unwrap()
  assert_true(owner.mounted.activate(save))
  let event = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Commit(text="日本"))
  owner.mounted.validate_terminal_text_delivery(lease, event).unwrap()
  assert_true(owner.mounted.text_input(7UL, event).unwrap())
  assert_eq(owner.mounted.focused_text().unwrap().document().text(), "日本")
  assert_eq(owner.model().name(), "")
  assert_true(owner.mounted.next_terminal_text_action(lease) is Err(_))
  assert_true(owner.mounted.next_action() is Some(@view.Activate(_)))
  assert_true(owner.mounted.next_action() is Some(@view.TextChanged(_, "日本")))
  assert_eq(host.stop_count(), 0)
}

///|
test "owned delivery refuses an earlier action before applying commit" {
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
  owner.terminal_owner = Some(owner.mounted.capture_terminal_text_owner(7UL).unwrap())
  let save = owner.mounted.callback(@shared_settings.settings_save()).unwrap()
  assert_true(owner.mounted.activate(save))
  let event = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Commit(text="日本"))
  owner.inflight = Some(OrderedText(event))
  assert_true(owner.deliver_owned_observation(event) is Err(_))
  assert_true(owner.owned_text_delivery() is None)
  assert_true(owner.inflight_record() is Some(OrderedText(_)))
  assert_eq(owner.mounted.focused_text().unwrap().document().text(), "")
  assert_eq(owner.model().name(), "")
  assert_true(owner.mounted.next_action() is Some(@view.Activate(_)))
  assert_true(owner.mounted.next_action() is None)
  assert_eq(host.stop_count(), 0)
}

///|
test "owned delivery retains extracted action until model application" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port)).unwrap()
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, text_runner_measure).unwrap())
  assert_true(owner.mounted.focus(@shared_settings.settings_name()))
  let lease = owner.mounted.capture_terminal_text_owner(7UL).unwrap()
  let event = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Commit(text="日本"))
  let receipt = owner.mounted.reserve_owned_text(lease, event).unwrap()
  owner.owned_delivery = Some(receipt)
  assert_true(receipt.identity() is (_, 7UL, _, _, 1L))
  assert_false(receipt.owner_noted())
  assert_false(receipt.model_applied())
  owner.mounted.apply_owned_text(receipt).unwrap()
  assert_true(receipt.applied())
  assert_true(receipt.action_required() is Some(true))
  assert_true(receipt.pending_action() is Some(@view.TextChanged(_, "日本")))
  assert_true(owner.mounted.mark_owned_text_model_applied(receipt) is Err(_))
  assert_true(owner.mounted.apply_owned_text(receipt) is Err(_))
  assert_true(owner.mounted.complete_owned_text_evidence(receipt) is Err(_))
  owner.mounted.note_owned_text(receipt).unwrap()
  assert_true(receipt.owner_noted())
  assert_true(owner.mounted.note_owned_text(receipt) is Err(_))
  assert_true(owner.mounted.mark_owned_text_model_applied(receipt) is Err(_))
  let action = owner.mounted.owned_text_action(receipt).unwrap().unwrap()
  assert_true(action is @view.TextChanged(_, "日本"))
  assert_true(receipt.pending_action() is Some(@view.TextChanged(_, "日本")))
  assert_eq(owner.model().name(), "")
  let next = owner.settings.update(@shared_settings.Ui(action))
  owner.mounted.mark_owned_text_model_applied(receipt).unwrap()
  owner.settings = next
  assert_true(receipt.model_applied())
  assert_eq(owner.model().name(), "日本")
  assert_true(receipt.pending_action() is None)
  assert_true(owner.mounted.mark_owned_text_model_applied(receipt) is Err(_))
  assert_true(owner.mounted.owned_text_action(receipt) is Err(_))
  assert_eq(owner.model().name(), "日本")
  assert_eq(host.stop_count(), 0)
}

///|
test "applied owned commit survives focus change without reapplication" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port)).unwrap()
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, text_runner_measure).unwrap())
  assert_true(owner.mounted.focus(@shared_settings.settings_name()))
  let lease = owner.mounted.capture_terminal_text_owner(7UL).unwrap()
  let event = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Commit(text="日本"))
  let receipt = owner.mounted.reserve_owned_text(lease, event).unwrap()
  owner.owned_delivery = Some(receipt)
  owner.mounted.apply_owned_text(receipt).unwrap()
  assert_true(receipt.applied())
  assert_true(receipt.action_required() is Some(true))
  assert_true(receipt.pending_action() is Some(@view.TextChanged(_, "日本")))
  assert_true(owner.mounted.focus(@shared_settings.settings_save()))
  assert_true(owner.mounted.note_owned_text(receipt) is Err(_))
  assert_true(owner.mounted.apply_owned_text(receipt) is Err(_))
  assert_true(owner.mounted.mark_owned_text_model_applied(receipt) is Err(_))
  assert_true(owner.owned_text_delivery() is Some(_))
  assert_true(receipt.pending_action() is Some(@view.TextChanged(_, "日本")))
  assert_eq(owner.model().name(), "")
  assert_true(owner.mounted.focus(@shared_settings.settings_name()))
  assert_true(owner.mounted.note_owned_text(receipt) is Err(_))
  assert_true(owner.mounted.owned_text_action(receipt) is Err(_))
  assert_eq(owner.mounted.focused_text().unwrap().document().text(), "日本")
  assert_eq(host.stop_count(), 0)
}

///|
test "suspended applied delivery reconciles retained action once" {
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
  let lease = owner.mounted.capture_terminal_text_owner(7UL).unwrap()
  owner.terminal_owner = Some(lease)
  let event = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Commit(text="日本"))
  owner.inflight = Some(OrderedText(event))
  owner.acknowledged_receipts.push({
    receipt: NativeRetainedReceipt::new(Some(OrderedText(event)), owner.window, 42, binding, 7UL, fn() { Ok(()) }),
    stage: ReceiptAcknowledgedOnly,
  })
  let receipt = owner.mounted.reserve_owned_text(lease, event).unwrap()
  owner.owned_delivery = Some(receipt)
  owner.mounted.apply_owned_text(receipt).unwrap()
  owner.mounted.note_owned_text(receipt).unwrap()
  assert_true(owner.mounted.owned_text_action(receipt).unwrap() is Some(@view.TextChanged(_, "日本")))
  assert_true(receipt.pending_action() is Some(@view.TextChanged(_, "日本")))
  owner.suspended = true
  let entry : SettingsEntryController = {
    host, outcome: Suspended(owner, runner_error("test", "interrupted")),
    stop_attempted: false, stopped: false,
  }
  assert_true(entry.owned_delivery_sequence() is Some(42L))
  assert_true(entry.reconcile_owned_sequence(43L) is Err(_))
  owner.session = Some({ epoch: 7UL, binding: binding + 1UL, })
  assert_true(entry.reconcile_owned_sequence(42L) is Err(_))
  assert_eq(owner.model().name(), "")
  owner.session = Some({ epoch: 7UL, binding, })
  owner.inflight = Some(OrderedText(@text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Commit(text="偽"))))
  assert_true(entry.owned_delivery_sequence() is None)
  assert_true(entry.reconcile_owned_sequence(42L) is Err(_))
  owner.inflight = Some(OrderedText(event))
  assert_eq(owner.model().name(), "")
  entry.reconcile_owned_sequence(42L).unwrap()
  assert_eq(owner.model().name(), "日本")
  assert_true(owner.receipt_stage_for_sequence(42L) is Some(ReceiptModelApplied))
  assert_true(owner.owned_text_delivery() is None)
  assert_true(owner.inflight_record() is None)
  assert_true(entry.reconcile_owned_sequence(42L) is Err(_))
  assert_eq(owner.model().name(), "日本")
  assert_false(owner.can_stop())
  assert_eq(host.stop_count(), 0)
}

///|
test "focus change after action extraction retains the original action" {
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
  let lease = owner.mounted.capture_terminal_text_owner(7UL).unwrap()
  owner.terminal_owner = Some(lease)
  let event = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Commit(text="日本"))
  owner.inflight = Some(OrderedText(event))
  let receipt = owner.mounted.reserve_owned_text(lease, event).unwrap()
  owner.owned_delivery = Some(receipt)
  owner.mounted.apply_owned_text(receipt).unwrap()
  owner.mounted.note_owned_text(receipt).unwrap()
  assert_true(owner.mounted.owned_text_action(receipt).unwrap() is Some(@view.TextChanged(_, "日本")))
  assert_true(owner.mounted.focus(@shared_settings.settings_save()))
  owner.suspended = true
  assert_true(owner.mounted.mark_owned_text_model_applied(receipt) is Err(_))
  assert_true(owner.reconcile_owned_delivery() is Err(_))
  assert_true(receipt.pending_action() is Some(@view.TextChanged(_, "日本")))
  assert_true(owner.owned_text_delivery() is Some(_))
  assert_true(owner.inflight_record() is Some(OrderedText(_)))
  assert_eq(owner.model().name(), "")
  assert_true(owner.mounted.apply_owned_text(receipt) is Err(_))
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
  owner.host_epoch_verified = true
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
  owner.host_epoch_verified = true
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
  owner.host_epoch_verified = false
  assert_true(owner.try_terminal_text_cutoff() is Err(_))
  assert_eq(calls.val, 0)
  owner.host_epoch_verified = true
  // A newly admitted commit keeps the native cutoff Busy. Moving it to the
  // local buffer and applying it to the original model precedes retry.
  pending.push(OrderedText(@text_host.TextInputEvent::new(owner.window, 3L, 7UL, @text_host.Commit(text="日本"))))
  assert_true(owner.try_terminal_text_cutoff() is Err(_))
  assert_false(owner.cutoff_completed())
  assert_eq(pending.length(), 1)
  assert_true(owner.terminal_step(PollOnce).unwrap() is RecordBuffered)
  assert_true(owner.terminal_step(ApplyNext).unwrap() is ModelApplied(3L, true))
  assert_eq(owner.model().name(), "日本")
  assert_true(owner.terminal_step(TryTextCutoff).unwrap() is TextCutoffCompleted)
  assert_eq(calls.val, 2)
  assert_true(owner.cutoff_completed())
  assert_true(owner.try_terminal_text_cutoff() is Err(_))
  pending.push(OrderedText(@text_host.TextInputEvent::new(owner.window, 4L, 7UL, @text_host.Commit(text="古"))))
  assert_true(owner.terminal_step(PollOnce) is Err(_))
  assert_eq(pending.length(), 1)
  owner.buffered.push(pending[0])
  assert_true(owner.terminal_step(ApplyNext) is Err(_))
  assert_true(owner.reconcile_terminal_observation() is Err(_))
  assert_eq(owner.pending_records().length(), 1)
  assert_eq(owner.model().name(), "日本")
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
    assert_eq(owner.host_epoch_verified(), replaced)
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
  owner.host_epoch_verified = true
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

///|
test "terminal control enforces backpressure before polling host" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let reads = Ref(0)
  let ordered = NativeOrderedTextPort::new(
    fn(_) { reads.val += 1; Ok(None) }, fn(_) { Ok(()) },
  )
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port), ordered_text=Some(ordered)).unwrap()
  owner.suspended = true
  owner.inflight = Some(OrderedPlatform(@platform.Event::new(owner.window, 1L, 1.0, @platform.Destroyed)))
  for _ in 0..<64 {
    owner.buffered.push(OrderedPlatform(@platform.Event::new(owner.window, 2L, 1.0, @platform.FrameCompleted)))
  }
  assert_true(owner.terminal_step(PollOnce) is Err(_))
  assert_eq(reads.val, 0)
  assert_eq(owner.pending_records().length(), 64)
  assert_true(owner.inflight_record() is Some(OrderedPlatform(_)))
  assert_false(owner.can_stop())
  assert_eq(host.stop_count(), 0)
}

///|
test "entry controller stops a proved-complete fake host at most once" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  // A synthetic Completed outcome exercises only the caller's stop guard.
  let entry : SettingsEntryController = {
    host,
    outcome: Completed,
    stop_attempted: false,
    stopped: false,
  }
  entry.try_stop().unwrap()
  assert_eq(host.stop_count(), 1)
  assert_true(entry.try_stop() is Err(_))
  assert_eq(host.stop_count(), 1)
}

///|
test "terminal measurement cannot reenter owner polling" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let owner_ref : Ref[SettingsRunOwner?] = Ref(None)
  let trigger = Ref(false)
  let rejected = Ref(false)
  let reads = Ref(0)
  let measure : @components.TextMeasure = fn(value, size) {
    if trigger.val {
      match owner_ref.val {
        Some(owner) => rejected.val = owner.terminal_step(PollOnce) is Err(_)
        None => ()
      }
    }
    text_runner_measure(value, size)
  }
  let ordered = NativeOrderedTextPort::new(
    fn(_) { reads.val += 1; Ok(None) }, fn(_) { Ok(()) },
  )
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, measure, text_port=Some(port), ordered_text=Some(ordered)).unwrap()
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, measure).unwrap())
  assert_true(owner.mounted.focus(@shared_settings.settings_name()))
  let field = owner.mounted.focused_text().unwrap()
  owner.session = Some({ epoch: 7UL, binding: field.binding_id(), })
  owner.host_epoch = Some(7UL)
  owner.host_epoch_verified = true
  owner.terminal_owner = Some(owner.mounted.capture_terminal_text_owner(7UL).unwrap())
  owner.mounted.invalidate_layout()
  owner.suspended = true
  owner.buffered.push(OrderedText(@text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Commit(text="日本"))))
  owner.inflight = Some(OrderedPlatform(@platform.Event::new(owner.window, 2L, 1.0, @platform.Destroyed)))
  owner_ref.val = Some(owner)
  trigger.val = true
  assert_true(owner.terminal_step(ApplyNext).unwrap() is ModelApplied(1L, true))
  assert_true(rejected.val)
  assert_eq(reads.val, 0)
  assert_eq(owner.model().name(), "日本")
  assert_eq(host.stop_count(), 0)
}

///|
test "retained host receipt is owned before ack and retry does not replay commit" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let owner_ref : Ref[SettingsRunOwner?] = Ref(None)
  let available = Ref(true)
  let ack_calls = Ref(0)
  let owned_at_ack = Ref(false)
  let reads = Ref(0)
  let ordered = NativeOrderedTextPort::with_retained_receipts(
    fn(_) {
      reads.val += 1
      if !available.val { return Ok(None) }
      let owner = owner_ref.val.unwrap()
      let event = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Commit(text="日本"))
      let binding = owner.session.unwrap().binding
      Ok(Some(NativeRetainedReceipt::new(
        Some(OrderedText(event)), owner.window, 42, binding, 7UL,
        fn() {
          ack_calls.val += 1
          owned_at_ack.val = owner.pending_records().length() == 1 &&
            owner.pending_receipt_identity() is Some((_, 42, value, 7UL)) && value == binding &&
            owner.terminal_step(ApplyNext) is Err(_)
          if ack_calls.val == 1 {
            return Err(runner_error("test_ack", "injected failure"))
          }
          available.val = false
          Ok(())
        },
      )))
    },
    fn(_) { Ok(()) },
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
  owner.host_epoch_verified = true
  owner.terminal_owner = Some(owner.mounted.capture_terminal_text_owner(7UL).unwrap())
  owner.mounted.invalidate_layout()
  owner.suspended = true
  owner.inflight = Some(OrderedPlatform(@platform.Event::new(owner.window, 2L, 1.0, @platform.CloseRequested)))
  owner_ref.val = Some(owner)
  assert_true(owner.terminal_step(PollOnce) is Err(_))
  assert_true(owned_at_ack.val)
  assert_eq(owner.pending_records().length(), 1)
  assert_eq(owner.model().name(), "")
  assert_true(owner.terminal_step(PollOnce) is Err(_))
  assert_eq(reads.val, 1)
  assert_true(owner.terminal_step(RetryReceiptAck).unwrap() is ReceiptAcknowledged)
  assert_true(owner.pending_receipt_identity() is None)
  assert_eq(owner.acknowledged_receipt_count(), 1)
  assert_true(owner.acknowledged_receipt_identity(0) is Some((_, 42, binding, 7UL)) && binding == field.binding_id())
  assert_true(owner.acknowledged_receipt_stage(0) is Some(ReceiptAcknowledgedOnly))
  assert_true(owner.receipt_stage_for_sequence(42L) is Some(ReceiptAcknowledgedOnly))
  let wrong_payload = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Commit(text="偽"))
  let old_epoch = @text_host.TextInputEvent::new(owner.window, 1L, 6UL, @text_host.Commit(text="日本"))
  owner.note_text_receipt_stage(wrong_payload, ReceiptModelApplied)
  owner.note_text_receipt_stage(old_epoch, ReceiptModelApplied)
  assert_true(owner.acknowledged_receipt_stage(0) is Some(ReceiptAcknowledgedOnly))
  assert_true(owner.terminal_step(RetryReceiptAck) is Err(_))
  assert_true(owner.terminal_step(ApplyNext).unwrap() is ModelApplied(1L, true))
  assert_eq(owner.model().name(), "日本")
  assert_true(owner.acknowledged_receipt_identity(0) is Some((_, 42, binding, 7UL)) && binding == field.binding_id())
  assert_true(owner.acknowledged_receipt_stage(0) is Some(ReceiptModelApplied))
  assert_true(owner.receipt_stage_for_sequence(42L) is Some(ReceiptModelApplied))
  let original = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Commit(text="日本"))
  owner.acknowledged_receipts.push({
    receipt: NativeRetainedReceipt::new(Some(OrderedText(original)), owner.window, 43, field.binding_id(), 7UL, fn() { Ok(()) }),
    stage: ReceiptAcknowledgedOnly,
  })
  owner.note_text_receipt_stage(original, ReceiptModelApplied)
  assert_true(owner.acknowledged_receipt_stage(0) is None)
  assert_true(owner.acknowledged_receipt_stage(1) is None)
  assert_true(owner.receipt_stage_for_sequence(42L) is None)
  assert_true(owner.terminal_step(ApplyNext) is Err(_))
  assert_eq(owner.model().name(), "日本")
  assert_eq(ack_calls.val, 2)
  assert_eq(host.stop_count(), 0)
}

///|
test "full receipt ledger stops admission without dropping its owner" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let reads = Ref(0)
  let ordered = NativeOrderedTextPort::with_retained_receipts(
    fn(_) { reads.val += 1; Ok(None) }, fn(_) { Ok(()) },
  )
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port), ordered_text=Some(ordered)).unwrap()
  owner.suspended = true
  owner.inflight = Some(OrderedPlatform(@platform.Event::new(owner.window, 2L, 1.0, @platform.Destroyed)))
  for i = 0; i < 64; i = i + 1 {
    owner.acknowledged_receipts.push({
      receipt: NativeRetainedReceipt::new(None, owner.window, i, 9UL, 7UL, fn() { Ok(()) }),
      stage: ReceiptAcknowledgedOnly,
    })
  }
  assert_true(owner.terminal_step(PollOnce) is Err(_))
  assert_eq(reads.val, 0)
  assert_eq(owner.acknowledged_receipt_count(), 64)
  assert_true(owner.acknowledged_receipt_identity(63) is Some((_, 63, 9UL, 7UL)))
  owner.inflight = None
  owner.live_step_ready = true
  owner.live_step_generation = 1L
  assert_true(owner.advance_once(1L) is Err(_))
  assert_eq(reads.val, 0)
  assert_eq(owner.acknowledged_receipt_count(), 64)
  assert_true(owner.advance_generation() is None)
  assert_false(owner.can_stop())
  assert_eq(host.stop_count(), 0)
}

///|
test "entered acknowledgment requires the original session and native target" {
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
  owner.host_epoch = Some(7UL)
  owner.host_epoch_verified = true
  owner.terminal_owner = Some(owner.mounted.capture_terminal_text_owner(7UL).unwrap())
  let attempts = Ref(0)
  let ack = fn() { attempts.val += 1; Ok(()) }
  let wrong_window = NativeRetainedReceipt::entered(@platform.WindowId::new(owner.window.value() + 1L), 1, binding, 7UL, 5, 11L, 4, ack)
  let wrong_binding = NativeRetainedReceipt::entered(owner.window, 1, binding + 1UL, 7UL, 5, 11L, 4, ack)
  let wrong_epoch = NativeRetainedReceipt::entered(owner.window, 1, binding, 8UL, 5, 11L, 4, ack)
  let no_seat = NativeRetainedReceipt::entered(owner.window, 1, binding, 7UL, 5, 0L, 4, ack)
  let no_proxy = NativeRetainedReceipt::entered(owner.window, 1, binding, 7UL, 5, 11L, 0, ack)
  for bad in [wrong_window, wrong_binding, wrong_epoch, no_seat, no_proxy] {
    assert_true(owner.own_entered(bad) is Err(_))
    assert_true(owner.entered_target is None)
  }
  assert_eq(attempts.val, 0)
  let entered = NativeRetainedReceipt::entered(owner.window, 1, binding, 7UL, 5, 11L, 4, ack)
  owner.host_epoch_verified = false
  assert_true(owner.own_entered(entered) is Err(_))
  owner.host_epoch_verified = true
  owner.pending_host_receipt = Some(entered)
  assert_true(owner.ack_owned_receipt() is Err(_))
  owner.own_entered(entered).unwrap()
  assert_true(owner.entered_target is Some((5, 11L, 4)))
  owner.host_epoch_verified = false
  assert_true(owner.ack_owned_receipt() is Err(_))
  assert_eq(attempts.val, 0)
  owner.host_epoch_verified = true
  owner.ack_owned_receipt().unwrap()
  assert_eq(attempts.val, 1)
  assert_true(owner.own_entered(entered) is Err(_))
  assert_eq(owner.acknowledged_receipt_count(), 1)
  assert_eq(host.stop_count(), 0)
}

///|
test "ack retry resumes the exact not-yet-dispatched text only once" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let window = @platform.WindowId::new(1L)
  let records : Array[NativeOrderedEvent] = [
    OrderedPlatform(@platform.Event::new(window, 1L, 1.0, @platform.FrameCompleted)),
    OrderedPlatform(@platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted)),
    OrderedText(@text_host.TextInputEvent::new(window, 1L, 7UL, @text_host.Commit(text="日本"))),
    OrderedPlatform(@platform.Event::new(window, 3L, 1.0, @platform.Destroyed)),
  ]
  let native_sequence = Ref(1)
  let binding = Ref(0UL)
  let fail_once = Ref(true)
  let ordered = NativeOrderedTextPort::with_retained_receipts(
    fn(_) {
      if records.is_empty() { return Ok(None) }
      let record = records[0]
      let sequence = native_sequence.val
      Ok(Some(NativeRetainedReceipt::new(Some(record), window, sequence, binding.val, 7UL, fn() {
        if record is OrderedText(_) && fail_once.val {
          fail_once.val = false
          return Err(runner_error("test_ack", "injected failure"))
        }
        ignore(records.remove(0))
        native_sequence.val += 1
        Ok(())
      })))
    },
    fn(_) { Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "cutoff")) },
  )
  let port = NativeTextInputPort::new(
    fn(_, root) { binding.val = root; Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let entry = SettingsEntryController::start(host, Linux, text_runner_measure, text_port=Some(port), ordered_text=Some(ordered))
  let owner = entry.owner().unwrap()
  assert_true(owner.inflight_record() is Some(OrderedText(_)))
  assert_true(owner.receipt_stage_for_sequence(1L) is Some(ReceiptPlatformHandled))
  assert_true(owner.receipt_stage_for_sequence(2L) is Some(ReceiptPlatformHandled))
  assert_eq(owner.model().name(), "")
  assert_true(owner.resumable_receipt_identity() is None)
  assert_true(entry.resume_receipt_sequence(3L) is Err(_))
  assert_true(entry.retry_receipt_sequence(4L) is Err(_))
  assert_true(entry.retry_receipt_sequence(3L).unwrap() is ReceiptAcknowledged)
  assert_true(owner.acknowledged_receipt_stage(2) is Some(ReceiptAcknowledgedOnly))
  assert_true(owner.resumable_receipt_identity() is Some((_, 3, _, _)))
  assert_true(entry.retry_receipt_sequence(3L) is Err(_))
  assert_true(entry.resume_receipt_sequence(4L) is Err(_))
  assert_true(entry.resume_receipt_sequence(3L).unwrap() is ReceiptDispatched)
  assert_true(owner.resumable_receipt_identity() is None)
  assert_eq(owner.model().name(), "日本")
  assert_true(owner.acknowledged_receipt_stage(2) is Some(ReceiptModelApplied))
  assert_true(entry.resume_receipt_sequence(3L) is Err(_))
  assert_eq(owner.model().name(), "日本")
  assert_eq(records.length(), 1)
  assert_eq(host.stop_count(), 0)
}

///|
test "entered ack retry continues original session without consuming text" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let window = @platform.WindowId::new(1L)
  let binding = Ref(0UL)
  let step = Ref(0)
  let fail_once = Ref(true)
  let ordered = NativeOrderedTextPort::with_retained_receipts(
    fn(_) {
      let sequence = step.val + 1
      let ack = fn() {
        if step.val == 2 && fail_once.val {
          fail_once.val = false
          return Err(runner_error("test_ack", "injected entered failure"))
        }
        step.val += 1
        Ok(())
      }
      if step.val == 2 {
        return Ok(Some(NativeRetainedReceipt::entered(window, sequence, binding.val, 7UL, 5, 11L, 4, ack)))
      }
      let event = match step.val {
        0 => OrderedPlatform(@platform.Event::new(window, 1L, 1.0, @platform.FrameCompleted))
        1 => OrderedPlatform(@platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted))
        3 => OrderedText(@text_host.TextInputEvent::new(window, 1L, 7UL, @text_host.Commit(text="日本")))
        4 => OrderedPlatform(@platform.Event::new(window, 3L, 1.0, @platform.Destroyed))
        _ => return Ok(None)
      }
      Ok(Some(NativeRetainedReceipt::new(Some(event), window, sequence, binding.val, 7UL, ack)))
    },
    fn(_) { Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "cutoff")) },
  )
  let port = NativeTextInputPort::new(
    fn(_, root) { binding.val = root; Ok(7UL) }, fn(epoch, _) { Ok(epoch) },
    fn(epoch) { Ok(epoch) }, fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let entry = SettingsEntryController::start(host, Linux, text_runner_measure, text_port=Some(port), ordered_text=Some(ordered))
  let owner = entry.owner().unwrap()
  assert_true(owner.pending_receipt_identity() is Some((_, 3, _, 7UL)))
  assert_true(owner.inflight_record() is None)
  assert_true(owner.entered_target is Some((5, 11L, 4)))
  assert_eq(step.val, 2)
  assert_true(entry.retry_receipt_sequence(3L).unwrap() is ReceiptAcknowledged)
  assert_true(owner.receipt_stage_for_sequence(3L) is Some(ReceiptOwnerEntered))
  assert_eq(step.val, 3)
  assert_true(entry.resume_receipt_sequence(4L) is Err(_))
  assert_true(entry.resume_receipt_sequence(3L).unwrap() is ReceiptDispatched)
  assert_eq(owner.model().name(), "")
  assert_eq(step.val, 3)
  assert_true(entry.resume_receipt_sequence(3L) is Err(_))
  assert_true(entry.advance_generation() is Some(1L))
  assert_true(entry.advance_once(2L) is Err(_))
  assert_eq(step.val, 3)
  assert_true(entry.advance_once(1L).unwrap() is ContinuationStepped)
  assert_eq(owner.model().name(), "日本")
  assert_eq(step.val, 4)
  assert_true(entry.advance_once(1L) is Err(_))
  assert_true(entry.advance_generation() is Some(2L))
  assert_eq(owner.model().name(), "日本")
  assert_eq(host.stop_count(), 0)
}

///|
test "empty continuation still consumes its generation" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let reads = Ref(0)
  let ordered = NativeOrderedTextPort::with_retained_receipts(
    fn(_) { reads.val += 1; Ok(None) }, fn(_) { Ok(()) },
  )
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port), ordered_text=Some(ordered)).unwrap()
  owner.suspended = true
  owner.live_step_ready = true
  owner.live_step_generation = 1L
  assert_true(owner.advance_once(1L).unwrap() is ContinuationStepped)
  assert_eq(reads.val, 1)
  assert_true(owner.advance_once(1L) is Err(_))
  assert_eq(reads.val, 1)
  assert_true(owner.advance_generation() is Some(2L))
  assert_true(owner.advance_once(2L).unwrap() is ContinuationStepped)
  assert_eq(reads.val, 2)
  assert_false(owner.can_stop())
  assert_eq(host.stop_count(), 0)
}

///|
test "receipt stages distinguish no-action preedit from input ACK" {
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
  owner.terminal_owner = Some(owner.mounted.capture_terminal_text_owner(7UL).unwrap())
  let preedit = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Preedit(text="にほん", cursor=3))
  owner.acknowledged_receipts.push({
    receipt: NativeRetainedReceipt::new(Some(OrderedText(preedit)), owner.window, 1, binding, 7UL, fn() { Ok(()) }),
    stage: ReceiptAcknowledgedOnly,
  })
  owner.deliver_owned_observation(preedit).unwrap()
  assert_true(owner.receipt_stage_for_sequence(1L) is Some(ReceiptNoModelAction))
  assert_eq(owner.model().name(), "")
  assert_true(owner.mounted.focused_text().unwrap().composing())
  let press = @platform.Event::new(owner.window, 2L, 1.0,
    @platform.Input(@primitives.KeyPressed(key=@primitives.Character("n"), repeat=false, modifiers=@primitives.Modifiers::none())))
  owner.acknowledged_receipts.push({
    receipt: NativeRetainedReceipt::new(Some(OrderedPlatform(press)), owner.window, 2, binding, 7UL, fn() { Ok(()) }),
    stage: ReceiptAcknowledgedOnly,
  })
  owner.note_handled_platform(press)
  assert_true(owner.receipt_stage_for_sequence(2L) is Some(ReceiptAcknowledgedOnly))
  assert_eq(host.stop_count(), 0)
}

///|
test "pending action blocks ordered resize before layout invalidation" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let window = @platform.WindowId::new(1L)
  let owner_ref : Ref[SettingsRunOwner?] = Ref(None)
  let activated = Ref(false)
  let sequence = Ref(1)
  let ordered = NativeOrderedTextPort::with_retained_receipts(
    fn(_) {
      let index = sequence.val
      let event = match index {
        1 => @platform.Event::new(window, 1L, 1.0, @platform.FrameCompleted)
        2 => @platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted)
        3 => {
          let owner = owner_ref.val.unwrap()
          let save = owner.mounted.callback(@shared_settings.settings_save()).unwrap()
          activated.val = owner.mounted.activate(save)
          @platform.Event::new(window, 3L, 1.0, @platform.Resized(width=800.0, height=600.0))
        }
        _ => return Ok(None)
      }
      Ok(Some(NativeRetainedReceipt::new(Some(OrderedPlatform(event)), window, index, 0UL, 0UL, fn() {
        sequence.val += 1
        Ok(())
      })))
    },
    fn(_) { Ok(()) },
  )
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port), ordered_text=Some(ordered)).unwrap()
  owner_ref.val = Some(owner)
  assert_true(owner.drive() is Err(_))
  assert_true(activated.val)
  assert_true(owner.inflight_record() is Some(OrderedPlatform(_)))
  assert_true(owner.receipt_stage_for_sequence(3L) is Some(ReceiptAcknowledgedOnly))
  assert_true(owner.mounted.has_pending_actions())
  assert_true(owner.mounted.next_action() is Some(@view.Activate(_)))
  assert_false(owner.mounted.has_pending_actions())
  assert_false(owner.can_stop())
  assert_eq(host.stop_count(), 0)
}

///|
test "rejected focus handler retains its exact acknowledged event" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let window = @platform.WindowId::new(1L)
  let owner_ref : Ref[SettingsRunOwner?] = Ref(None)
  let advanced = Ref(false)
  let sequence = Ref(1)
  let ordered = NativeOrderedTextPort::with_retained_receipts(
    fn(_) {
      let index = sequence.val
      let event = match index {
        1 => @platform.Event::new(window, 1L, 1.0, @platform.FrameCompleted)
        2 => @platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted)
        3 => {
          // Make the Mounted handler reject the subsequently delivered focus
          // event after it was already acknowledged by the native queue.
          let owner = owner_ref.val.unwrap()
          let later = @platform.Event::new(window, 4L, 1.0, @platform.FocusChanged(true))
          advanced.val = owner.mounted.handle_event(later).unwrap()
          @platform.Event::new(window, 3L, 1.0, @platform.FocusChanged(true))
        }
        _ => return Ok(None)
      }
      Ok(Some(NativeRetainedReceipt::new(Some(OrderedPlatform(event)), window, index, 0UL, 0UL, fn() {
        sequence.val += 1
        Ok(())
      })))
    },
    fn(_) { Ok(()) },
  )
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port), ordered_text=Some(ordered)).unwrap()
  owner_ref.val = Some(owner)
  assert_true(owner.drive() is Err(_))
  assert_true(advanced.val)
  assert_true(owner.inflight_record() is Some(OrderedPlatform(event)) && event.sequence() == 3L)
  assert_true(owner.receipt_stage_for_sequence(3L) is Some(ReceiptAcknowledgedOnly))
  assert_false(owner.can_stop())
  assert_eq(host.stop_count(), 0)
}

///|
test "platform stage refuses wrong payload and ambiguous receipt sequence" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port)).unwrap()
  let frame = @platform.Event::new(owner.window, 1L, 1.0, @platform.FrameCompleted)
  let resize = @platform.Event::new(owner.window, 1L, 1.0, @platform.Resized(width=800.0, height=600.0))
  owner.acknowledged_receipts.push({
    receipt: NativeRetainedReceipt::new(Some(OrderedPlatform(frame)), owner.window, 1, 0UL, 0UL, fn() { Ok(()) }),
    stage: ReceiptAcknowledgedOnly,
  })
  owner.note_handled_platform(resize)
  assert_true(owner.receipt_stage_for_sequence(1L) is Some(ReceiptAcknowledgedOnly))
  let wrong_scale = @platform.Event::new(owner.window, 1L, 2.0, @platform.FrameCompleted)
  owner.note_handled_platform(wrong_scale)
  assert_true(owner.receipt_stage_for_sequence(1L) is Some(ReceiptAcknowledgedOnly))
  owner.acknowledged_receipts.push({
    receipt: NativeRetainedReceipt::new(Some(OrderedPlatform(frame)), owner.window, 1, 0UL, 0UL, fn() { Ok(()) }),
    stage: ReceiptAcknowledgedOnly,
  })
  owner.note_handled_platform(frame)
  assert_true(owner.receipt_stage_for_sequence(1L) is None)
  assert_true(owner.acknowledged_receipts[0].stage is ReceiptAcknowledgedOnly)
  assert_true(owner.acknowledged_receipts[1].stage is ReceiptAcknowledgedOnly)
  assert_false(owner.can_stop())
}

///|
test "retained pointer move requires dispatch and an empty action queue" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let window = @platform.WindowId::new(1L)
  let sequence = Ref(1)
  let ordered = NativeOrderedTextPort::with_retained_receipts(
    fn(_) {
      let index = sequence.val
      let event = match index {
        1 | 2 => Some(OrderedPlatform(@platform.Event::new(window, index.to_int64(), 1.0, @platform.FrameCompleted)))
        3 => Some(OrderedPlatform(@platform.Event::new(window, 3L, 1.0,
          @platform.Input(@primitives.PointerMoved(position=@primitives.Point::new(10.0, 10.0).unwrap())))))
        4 => None
        _ => return Ok(None)
      }
      Ok(Some(NativeRetainedReceipt::new(event, window, index, 0UL, 0UL, fn() {
        sequence.val += 1
        Ok(())
      })))
    },
    fn(_) { Ok(()) },
  )
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port), ordered_text=Some(ordered)).unwrap()
  assert_true(owner.drive() is Err(_))
  assert_eq(owner.mounted.last_dispatched_input_sequence(), 3L)
  assert_true(owner.receipt_stage_for_sequence(3L) is Some(ReceiptPointerMovedHandled))
  assert_true(owner.pending_receipt_identity() is Some((_, 4, _, _)))
  assert_false(owner.can_stop())
  assert_eq(host.stop_count(), 0)
}

///|
test "pending action retains pointer move without dispatch" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let window = @platform.WindowId::new(1L)
  let owner_ref : Ref[SettingsRunOwner?] = Ref(None)
  let activated = Ref(false)
  let sequence = Ref(1)
  let ordered = NativeOrderedTextPort::with_retained_receipts(
    fn(_) {
      let index = sequence.val
      let event = match index {
        1 | 2 => @platform.Event::new(window, index.to_int64(), 1.0, @platform.FrameCompleted)
        3 => {
          let owner = owner_ref.val.unwrap()
          activated.val = owner.mounted.activate(owner.mounted.callback(@shared_settings.settings_save()).unwrap())
          @platform.Event::new(window, 3L, 1.0,
            @platform.Input(@primitives.PointerMoved(position=@primitives.Point::new(10.0, 10.0).unwrap())))
        }
        _ => return Ok(None)
      }
      Ok(Some(NativeRetainedReceipt::new(Some(OrderedPlatform(event)), window, index, 0UL, 0UL, fn() {
        sequence.val += 1
        Ok(())
      })))
    },
    fn(_) { Ok(()) },
  )
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port), ordered_text=Some(ordered)).unwrap()
  owner_ref.val = Some(owner)
  assert_true(owner.drive() is Err(_))
  assert_true(activated.val)
  assert_true(owner.inflight_record() is Some(OrderedPlatform(event)) && event.sequence() == 3L)
  assert_true(owner.receipt_stage_for_sequence(3L) is Some(ReceiptAcknowledgedOnly))
  assert_true(owner.mounted.has_pending_actions())
  assert_eq(owner.mounted.last_dispatched_input_sequence(), 0L)
  assert_eq(host.stop_count(), 0)
}

///|
test "rejected pointer move remains owned and does not advance stage" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let window = @platform.WindowId::new(1L)
  let owner_ref : Ref[SettingsRunOwner?] = Ref(None)
  let advanced = Ref(false)
  let sequence = Ref(1)
  let ordered = NativeOrderedTextPort::with_retained_receipts(
    fn(_) {
      let index = sequence.val
      let event = match index {
        1 | 2 => @platform.Event::new(window, index.to_int64(), 1.0, @platform.FrameCompleted)
        3 => {
          let owner = owner_ref.val.unwrap()
          advanced.val = owner.mounted.handle_event(@platform.Event::new(window, 4L, 1.0, @platform.FocusChanged(true))).unwrap()
          @platform.Event::new(window, 3L, 1.0,
            @platform.Input(@primitives.PointerMoved(position=@primitives.Point::new(10.0, 10.0).unwrap())))
        }
        _ => return Ok(None)
      }
      Ok(Some(NativeRetainedReceipt::new(Some(OrderedPlatform(event)), window, index, 0UL, 0UL, fn() {
        sequence.val += 1
        Ok(())
      })))
    },
    fn(_) { Ok(()) },
  )
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port), ordered_text=Some(ordered)).unwrap()
  owner_ref.val = Some(owner)
  assert_true(owner.drive() is Err(_))
  assert_true(advanced.val)
  assert_true(owner.inflight_record() is Some(OrderedPlatform(event)) && event.sequence() == 3L)
  assert_true(owner.receipt_stage_for_sequence(3L) is Some(ReceiptAcknowledgedOnly))
  assert_eq(owner.mounted.last_dispatched_input_sequence(), 0L)
  assert_eq(host.stop_count(), 0)
}

///|
test "local unsupported prefix snapshot requires consecutive resolved original owner" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port)).unwrap()
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, text_runner_measure).unwrap())
  assert_true(owner.mounted.focus(@shared_settings.settings_name()))
  let binding = owner.mounted.focused_text().unwrap().binding_id()
  owner.session = Some({ epoch: 7UL, binding })
  owner.host_epoch = Some(7UL)
  owner.host_epoch_verified = true
  owner.terminal_owner = Some(owner.mounted.capture_terminal_text_owner(7UL).unwrap())
  owner.entered_target = Some((5, 11L, 4))
  let frame = @platform.Event::new(owner.window, 1L, 1.0, @platform.FrameCompleted)
  owner.acknowledged_receipts.push({
    receipt: NativeRetainedReceipt::new(Some(OrderedPlatform(frame)), owner.window, 1, 0UL, 0UL, fn() { Ok(()) }),
    stage: ReceiptAcknowledgedOnly,
  })
  owner.note_handled_platform(frame)
  owner.acknowledged_receipts.push({
    receipt: NativeRetainedReceipt::entered(owner.window, 2, binding, 7UL, 5, 11L, 4, fn() { Ok(()) }),
    stage: ReceiptOwnerEntered,
  })
  let preedit = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Preedit(text="にほん", cursor=3))
  owner.acknowledged_receipts.push({
    receipt: NativeRetainedReceipt::new(Some(OrderedText(preedit)), owner.window, 3, binding, 7UL, fn() { Ok(()) }),
    stage: ReceiptAcknowledgedOnly,
  })
  owner.deliver_owned_observation(preedit).unwrap()
  let pending = NativeRetainedReceipt::new(None, owner.window, 4, binding, 7UL, fn() { Ok(()) })
  owner.pending_host_receipt = Some(pending)
  owner.receipt_pre_dispatch = Some(pending)
  owner.suspended = true
  assert_true(owner.unsupported_prefix_has_observed_stages())
  assert_true(owner.capture_unsupported_prefix(3L) is Err(_))
  let snapshot = owner.capture_unsupported_prefix(4L).unwrap()
  assert_true(snapshot.is_current())
  assert_true(owner.mounted.focused_text().unwrap().composing())
  // The snapshot is not permission to ACK; existing policy still refuses it.
  assert_true(owner.ack_owned_receipt() is Err(_))
  owner.acknowledged_receipts[2].stage = ReceiptSessionApplied
  assert_false(owner.unsupported_prefix_has_observed_stages())
  assert_false(snapshot.is_current())
  owner.acknowledged_receipts[2].stage = ReceiptNoModelAction
  owner.buffered.push(OrderedText(preedit))
  assert_false(owner.unsupported_prefix_has_observed_stages())
  assert_false(snapshot.is_current())
  ignore(owner.buffered.pop())
  owner.host_epoch = Some(8UL)
  assert_false(owner.unsupported_prefix_has_observed_stages())
  assert_false(snapshot.is_current())
  owner.host_epoch = Some(7UL)
  let original_entry = owner.acknowledged_receipts[0]
  let changed_frame = @platform.Event::new(owner.window, 1L, 2.0, @platform.FrameCompleted)
  owner.acknowledged_receipts[0] = {
    receipt: NativeRetainedReceipt::new(Some(OrderedPlatform(changed_frame)), owner.window, 1, 0UL, 0UL, fn() { Ok(()) }),
    stage: ReceiptPlatformHandled,
  }
  assert_true(owner.unsupported_prefix_has_observed_stages())
  assert_false(snapshot.is_current())
  owner.acknowledged_receipts[0] = original_entry
  assert_true(snapshot.is_current())
  owner.session = Some({ epoch: 7UL, binding: binding + 1UL })
  assert_false(owner.unsupported_prefix_has_observed_stages())
  owner.session = Some({ epoch: 7UL, binding })
  let substitute = NativeRetainedReceipt::new(None, owner.window, 4, binding + 1UL, 7UL, fn() { Ok(()) })
  owner.pending_host_receipt = Some(substitute)
  assert_false(snapshot.is_current())
  owner.pending_host_receipt = Some(pending)
  assert_true(snapshot.is_current())
  let save = owner.mounted.callback(@shared_settings.settings_save()).unwrap()
  assert_true(owner.mounted.activate(save))
  assert_false(owner.unsupported_prefix_has_observed_stages())
  assert_false(snapshot.is_current())
  assert_true(owner.pending_receipt_identity() is Some((_, 4, _, 7UL)))
  assert_false(owner.can_stop())
  assert_eq(host.stop_count(), 0)
  ignore(owner.mounted.next_action())
  let next_preedit = @text_host.TextInputEvent::new(owner.window, 2L, 7UL, @text_host.Preedit(text="日本", cursor=2))
  owner.deliver_owned_observation(next_preedit).unwrap()
  assert_false(snapshot.is_current())
  // Invalidating the mounted frame makes the captured owner's token/geometry
  // unusable for this snapshot even though its epoch and binding still match.
  owner.mounted.invalidate_layout()
  assert_false(owner.unsupported_prefix_has_observed_stages())
}

///|
fn publication_fixture() -> (SettingsRunOwner, @ui.Frame) {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let owner = SettingsRunOwner::new(host, Linux, text_runner_measure, text_port=Some(port)).unwrap()
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, text_runner_measure).unwrap())
  if !owner.mounted.focus(@shared_settings.settings_name()) { abort("fixture focus failed") }
  let frame = owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, text_runner_measure).unwrap()
  let field = owner.mounted.focused_text().unwrap()
  let binding = field.binding_id()
  owner.session = Some({ epoch: 7UL, binding })
  owner.host_epoch = Some(7UL)
  owner.host_epoch_verified = true
  owner.terminal_owner = Some(owner.mounted.capture_terminal_text_owner(7UL).unwrap())
  owner.entered_target = Some((5, 11L, 4))
  owner.last_document = field.document().text()
  owner.last_caret = settings_caret(field.caret())
  owner.dirty = false
  owner.acknowledged_receipts.push({
    receipt: NativeRetainedReceipt::entered(owner.window, 1, binding, 7UL, 5, 11L, 4, fn() { Ok(()) }),
    stage: ReceiptOwnerEntered,
  })
  (owner, frame)
}

///|
test "frame completion covers only the prefix captured before present" {
  let (owner, frame) = publication_fixture()
  let present_count = Ref(0)
  owner.present_with_frame_publication(frame, fn(_, _) { present_count.val += 1; Ok(()) }).unwrap()
  let candidate = owner.pending_publication.unwrap()
  assert_eq(candidate.watermark(), 1)
  assert_eq(candidate.scene_revision(), frame.revision())
  assert_true(candidate.presented())
  assert_false(candidate.frame_completed())
  // A later acknowledged event arrives while this frame is in flight. It is
  // not retroactively included in the already captured scene watermark.
  let later = @platform.Event::new(owner.window, 2L, 1.0, @platform.FrameCompleted)
  owner.acknowledged_receipts.push({
    receipt: NativeRetainedReceipt::new(Some(OrderedPlatform(later)), owner.window, 2, candidate.binding, 7UL, fn() { Ok(()) }),
    stage: ReceiptPlatformHandled,
  })
  owner.complete_frame_publication()
  assert_eq(present_count.val, 1)
  assert_eq(owner.completed_publication_count(), 1)
  assert_eq(owner.completed_publication(0).unwrap().watermark(), 1)
  assert_true(owner.completed_publication(0).unwrap().frame_completed())
  assert_eq(owner.acknowledged_receipt_count(), 2)
  assert_false(owner.can_stop())
}

///|
test "uncertain host geometry or present failure cannot publish a prefix" {
  let (owner, frame) = publication_fixture()
  owner.host_epoch_verified = false
  assert_true(owner.prepare_frame_publication(frame) is None)
  assert_eq(owner.acknowledged_receipt_count(), 1)
  owner.host_epoch_verified = true
  let side_effect = Ref(false)
  let present = fn(_, _) { side_effect.val = true; Err(runner_error("test_present", "injected failure")) }
  assert_true(owner.present_with_frame_publication(frame, present) is Err(_))
  assert_true(side_effect.val)
  assert_true(owner.pending_publication is Some(_))
  assert_false(owner.pending_publication.unwrap().presented())
  assert_eq(owner.completed_publication_count(), 0)
  assert_eq(owner.acknowledged_receipt_count(), 1)
  assert_false(owner.can_stop())
}

///|
test "later field change prevents completion of an earlier owner snapshot" {
  let (owner, frame) = publication_fixture()
  owner.present_with_frame_publication(frame, fn(_, _) { Ok(()) }).unwrap()
  let binding = owner.session.unwrap().binding
  let preedit = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Preedit(text="にほん", cursor=3))
  owner.acknowledged_receipts.push({
    receipt: NativeRetainedReceipt::new(Some(OrderedText(preedit)), owner.window, 2, binding, 7UL, fn() { Ok(()) }),
    stage: ReceiptAcknowledgedOnly,
  })
  owner.deliver_owned_observation(preedit).unwrap()
  owner.complete_frame_publication()
  assert_eq(owner.completed_publication_count(), 0)
  assert_true(owner.pending_publication is Some(_))
  assert_false(owner.pending_publication.unwrap().frame_completed())
  assert_true(owner.present_with_frame_publication(frame, fn(_, _) { Ok(()) }) is Err(_))
  assert_true(owner.mounted.focused_text().unwrap().composing())
  assert_eq(owner.acknowledged_receipt_count(), 2)
  assert_false(owner.can_stop())
}

///|
test "frame proof retains ambiguity after captured receipt changes" {
  let (owner, frame) = publication_fixture()
  owner.present_with_frame_publication(frame, fn(_, _) { Ok(()) }).unwrap()
  let binding = owner.session.unwrap().binding
  owner.acknowledged_receipts.push({
    receipt: NativeRetainedReceipt::entered(owner.window, 1, binding, 7UL, 5, 11L, 4, fn() { Ok(()) }),
    stage: ReceiptOwnerEntered,
  })
  owner.complete_frame_publication()
  assert_eq(owner.completed_publication_count(), 0)
  assert_true(owner.pending_frame_publication() is Some(_))
  assert_eq(owner.acknowledged_receipt_count(), 2)
  assert_false(owner.can_stop())
}

///|
test "resize then failed ack retains commit across destroyed window" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let window = @platform.WindowId::new(1L)
  let records : Array[NativeOrderedEvent] = [
    OrderedPlatform(@platform.Event::new(window, 1L, 1.0, @platform.FrameCompleted)),
    OrderedPlatform(@platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted)),
    OrderedPlatform(@platform.Event::new(window, 3L, 1.0, @platform.Resized(width=800.0, height=600.0))),
    OrderedText(@text_host.TextInputEvent::new(window, 1L, 7UL, @text_host.Commit(text="日本"))),
    OrderedPlatform(@platform.Event::new(window, 5L, 1.0, @platform.Destroyed)),
  ]
  let native_sequence = Ref(1)
  let binding = Ref(0UL)
  let fail_once = Ref(true)
  let ordered = NativeOrderedTextPort::with_retained_receipts(
    fn(_) {
      if records.is_empty() { return Ok(None) }
      let record = records[0]
      let sequence = native_sequence.val
      Ok(Some(NativeRetainedReceipt::new(Some(record), window, sequence, binding.val, if binding.val == 0UL { 0UL } else { 7UL }, fn() {
        if record is OrderedText(_) && fail_once.val {
          fail_once.val = false
          return Err(runner_error("test_ack", "injected failure"))
        }
        ignore(records.remove(0))
        native_sequence.val += 1
        Ok(())
      })))
    },
    fn(_) { Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "cutoff")) },
  )
  let port = NativeTextInputPort::new(
    fn(_, root) { binding.val = root; Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let entry = SettingsEntryController::start(host, Linux, text_runner_measure, text_port=Some(port), ordered_text=Some(ordered))
  let owner = entry.owner().unwrap()
  assert_true(owner.inflight_record() is Some(OrderedText(_)))
  assert_true(entry.retry_receipt_sequence(4L).unwrap() is ReceiptAcknowledged)
  assert_true(entry.resume_receipt_sequence(4L).unwrap() is ReceiptDispatched)
  assert_eq(owner.model().name(), "")
  assert_eq(owner.pending_records().length(), 1)
  assert_true(entry.advance_once(1L) is Err(_))
  assert_true(owner.inflight_record() is Some(OrderedPlatform(_)))
  assert_true(owner.receipt_stage_for_sequence(5L) is Some(ReceiptAcknowledgedOnly))
  assert_true(owner.resolve_destroyed_receipt(5L) is Err(_))
  assert_true(owner.retire_destroyed_model_receipt(4L) is Err(_))
  assert_true(entry.terminal_step(ApplyNext).unwrap() is ModelApplied(1L, true))
  assert_eq(owner.model().name(), "日本")
  assert_true(owner.receipt_stage_for_sequence(4L) is Some(ReceiptModelApplied))
  assert_true(owner.resolve_destroyed_receipt(4L) is Err(_))
  let original_session = owner.session.unwrap()
  owner.session = Some({ epoch: original_session.epoch, binding: original_session.binding + 1UL, })
  assert_true(owner.resolve_destroyed_receipt(5L) is Err(_))
  owner.session = Some({ epoch: original_session.epoch + 1UL, binding: original_session.binding, })
  assert_true(owner.resolve_destroyed_receipt(5L) is Err(_))
  owner.session = Some(original_session)
  owner.terminal_applied = Some((1L, true))
  assert_true(owner.resolve_destroyed_receipt(5L) is Err(_))
  owner.terminal_applied = None
  assert_true(owner.receipt_stage_for_sequence(4L) is Some(ReceiptModelApplied))
  owner.resolve_destroyed_receipt(5L).unwrap()
  assert_true(owner.receipt_stage_for_sequence(5L) is Some(ReceiptTerminalResolved))
  assert_true(owner.retire_destroyed_model_receipt(5L) is Err(_))
  owner.terminal_applied = Some((1L, true))
  assert_true(owner.retire_destroyed_model_receipt(4L) is Err(_))
  owner.terminal_applied = None
  owner.session = Some({ epoch: original_session.epoch, binding: original_session.binding + 1UL, })
  assert_true(owner.retire_destroyed_model_receipt(4L) is Err(_))
  owner.session = Some(original_session)
  assert_true(owner.acknowledged_receipt_identity(3) is Some((_, 4, _, 7UL)))
  owner.acknowledged_receipts[3].stage = ReceiptActionRequired
  assert_true(owner.retire_destroyed_model_receipt(4L) is Err(_))
  owner.acknowledged_receipts[3].stage = ReceiptModelApplied
  owner.retire_destroyed_model_receipt(4L).unwrap()
  assert_true(owner.receipt_stage_for_sequence(4L) is None)
  assert_true(owner.receipt_stage_for_sequence(5L) is Some(ReceiptTerminalResolved))
  assert_true(owner.retire_destroyed_model_receipt(4L) is Err(_))
  assert_true(entry.terminal_step(ApplyNext) is Err(_))
  assert_eq(owner.model().name(), "日本")
  assert_false(owner.can_stop())
  assert_eq(host.stop_count(), 0)
}

///|
test "terminal receipt identity cannot be replaced by later poll" {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let window = @platform.WindowId::new(1L)
  let records : Array[NativeOrderedEvent] = [
    OrderedPlatform(@platform.Event::new(window, 1L, 1.0, @platform.FrameCompleted)),
    OrderedPlatform(@platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted)),
    OrderedPlatform(@platform.Event::new(window, 3L, 1.0, @platform.Destroyed)),
    OrderedText(@text_host.TextInputEvent::new(window, 1L, 7UL, @text_host.Commit(text="日本"))),
  ]
  let sequence = Ref(1)
  let reads = Ref(0)
  let fail_once = Ref(true)
  let ordered = NativeOrderedTextPort::with_retained_receipts(
    fn(_) {
      reads.val += 1
      if records.is_empty() { return Ok(None) }
      let record = records[0]
      let current = sequence.val
      Ok(Some(NativeRetainedReceipt::new(Some(record), window, current, 0UL, 0UL, fn() {
        if current == 3 && fail_once.val {
          fail_once.val = false
          return Err(runner_error("test_ack", "injected terminal ACK failure"))
        }
        ignore(records.remove(0))
        sequence.val += 1
        Ok(())
      })))
    },
    fn(_) { Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "cutoff")) },
  )
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  let entry = SettingsEntryController::start(host, Linux, text_runner_measure, text_port=Some(port), ordered_text=Some(ordered))
  let owner = entry.owner().unwrap()
  assert_true(owner.inflight_record() is Some(OrderedPlatform(_)))
  assert_true(entry.retry_receipt_sequence(3L).unwrap() is ReceiptAcknowledged)
  assert_true(owner.resumable_receipt_identity() is Some((_, 3, _, _)))
  assert_true(entry.terminal_step(PollOnce) is Err(_))
  assert_eq(reads.val, 3)
  assert_eq(records.length(), 1)
  // Even an independently retained later identity cannot alter the original
  // dispatch token or make a stale request act on this event.
  owner.acknowledged_receipts.push({
    receipt: NativeRetainedReceipt::new(None, window, 4, 0UL, 0UL, fn() { Ok(()) }),
    stage: ReceiptAcknowledgedOnly,
  })
  assert_true(owner.resumable_receipt_identity() is Some((_, 3, _, _)))
  assert_true(entry.resume_receipt_sequence(4L) is Err(_))
  assert_true(entry.resume_receipt_sequence(3L) is Err(_))
  assert_true(owner.inflight_record() is Some(OrderedPlatform(_)))
  assert_true(entry.terminal_step(PollOnce).unwrap() is RecordBuffered)
  assert_true(entry.terminal_step(ApplyNext) is Err(_))
  assert_eq(owner.pending_records().length(), 1)
  assert_eq(owner.model().name(), "")
  assert_eq(host.stop_count(), 0)
}

///|
test "destroyed terminal policy preserves active preedit until observed resolution" {
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
  owner.host_epoch = Some(7UL)
  owner.host_epoch_verified = true
  let lease = owner.mounted.capture_terminal_text_owner(7UL).unwrap()
  owner.terminal_owner = Some(lease)
  let preedit = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Preedit(text="にほん", cursor=3))
  owner.mounted.validate_terminal_text_delivery(lease, preedit).unwrap()
  assert_true(owner.mounted.text_input(7UL, preedit).unwrap())
  owner.mounted.note_terminal_text_delivery(lease, preedit).unwrap()
  assert_true(owner.mounted.focused_text().unwrap().composing())
  owner.mounted.invalidate_layout()
  owner.suspended = true
  let destroyed = @platform.Event::new(owner.window, 3L, 1.0, @platform.Destroyed)
  owner.inflight = Some(OrderedPlatform(destroyed))
  owner.retained_destroyed_prefix = Some(0)
  owner.acknowledged_receipts.push({
    receipt: NativeRetainedReceipt::new(Some(OrderedPlatform(destroyed)), owner.window, 3, binding, 7UL, fn() { Ok(()) }),
    stage: ReceiptAcknowledgedOnly,
  })
  assert_true(owner.resolve_destroyed_receipt(3L) is Err(_))
  assert_true(owner.terminal_destroyed_sequence is None)
  assert_true(owner.receipt_stage_for_sequence(3L) is Some(ReceiptAcknowledgedOnly))
  assert_eq(owner.model().name(), "")
  // An independently observed pre-Destroyed Cancel remains a real ordered
  // observation; the terminal operation itself never manufactures one.
  owner.retained_destroyed_prefix = Some(1)
  owner.buffered.push(OrderedText(@text_host.TextInputEvent::new(owner.window, 2L, 7UL, @text_host.Cancel)))
  owner.reconcile_terminal_observation().unwrap()
  owner.resolve_destroyed_receipt(3L).unwrap()
  assert_true(owner.receipt_stage_for_sequence(3L) is Some(ReceiptTerminalResolved))
  assert_eq(owner.model().name(), "")
  assert_false(owner.can_stop())
  assert_eq(host.stop_count(), 0)
}

///|
test "entry sequence retry does not apply the next record" {
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
  owner.buffered.push(OrderedText(@text_host.TextInputEvent::new(owner.window, 2L, 7UL, @text_host.Commit(text="日本"))))
  owner.inflight = Some(OrderedPlatform(@platform.Event::new(owner.window, 3L, 1.0, @platform.Destroyed)))
  let entry : SettingsEntryController = {
    host,
    outcome: Suspended(owner, runner_error("test", "terminal")),
    stop_attempted: false,
    stopped: false,
  }
  assert_true(entry.apply_sequence(1L).unwrap() is FieldApplied(1L))
  assert_true(entry.apply_sequence(1L) is Err(_))
  assert_eq(owner.pending_records().length(), 1)
  assert_eq(owner.model().name(), "")
  assert_true(entry.apply_sequence(2L).unwrap() is ModelApplied(2L, true))
  assert_eq(owner.model().name(), "日本")
  assert_true(entry.try_stop() is Err(_))
  assert_eq(host.stop_count(), 0)
}
