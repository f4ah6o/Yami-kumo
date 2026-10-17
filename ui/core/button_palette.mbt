///|
/// Explicit per-Button paint only. No inherited or system appearance.
pub(all) enum ButtonPaletteToken {
  Light
  Dark
} derive(Eq, @debug.Debug)

///|
pub(all) enum ButtonPaintRole {
  NormalBorder
  FocusedBorder
  DisabledBorder
  NormalFill
  HoveredFill
  PressedFill
  LoadingFill
  DisabledFill
  EnabledForeground
  DisabledForeground
} derive(Eq, @debug.Debug)

///|
/// Closed, opaque palette color. Only the two token tables can construct it.
pub struct ButtonPaletteColor {
  priv red : Int
  priv green : Int
  priv blue : Int
} derive(Eq, @debug.Debug)

///|
pub fn ButtonPaletteColor::red(self : ButtonPaletteColor) -> Int {
  self.red
}

///|
pub fn ButtonPaletteColor::green(self : ButtonPaletteColor) -> Int {
  self.green
}

///|
pub fn ButtonPaletteColor::blue(self : ButtonPaletteColor) -> Int {
  self.blue
}

///|
pub fn ButtonPaletteColor::alpha(_self : ButtonPaletteColor) -> Int {
  255
}

///|
pub fn ButtonPaletteToken::color(
  self : ButtonPaletteToken,
  role : ButtonPaintRole,
) -> ButtonPaletteColor {
  match (self, role) {
    (Light, NormalBorder) => { red: 130, green: 146, blue: 164, }
    (Light, FocusedBorder) => { red: 35, green: 110, blue: 210, }
    (Light, DisabledBorder) => { red: 184, green: 190, blue: 198, }
    (Light, NormalFill) => { red: 245, green: 248, blue: 252, }
    (Light, HoveredFill) => { red: 226, green: 237, blue: 250, }
    (Light, PressedFill) => { red: 206, green: 224, blue: 245, }
    (Light, LoadingFill) => { red: 232, green: 237, blue: 244, }
    (Light, DisabledFill) => { red: 238, green: 240, blue: 243, }
    (Light, EnabledForeground) => { red: 25, green: 43, blue: 62, }
    (Light, DisabledForeground) => { red: 120, green: 128, blue: 139, }
    (Dark, NormalBorder) => { red: 102, green: 126, blue: 150, }
    (Dark, FocusedBorder) => { red: 98, green: 170, blue: 255, }
    (Dark, DisabledBorder) => { red: 100, green: 106, blue: 114, }
    (Dark, NormalFill) => { red: 42, green: 71, blue: 101, }
    (Dark, HoveredFill) => { red: 48, green: 91, blue: 137, }
    (Dark, PressedFill) => { red: 35, green: 77, blue: 119, }
    (Dark, LoadingFill) => { red: 55, green: 70, blue: 88, }
    (Dark, DisabledFill) => { red: 47, green: 52, blue: 60, }
    (Dark, EnabledForeground) => { red: 242, green: 246, blue: 250, }
    (Dark, DisabledForeground) => { red: 166, green: 171, blue: 178, }
  }
}

///|
pub fn button_with_palette(
  key : NodeKey,
  label : String,
  palette : ButtonPaletteToken,
  disabled~ : Bool = false,
  loading~ : Bool = false,
) -> View {
  { ..button(key, label, disabled~, loading~), button_palette: Some(palette), }
}

///|
pub fn View::button_palette(self : View) -> ButtonPaletteToken? {
  self.button_palette
}

///|
pub extend ButtonPaletteToken with Eq::{equal, not_equal}

///|
pub extend ButtonPaletteToken with @debug.Debug::{to_repr}

///|
pub extend ButtonPaintRole with Eq::{equal, not_equal}

///|
pub extend ButtonPaintRole with @debug.Debug::{to_repr}

///|
pub extend ButtonPaletteColor with Eq::{equal, not_equal}

///|
pub extend ButtonPaletteColor with @debug.Debug::{to_repr}
