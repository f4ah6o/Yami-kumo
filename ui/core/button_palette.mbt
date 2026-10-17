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
  // Keep the established per-Button API while sharing one numeric token table
  // with the root theme. This chooses a color role, never an interaction state.
  let colors = match self {
    Light => @theme.Light.button_colors()
    Dark => @theme.Dark.button_colors()
  }
  let value = match role {
    NormalBorder => colors.normal_border
    FocusedBorder => colors.focused_border
    DisabledBorder => colors.disabled_border
    NormalFill => colors.normal_fill
    HoveredFill => colors.hovered_fill
    PressedFill => colors.pressed_fill
    LoadingFill => colors.loading_fill
    DisabledFill => colors.disabled_fill
    EnabledForeground => colors.enabled_foreground
    DisabledForeground => colors.disabled_foreground
  }
  { red: value.red(), green: value.green(), blue: value.blue(), }
}

///|
pub fn button_with_palette(
  key : NodeKey,
  label : String,
  palette : ButtonPaletteToken,
  disabled? : Bool = false,
  loading? : Bool = false,
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
