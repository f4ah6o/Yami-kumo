///|
test "owned staged geometry remeasures preview and rollback without publication" {
  let (owner, original_frame) = publication_fixture()
  let lease = owner.terminal_owner.unwrap()
  let preedit = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Preedit(text="にほん", cursor=3))
  owner.deliver_owned_observation(preedit).unwrap()
  let measured : Ref[Array[String]] = Ref([])
  let measure = fn(value, size) {
    measured.val.push(value)
    text_runner_measure(value, size * 1.1)
  }
  let prepared = owner.mounted.stage_owned_text_geometry(lease, owner.settings.view(), 640.0, 480.0, 1.5, measure).unwrap()
  let geometry = match owner.mounted.inspect_staged_text_geometry(lease, prepared) {
    Ok(value) => value
    Err(error) => abort(format_framework_error(error))
  }
  assert_true(geometry.composing())
  let (source_revision, candidate_revision) = geometry.revisions()
  assert_eq(candidate_revision, source_revision + 1)
  assert_eq(geometry.preview().text(), "にほん")
  assert_eq(geometry.committed().text(), "")
  assert_true(measured.val.contains("にほん"))
  assert_true(measured.val.contains(""))
  assert_true(geometry.scene_revision() > original_frame.revision())
  assert_eq(owner.mounted.frame().unwrap().revision(), original_frame.revision())
  assert_true(owner.mounted.focused_text().unwrap().composing())
  assert_true(owner.mounted.publish(prepared) is Err(_))
  assert_eq(owner.model().name(), "")
  assert_true(owner.mounted.terminal_owner_is_current(lease))
  let cancel = @text_host.TextInputEvent::new(owner.window, 2L, 7UL, @text_host.Cancel)
  owner.deliver_owned_observation(cancel).unwrap()
  assert_true(owner.mounted.inspect_staged_text_geometry(lease, prepared) is Err(_))
  assert_eq(owner.mounted.focused_text().unwrap().document().text(), "")
}

///|
test "owned staged rollback measurement failure preserves active preview" {
  let (owner, original_frame) = publication_fixture()
  let lease = owner.terminal_owner.unwrap()
  let preedit = @text_host.TextInputEvent::new(owner.window, 1L, 7UL, @text_host.Preedit(text="にほん", cursor=3))
  owner.deliver_owned_observation(preedit).unwrap()
  let seen = Ref(false)
  let measure = fn(value, size) {
    if value == "にほん" { seen.val = true }
    if seen.val && value == "" { Err(runner_error("fixture", "rollback measurement failed")) }
    else { text_runner_measure(value, size) }
  }
  assert_true(owner.mounted.stage_owned_text_geometry(lease, owner.settings.view(), 640.0, 480.0, 1.5, measure) is Err(_))
  assert_true(seen.val)
  assert_true(owner.mounted.focused_text().unwrap().composing())
  assert_true(owner.mounted.terminal_owner_is_current(lease))
  assert_eq(owner.mounted.frame().unwrap().revision(), original_frame.revision())
  assert_eq(owner.model().name(), "")
}

///|
test "owned staged geometry rejects a replacement view and reentrant focus" {
  let (owner, frame) = publication_fixture()
  let lease = owner.terminal_owner.unwrap()
  let changed = owner.settings.update(@shared_settings.Ui(@view.TextChanged(@shared_settings.settings_name(), "別")))
  assert_true(owner.mounted.stage_owned_text_geometry(lease, changed.view(), 640.0, 480.0, 1.5, text_runner_measure) is Err(_))
  assert_eq(owner.mounted.frame().unwrap().revision(), frame.revision())
  assert_true(owner.mounted.terminal_owner_is_current(lease))
  let attempted = Ref(false)
  let admitted = Ref(false)
  let measure = fn(value, size) {
    if !attempted.val {
      attempted.val = true
      admitted.val = owner.mounted.focus(@shared_settings.settings_save())
    }
    text_runner_measure(value, size)
  }
  let prepared = owner.mounted.stage_owned_text_geometry(lease, owner.settings.view(), 640.0, 480.0, 1.5, measure).unwrap()
  assert_true(attempted.val)
  assert_false(admitted.val)
  assert_true(owner.mounted.inspect_staged_text_geometry(lease, prepared) is Ok(_))
  assert_true(owner.mounted.publish(prepared) is Err(_))
  assert_true(owner.mounted.terminal_owner_is_current(lease))
}
