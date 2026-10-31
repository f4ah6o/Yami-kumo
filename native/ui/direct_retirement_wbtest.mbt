///|
fn direct_retirement_measure(
  value : String,
  size : Double,
) -> Result[@text_layout.TextMeasurement, @diagnostics.FrameworkError] {
  let document = @text.TextDocument::new(value).unwrap()
  let bounds = @primitives.Rect::new(
    0.0,
    0.0,
    (value.length() + 1).to_double() * size,
    size,
  ).unwrap()
  let carets = []
  let mut offset = 0
  let first = @primitives.Rect::new(0.0, 0.0, 1.0, size).unwrap()
  carets.push(@text_layout.CaretGeometry::new(0, true, first, first).unwrap())
  for scalar in value.iter() {
    offset += if scalar.to_int() > 0xFFFF { 2 } else { 1 }
    let caret = @primitives.Rect::new(offset.to_double() * size, 0.0, 1.0, size).unwrap()
    carets.push(
      @text_layout.CaretGeometry::new(offset, true, caret, caret).unwrap(),
    )
  }
  Ok(
    @text_layout.TextMeasurement::new(
      document,
      bounds,
      bounds,
      size * 0.8,
      1,
      0,
      carets,
    ).unwrap(),
  )
}

///|
fn direct_retirement_fixture() -> (Mounted, TerminalTextOwner) raise {
  let mounted = Mounted::new(@platform.WindowId::new(1L))
  let field = @view.NodeKey::new("name")
  let view = @view.column(@view.NodeKey::new("root"), [
    @view.text_field(field, @view.TextFieldProps::new("", "Name")),
    @view.button(@view.NodeKey::new("save"), "Save"),
  ])
  ignore(
    mounted.commit(view, 640.0, 480.0, 1.0, direct_retirement_measure).unwrap(),
  )
  assert_true(mounted.focus(field))
  (mounted, mounted.capture_terminal_text_owner(7UL).unwrap())
}

///|
fn direct_retirement_insert(
  mounted : Mounted,
  owner : TerminalTextOwner,
  sequence : Int32,
  ordinal : Int64,
  value : String,
) -> OwnedDirectDelivery raise {
  let event = @platform.Event::new(
    @platform.WindowId::new(1L),
    sequence.to_int64(),
    1.0,
    @platform.Input(@primitives.TextInput(text=value)),
  )
  let delivery = mounted
    .reserve_owned_direct_text(owner, event, sequence, ordinal)
    .unwrap()
  assert_true(delivery.after_document() is None)
  assert_true(delivery.after_progress() is None)
  mounted.apply_owned_direct_text(delivery).unwrap()
  let expected = delivery.after_document().unwrap()
  match mounted.owned_direct_text_action(delivery).unwrap() {
    Some(@view.TextChanged(_, actual)) => assert_eq(actual, expected)
    _ => fail("the delivery must retain its exact model action")
  }
  mounted.mark_owned_direct_text_model_applied(delivery).unwrap()
  delivery
}

///|
test "direct receipt freezes its own progress while later edits advance the owner" {
  let (mounted, owner) = direct_retirement_fixture()
  let before = owner.observed_progress()
  let first = direct_retirement_insert(mounted, owner, 1, 1L, "ab")
  assert_eq(first.before_progress(), before)
  assert_eq(first.before_document(), "")
  assert_eq(first.after_document(), Some("ab"))
  assert_eq(first.after_progress(), Some(owner.observed_progress()))
  assert_eq(owner.direct_progress(), (1L, 1))
  let frozen = first.after_progress()
  let backspace = @platform.Event::new(
    @platform.WindowId::new(1L),
    2L,
    1.0,
    @platform.Input(
      @primitives.KeyPressed(
        key=@primitives.Backspace,
        repeat=false,
        modifiers=@primitives.Modifiers::none(),
      ),
    ),
  )
  let edit = mounted.reserve_owned_edit_key(owner, backspace, 2).unwrap()
  assert_eq(Some(edit.before_progress()), frozen)
  mounted.apply_owned_direct_text(edit).unwrap()
  assert_true(
    mounted.owned_direct_text_action(edit).unwrap()
    is Some(@view.TextChanged(_, "a")),
  )
  mounted.mark_owned_direct_text_model_applied(edit).unwrap()
  assert_eq(edit.after_document(), Some("a"))
  assert_eq(edit.after_progress(), Some(owner.observed_progress()))
  assert_eq(owner.direct_progress(), (1L, 2))
  assert_eq(first.after_progress(), frozen)
  assert_true(first.after_progress() != edit.after_progress())
  assert_true(first.matches_owner(owner))
  assert_true(edit.matches_owner(owner))
  let next = direct_retirement_insert(mounted, owner, 3, 2L, "c")
  assert_eq(next.before_document(), "a")
  assert_eq(next.after_document(), Some("ac"))
  assert_eq(owner.direct_progress(), (2L, 3))
  assert_eq(first.after_progress(), frozen)
  mounted.dispose()
}

///|
test "no-model editing receipt still records its completed progress" {
  let (mounted, owner) = direct_retirement_fixture()
  let arrow = @platform.Event::new(
    @platform.WindowId::new(1L),
    1L,
    1.0,
    @platform.Input(
      @primitives.KeyPressed(
        key=@primitives.ArrowLeft,
        repeat=false,
        modifiers=@primitives.Modifiers::none(),
      ),
    ),
  )
  let delivery = mounted.reserve_owned_edit_key(owner, arrow, 1).unwrap()
  mounted.apply_owned_direct_text(delivery).unwrap()
  assert_true(delivery.owner_noted())
  assert_eq(delivery.action_required(), Some(false))
  assert_eq(delivery.after_document(), Some(""))
  assert_eq(delivery.after_progress(), Some(owner.observed_progress()))
  assert_eq(owner.direct_progress(), (0L, 1))
  assert_true(delivery.pending_action() is None)
  assert_false(delivery.model_applied())
  mounted.dispose()
}

///|
test "matching numeric owner IDs cannot transfer a direct receipt to another mount" {
  let (mounted, owner) = direct_retirement_fixture()
  let delivery = direct_retirement_insert(mounted, owner, 1, 1L, "a")
  let (other, foreign) = direct_retirement_fixture()
  assert_true(delivery.matches_owner(owner))
  assert_false(delivery.matches_owner(foreign))
  assert_true(other.release_terminal_text_owner(owner) is Err(_))
  assert_true(other.terminal_owner_is_current(foreign))
  assert_true(mounted.terminal_owner_is_current(owner))
  mounted.dispose()
  assert_false(delivery.matches_owner(owner))
  other.dispose()
}

///|
test "released terminal owner cannot accept late input or be reused after reopening" {
  let (mounted, owner) = direct_retirement_fixture()
  let delivery = direct_retirement_insert(mounted, owner, 1, 1L, "a")
  let frozen = delivery.after_progress()
  mounted.release_terminal_text_owner(owner).unwrap()
  assert_false(
    owner.matches_session(@platform.WindowId::new(1L), 7UL, owner.binding),
  )
  assert_false(delivery.matches_owner(owner))
  assert_eq(delivery.after_progress(), frozen)
  assert_true(mounted.release_terminal_text_owner(owner) is Err(_))
  assert_true(mounted.capture_terminal_text_owner(7UL) is Err(_))
  assert_true(mounted.begin_held_text(7UL) is Err(_))
  let late = @text_host.TextInputEvent::new(
    @platform.WindowId::new(1L),
    1L,
    7UL,
    @text_host.Commit(text="late"),
  )
  assert_false(mounted.text_input(7UL, late).unwrap())
  assert_eq(mounted.focused_text().unwrap().document().text(), "a")
  let reopened = mounted.capture_terminal_text_owner(8UL).unwrap()
  assert_true(mounted.terminal_owner_is_current(reopened))
  assert_false(delivery.matches_owner(reopened))
  assert_true(mounted.release_terminal_text_owner(owner) is Err(_))
  assert_false(mounted.text_input(7UL, late).unwrap())
  assert_true(
    mounted.reserve_owned_direct_text(
      owner,
      @platform.Event::new(
        @platform.WindowId::new(1L),
        2L,
        1.0,
        @platform.Input(@primitives.TextInput(text="late")),
      ),
      2,
      2L,
    )
    is Err(_),
  )
  let current = direct_retirement_insert(mounted, reopened, 2, 1L, "b")
  assert_eq(current.after_document(), Some("ab"))
  mounted.release_terminal_text_owner(reopened).unwrap()
  mounted.dispose()
}

///|
test "queued action blocks owner release without discarding the action" {
  let (mounted, owner) = direct_retirement_fixture()
  let save = mounted.callback(@view.NodeKey::new("save")).unwrap()
  assert_true(mounted.activate(save))
  assert_true(mounted.release_terminal_text_owner(owner) is Err(_))
  assert_true(
    owner.matches_session(@platform.WindowId::new(1L), 7UL, owner.binding),
  )
  assert_true(mounted.next_action() is Some(@view.Activate(_)))
  mounted.release_terminal_text_owner(owner).unwrap()
  mounted.dispose()
}

///|
test "preedit and held text block owner release until their observed resolution" {
  let (mounted, owner) = direct_retirement_fixture()
  let preedit = @text_host.TextInputEvent::new(
    @platform.WindowId::new(1L),
    1L,
    7UL,
    @text_host.Preedit(text="に", cursor=1),
  )
  assert_true(mounted.text_input(7UL, preedit).unwrap())
  mounted.note_terminal_text_delivery(owner, preedit).unwrap()
  assert_true(mounted.release_terminal_text_owner(owner) is Err(_))
  assert_true(mounted.focused_text().unwrap().composing())
  let cancel = @text_host.TextInputEvent::new(
    @platform.WindowId::new(1L),
    2L,
    7UL,
    @text_host.Cancel,
  )
  assert_true(mounted.text_input(7UL, cancel).unwrap())
  mounted.note_terminal_text_delivery(owner, cancel).unwrap()
  assert_true(mounted.begin_held_text(7UL).unwrap())
  assert_true(mounted.release_terminal_text_owner(owner) is Err(_))
  assert_true(mounted.held_text is Some(_))
  mounted.finish_held_text(7UL).unwrap()
  mounted.release_terminal_text_owner(owner).unwrap()
  mounted.dispose()
}

///|
test "changed focus blocks release of the original owner" {
  let (mounted, owner) = direct_retirement_fixture()
  assert_true(mounted.focus(@view.NodeKey::new("save")))
  assert_true(mounted.release_terminal_text_owner(owner) is Err(_))
  assert_true(
    owner.matches_session(@platform.WindowId::new(1L), 7UL, owner.binding),
  )
  assert_true(mounted.capture_terminal_text_owner(8UL) is Err(_))
  mounted.dispose()
}
