///|
/// Stable identity for the Shared Settings root. Hosts and tests use these
/// functions instead of repeating literals so one rename cannot split the
/// application state from the host observation.

///|
pub fn settings_shell() -> @core.NodeKey {
  @core.NodeKey::new("settings-shell")
}

///|
pub fn settings_brand() -> @core.NodeKey {
  @core.NodeKey::new("settings-brand")
}

///|
pub fn settings_content() -> @core.NodeKey {
  @core.NodeKey::new("settings-content")
}

///|
pub fn settings_title() -> @core.NodeKey {
  @core.NodeKey::new("settings-title")
}

///|
pub fn settings_hint() -> @core.NodeKey {
  @core.NodeKey::new("settings-hint")
}

///|
pub fn settings_name() -> @core.NodeKey {
  @core.NodeKey::new("settings-name")
}

///|
pub fn settings_status() -> @core.NodeKey {
  @core.NodeKey::new("settings-status")
}

///|
pub fn settings_save() -> @core.NodeKey {
  @core.NodeKey::new("settings-save")
}

///|
pub fn settings_dialog() -> @core.NodeKey {
  @core.NodeKey::new("settings-dialog")
}

///|
pub fn settings_dialog_body() -> @core.NodeKey {
  @core.NodeKey::new("settings-dialog-body")
}

///|
pub fn settings_confirm() -> @core.NodeKey {
  @core.NodeKey::new("settings-confirm")
}

///|
pub fn settings_cancel() -> @core.NodeKey {
  @core.NodeKey::new("settings-cancel")
}

///|
/// Application-owned completion of the simulated save. Hosts deliver it from
/// their own tick (DOM timer or native frame); the model keeps the transition
/// so every platform observes the same states.
pub(all) enum Action {
  Ui(@core.SemanticAction)
  SaveFinished
} derive(Eq, @debug.Debug)

///|
pub extend Action with Eq::{equal, not_equal}

///|
pub extend Action with @debug.Debug::{to_repr}

///|
/// One immutable Settings model. The Web and native entries import this
/// package unchanged; hosts own neither a second name value nor a second
/// save state.
pub struct Model {
  priv name : String
  priv error : String?
  priv saving : Bool
  priv saved : Bool
  priv dialog_open : Bool
} derive(Eq, @debug.Debug)

///|
pub extend Model with Eq::{equal, not_equal}

///|
pub extend Model with @debug.Debug::{to_repr}

///|
pub fn Model::new() -> Model {
  { name: "", error: None, saving: false, saved: false, dialog_open: false, }
}

///|
pub fn Model::name(self : Model) -> String {
  self.name
}

///|
pub fn Model::error(self : Model) -> String? {
  self.error
}

///|
pub fn Model::saving(self : Model) -> Bool {
  self.saving
}

///|
pub fn Model::saved(self : Model) -> Bool {
  self.saved
}

///|
pub fn Model::dialog_open(self : Model) -> Bool {
  self.dialog_open
}

///|
fn Model::request_save(self : Model) -> Model {
  if self.saving || self.dialog_open {
    return self
  }
  if self.name.trim().is_empty() {
    { ..self, error: Some("Enter a name before saving."), }
  } else {
    { ..self, error: None, dialog_open: true, }
  }
}

///|
fn Model::cancel_dialog(self : Model) -> Model {
  if self.dialog_open && !self.saving {
    { ..self, dialog_open: false, }
  } else {
    self
  }
}

///|
fn Model::confirm_dialog(self : Model) -> Model {
  if self.dialog_open && !self.saving {
    { ..self, dialog_open: false, saving: true, saved: false, }
  } else {
    self
  }
}

///|
/// Apply one action. Every transition is a pure replacement, so replaying the
/// same action sequence produces the same model and view.
pub fn Model::update(self : Model, action : Action) -> Model {
  match action {
    Ui(@core.TextChanged(key, value)) =>
      if key == settings_name() && value != self.name {
        { ..self, name: value, error: None, }
      } else {
        self
      }
    Ui(@core.Submitted(key)) =>
      if key == settings_name() {
        self.request_save()
      } else {
        self
      }
    Ui(@core.Activate(key)) =>
      if key == settings_save() {
        self.request_save()
      } else if key == settings_confirm() {
        self.confirm_dialog()
      } else if key == settings_cancel() {
        self.cancel_dialog()
      } else {
        self
      }
    Ui(@core.Dismissed(key)) =>
      if key == settings_dialog() {
        self.cancel_dialog()
      } else {
        self
      }
    Ui(@core.Confirmed(key)) =>
      if key == settings_dialog() {
        self.confirm_dialog()
      } else {
        self
      }
    SaveFinished =>
      if self.saving {
        { ..self, saving: false, saved: true, }
      } else {
        self
      }
  }
}

///|
fn Model::status_text(self : Model) -> String {
  if self.saving {
    "Saving..."
  } else if self.saved {
    "Saved"
  } else {
    "Not saved"
  }
}

///|
pub fn Model::view(self : Model) -> @core.View {
  let main = @core.column(settings_content(), [
    @core.text(settings_title(), "Settings"),
    @core.text(
      settings_hint(),
      "The name is shared by the Web and native hosts.",
    ),
    @core.text_field(
      settings_name(),
      @core.TextFieldProps::new(
        self.name,
        "Name",
        description="Shown on the saved profile.",
        error=self.error,
        required=true,
      ),
    ),
    @core.text(settings_status(), self.status_text()),
    @core.button(settings_save(), "Save", loading=self.saving),
    self.dialog_view(),
  ])
  @core.app_shell(settings_shell(), @core.text(settings_brand(), "Yami"), main)
}

///|
fn Model::dialog_view(self : Model) -> @core.View {
  @core.dialog(
    settings_dialog(),
    @core.DialogProps::new(
      self.dialog_open,
      "Save changes?",
      initial_focus=Some(settings_confirm()),
    ),
    [
      @core.text(settings_dialog_body(), "Save this name?"),
      @core.button(settings_confirm(), "Save"),
      @core.button(settings_cancel(), "Cancel"),
    ],
  )
}
