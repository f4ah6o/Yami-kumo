///|
fn deferred_preedit_fixture(
  head : Ref[NativeRetainedReceipt?],
) -> (SettingsRunOwner, @platform.Event) {
  let ordered = NativeOrderedTextPort::with_retained_receipts(
    fn(_) { Ok(head.val) },
    fn(_) { Err(runner_error("fixture", "unexpected cutoff")) },
  )
  let (owner, _) = publication_fixture_with_ordered(Some(ordered))
  let binding = owner.session.unwrap().binding
  let preedit = @text_host.TextInputEvent::new(
    owner.window,
    1L,
    7UL,
    @text_host.Preedit(text="にほん", cursor=3),
  )
  owner.acknowledged_receipts.push({
    receipt: NativeRetainedReceipt::new(
      Some(OrderedText(preedit)),
      owner.window,
      2,
      binding,
      7UL,
      fn() { Ok(()) },
    ),
    stage: ReceiptAcknowledgedOnly,
  })
  owner.deliver_owned_observation(preedit).unwrap()
  let tab = @platform.Event::new(
    owner.window,
    3L,
    1.0,
    @platform.Input(
      @primitives.KeyPressed(
        key=@primitives.Tab,
        modifiers=@primitives.Modifiers::none(),
        repeat=false,
      ),
    ),
  )
  owner.acknowledged_receipts.push({
    receipt: NativeRetainedReceipt::new(
      Some(OrderedPlatform(tab)),
      owner.window,
      3,
      binding,
      7UL,
      fn() { Ok(()) },
    ),
    stage: ReceiptAcknowledgedOnly,
  })
  owner.inflight = Some(OrderedPlatform(tab))
  owner.last_sequence = 3L
  owner.suspended = true
  (owner, tab)
}

///|
test "suspended Tab preedit can admit later original commit without dropping Tab" {
  let head : Ref[NativeRetainedReceipt?] = Ref(None)
  let (owner, tab) = deferred_preedit_fixture(head)
  let event = @text_host.TextInputEvent::new(
    owner.window,
    2L,
    7UL,
    @text_host.Commit(text="日本"),
  )
  let acks = Ref(0)
  head.val = Some(
    NativeRetainedReceipt::new(
      Some(OrderedText(event)),
      owner.window,
      4,
      owner.session.unwrap().binding,
      7UL,
      fn() {
        acks.val += 1
        head.val = None
        Ok(())
      },
    ),
  )
  assert_true(owner.poll_deferred_preedit() is Ok(RecordBuffered))
  assert_eq(acks.val, 1)
  assert_true(
    owner.inflight is Some(OrderedPlatform(value)) &&
    value.sequence() == tab.sequence(),
  )
  assert_true(owner.apply_deferred_preedit() is Ok(ModelApplied(2L, true)))
  assert_eq(owner.model().name(), "日本")
  assert_true(
    owner.inflight is Some(OrderedPlatform(value)) &&
    value.sequence() == tab.sequence(),
  )
  assert_true(owner.buffered.is_empty())
  assert_true(owner.apply_deferred_preedit() is Err(_))
  assert_eq(owner.model().name(), "日本")
  assert_false(owner.can_stop())
}

///|
test "deferred preedit ack failure retains buffer and original intent until exact retry" {
  let head : Ref[NativeRetainedReceipt?] = Ref(None)
  let (owner, tab) = deferred_preedit_fixture(head)
  let event = @text_host.TextInputEvent::new(
    owner.window,
    2L,
    7UL,
    @text_host.Cancel,
  )
  let attempts = Ref(0)
  let blocked_reentry = Ref(false)
  head.val = Some(
    NativeRetainedReceipt::new(
      Some(OrderedText(event)),
      owner.window,
      4,
      owner.session.unwrap().binding,
      7UL,
      fn() {
        attempts.val += 1
        blocked_reentry.val = owner.poll_deferred_preedit() is Err(_)
        if attempts.val == 1 {
          return Err(runner_error("fixture_ack", "temporary failure"))
        }
        head.val = None
        Ok(())
      },
    ),
  )
  assert_true(owner.poll_deferred_preedit() is Err(_))
  assert_true(blocked_reentry.val)
  assert_eq(owner.buffered.length(), 1)
  assert_true(owner.pending_receipt_identity() is Some((_, 4, _, 7UL)))
  assert_true(owner.poll_deferred_preedit() is Err(_))
  assert_true(owner.apply_deferred_preedit() is Err(_))
  assert_eq(owner.model().name(), "")
  assert_true(owner.terminal_step(RetryReceiptAck) is Ok(ReceiptAcknowledged))
  assert_eq(attempts.val, 2)
  assert_true(owner.apply_deferred_preedit() is Ok(FieldApplied(2L)))
  assert_eq(owner.model().name(), "")
  assert_false(owner.mounted.focused_text().unwrap().composing())
  assert_true(
    owner.inflight is Some(OrderedPlatform(value)) &&
    value.sequence() == tab.sequence(),
  )
  assert_true(owner.apply_deferred_preedit() is Err(_))
  assert_false(owner.can_stop())
}

///|
test "deferred poll preserves nontext head and full ledger applies backpressure" {
  let head : Ref[NativeRetainedReceipt?] = Ref(None)
  let (owner, _) = deferred_preedit_fixture(head)
  let acks = Ref(0)
  let nontext = @platform.Event::new(
    owner.window,
    4L,
    1.0,
    @platform.FocusChanged(false),
  )
  head.val = Some(
    NativeRetainedReceipt::new(
      Some(OrderedPlatform(nontext)),
      owner.window,
      4,
      owner.session.unwrap().binding,
      7UL,
      fn() {
        acks.val += 1
        Ok(())
      },
    ),
  )
  assert_true(owner.poll_deferred_preedit() is Err(_))
  assert_eq(acks.val, 0)
  assert_true(head.val is Some(_))
  assert_true(owner.buffered.is_empty())
  // Fill the bounded ledger with receipts after the original intent. It must
  // refuse before peeking/ACK even when the next event would otherwise fit.
  for i in 4..<65 {
    let item = @platform.Event::new(
      owner.window,
      i.to_int64(),
      1.0,
      @platform.FrameCompleted,
    )
    owner.acknowledged_receipts.push({
      receipt: NativeRetainedReceipt::new(
        Some(OrderedPlatform(item)),
        owner.window,
        i,
        owner.session.unwrap().binding,
        7UL,
        fn() { Ok(()) },
      ),
      stage: ReceiptAcknowledgedOnly,
    })
  }
  assert_eq(owner.acknowledged_receipts.length(), 64)
  assert_true(owner.poll_deferred_preedit() is Err(_))
  assert_eq(acks.val, 0)
  assert_true(head.val is Some(_))
  assert_false(owner.can_stop())
}

///|
test "deferred poll has zero timeout and rejects stale owner without ACK" {
  let calls = Ref(0)
  let seen_timeout = Ref(-1)
  let head : Ref[NativeRetainedReceipt?] = Ref(None)
  let ordered = NativeOrderedTextPort::with_retained_receipts(
    fn(timeout) {
      seen_timeout.val = timeout
      calls.val += 1
      Ok(head.val)
    },
    fn(_) { Err(runner_error("fixture", "unexpected cutoff")) },
  )
  let (owner, _) = publication_fixture_with_ordered(Some(ordered))
  let binding = owner.session.unwrap().binding
  let preedit = @text_host.TextInputEvent::new(
    owner.window,
    1L,
    7UL,
    @text_host.Preedit(text="にほん", cursor=3),
  )
  owner.acknowledged_receipts.push({
    receipt: NativeRetainedReceipt::new(
      Some(OrderedText(preedit)),
      owner.window,
      2,
      binding,
      7UL,
      fn() { Ok(()) },
    ),
    stage: ReceiptAcknowledgedOnly,
  })
  owner.deliver_owned_observation(preedit).unwrap()
  let blur = @platform.Event::new(
    owner.window,
    3L,
    1.0,
    @platform.FocusChanged(false),
  )
  owner.acknowledged_receipts.push({
    receipt: NativeRetainedReceipt::new(
      Some(OrderedPlatform(blur)),
      owner.window,
      3,
      binding,
      7UL,
      fn() { Ok(()) },
    ),
    stage: ReceiptAcknowledgedOnly,
  })
  owner.inflight = Some(OrderedPlatform(blur))
  owner.last_sequence = 3L
  owner.suspended = true
  assert_true(owner.poll_deferred_preedit() is Ok(NoRecord))
  assert_eq(calls.val, 1)
  assert_eq(seen_timeout.val, 0)
  let acks = Ref(0)
  let event = @text_host.TextInputEvent::new(
    owner.window,
    2L,
    7UL,
    @text_host.Cancel,
  )
  head.val = Some(
    NativeRetainedReceipt::new(
      Some(OrderedText(event)),
      owner.window,
      4,
      binding + 1UL,
      7UL,
      fn() {
        acks.val += 1
        Ok(())
      },
    ),
  )
  assert_true(owner.poll_deferred_preedit() is Err(_))
  assert_eq(acks.val, 0)
  assert_true(head.val is Some(_))
  assert_eq(owner.model().name(), "")
}

///|
test "already applied deferred commit reconciles its retained action without replay" {
  let head : Ref[NativeRetainedReceipt?] = Ref(None)
  let (owner, tab) = deferred_preedit_fixture(head)
  let event = @text_host.TextInputEvent::new(
    owner.window,
    2L,
    7UL,
    @text_host.Commit(text="日本"),
  )
  head.val = Some(
    NativeRetainedReceipt::new(
      Some(OrderedText(event)),
      owner.window,
      4,
      owner.session.unwrap().binding,
      7UL,
      fn() {
        head.val = None
        Ok(())
      },
    ),
  )
  ignore(owner.poll_deferred_preedit().unwrap())
  // Controlled interruption immediately after field application and action
  // extraction, before model application. This does not simulate a crash.
  let receipt = owner.mounted
    .reserve_owned_text(owner.terminal_owner.unwrap(), event)
    .unwrap()
  owner.owned_model_before = Some(owner.settings)
  owner.owned_model_fence = Some(owner.model_fence)
  owner.owned_delivery = Some(receipt)
  owner.mounted.apply_owned_text(receipt).unwrap()
  assert_true(receipt.applied())
  assert_eq(owner.model().name(), "")
  assert_eq(owner.buffered.length(), 1)
  assert_true(owner.apply_deferred_preedit() is Ok(ModelApplied(2L, true)))
  assert_eq(owner.model().name(), "日本")
  assert_true(
    owner.inflight is Some(OrderedPlatform(value)) &&
    value.sequence() == tab.sequence(),
  )
  assert_true(owner.apply_deferred_preedit() is Err(_))
  assert_eq(owner.model().name(), "日本")
}

///|
test "failed deferred measurement retains receipt and retries original commit once" {
  let head : Ref[NativeRetainedReceipt?] = Ref(None)
  let fail = Ref(false)
  let measure = fn(value, size) {
    if fail.val && value == "日本" {
      Err(runner_error("fixture", "measurement failed"))
    } else {
      text_runner_measure(value, size)
    }
  }
  let host = @testing.ScriptedBackend::new(640.0, 480.0, 1.0).unwrap()
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) },
    fn(epoch, _) { Ok(epoch) },
    fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) },
    fn(_) { Ok(None) },
  )
  let ordered = NativeOrderedTextPort::with_retained_receipts(
    fn(_) { Ok(head.val) },
    fn(_) { Err(runner_error("fixture", "unexpected cutoff")) },
  )
  let owner = SettingsRunOwner::new(
    host,
    Linux,
    measure,
    text_port=Some(port),
    ordered_text=Some(ordered),
  ).unwrap()
  ignore(
    owner.mounted
    .commit(owner.settings.view(), 640.0, 480.0, 1.0, measure)
    .unwrap(),
  )
  assert_true(owner.mounted.focus(@shared_settings.settings_name()))
  let binding = owner.mounted.focused_text().unwrap().binding_id()
  owner.session = Some({ epoch: 7UL, binding, })
  owner.host_epoch = Some(7UL)
  owner.host_epoch_verified = true
  owner.terminal_owner = Some(
    owner.mounted.capture_terminal_text_owner(7UL).unwrap(),
  )
  owner.entered_target = Some((5, 11L, 4))
  owner.acknowledged_receipts.push({
    receipt: NativeRetainedReceipt::entered(
      owner.window,
      1,
      binding,
      7UL,
      5,
      11L,
      4,
      fn() { Ok(()) },
    ),
    stage: ReceiptOwnerEntered,
  })
  let preedit = @text_host.TextInputEvent::new(
    owner.window,
    1L,
    7UL,
    @text_host.Preedit(text="にほん", cursor=3),
  )
  owner.acknowledged_receipts.push({
    receipt: NativeRetainedReceipt::new(
      Some(OrderedText(preedit)),
      owner.window,
      2,
      binding,
      7UL,
      fn() { Ok(()) },
    ),
    stage: ReceiptAcknowledgedOnly,
  })
  owner.deliver_owned_observation(preedit).unwrap()
  let tab = @platform.Event::new(
    owner.window,
    3L,
    1.0,
    @platform.Input(
      @primitives.KeyPressed(
        key=@primitives.Tab,
        modifiers=@primitives.Modifiers::none(),
        repeat=false,
      ),
    ),
  )
  owner.acknowledged_receipts.push({
    receipt: NativeRetainedReceipt::new(
      Some(OrderedPlatform(tab)),
      owner.window,
      3,
      binding,
      7UL,
      fn() { Ok(()) },
    ),
    stage: ReceiptAcknowledgedOnly,
  })
  owner.inflight = Some(OrderedPlatform(tab))
  owner.last_sequence = 3L
  owner.suspended = true
  let event = @text_host.TextInputEvent::new(
    owner.window,
    2L,
    7UL,
    @text_host.Commit(text="日本"),
  )
  head.val = Some(
    NativeRetainedReceipt::new(
      Some(OrderedText(event)),
      owner.window,
      4,
      binding,
      7UL,
      fn() {
        head.val = None
        Ok(())
      },
    ),
  )
  ignore(owner.poll_deferred_preedit().unwrap())
  fail.val = true
  assert_true(owner.apply_deferred_preedit() is Err(_))
  assert_true(owner.owned_delivery is Some(receipt) && !receipt.applied())
  assert_eq(owner.buffered.length(), 1)
  assert_eq(owner.model().name(), "")
  assert_true(owner.mounted.focused_text().unwrap().composing())
  fail.val = false
  assert_true(owner.apply_deferred_preedit() is Ok(ModelApplied(2L, true)))
  assert_eq(owner.model().name(), "日本")
  assert_true(owner.apply_deferred_preedit() is Err(_))
  assert_eq(host.stop_count(), 0)
  assert_false(owner.can_stop())
}

///|
test "deferred poll leaves a full local buffer and native head unchanged" {
  let head : Ref[NativeRetainedReceipt?] = Ref(None)
  let (owner, _) = deferred_preedit_fixture(head)
  // Existing buffers may have been filled before the suspended transition.
  // They are not consumed or reordered by the one-slot resolution policy.
  for i in 0..<64 {
    owner.buffered.push(
      OrderedPlatform(
        @platform.Event::new(
          owner.window,
          (i + 4).to_int64(),
          1.0,
          @platform.FrameCompleted,
        ),
      ),
    )
  }
  let ack = Ref(0)
  let event = @text_host.TextInputEvent::new(
    owner.window,
    2L,
    7UL,
    @text_host.Cancel,
  )
  head.val = Some(
    NativeRetainedReceipt::new(
      Some(OrderedText(event)),
      owner.window,
      4,
      owner.session.unwrap().binding,
      7UL,
      fn() {
        ack.val += 1
        Ok(())
      },
    ),
  )
  assert_true(owner.poll_deferred_preedit() is Err(_))
  assert_eq(owner.buffered.length(), 64)
  assert_eq(ack.val, 0)
  assert_true(head.val is Some(_))
  assert_false(owner.can_stop())
}

///|
test "deferred original intent cannot resume after later platform watermark" {
  let head : Ref[NativeRetainedReceipt?] = Ref(None)
  let (owner, tab) = deferred_preedit_fixture(head)
  let ack = Ref(0)
  let commit = @text_host.TextInputEvent::new(
    owner.window,
    2L,
    7UL,
    @text_host.Commit(text="日本"),
  )
  head.val = Some(
    NativeRetainedReceipt::new(
      Some(OrderedText(commit)),
      owner.window,
      4,
      owner.session.unwrap().binding,
      7UL,
      fn() {
        ack.val += 1
        Ok(())
      },
    ),
  )
  // Simulate a pre-existing ordering violation, not a valid recovery path.
  owner.last_sequence = 4L
  assert_true(owner.poll_deferred_preedit() is Err(_))
  assert_eq(ack.val, 0)
  assert_true(head.val is Some(_))
  assert_true(
    owner.inflight is Some(OrderedPlatform(value)) &&
    value.sequence() == tab.sequence(),
  )
  assert_true(owner.buffered.is_empty())
  assert_false(owner.can_stop())
}
