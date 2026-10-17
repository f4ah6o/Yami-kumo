///|
pub(all) enum Theme {
  Light
  Dark
} derive(Eq, @debug.Debug)

///|
pub struct Color {
  priv red : Int
  priv green : Int
  priv blue : Int
} derive(Eq, @debug.Debug)

///|
fn rgb(red : Int, green : Int, blue : Int) -> Color {
  { red, green, blue, }
}

///|
pub fn Color::red(self : Color) -> Int {
  self.red
}

///|
pub fn Color::green(self : Color) -> Int {
  self.green
}

///|
pub fn Color::blue(self : Color) -> Int {
  self.blue
}

///|
pub fn Color::css(self : Color) -> String {
  "rgb(\{self.red}, \{self.green}, \{self.blue})"
}

///|
pub struct ButtonColors {
  normal_border : Color
  focused_border : Color
  disabled_border : Color
  normal_fill : Color
  hovered_fill : Color
  pressed_fill : Color
  loading_fill : Color
  disabled_fill : Color
  enabled_foreground : Color
  disabled_foreground : Color
} derive(Eq, @debug.Debug)

///|
pub fn Theme::name(self : Theme) -> String {
  match self {
    Light => "light"
    Dark => "dark"
  }
}

///|
pub fn Theme::button_colors(self : Theme) -> ButtonColors {
  match self {
    Light =>
      {
        normal_border: rgb(130, 146, 164),
        focused_border: rgb(35, 110, 210),
        disabled_border: rgb(184, 190, 198),
        normal_fill: rgb(245, 248, 252),
        hovered_fill: rgb(226, 237, 250),
        pressed_fill: rgb(206, 224, 245),
        loading_fill: rgb(232, 237, 244),
        disabled_fill: rgb(238, 240, 243),
        enabled_foreground: rgb(25, 43, 62),
        disabled_foreground: rgb(120, 128, 139),
      }
    Dark =>
      {
        normal_border: rgb(102, 126, 150),
        focused_border: rgb(98, 170, 255),
        disabled_border: rgb(100, 106, 114),
        normal_fill: rgb(42, 71, 101),
        hovered_fill: rgb(48, 91, 137),
        pressed_fill: rgb(35, 77, 119),
        loading_fill: rgb(55, 70, 88),
        disabled_fill: rgb(47, 52, 60),
        enabled_foreground: rgb(242, 246, 250),
        disabled_foreground: rgb(166, 171, 178),
      }
  }
}

///|
pub fn ButtonColors::entries(self : ButtonColors) -> Array[(String, Color)] {
  [
    ("normal_border", self.normal_border),
    ("focused_border", self.focused_border),
    ("disabled_border", self.disabled_border),
    ("normal_fill", self.normal_fill),
    ("hovered_fill", self.hovered_fill),
    ("pressed_fill", self.pressed_fill),
    ("loading_fill", self.loading_fill),
    ("disabled_fill", self.disabled_fill),
    ("enabled_foreground", self.enabled_foreground),
    ("disabled_foreground", self.disabled_foreground),
  ]
}

///|
pub extend Theme with Eq::{equal, not_equal}

///|
pub extend Theme with @debug.Debug::{to_repr}

///|
pub extend Color with Eq::{equal, not_equal}

///|
pub extend Color with @debug.Debug::{to_repr}

///|
pub extend ButtonColors with Eq::{equal, not_equal}

///|
pub extend ButtonColors with @debug.Debug::{to_repr}
