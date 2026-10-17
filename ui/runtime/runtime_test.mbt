///|
fn key(value : String) -> @core.NodeKey {
  @core.NodeKey::new(value)
}

///|
fn button(
  name : String,
  disabled~ : Bool = false,
  loading~ : Bool = false,
) -> @core.View {
  @core.button(key(name), name, disabled~, loading~)
}

///|
fn tree(children : Array[@core.View]) -> @core.View {
  @core.column(key("root"), children)
}

///|
fn token(runtime : @runtime.Runtime, name : String) -> @runtime.InstanceToken {
  match runtime.token(key(name)) {
    Some(value) => value
    None => abort("missing test token: " + name)
  }
}

///|
fn focus(
  runtime : @runtime.Runtime,
  target : @runtime.InstanceToken,
) -> @runtime.FocusRequest {
  match runtime.request_focus(target) {
    Ok(request) => request
    Err(_) => abort("test focus request failed")
  }
}

///|
test "duplicate and empty keys reject whole commit without mutation" {
  let runtime = @runtime.Runtime::new()
  let original = tree([button("save")])
  assert_eq(runtime.commit(original), Ok(()))
  let saved = token(runtime, "save")
  assert_true(runtime.enqueue_activate(saved))
  let request = focus(runtime, saved)
  let duplicate = tree([
    @core.text(key("save"), "would replace button"),
    @core.row(key("nested"), [button("save")]),
  ])
  assert_eq(runtime.commit(duplicate), Err(@runtime.DuplicateKey(key("save"))))
  assert_eq(runtime.view(), Some(original))
  assert_true(runtime.is_current(saved))
  assert_true(token(runtime, "save") == saved)
  assert_eq(runtime.commit(tree([button("")])), Err(@runtime.EmptyKey))
  assert_eq(runtime.view(), Some(original))
  assert_true(runtime.complete_focus(request, @core.Focused))
  assert_eq(runtime.next_action(), Some(@core.Activate(key("save"))))
  let result = runtime.next_focus_result().unwrap()
  assert_eq(result.key(), key("save"))
  assert_eq(result.outcome(), @core.Focused)
}

///|
test "keys are root-wide including the root and containers" {
  let runtime = @runtime.Runtime::new()
  assert_eq(
    runtime.commit(tree([button("root")])),
    Err(@runtime.DuplicateKey(key("root"))),
  )
  assert_eq(runtime.view(), None)
  assert_eq(runtime.commit(@core.text(key(""), "bad")), Err(@runtime.EmptyKey))
  assert_eq(runtime.view(), None)
}

///|
test "same key kind preserves token through label edits reorder and reparent" {
  let runtime = @runtime.Runtime::new()
  assert_eq(runtime.commit(tree([button("a"), button("b")])), Ok(()))
  let a = token(runtime, "a")
  let b = token(runtime, "b")
  assert_true(runtime.enqueue_activate(a))
  assert_eq(
    runtime.commit(
      tree([
        button("b"),
        @core.row(key("group"), [@core.button(key("a"), "New label")]),
      ]),
    ),
    Ok(()),
  )
  assert_true(token(runtime, "a") == a)
  assert_true(token(runtime, "b") == b)
  assert_eq(runtime.next_action(), Some(@core.Activate(key("a"))))
}

///|
test "type changes and remove reinsert never revive an old mount" {
  let runtime = @runtime.Runtime::new()
  assert_eq(runtime.commit(tree([button("a")])), Ok(()))
  let original = token(runtime, "a")
  assert_true(runtime.enqueue_activate(original))
  assert_eq(runtime.commit(tree([@core.text(key("a"), "replacement")])), Ok(()))
  let replacement = token(runtime, "a")
  assert_true(replacement != original)
  assert_true(!runtime.is_current(original))
  assert_true(!runtime.enqueue_activate(original))
  assert_eq(runtime.next_action(), None)
  assert_eq(runtime.commit(tree([button("a")])), Ok(()))
  let remounted = token(runtime, "a")
  assert_true(remounted != original && remounted != replacement)
  assert_eq(runtime.commit(tree([])), Ok(()))
  assert_true(!runtime.is_current(remounted))
  assert_eq(runtime.commit(tree([button("a")])), Ok(()))
  assert_true(token(runtime, "a") != remounted)
}

///|
test "opaque root ownership rejects same-key tokens from another root" {
  let first = @runtime.Runtime::new()
  let second = @runtime.Runtime::new()
  assert_eq(first.commit(tree([button("a")])), Ok(()))
  assert_eq(second.commit(tree([button("a")])), Ok(()))
  let a = token(first, "a")
  let b = token(second, "a")
  assert_true(a != b)
  assert_true(!second.is_current(a))
  assert_true(!second.enqueue_activate(a))
  assert_true(second.request_focus(a) is Err(@runtime.StaleToken))
  let request = focus(first, a)
  assert_true(!second.complete_focus(request, @core.Focused))
  assert_true(first.complete_focus(request, @core.Focused))
  assert_eq(second.next_action(), None)
  assert_true(second.next_focus_result() is None)
}

///|
test "activation gate is per button and rejects non-buttons" {
  let runtime = @runtime.Runtime::new()
  assert_eq(
    runtime.commit(
      tree([
        button("disabled", disabled=true),
        button("loading", loading=true),
        button("active"),
        @core.text(key("caption"), "Text"),
      ]),
    ),
    Ok(()),
  )
  assert_true(!runtime.enqueue_activate(token(runtime, "disabled")))
  assert_true(!runtime.enqueue_activate(token(runtime, "loading")))
  assert_true(!runtime.enqueue_activate(token(runtime, "caption")))
  assert_true(!runtime.enqueue_activate(token(runtime, "root")))
  assert_true(runtime.enqueue_activate(token(runtime, "active")))
  assert_eq(runtime.next_action(), Some(@core.Activate(key("active"))))
  assert_eq(runtime.next_action(), None)
}

///|
test "queued actions are FIFO and checked between model-owned commits" {
  let runtime = @runtime.Runtime::new()
  assert_eq(runtime.commit(tree([button("a"), button("b")])), Ok(()))
  let a = token(runtime, "a")
  let b = token(runtime, "b")
  assert_true(runtime.enqueue_activate(b))
  assert_true(runtime.enqueue_activate(a))
  assert_true(runtime.enqueue_activate(a))
  assert_eq(runtime.next_action(), Some(@core.Activate(key("b"))))
  assert_eq(runtime.next_action(), Some(@core.Activate(key("a"))))
  // The single model owner starts work and commits loading before next drain.
  assert_eq(
    runtime.commit(tree([button("a", loading=true), button("b")])),
    Ok(()),
  )
  assert_true(token(runtime, "a") == a)
  assert_eq(runtime.next_action(), None)
  assert_true(runtime.enqueue_activate(b))
  assert_eq(runtime.next_action(), Some(@core.Activate(key("b"))))
}

///|
test "pending action cannot revive after disabled or loading toggles" {
  let runtime = @runtime.Runtime::new()
  assert_eq(runtime.commit(tree([button("a")])), Ok(()))
  let a = token(runtime, "a")
  assert_true(runtime.enqueue_activate(a))
  assert_eq(runtime.commit(tree([button("a", disabled=true)])), Ok(()))
  assert_eq(runtime.commit(tree([button("a")])), Ok(()))
  assert_true(token(runtime, "a") == a)
  assert_eq(runtime.next_action(), None)
  assert_true(runtime.enqueue_activate(a))
  assert_eq(runtime.commit(tree([button("a", loading=true)])), Ok(()))
  assert_eq(runtime.commit(tree([button("a")])), Ok(()))
  assert_eq(runtime.next_action(), None)
  assert_true(runtime.enqueue_activate(a))
  assert_eq(runtime.next_action(), Some(@core.Activate(key("a"))))
}

///|
test "focus request is not a result and completion is single-use typed outcome" {
  let runtime = @runtime.Runtime::new()
  assert_eq(runtime.commit(tree([button("a")])), Ok(()))
  let a = token(runtime, "a")
  let request = focus(runtime, a)
  assert_true(request.target() == a)
  assert_true(runtime.next_focus_result() is None)
  assert_true(runtime.complete_focus(request, @core.Unsupported))
  assert_true(!runtime.complete_focus(request, @core.Focused))
  let result = runtime.next_focus_result().unwrap()
  assert_eq(result.key(), key("a"))
  assert_eq(result.outcome(), @core.Unsupported)
  assert_eq(runtime.next_action(), None)
  let rejected = focus(runtime, a)
  assert_true(runtime.complete_focus(rejected, @core.Rejected))
  assert_eq(runtime.next_focus_result().unwrap().outcome(), @core.Rejected)
}

///|
test "new focus request supersedes pending request and undelivered observation" {
  let runtime = @runtime.Runtime::new()
  assert_eq(runtime.commit(tree([button("a"), button("b")])), Ok(()))
  let old = focus(runtime, token(runtime, "a"))
  let current = focus(runtime, token(runtime, "b"))
  assert_true(!runtime.complete_focus(old, @core.Focused))
  assert_true(runtime.complete_focus(current, @core.Focused))
  let newest = focus(runtime, token(runtime, "a"))
  assert_true(runtime.next_focus_result() is None)
  assert_true(runtime.complete_focus(newest, @core.Focused))
  assert_eq(runtime.next_focus_result().unwrap().key(), key("a"))
}

///|
test "focus validates kind availability mount and queued result freshness" {
  let runtime = @runtime.Runtime::new()
  assert_eq(
    runtime.commit(tree([button("a"), @core.text(key("caption"), "Text")])),
    Ok(()),
  )
  let a = token(runtime, "a")
  assert_true(
    runtime.request_focus(token(runtime, "caption"))
    is Err(@runtime.NotFocusable),
  )
  let removed = focus(runtime, a)
  assert_eq(runtime.commit(tree([])), Ok(()))
  assert_true(!runtime.complete_focus(removed, @core.Focused))
  assert_eq(runtime.commit(tree([button("a", loading=true)])), Ok(()))
  assert_true(
    runtime.request_focus(token(runtime, "a")) is Err(@runtime.Unavailable),
  )
  assert_eq(runtime.commit(tree([button("a")])), Ok(()))
  let enabled = token(runtime, "a")
  let obsolete = focus(runtime, enabled)
  assert_eq(runtime.commit(tree([button("a", disabled=true)])), Ok(()))
  assert_eq(runtime.commit(tree([button("a")])), Ok(()))
  assert_true(!runtime.complete_focus(obsolete, @core.Focused))
  let complete = focus(runtime, enabled)
  assert_true(runtime.complete_focus(complete, @core.Focused))
  assert_eq(runtime.commit(tree([])), Ok(()))
  assert_true(runtime.next_focus_result() is None)
}

///|
test "dispose is idempotent and clears queues and rejects later callbacks" {
  let runtime = @runtime.Runtime::new()
  assert_eq(runtime.commit(tree([button("a")])), Ok(()))
  let a = token(runtime, "a")
  assert_true(runtime.enqueue_activate(a))
  let request = focus(runtime, a)
  runtime.dispose()
  runtime.dispose()
  assert_true(runtime.is_disposed())
  assert_eq(runtime.view(), None)
  assert_true(runtime.token(key("a")) is None)
  assert_true(!runtime.is_current(a))
  assert_true(!runtime.enqueue_activate(a))
  assert_true(!runtime.complete_focus(request, @core.Focused))
  assert_true(runtime.request_focus(a) is Err(@runtime.RequestError::Disposed))
  assert_eq(runtime.commit(tree([])), Err(@runtime.CommitError::Disposed))
  assert_eq(runtime.next_action(), None)
  assert_true(runtime.next_focus_result() is None)
  let newer = @runtime.Runtime::new()
  assert_eq(newer.commit(tree([button("a")])), Ok(()))
  assert_true(!newer.is_current(a))
  assert_true(!newer.enqueue_activate(a))
}

///|
test "token identity is symmetric stable and independent of identical roots or disposal" {
  let first = @runtime.Runtime::new()
  let second = @runtime.Runtime::new()
  let view = tree([button("a")])
  assert_eq(first.commit(view), Ok(()))
  assert_eq(second.commit(view), Ok(()))
  let a = token(first, "a")
  let copied = a
  let b = token(second, "a")
  assert_eq(a.key(), b.key())
  assert_eq(first.view(), second.view())
  for _ in 0..<3 {
    assert_true(a == a && a == copied && copied == a)
    assert_true(a != b && b != a)
    assert_true(first.is_current(copied) && second.is_current(b))
    assert_true(!first.is_current(b) && !second.is_current(a))
    assert_true(!first.enqueue_activate(b) && !second.enqueue_activate(a))
  }
  let first_request = focus(first, copied)
  let copied_request = first_request
  let second_request = focus(second, b)
  assert_true(!second.complete_focus(first_request, @core.Focused))
  assert_true(!first.complete_focus(second_request, @core.Focused))
  assert_true(first.complete_focus(copied_request, @core.Focused))
  assert_true(!first.complete_focus(first_request, @core.Focused))
  assert_true(second.complete_focus(second_request, @core.Focused))
  assert_eq(first.next_focus_result().unwrap().outcome(), @core.Focused)
  assert_eq(second.next_focus_result().unwrap().outcome(), @core.Focused)
  first.dispose()
  for _ in 0..<3 {
    assert_true(a == copied && copied == a)
    assert_true(a != b && b != a)
    assert_true(!first.is_current(copied))
    assert_true(second.is_current(b))
    assert_true(!second.enqueue_activate(copied))
  }
  second.dispose()
  assert_true(a == copied && copied == a)
  assert_true(a != b && b != a)
}

///|
test "Button flags share activation gate while loading retains no new common focus admission" {
  let runtime = @runtime.Runtime::new()
  assert_eq(runtime.commit(tree([button("save")])), Ok(()))
  let saved = token(runtime, "save")
  for flags in [(true, false), (false, true), (true, true)] {
    assert_true(runtime.enqueue_activate(saved))
    assert_eq(
      runtime.commit(tree([button("save", disabled=flags.0, loading=flags.1)])),
      Ok(()),
    )
    assert_true(runtime.is_current(saved))
    assert_true(!runtime.enqueue_activate(saved))
    assert_true(runtime.request_focus(saved) is Err(@runtime.Unavailable))
    assert_eq(runtime.commit(tree([button("save")])), Ok(()))
    assert_true(runtime.next_action() is None)
    assert_true(runtime.request_focus(saved) is Ok(_))
  }
  runtime.dispose()
}

///|
test "spacing changes preserve tokens queued actions and eligible focus" {
  let runtime = @runtime.Runtime::new()
  let key = @core.NodeKey::new("spacing-root")
  let button = @core.NodeKey::new("spacing-button")
  let children = [@core.button(button, "Press")]
  ignore(runtime.commit(@core.column(key, children)).unwrap())
  let original = runtime.token(button).unwrap()
  let root = runtime.token(key).unwrap()
  assert_true(runtime.enqueue_activate(original))
  ignore(
    runtime
    .commit(
      @core.column_with_spacing(
        key,
        children,
        @core.StackSpacing::new(@core.Zero, @core.Sixteen),
      ),
    )
    .unwrap(),
  )
  assert_true(runtime.is_current(original))
  assert_true(runtime.is_current(root))
  assert_eq(runtime.next_action(), Some(@core.Activate(button)))
  assert_true(runtime.request_focus(original) is Ok(_))
  ignore(
    runtime
    .commit(
      @core.column_with_spacing(
        key,
        children,
        @core.StackSpacing::new(@core.Twelve, @core.Four),
      ),
    )
    .unwrap(),
  )
  assert_true(runtime.is_current(original))
  assert_true(runtime.is_current(root))
  ignore(runtime.commit(@core.card(key, children)).unwrap())
  assert_true(runtime.is_current(root))
  assert_true(runtime.is_current(original))
}
