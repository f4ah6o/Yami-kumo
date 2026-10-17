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
    Light => {
      normal_border: rgb(100, 116, 139),
      focused_border: rgb(29, 78, 216),
      disabled_border: rgb(148, 163, 184),
      normal_fill: rgb(255, 255, 255),
      hovered_fill: rgb(241, 245, 249),
      pressed_fill: rgb(226, 232, 240),
      loading_fill: rgb(219, 234, 254),
      disabled_fill: rgb(241, 245, 249),
      enabled_foreground: rgb(15, 23, 42),
      disabled_foreground: rgb(100, 116, 139),
    }
    Dark => {
      normal_border: rgb(148, 163, 184),
      focused_border: rgb(96, 165, 250),
      disabled_border: rgb(71, 85, 105),
      normal_fill: rgb(30, 41, 59),
      hovered_fill: rgb(51, 65, 85),
      pressed_fill: rgb(71, 85, 105),
      loading_fill: rgb(30, 58, 138),
      disabled_fill: rgb(15, 23, 42),
      enabled_foreground: rgb(248, 250, 252),
      disabled_foreground: rgb(148, 163, 184),
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
