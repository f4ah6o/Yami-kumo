///|
pub(all) enum Mode {
  Normal
  Disabled
  Loading
  DisabledLoading
} derive(Eq, @debug.Debug)

///|
pub fn Mode::name(self : Mode) -> String {
  match self {
    Normal => "normal"
    Disabled => "disabled"
    Loading => "loading"
    DisabledLoading => "disabled-loading"
  }
}

///|
pub struct Model {
  priv theme : @theme.Theme
  priv mode : Mode
  priv value : Int
} derive(Eq, @debug.Debug)

///|
pub fn Model::new() -> Model {
  { theme: @theme.Light, mode: Normal, value: 0, }
}

///|
pub fn Model::theme(self : Model) -> @theme.Theme {
  self.theme
}

///|
pub fn Model::mode(self : Model) -> Mode {
  self.mode
}

///|
pub fn Model::value(self : Model) -> Int {
  self.value
}

///|
pub fn Model::with_theme(self : Model, theme : @theme.Theme) -> Model {
  { ..self, theme, }
}

///|
pub fn Model::with_mode(self : Model, mode : Mode) -> Model {
  { ..self, mode, }
}

///|
pub fn Model::update(self : Model, action : @core.SemanticAction) -> Model {
  match action {
    @core.Activate(key) if key == @core.NodeKey::new("increment") =>
      { ..self, value: self.value + 1, }
    @core.Activate(key) if key == @core.NodeKey::new("theme-toggle") =>
      self.with_theme(match self.theme {
        @theme.Light => @theme.Dark
        @theme.Dark => @theme.Light
      })
    _ => self
  }
}

///|
pub fn Model::view(self : Model) -> @core.View {
  @core.column(@core.NodeKey::new("theme-counter"), [
    @core.text(@core.NodeKey::new("heading"), "Shared Button theme"),
    @core.text(@core.NodeKey::new("value"), "Count: \{self.value}"),
    @core.button(
      @core.NodeKey::new("increment"),
      "Increment",
      disabled=self.mode == Disabled || self.mode == DisabledLoading,
      loading=self.mode == Loading || self.mode == DisabledLoading,
    ),
    @core.button(@core.NodeKey::new("theme-toggle"), "Toggle theme"),
  ])
}

///|
pub extend Mode with Eq::{equal, not_equal}

///|
pub extend Mode with @debug.Debug::{to_repr}

///|
pub extend Model with Eq::{equal, not_equal}

///|
pub extend Model with @debug.Debug::{to_repr}
