///|
test "Settings focused save activates and renders confirmation in portable dispatch" {
  let (owner, _) = publication_fixture()
  owner.replace_settings(owner.settings.update(@shared_settings.Ui(@view.TextChanged(@shared_settings.settings_name(), "abc"))))
  ignore(owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, text_runner_measure).unwrap())
  assert_true(owner.mounted.focus(@shared_settings.settings_save()))
  let enter = @platform.Event::new(owner.window, 10L, 1.0,
    @platform.Input(@primitives.KeyPressed(key=@primitives.Enter, repeat=false, modifiers=@primitives.Modifiers::none())))
  assert_true(owner.mounted.handle_event(enter).unwrap())
  let action = owner.mounted.next_action().unwrap()
  assert_true(action is @view.Activate(key) && key == @shared_settings.settings_save())
  owner.replace_settings(owner.settings.update(@shared_settings.Ui(action)))
  assert_true(owner.model().dialog_open())
  let frame = owner.mounted.commit(owner.settings.view(), 640.0, 480.0, 1.0, text_runner_measure).unwrap()
  assert_true(frame.focused(@shared_settings.settings_confirm()))
}
