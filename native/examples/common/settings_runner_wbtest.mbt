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
    fn(_, _) {
      Err(runner_error("test_update", "transport unavailable"))
    },
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
  run_native_settings_sample(
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
