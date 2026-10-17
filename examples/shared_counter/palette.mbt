///|
/// One application owner: the unchanged spacing demo contains the only counter.
pub struct PaletteModel {
  priv spacing : SpacingModel
  priv palette : @core.ButtonPaletteToken?
} derive(Eq, @debug.Debug)

///|
pub fn PaletteModel::new() -> PaletteModel {
  { spacing: SpacingModel::new(), palette: None, }
}

///|
pub fn PaletteModel::palette(self : PaletteModel) -> @core.ButtonPaletteToken? {
  self.palette
}

///|
pub fn PaletteModel::counter(self : PaletteModel) -> Model {
  self.spacing.counter()
}

///|
pub fn PaletteModel::value(self : PaletteModel) -> Int {
  self.spacing.value()
}

///|
pub fn PaletteModel::expanded(self : PaletteModel) -> Bool {
  self.spacing.expanded()
}

///|
pub fn PaletteModel::view(self : PaletteModel) -> @core.View {
  self.spacing.view()
}

///|
pub fn PaletteModel::update(
  self : PaletteModel,
  action : @core.SemanticAction,
) -> PaletteModel {
  { ..self, spacing: self.spacing.update(action), }
}

///|
pub fn PaletteModel::update_counter(
  self : PaletteModel,
  action : @core.SemanticAction,
) -> PaletteModel {
  { ..self, spacing: self.spacing.update_counter(action), }
}

///|
pub fn PaletteModel::update_palette(
  self : PaletteModel,
  action : @core.SemanticAction,
) -> PaletteModel {
  match action {
    @core.Activate(key) if key == @core.NodeKey::new("palette-toggle") => {
      let palette = match self.palette {
        None => Some(@core.Light)
        Some(Light) => Some(@core.Dark)
        Some(Dark) => None
      }
      { ..self, palette, }
    }
    _ => self.update_counter(action)
  }
}

///|
pub fn PaletteModel::palette_view(self : PaletteModel) -> @core.View {
  fn painted(key : String, label : String) -> @core.View {
    match self.palette {
      None => @core.button(@core.NodeKey::new(key), label)
      Some(token) =>
        @core.button_with_palette(@core.NodeKey::new(key), label, token)
    }
  }
  @core.column(@core.NodeKey::new("counter"), [
    @core.text(@core.NodeKey::new("heading"), "Shared palette"),
    @core.text(@core.NodeKey::new("value"), "Count: \{self.value()}"),
    @core.row(@core.NodeKey::new("actions"), [
      painted("increment", "Increment"),
      painted("palette-toggle", "Palette"),
    ]),
  ])
}

///|
pub extend PaletteModel with Eq::{equal, not_equal}

///|
pub extend PaletteModel with @debug.Debug::{to_repr}
