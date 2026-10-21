///|
fn find(view : @core.View, key : @core.NodeKey) -> @core.View? {
  if view.key() == key {
    return Some(view)
  }
  for child in view.children() {
    match find(child, key) {
      Some(found) => return Some(found)
      None => ()
    }
  }
  None
}

///|
fn shown(view : @core.View, key : @core.NodeKey) -> @core.View raise {
  match find(view, key) {
    Some(found) => found
    None => fail("missing view node: \{key.value()}")
  }
}

///|
fn field_error(model : @shared_settings.Model) -> String? raise {
  shown(model.view(), @shared_settings.settings_name())
  .text_field_props()
  .unwrap()
  .error()
}

///|
test "new settings model owns the empty draft without an error" {
  let model = @shared_settings.Model::new()
  assert_eq(model.name(), "")
  assert_eq(model.error(), None)
  assert_true(!model.saving())
  assert_true(!model.saved())
  assert_true(!model.dialog_open())
  let view = model.view()
  assert_true(find(view, @shared_settings.settings_shell()) is Some(_))
  assert_eq(shown(view, @shared_settings.settings_title()).label(), "Settings")
  let field = shown(view, @shared_settings.settings_name())
  let props = field.text_field_props().unwrap()
  assert_eq(props.value(), "")
  assert_eq(props.label(), "Name")
  assert_true(props.required())
  assert_eq(props.error(), None)
  let save = shown(view, @shared_settings.settings_save())
  assert_eq(save.label(), "Save")
  assert_true(!save.disabled())
  assert_true(!save.loading())
  assert_eq(
    shown(view, @shared_settings.settings_status()).label(),
    "Not saved",
  )
  assert_true(
    !shown(view, @shared_settings.settings_dialog())
    .dialog_props()
    .unwrap()
    .open(),
  )
}

///|
test "an empty or whitespace name cannot open the confirmation dialog" {
  let empty = @shared_settings.Model::new().update(
    @shared_settings.Ui(@core.Activate(@shared_settings.settings_save())),
  )
  assert_eq(empty.error(), Some("Enter a name before saving."))
  assert_true(!empty.dialog_open())
  assert_eq(field_error(empty), Some("Enter a name before saving."))
  let blank = empty.update(
    @shared_settings.Ui(
      @core.TextChanged(@shared_settings.settings_name(), "   "),
    ),
  )
  let blocked = blank.update(
    @shared_settings.Ui(@core.Activate(@shared_settings.settings_save())),
  )
  assert_eq(blocked.error(), Some("Enter a name before saving."))
  assert_true(!blocked.dialog_open())
}

///|
test "editing clears the error and a named draft opens the dialog" {
  let failed = @shared_settings.Model::new().update(
    @shared_settings.Ui(@core.Activate(@shared_settings.settings_save())),
  )
  let edited = failed.update(
    @shared_settings.Ui(
      @core.TextChanged(@shared_settings.settings_name(), "闇雲"),
    ),
  )
  assert_eq(edited.error(), None)
  let opened = edited.update(
    @shared_settings.Ui(@core.Activate(@shared_settings.settings_save())),
  )
  assert_eq(opened.name(), "闇雲")
  assert_true(opened.dialog_open())
  let dialog = shown(opened.view(), @shared_settings.settings_dialog())
  let props = dialog.dialog_props().unwrap()
  assert_true(props.open())
  assert_eq(props.title(), "Save changes?")
  assert_eq(props.initial_focus(), Some(@shared_settings.settings_confirm()))
}

///|
test "submitting the field follows the same validation path" {
  let blocked = @shared_settings.Model::new().update(
    @shared_settings.Ui(@core.Submitted(@shared_settings.settings_name())),
  )
  assert_eq(blocked.error(), Some("Enter a name before saving."))
  let opened = blocked
    .update(
      @shared_settings.Ui(
        @core.TextChanged(@shared_settings.settings_name(), "Name"),
      ),
    )
    .update(
      @shared_settings.Ui(@core.Submitted(@shared_settings.settings_name())),
    )
  assert_true(opened.dialog_open())
}

///|
test "cancelling or dismissing the dialog keeps the draft and the phase" {
  let opened = @shared_settings.Model::new()
    .update(
      @shared_settings.Ui(
        @core.TextChanged(@shared_settings.settings_name(), "Kumo"),
      ),
    )
    .update(
      @shared_settings.Ui(@core.Activate(@shared_settings.settings_save())),
    )
  let cancelled = opened.update(
    @shared_settings.Ui(@core.Activate(@shared_settings.settings_cancel())),
  )
  assert_true(!cancelled.dialog_open())
  assert_eq(cancelled.name(), "Kumo")
  assert_true(!cancelled.saving())
  assert_true(!cancelled.saved())
  let dismissed = opened.update(
    @shared_settings.Ui(@core.Dismissed(@shared_settings.settings_dialog())),
  )
  assert_true(!dismissed.dialog_open())
  assert_eq(dismissed.name(), "Kumo")
  assert_eq(dismissed, cancelled)
}

///|
test "confirming starts the save once and completion is idempotent" {
  let opened = @shared_settings.Model::new()
    .update(
      @shared_settings.Ui(
        @core.TextChanged(@shared_settings.settings_name(), "Kumo"),
      ),
    )
    .update(
      @shared_settings.Ui(@core.Activate(@shared_settings.settings_save())),
    )
  let saving = opened.update(
    @shared_settings.Ui(@core.Confirmed(@shared_settings.settings_dialog())),
  )
  assert_true(!saving.dialog_open())
  assert_true(saving.saving())
  assert_true(!saving.saved())
  assert_eq(
    shown(saving.view(), @shared_settings.settings_status()).label(),
    "Saving...",
  )
  let button = shown(saving.view(), @shared_settings.settings_save())
  assert_true(button.loading())
  assert_true(!button.disabled())
  let duplicate = saving.update(
    @shared_settings.Ui(@core.Activate(@shared_settings.settings_confirm())),
  )
  assert_eq(duplicate, saving)
  let reopened = saving.update(
    @shared_settings.Ui(@core.Activate(@shared_settings.settings_save())),
  )
  assert_eq(reopened, saving)
  let done = saving.update(@shared_settings.SaveFinished)
  assert_true(!done.saving())
  assert_true(done.saved())
  assert_eq(
    shown(done.view(), @shared_settings.settings_status()).label(),
    "Saved",
  )
  assert_eq(done.update(@shared_settings.SaveFinished), done)
  assert_eq(
    done.update(
      @shared_settings.Ui(@core.Dismissed(@shared_settings.settings_dialog())),
    ),
    done,
  )
}

///|
test "a stale confirm after cancel does not start a save" {
  let opened = @shared_settings.Model::new()
    .update(
      @shared_settings.Ui(
        @core.TextChanged(@shared_settings.settings_name(), "Kumo"),
      ),
    )
    .update(
      @shared_settings.Ui(@core.Activate(@shared_settings.settings_save())),
    )
  let cancelled = opened.update(
    @shared_settings.Ui(@core.Activate(@shared_settings.settings_cancel())),
  )
  let stale = cancelled.update(
    @shared_settings.Ui(@core.Confirmed(@shared_settings.settings_dialog())),
  )
  assert_eq(stale, cancelled)
  assert_true(!stale.saving())
}

///|
test "unrelated actions leave the model unchanged" {
  let model = @shared_settings.Model::new().update(
    @shared_settings.Ui(
      @core.TextChanged(@shared_settings.settings_name(), "Kumo"),
    ),
  )
  assert_eq(
    model.update(
      @shared_settings.Ui(@core.Activate(@core.NodeKey::new("unknown"))),
    ),
    model,
  )
  assert_eq(
    model.update(
      @shared_settings.Ui(@core.TextChanged(@core.NodeKey::new("other"), "x")),
    ),
    model,
  )
  assert_eq(
    model.update(
      @shared_settings.Ui(
        @core.TextChanged(@shared_settings.settings_name(), "Kumo"),
      ),
    ),
    model,
  )
  assert_eq(model.update(@shared_settings.SaveFinished), model)
}

///|
test "two settings roots keep independent state" {
  let first = @shared_settings.Model::new()
    .update(
      @shared_settings.Ui(
        @core.TextChanged(@shared_settings.settings_name(), "First"),
      ),
    )
    .update(@shared_settings.SaveFinished)
  let second = @shared_settings.Model::new().update(
    @shared_settings.Ui(
      @core.TextChanged(@shared_settings.settings_name(), "Second"),
    ),
  )
  assert_eq(first.name(), "First")
  assert_eq(second.name(), "Second")
  assert_true(!first.saved())
  assert_true(!second.saved())
  assert_true(first != second)
}

///|
test "the same action sequence rebuilds an equal model and view" {
  let actions = [
    @shared_settings.Ui(
      @core.TextChanged(@shared_settings.settings_name(), "闇雲"),
    ),
    @shared_settings.Ui(@core.Activate(@shared_settings.settings_save())),
    @shared_settings.Ui(@core.Confirmed(@shared_settings.settings_dialog())),
    @shared_settings.SaveFinished,
  ]
  let run = fn() {
    actions.fold(init=@shared_settings.Model::new(), (model, action) => {
      model.update(action)
    })
  }
  let left = run()
  let right = run()
  assert_eq(left, right)
  assert_eq(left.view(), right.view())
}
