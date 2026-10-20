///|
/// Stable identities for the native TextField proof sample.
pub fn text_sample_root() -> @view.NodeKey {
  @view.NodeKey::new("text-root")
}

///|
pub fn text_sample_field() -> @view.NodeKey {
  @view.NodeKey::new("text-name")
}

///|
pub fn text_sample_submit() -> @view.NodeKey {
  @view.NodeKey::new("text-submit")
}

///|
pub fn text_sample_status() -> @view.NodeKey {
  @view.NodeKey::new("text-status")
}

///|
/// A single controlled TextField plus a Submit Button. The application owns the
/// committed value; the host owns editing, selection and composition. This is a
/// proof fixture for the portable text-input transport, not a general form.
pub struct TextSample {
  priv mut value : String
  priv mut submitted : String?
}

///|
pub fn TextSample::new() -> TextSample {
  { value: "", submitted: None, }
}

///|
pub fn TextSample::value(self : TextSample) -> String {
  self.value
}

///|
pub fn TextSample::submitted(self : TextSample) -> String? {
  self.submitted
}

///|
fn TextSample::status_text(self : TextSample) -> String {
  match self.submitted {
    Some(value) => "Submitted: " + value
    None => "No submission"
  }
}

///|
pub fn TextSample::view(self : TextSample) -> @view.View {
  @view.column(text_sample_root(), [
    @view.text(text_sample_status(), self.status_text()),
    @view.text_field(
      text_sample_field(),
      @view.TextFieldProps::new(self.value, "Name"),
    ),
    @view.button(text_sample_submit(), "Submit"),
  ])
}

///|
/// Apply one accepted semantic action. Returns true when the sample changed and
/// the caller must regenerate the view.
pub fn TextSample::apply(
  self : TextSample,
  action : @view.SemanticAction,
) -> Bool {
  match action {
    @view.TextChanged(key, text) =>
      if key == text_sample_field() && self.value != text {
        self.value = text
        true
      } else {
        false
      }
    @view.Submitted(key) =>
      if key == text_sample_field() {
        self.submitted = Some(self.value)
        true
      } else {
        false
      }
    @view.Activate(key) =>
      if key == text_sample_submit() {
        self.submitted = Some(self.value)
        true
      } else {
        false
      }
    @view.Dismissed(_) | @view.Confirmed(_) => false
  }
}
