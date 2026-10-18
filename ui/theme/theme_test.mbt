///|
test "standard themes expose complete distinct opaque RGB palettes" {
  assert_eq(@theme.Light.name(), "light")
  assert_eq(@theme.Dark.name(), "dark")
  let light = @theme.Light.button_colors().entries()
  let dark = @theme.Dark.button_colors().entries()
  assert_eq(light.length(), 10)
  assert_eq(dark.length(), 10)
  for index = 0; index < light.length(); index = index + 1 {
    let (light_name, light_color) = light[index]
    let (dark_name, dark_color) = dark[index]
    assert_eq(light_name, dark_name)
    assert_true(light_color != dark_color)
    for color in [light_color, dark_color] {
      for channel in [color.red(), color.green(), color.blue()] {
        assert_true(channel >= 0 && channel <= 255)
      }
      assert_eq(
        color.css(),
        "rgb(\{color.red()}, \{color.green()}, \{color.blue()})",
      )
    }
  }
}

///|
test "editing an exported token list cannot change a standard theme" {
  let before = @theme.Light.button_colors()
  let exported = before.entries()
  exported[0] = @theme.Dark.button_colors().entries()[0]
  assert_eq(@theme.Light.button_colors(), before)
  assert_true(exported != before.entries())
}

///|
test "shell themes expose complete distinct opaque RGB palettes" {
  let light = @theme.Light.shell_colors().entries()
  let dark = @theme.Dark.shell_colors().entries()
  assert_eq(light.length(), 7)
  assert_eq(dark.length(), 7)
  for index = 0; index < light.length(); index = index + 1 {
    let (light_name, light_color) = light[index]
    let (dark_name, dark_color) = dark[index]
    assert_eq(light_name, dark_name)
    assert_true(light_color != dark_color)
    for color in [light_color, dark_color] {
      for channel in [color.red(), color.green(), color.blue()] {
        assert_true(channel >= 0 && channel <= 255)
      }
    }
  }
  assert_eq(@theme.Light.shell_colors().background.css(), "rgb(238, 240, 242)")
  assert_eq(@theme.Dark.shell_colors().text.css(), "rgb(238, 242, 246)")
}
