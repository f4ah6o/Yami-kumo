///|
/// Theme modes for the bounded native Kumo visual subset.
pub(all) enum ThemeMode {
  Light
  Dark
} derive(Eq)

///|
pub extend ThemeMode with Eq::{not_equal, equal}

///|
/// A resolved Kumo theme. Native components use solid colors and square
/// geometry; gradients, shadows, radii and font weights are outside this
/// rendering subset.
pub struct Theme {
  mode : ThemeMode
}

///|
pub fn Theme::light() -> Theme {
  { mode: Light, }
}

///|
pub fn Theme::dark() -> Theme {
  { mode: Dark, }
}

///|
pub fn Theme::mode(self : Theme) -> ThemeMode {
  self.mode
}

///|
/// Kumo base canvas color from the pinned 2.14.0 standalone stylesheet.
pub fn Theme::base(self : Theme) -> @primitives.Color {
  match self.mode {
    Light => rgb(255, 255, 255)
    Dark => rgb(15, 15, 15)
  }
}

///|
/// Elevated LayerCard color from the pinned Kumo 2.14.0 neutral tokens.
pub fn Theme::elevated(self : Theme) -> @primitives.Color {
  match self.mode {
    Light => rgb(248, 248, 248)
    Dark => rgb(6, 6, 6)
  }
}

///|
/// Default body text color.
pub fn Theme::default_text(self : Theme) -> @primitives.Color {
  match self.mode {
    Light => rgb(23, 23, 23)
    Dark => rgb(245, 245, 245)
  }
}

///|
/// Subtle secondary text color.
pub fn Theme::subtle_text(self : Theme) -> @primitives.Color {
  match self.mode {
    Light => rgb(115, 115, 115)
    Dark => rgb(161, 161, 161)
  }
}

///|
/// Link and success text color in the checked-in Kumo token set.
pub fn Theme::link_text(self : Theme) -> @primitives.Color {
  match self.mode {
    Light => rgb(25, 60, 184)
    Dark => rgb(81, 162, 255)
  }
}

///|
/// Success text from Kumo's `--text-color-kumo-success` token.
pub fn Theme::success_text(self : Theme) -> @primitives.Color {
  match self.mode {
    Light => rgb(0, 96, 69)
    Dark => rgb(164, 244, 207)
  }
}

///|
/// Error text from Kumo's `--text-color-kumo-danger` token. Destructive
/// controls use the separate red500/red600 `danger` fill token.
pub fn Theme::danger_text(self : Theme) -> @primitives.Color {
  match self.mode {
    Light => rgb(193, 0, 7)
    Dark => rgb(255, 100, 103)
  }
}

///|
/// Error and destructive-action color.
pub fn Theme::danger(self : Theme) -> @primitives.Color {
  match self.mode {
    Light => rgb(251, 44, 54)
    Dark => rgb(231, 0, 11)
  }
}

///|
/// Primary-action color from Kumo's `--color-kumo-brand` token.
pub fn Theme::brand(self : Theme) -> @primitives.Color {
  match self.mode {
    Light => rgb(5, 109, 255)
    Dark => rgb(0, 90, 235)
  }
}

///|
/// Hairline boundary color, represented as an opaque token color because the
/// native subset does not composite CSS color-mix expressions.
pub fn Theme::hairline(self : Theme) -> @primitives.Color {
  match self.mode {
    Light => rgb(233, 233, 233)
    Dark => rgb(38, 38, 38)
  }
}

///|
/// Kumo control ring/border color. Light mode preserves Kumo's 10% alpha;
/// dark mode uses the opaque neutral-750 token.
pub fn Theme::line(self : Theme) -> @primitives.Color {
  match self.mode {
    Light => rgba(10, 10, 10, 26)
    Dark => rgba(51, 51, 51, 255)
  }
}

///|
/// Kumo semantic text color for the native-supported plain-text variants.
/// Mono variants return an explicit unsupported-feature error because all
/// native adapters currently measure and render the fixed system-sans face.
pub fn Theme::text_color(
  self : Theme,
  variant : @yami_kumo.TextVariant,
) -> Result[@primitives.Color, @diagnostics.FrameworkError] {
  match variant {
    @yami_kumo.Heading | @yami_kumo.Body => Ok(self.default_text())
    @yami_kumo.Secondary => Ok(self.subtle_text())
    // The pinned generated class contract maps TextVariant::Success to the
    // link token; its public enum name does not select the emerald palette.
    @yami_kumo.Success => Ok(self.link_text())
    @yami_kumo.Error => Ok(self.danger_text())
    @yami_kumo.Mono | @yami_kumo.MonoSecondary =>
      Err(
        unsupported(
          "Theme::text_color", "monospace text is not supported by the system-sans native subset",
        ),
      )
  }
}

///|
/// Surface text color placed on an emphasized Button.
pub fn Theme::inverse_text(_self : Theme) -> @primitives.Color {
  rgb(255, 255, 255)
}

///|
/// Construct the flat native Button palette corresponding to a root Kumo
/// ButtonVariant. A CSS gradient or border radius is intentionally not implied.
pub fn Theme::button_colors(
  self : Theme,
  variant : @yami_kumo.ButtonVariant,
  disabled : Bool,
) -> ButtonColors {
  let neutral = self.default_text()
  let base = self.base()
  let subtle = self.subtle_text()
  let line = self.line()
  let (background, foreground, border) = match variant {
    @yami_kumo.Primary => (self.brand(), self.inverse_text(), self.brand())
    @yami_kumo.Destructive =>
      (self.danger(), self.inverse_text(), self.danger())
    @yami_kumo.Secondary => (base, neutral, line)
    @yami_kumo.SecondaryDestructive => (base, self.danger_text(), line)
    @yami_kumo.Ghost => (transparent(), neutral, transparent())
    @yami_kumo.Outline => (transparent(), neutral, line)
  }
  if disabled {
    {
      background: attenuate_alpha(background, 128),
      foreground: attenuate_alpha(
        if variant is @yami_kumo.Primary || variant is @yami_kumo.Destructive {
          self.inverse_text()
        } else {
          subtle
        },
        179,
      ),
      border: attenuate_alpha(border, 128),
    }
  } else {
    { background, foreground, border, }
  }
}

///|
pub struct ButtonColors {
  background : @primitives.Color
  foreground : @primitives.Color
  border : @primitives.Color
}

///|
pub fn ButtonColors::background(self : ButtonColors) -> @primitives.Color {
  self.background
}

///|
pub fn ButtonColors::foreground(self : ButtonColors) -> @primitives.Color {
  self.foreground
}

///|
pub fn ButtonColors::border(self : ButtonColors) -> @primitives.Color {
  self.border
}

///|
fn rgb(red : Int, green : Int, blue : Int) -> @primitives.Color {
  rgba(red, green, blue, 255)
}

///|
fn rgba(red : Int, green : Int, blue : Int, alpha : Int) -> @primitives.Color {
  match @primitives.Color::rgba(red, green, blue, alpha) {
    Ok(color) => color
    Err(_) => abort("constant theme color channel is out of range")
  }
}

///|
fn transparent() -> @primitives.Color {
  match @primitives.Color::rgba(0, 0, 0, 0) {
    Ok(color) => color
    Err(_) => abort("transparent theme color is out of range")
  }
}

///|
fn attenuate_alpha(
  color : @primitives.Color,
  opacity : Int,
) -> @primitives.Color {
  let scaled_alpha = (color.alpha() * opacity + 127) / 255
  rgba(color.red(), color.green(), color.blue(), scaled_alpha)
}

///|
fn unsupported(
  operation : String,
  message : String,
) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    @diagnostics.UnsupportedCapability,
    operation,
    subsystem="native-components",
    message~,
  )
}
