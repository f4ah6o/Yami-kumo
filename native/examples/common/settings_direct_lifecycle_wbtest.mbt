///|
struct DirectLifecycleFixture {
  owner : SettingsRunOwner
  host : @testing.ScriptedBackend
  commands : Array[@platform.EventKind]
  fail_ack : Ref[String?]
  fail_release : Ref[Bool]
  fail_rebind : Ref[String?]
  fail_seal : Ref[Bool]
  frames : Ref[Bool]
  cutoff_count : Ref[Int32]
  release_count : Ref[Int32]
  rebind_count : Ref[Int32]
  seal_count : Ref[Int32]
  epoch : Ref[UInt64]
  binding : Ref[UInt64]
  sequence : Ref[Int32]
}

///|
fn direct_press(
  key : @primitives.Key,
  shift~ : Bool = false,
) -> @platform.EventKind {
  @platform.Input(
    @primitives.KeyPressed(
      key~,
      repeat=false,
      modifiers=@primitives.Modifiers::new(
        shift~,
        control=false,
        alt=false,
        meta=false,
      ),
    ),
  )
}

///|
fn direct_release(key : @primitives.Key) -> @platform.EventKind {
  @platform.Input(
    @primitives.KeyReleased(key~, modifiers=@primitives.Modifiers::none()),
  )
}

///|
fn direct_fixture(
  commands : Array[@platform.EventKind],
  burst~ : Bool = false,
) -> DirectLifecycleFixture {
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let window = @platform.WindowId::new(1L)
  let owner_ref : Ref[SettingsRunOwner?] = Ref(None)
  let epoch = Ref(0UL)
  let binding = Ref(0UL)
  let sequence = Ref(1)
  let ordinal = Ref(0L)
  let pending : Ref[NativeRetainedReceipt?] = Ref(None)
  let pressed : Array[@primitives.Key] = []
  let frame_count = Ref(0)
  let idle_polls = Ref(0)
  let created = Ref(false)
  let destroyed = Ref(false)
  let fail_ack : Ref[String?] = Ref(None)
  let fail_release = Ref(false)
  let fail_rebind : Ref[String?] = Ref(None)
  let fail_seal = Ref(false)
  let frames = Ref(true)
  let cutoff_count = Ref(0)
  let release_count = Ref(0)
  let rebind_count = Ref(0)
  let seal_count = Ref(0)
  let port = NativeTextInputPort::with_initial_state(
    fn(_, root, _) {
      if binding.val != 0UL || epoch.val != 0UL {
        return Err(
          direct_lifecycle_error("fixture begin cannot erase retained history"),
        )
      }
      epoch.val += 1UL
      binding.val = root
      ordinal.val = 0L
      Ok(epoch.val)
    },
    fn(value, _) { Ok(value) },
    fn(value) { Ok(value) },
    fn(_) { Err(direct_lifecycle_error("fixture legacy end must not run")) },
    fn(_) { Ok(None) },
  ).with_linux_transport(fn() { DirectKeyboard })
  let ordered = NativeOrderedTextPort::with_retained_receipts(
    fn(_) {
      if pending.val is Some(_) {
        return Ok(pending.val)
      }
      let owner = owner_ref.val.unwrap()
      let kind = if !created.val {
        created.val = true
        @platform.Created
      } else if burst && owner.direct_run is Some(_) && !commands.is_empty() {
        let next = commands.remove(0)
        if next is @platform.FrameCompleted {
          frame_count.val = host.present_count()
        }
        next
      } else if frames.val && host.present_count() > frame_count.val {
        frame_count.val = host.present_count()
        @platform.FrameCompleted
      } else if host.destroy_count() > 0 && !destroyed.val {
        destroyed.val = true
        @platform.Destroyed
      } else if owner.dirty || owner.pending_frame is Some(_) {
        return Ok(None)
      } else if !commands.is_empty() {
        commands.remove(0)
      } else {
        idle_polls.val += 1
        if idle_polls.val < 8 {
          return Ok(None)
        }
        return Err(direct_lifecycle_error("fixture input exhausted"))
      }
      match kind {
        @platform.Input(@primitives.KeyPressed(key~, ..)) =>
          if !pressed.contains(key) {
            pressed.push(key)
          }
        @platform.Input(@primitives.KeyReleased(key~, ..)) =>
          for i = 0; i < pressed.length(); i = i + 1 {
            if pressed[i] == key {
              ignore(pressed.remove(i))
              break
            }
          }
        _ => ()
      }
      let seq = sequence.val
      let event = @platform.Event::new(window, seq.to_int64(), 1.0, kind)
      let direct = kind is @platform.Input(@primitives.TextInput(_))
      let edit = binding.val != 0UL && @ui.is_owned_edit_key(event)
      let ack = fn() {
        if (fail_ack.val == Some("direct") && (direct || edit)) ||
          (
            fail_ack.val == Some("platform") &&
            kind
            is @platform.Input(@primitives.KeyPressed(key=@primitives.Tab, ..))
          ) {
          fail_ack.val = None
          return Err(direct_lifecycle_error("fixture ACK failure"))
        }
        if sequence.val != seq || pending.val is None {
          return Err(direct_lifecycle_error("fixture stale ACK"))
        }
        if direct {
          ordinal.val += 1L
        }
        sequence.val += 1
        pending.val = None
        Ok(())
      }
      let receipt = if direct {
        NativeRetainedReceipt::direct(
          event,
          seq,
          binding.val,
          epoch.val,
          epoch.val.to_int(),
          ordinal.val + 1L,
          ack,
        )
      } else if edit {
        NativeRetainedReceipt::edit_key(
          event,
          seq,
          binding.val,
          epoch.val,
          epoch.val.to_int(),
          ack,
        )
      } else {
        NativeRetainedReceipt::new(
          Some(OrderedPlatform(event)),
          window,
          seq,
          binding.val,
          epoch.val,
          ack,
        )
      }
      pending.val = Some(receipt)
      Ok(Some(receipt))
    },
    fn(value) {
      cutoff_count.val += 1
      if value != epoch.val || binding.val == 0UL {
        return Err(direct_lifecycle_error("fixture cutoff owner"))
      }
      if !pressed.is_empty() || pending.val is Some(_) {
        return Err(
          @diagnostics.FrameworkError::new(@diagnostics.Busy, "fixture_cutoff"),
        )
      }
      Ok(())
    },
  ).with_direct_lifecycle(
    fn(value) {
      release_count.val += 1
      if fail_release.val ||
        value != epoch.val ||
        pending.val is Some(_) ||
        !pressed.is_empty() {
        return Err(direct_lifecycle_error("fixture release unresolved"))
      }
      binding.val = 0UL
      Ok(())
    },
    fn(w, root, released_epoch, retired_sequence) {
      rebind_count.val += 1
      match fail_rebind.val {
        Some("busy") => {
          fail_rebind.val = None
          return Err(
            @diagnostics.FrameworkError::new(
              @diagnostics.Busy,
              "fixture_rebind",
            ),
          )
        }
        Some(_) =>
          return Err(direct_lifecycle_error("fixture uncertain rebind"))
        None => ()
      }
      if w != window ||
        binding.val != 0UL ||
        released_epoch != epoch.val ||
        retired_sequence != sequence.val - 1 ||
        pending.val is Some(_) ||
        !pressed.is_empty() {
        return Err(direct_lifecycle_error("fixture rebind proof is unresolved"))
      }
      epoch.val += 1UL
      binding.val = root
      ordinal.val = 0L
      Ok(epoch.val)
    },
    fn(w, seq) {
      seal_count.val += 1
      if fail_seal.val ||
        !destroyed.val ||
        w != window ||
        seq != sequence.val - 1 ||
        binding.val != 0UL ||
        pending.val is Some(_) ||
        !pressed.is_empty() {
        return Err(direct_lifecycle_error("fixture seal unresolved"))
      }
      Ok(())
    },
  )
  let owner = SettingsRunOwner::new(
    host,
    Linux,
    text_runner_measure,
    text_port=Some(port),
    ordered_text=Some(ordered),
  ).unwrap()
  owner_ref.val = Some(owner)
  {
    owner,
    host,
    commands,
    fail_ack,
    fail_release,
    fail_rebind,
    fail_seal,
    frames,
    cutoff_count,
    release_count,
    rebind_count,
    seal_count,
    epoch,
    binding,
    sequence,
  }
}

///|
fn direct_typing() -> Array[@platform.EventKind] {
  [
    direct_press(@primitives.Character("a")),
    @platform.Input(@primitives.TextInput(text="a")),
    direct_release(@primitives.Character("a")),
    direct_press(@primitives.Character("b")),
    @platform.Input(@primitives.TextInput(text="b")),
    direct_release(@primitives.Character("b")),
    direct_press(@primitives.Backspace),
    direct_release(@primitives.Backspace),
  ]
}

///|
fn finish_direct_fixture(fixture : DirectLifecycleFixture) -> Unit raise {
  match fixture.owner.drive() {
    Ok(_) => ()
    Err(error) => fail(format_framework_error(error))
  }
  assert_true(fixture.owner.can_stop())
  assert_eq(fixture.owner.acknowledged_receipt_count(), 0)
  assert_eq(fixture.owner.direct_receipts.length(), 0)
  assert_eq(fixture.seal_count.val, 1)
  assert_eq(fixture.host.destroy_count(), 1)
  assert_true(fixture.commands.is_empty())
  assert_true(fixture.frames.val)
  assert_true(fixture.cutoff_count.val > 0)
  assert_eq(fixture.binding.val, 0UL)
  assert_true(fixture.sequence.val > 1)
  let entry : SettingsEntryController = {
    host: fixture.host,
    outcome: Completed,
    stop_attempted: false,
    stopped: false,
  }
  entry.try_stop().unwrap()
  assert_eq(fixture.host.stop_count(), 1)
  assert_true(entry.try_stop() is Err(_))
}

///|
test "direct lifecycle reflects insert and Backspace then seals an orderly close" {
  let commands = direct_typing()
  commands.push(@platform.CloseRequested)
  let fixture = direct_fixture(commands)
  finish_direct_fixture(fixture)
  assert_eq(fixture.owner.model().name(), "a")
  assert_eq(fixture.release_count.val, 1)
}

///|
test "direct lifecycle keeps Tab Enter release and dialog reopen on a fresh owner" {
  let commands = direct_typing()
  commands.push(direct_press(@primitives.Tab))
  commands.push(direct_release(@primitives.Tab))
  commands.push(direct_press(@primitives.Enter))
  commands.push(direct_release(@primitives.Enter))
  commands.push(direct_press(@primitives.Escape))
  commands.push(direct_release(@primitives.Escape))
  commands.push(direct_press(@primitives.Tab, shift=true))
  commands.push(direct_release(@primitives.Tab))
  commands.push(direct_press(@primitives.Character("c")))
  commands.push(@platform.Input(@primitives.TextInput(text="c")))
  commands.push(direct_release(@primitives.Character("c")))
  commands.push(@platform.CloseRequested)
  let fixture = direct_fixture(commands)
  finish_direct_fixture(fixture)
  assert_eq(fixture.owner.model().name(), "ac")
  assert_false(fixture.owner.model().dialog_open())
  assert_eq(fixture.epoch.val, 2UL)
  assert_eq(fixture.rebind_count.val, 1)
  assert_eq(fixture.release_count.val, 2)
}

///|
test "button Space release and repeated Enter still dispatch their model actions" {
  let commands = direct_typing()
  commands.push(direct_press(@primitives.Tab))
  commands.push(direct_release(@primitives.Tab))
  commands.push(direct_press(@primitives.Space))
  commands.push(direct_release(@primitives.Space))
  commands.push(direct_press(@primitives.Escape))
  commands.push(direct_release(@primitives.Escape))
  commands.push(direct_press(@primitives.Enter))
  commands.push(direct_release(@primitives.Enter))
  commands.push(direct_press(@primitives.Escape))
  commands.push(direct_release(@primitives.Escape))
  commands.push(direct_press(@primitives.Enter))
  commands.push(direct_release(@primitives.Enter))
  let fixture = direct_fixture(commands)
  assert_true(fixture.owner.drive() is Err(_))
  assert_true(fixture.owner.model().dialog_open())
  assert_eq(fixture.owner.model().name(), "a")
  assert_false(fixture.owner.can_stop())
}

///|
test "focus boundary reopens only when the host certifies a fresh owner" {
  let commands = direct_typing()
  commands.push(@platform.FocusChanged(false))
  commands.push(@platform.FocusChanged(true))
  commands.push(direct_press(@primitives.Character("c")))
  commands.push(@platform.Input(@primitives.TextInput(text="c")))
  commands.push(direct_release(@primitives.Character("c")))
  commands.push(@platform.CloseRequested)
  let fixture = direct_fixture(commands)
  finish_direct_fixture(fixture)
  assert_eq(fixture.epoch.val, 2UL)
  assert_eq(fixture.owner.model().name(), "ac")
}

///|
fn resume_direct_fixture(fixture : DirectLifecycleFixture) -> Unit raise {
  let owner = fixture.owner
  let entry : SettingsEntryController = {
    host: fixture.host,
    outcome: Suspended(owner, direct_lifecycle_error("fixture")),
    stop_attempted: false,
    stopped: false,
  }
  let (_, sequence, _, _) = owner.pending_receipt_identity().unwrap()
  assert_true(
    entry.retry_receipt_sequence(sequence.to_int64()).unwrap()
    is ReceiptAcknowledged,
  )
  assert_true(entry.retry_receipt_sequence(sequence.to_int64()) is Err(_))
  for _ in 0..<200 {
    if !entry.suspended() {
      break
    }
    let generation = match entry.advance_generation() {
      Some(value) => value
      None => fail("continuation was lost")
    }
    match entry.advance_once(generation) {
      Ok(_) => ()
      Err(error) => fail(format_framework_error(error))
    }
  }
  assert_false(entry.suspended())
  assert_true(owner.can_stop())
  entry.try_stop().unwrap()
  assert_eq(fixture.host.stop_count(), 1)
}

///|
test "failed direct ACK retains the exact edit and retry applies it once before safe stop" {
  let commands = direct_typing()
  commands.push(@platform.CloseRequested)
  let fixture = direct_fixture(commands)
  fixture.fail_ack.val = Some("direct")
  assert_true(fixture.owner.drive() is Err(_))
  assert_eq(fixture.owner.model().name(), "")
  assert_eq(fixture.owner.direct_receipts.length(), 0)
  assert_false(fixture.owner.can_stop())
  resume_direct_fixture(fixture)
  assert_eq(fixture.owner.model().name(), "a")
  assert_eq(fixture.release_count.val, 1)
}

///|
test "failed Tab ACK preserves a resumable boundary and completes through the controller" {
  let commands = direct_typing()
  commands.push(direct_press(@primitives.Tab))
  commands.push(direct_release(@primitives.Tab))
  commands.push(@platform.CloseRequested)
  let fixture = direct_fixture(commands)
  fixture.fail_ack.val = Some("platform")
  assert_true(fixture.owner.drive() is Err(_))
  assert_eq(fixture.owner.model().name(), "a")
  assert_eq(fixture.release_count.val, 0)
  resume_direct_fixture(fixture)
}

///|
test "release failure retains ACKed direct records and cannot reach seal or stop" {
  let commands = direct_typing()
  commands.push(@platform.CloseRequested)
  let fixture = direct_fixture(commands)
  fixture.fail_release.val = true
  assert_true(fixture.owner.drive() is Err(_))
  assert_eq(fixture.owner.model().name(), "a")
  assert_true(fixture.owner.cutoff_completed())
  assert_true(fixture.owner.direct_receipts.length() > 0)
  assert_true(fixture.owner.acknowledged_receipt_count() > 0)
  assert_eq(fixture.release_count.val, 1)
  assert_eq(fixture.seal_count.val, 0)
  assert_eq(fixture.host.destroy_count(), 0)
  assert_false(fixture.owner.can_stop())
}

///|
test "seal failure retains the terminal ledger and never authorizes host stop" {
  let commands = direct_typing()
  commands.push(@platform.CloseRequested)
  let fixture = direct_fixture(commands)
  fixture.fail_seal.val = true
  assert_true(fixture.owner.drive() is Err(_))
  assert_eq(fixture.release_count.val, 1)
  assert_eq(fixture.host.destroy_count(), 1)
  assert_eq(fixture.seal_count.val, 1)
  assert_true(fixture.owner.acknowledged_receipt_count() > 0)
  assert_false(fixture.owner.can_stop())
  assert_eq(fixture.host.stop_count(), 0)
}

///|
test "pending model action and uncompleted scene cannot certify direct retirement" {
  let fixture = direct_fixture(direct_typing())
  assert_true(fixture.owner.drive() is Err(_))
  let owner = fixture.owner
  let run = owner.direct_run.unwrap()
  assert_eq(owner.model().name(), "a")
  assert_true(owner.direct_scene_is_current(run))
  let scene = run.scene.unwrap()
  scene.completed = false
  assert_true(owner.verify_direct_prefix(run, run.records.length()) is Err(_))
  scene.completed = true
  let event = @platform.Event::new(
    owner.window,
    1000L,
    1.0,
    direct_press(@primitives.Enter),
  )
  assert_true(owner.mounted.handle_event(event).unwrap())
  assert_true(owner.mounted.has_pending_actions())
  assert_true(owner.verify_direct_prefix(run, run.records.length()) is Err(_))
  assert_eq(fixture.release_count.val, 0)
  assert_false(owner.can_stop())
}

///|
test "native character and Tab bursts preserve the final published direct prefix" {
  let commands = direct_typing()
  commands.push(@platform.FrameCompleted)
  commands.push(direct_press(@primitives.Tab))
  commands.push(direct_release(@primitives.Tab))
  commands.push(@platform.FrameCompleted)
  commands.push(@platform.CloseRequested)
  let fixture = direct_fixture(commands, burst=true)
  finish_direct_fixture(fixture)
  assert_eq(fixture.owner.model().name(), "a")
}

///|
test "close waits for an already admitted key release and its final scene" {
  let fixture = direct_fixture([
    direct_press(@primitives.Character("a")),
    @platform.Input(@primitives.TextInput(text="a")),
    @platform.CloseRequested,
    direct_release(@primitives.Character("a")),
  ])
  finish_direct_fixture(fixture)
  assert_eq(fixture.owner.model().name(), "a")
}

///|
test "long direct typing crosses several bounded leases without losing the pending character" {
  let commands : Array[@platform.EventKind] = []
  let mut expected = ""
  for _ in 0..<40 {
    commands.push(direct_press(@primitives.Character("a")))
    commands.push(@platform.Input(@primitives.TextInput(text="a")))
    commands.push(direct_release(@primitives.Character("a")))
    expected += "a"
  }
  commands.push(direct_press(@primitives.Backspace))
  commands.push(direct_release(@primitives.Backspace))
  commands.push(@platform.CloseRequested)
  let fixture = direct_fixture(commands)
  finish_direct_fixture(fixture)
  assert_eq(fixture.owner.model().name() + "a", expected)
  assert_true(fixture.epoch.val > 2UL)
}

///|
test "a scene alone cannot retire a direct lease without host cutoff" {
  let fixture = direct_fixture(direct_typing())
  assert_true(fixture.owner.drive() is Err(_))
  let owner = fixture.owner
  let run = owner.direct_run.unwrap()
  assert_true(owner.direct_scene_is_current(run))
  let count = owner.acknowledged_receipt_count()
  assert_true(owner.release_direct_lease(run) is Err(_))
  assert_eq(owner.acknowledged_receipt_count(), count)
  assert_eq(fixture.release_count.val, 0)
  assert_false(owner.can_stop())
}

///|
test "retirement rejects a different model effect or native identity without deleting records" {
  let fixture = direct_fixture(direct_typing())
  assert_true(fixture.owner.drive() is Err(_))
  let owner = fixture.owner
  let run = owner.direct_run.unwrap()
  let count = owner.acknowledged_receipt_count()
  let mut checked = false
  for proof in run.records {
    match proof.resolution {
      DirectEdit(delivery, before, after) => {
        proof.resolution = DirectEdit(
          delivery,
          before,
          after.update(
            @shared_settings.Ui(
              @view.TextChanged(@shared_settings.settings_name(), "wrong"),
            ),
          ),
        )
        assert_true(owner.verify_direct_prefix(run, count) is Err(_))
        proof.resolution = DirectEdit(delivery, before, after)
        checked = true
        break
      }
      _ => ()
    }
  }
  assert_true(checked)
  let original = owner.acknowledged_receipts[0]
  owner.acknowledged_receipts[0] = {
    ..original,
    receipt: { ..original.receipt, root: original.receipt.root + 1UL, },
  }
  assert_true(owner.verify_direct_prefix(run, count) is Err(_))
  assert_eq(owner.acknowledged_receipt_count(), count)
  assert_eq(fixture.release_count.val, 0)
}

///|
test "same-value model replacement invalidates the scene evidence" {
  let fixture = direct_fixture(direct_typing())
  assert_true(fixture.owner.drive() is Err(_))
  let owner = fixture.owner
  let run = owner.direct_run.unwrap()
  assert_true(owner.direct_scene_is_current(run))
  owner.replace_settings(owner.model())
  assert_false(owner.direct_scene_is_current(run))
  assert_true(owner.verify_direct_prefix(run, run.records.length()) is Err(_))
  assert_eq(fixture.release_count.val, 0)
}

///|
test "late direct receipt for an earlier epoch remains unacknowledged after reopen" {
  let commands = direct_typing()
  commands.push(@platform.FocusChanged(false))
  commands.push(@platform.FocusChanged(true))
  let fixture = direct_fixture(commands)
  assert_true(fixture.owner.drive() is Err(_))
  let owner = fixture.owner
  let run = owner.direct_run.unwrap()
  assert_eq(fixture.epoch.val, 2UL)
  let acked = Ref(false)
  let event = @platform.Event::new(
    owner.window,
    fixture.sequence.val.to_int64(),
    1.0,
    @platform.Input(@primitives.TextInput(text="late")),
  )
  let receipt = NativeRetainedReceipt::direct(
    event,
    fixture.sequence.val,
    fixture.binding.val,
    1UL,
    1,
    1L,
    fn() {
      acked.val = true
      Ok(())
    },
  )
  assert_true(owner.direct_admit(run, receipt) is Err(_))
  assert_false(acked.val)
  assert_eq(owner.model().name(), "a")
  assert_true(owner.pending_receipt_identity() is Some((_, _, _, 1UL)))
  assert_false(owner.can_stop())
}

///|
test "unbound button close waits for Space release and its model action" {
  let commands = direct_typing()
  commands.push(direct_press(@primitives.Tab))
  commands.push(direct_release(@primitives.Tab))
  commands.push(direct_press(@primitives.Space))
  commands.push(@platform.CloseRequested)
  commands.push(direct_release(@primitives.Space))
  let fixture = direct_fixture(commands)
  finish_direct_fixture(fixture)
  assert_true(fixture.owner.model().dialog_open())
}

///|
test "validation-rejected platform receipt cannot use the ACK retry path" {
  let fixture = direct_fixture(direct_typing())
  assert_true(fixture.owner.drive() is Err(_))
  let owner = fixture.owner
  let run = owner.direct_run.unwrap()
  let acknowledged = Ref(false)
  let event = @platform.Event::new(
    owner.window,
    fixture.sequence.val.to_int64(),
    1.0,
    direct_press(@primitives.Tab),
  )
  let receipt = NativeRetainedReceipt::new(
    Some(OrderedPlatform(event)),
    owner.window,
    fixture.sequence.val,
    fixture.binding.val,
    fixture.epoch.val + 1UL,
    fn() {
      acknowledged.val = true
      Ok(())
    },
  )
  assert_true(owner.direct_admit(run, receipt) is Err(_))
  assert_true(owner.terminal_step(RetryReceiptAck) is Err(_))
  assert_false(acknowledged.val)
  assert_eq(owner.model().name(), "a")
  assert_false(owner.can_stop())
}

///|
test "passive physical key edges preserve the completed scene without republishing" {
  let fixture = direct_fixture([])
  assert_true(fixture.owner.drive() is Err(_))
  let run = fixture.owner.direct_run.unwrap()
  assert_true(fixture.owner.direct_scene_is_current(run))
  let presented = fixture.host.present_count()
  fixture.commands.push(direct_press(@primitives.Character("a")))
  fixture.commands.push(direct_release(@primitives.Character("a")))
  assert_true(fixture.owner.drive() is Err(_))
  assert_true(fixture.owner.direct_scene_is_current(run))
  assert_eq(fixture.host.present_count(), presented)
  assert_eq(fixture.owner.model().name(), "")
  assert_false(fixture.owner.can_stop())
}

///|
test "released dialog actions reclaim only their completed model and scene prefix" {
  let commands = direct_typing()
  commands.push(direct_press(@primitives.Tab))
  commands.push(direct_release(@primitives.Tab))
  for _ in 0..<20 {
    commands.push(direct_press(@primitives.Enter))
    commands.push(direct_release(@primitives.Enter))
    commands.push(direct_press(@primitives.Escape))
    commands.push(direct_release(@primitives.Escape))
  }
  commands.push(@platform.CloseRequested)
  let fixture = direct_fixture(commands)
  finish_direct_fixture(fixture)
  assert_eq(fixture.owner.model().name(), "a")
  assert_false(fixture.owner.model().dialog_open())
  assert_eq(fixture.release_count.val, 1)
  assert_eq(fixture.epoch.val, 1UL)
  assert_true(fixture.sequence.val > 128)
}

///|
test "a locally valid platform effect must still match the anchored model prefix" {
  let fixture = direct_fixture(direct_typing())
  assert_true(fixture.owner.drive() is Err(_))
  let owner = fixture.owner
  let run = owner.direct_run.unwrap()
  let count = owner.acknowledged_receipt_count()
  assert_true(owner.verify_direct_prefix(run, count) is Ok(_))
  let mut checked = false
  for proof in run.records {
    match proof.resolution {
      DirectPlatform(before, actions, after) if actions.is_empty() => {
        let wrong = before.update(
          @shared_settings.Ui(
            @view.TextChanged(
              @shared_settings.settings_name(),
              "different-prefix",
            ),
          ),
        )
        proof.resolution = DirectPlatform(wrong, [], wrong)
        assert_true(owner.verify_direct_prefix(run, count) is Err(_))
        assert_eq(owner.acknowledged_receipt_count(), count)
        proof.resolution = DirectPlatform(before, actions, after)
        checked = true
        break
      }
      _ => ()
    }
  }
  assert_true(checked)
  assert_true(owner.verify_direct_prefix(run, count) is Ok(_))
  assert_eq(fixture.release_count.val, 0)
}

///|
test "save completion remains in the model chain before terminal retirement" {
  let commands = direct_typing()
  commands.push(direct_press(@primitives.Tab))
  commands.push(direct_release(@primitives.Tab))
  commands.push(direct_press(@primitives.Enter))
  commands.push(direct_release(@primitives.Enter))
  commands.push(direct_press(@primitives.Enter))
  commands.push(direct_release(@primitives.Enter))
  commands.push(@platform.CloseRequested)
  let fixture = direct_fixture(commands)
  finish_direct_fixture(fixture)
  assert_eq(fixture.owner.model().name(), "a")
  assert_false(fixture.owner.model().saving())
}

///|
test "uncertain host rebind preserves its published suffix and is never retried" {
  let commands = direct_typing()
  commands.push(direct_press(@primitives.Tab))
  commands.push(direct_release(@primitives.Tab))
  commands.push(direct_press(@primitives.Tab, shift=true))
  commands.push(direct_release(@primitives.Tab))
  let fixture = direct_fixture(commands)
  fixture.fail_rebind.val = Some("error")
  assert_true(fixture.owner.drive() is Err(_))
  let owner = fixture.owner
  let run = owner.direct_run.unwrap()
  let count = owner.acknowledged_receipt_count()
  assert_true(run.rebind_attempted)
  assert_true(count > 0)
  assert_eq(fixture.rebind_count.val, 1)
  assert_eq(fixture.binding.val, 0UL)
  assert_true(owner.drive() is Err(_))
  assert_eq(fixture.rebind_count.val, 1)
  assert_eq(owner.acknowledged_receipt_count(), count)
  assert_false(owner.can_stop())
}

///|
test "a side-effect-free busy rebind retries only after the same suffix remains resolved" {
  let commands = direct_typing()
  commands.push(direct_press(@primitives.Tab))
  commands.push(direct_release(@primitives.Tab))
  commands.push(direct_press(@primitives.Tab, shift=true))
  commands.push(direct_release(@primitives.Tab))
  let fixture = direct_fixture(commands)
  fixture.fail_rebind.val = Some("busy")
  assert_true(fixture.owner.drive() is Err(_))
  assert_eq(fixture.rebind_count.val, 2)
  assert_eq(fixture.epoch.val, 2UL)
  assert_false(fixture.owner.direct_run.unwrap().rebind_attempted)
  assert_true(fixture.owner.session is Some(_))
  assert_eq(fixture.owner.model().name(), "a")
  assert_false(fixture.owner.can_stop())
}

///|
test "native refusal after focus loss keeps the returned focus suffix retained" {
  let commands = direct_typing()
  commands.push(@platform.FocusChanged(false))
  commands.push(@platform.FocusChanged(true))
  let fixture = direct_fixture(commands)
  fixture.fail_rebind.val = Some("stale-focus-generation")
  assert_true(fixture.owner.drive() is Err(_))
  assert_eq(fixture.release_count.val, 1)
  assert_eq(fixture.rebind_count.val, 1)
  assert_eq(fixture.binding.val, 0UL)
  assert_eq(fixture.epoch.val, 1UL)
  assert_true(fixture.owner.session is None)
  assert_true(fixture.owner.terminal_owner is None)
  assert_true(fixture.owner.acknowledged_receipt_count() > 0)
  assert_eq(fixture.owner.model().name(), "a")
  assert_false(fixture.owner.can_stop())
}

///|
test "printable input during a busy rebind remains unacknowledged on its original receipt" {
  let commands = direct_typing()
  commands.push(direct_press(@primitives.Tab))
  commands.push(direct_release(@primitives.Tab))
  commands.push(direct_press(@primitives.Tab, shift=true))
  commands.push(direct_release(@primitives.Tab))
  commands.push(direct_press(@primitives.Character("c")))
  // Native direct mode is disabled, so no TextInput sibling exists for this
  // physical press. Keeping the record is required; synthesizing c is unsafe.
  commands.push(direct_release(@primitives.Character("c")))
  commands.push(@platform.CloseRequested)
  let fixture = direct_fixture(commands)
  fixture.fail_rebind.val = Some("busy")
  assert_true(fixture.owner.drive() is Err(_))
  assert_eq(fixture.owner.model().name(), "a")
  assert_false(fixture.owner.can_stop())
  assert_true(fixture.owner.pending_receipt_identity() is Some(_))
  assert_eq(fixture.rebind_count.val, 1)
  assert_eq(fixture.binding.val, 0UL)
  let sequence = fixture.sequence.val
  assert_true(fixture.owner.terminal_step(RetryReceiptAck) is Err(_))
  assert_eq(fixture.sequence.val, sequence)
  assert_eq(fixture.rebind_count.val, 1)
  assert_eq(fixture.seal_count.val, 0)
}
