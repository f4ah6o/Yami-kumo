///|
test "every closed palette role is frozen opaque RGB" {
  let value = @core.Light.color(@core.NormalBorder)
  assert_eq(
    (value.red(), value.green(), value.blue(), value.alpha()),
    (130, 146, 164, 255),
  )
  let value = @core.Light.color(@core.FocusedBorder)
  assert_eq(
    (value.red(), value.green(), value.blue(), value.alpha()),
    (35, 110, 210, 255),
  )
  let value = @core.Light.color(@core.DisabledBorder)
  assert_eq(
    (value.red(), value.green(), value.blue(), value.alpha()),
    (184, 190, 198, 255),
  )
  let value = @core.Light.color(@core.NormalFill)
  assert_eq(
    (value.red(), value.green(), value.blue(), value.alpha()),
    (245, 248, 252, 255),
  )
  let value = @core.Light.color(@core.HoveredFill)
  assert_eq(
    (value.red(), value.green(), value.blue(), value.alpha()),
    (226, 237, 250, 255),
  )
  let value = @core.Light.color(@core.PressedFill)
  assert_eq(
    (value.red(), value.green(), value.blue(), value.alpha()),
    (206, 224, 245, 255),
  )
  let value = @core.Light.color(@core.LoadingFill)
  assert_eq(
    (value.red(), value.green(), value.blue(), value.alpha()),
    (232, 237, 244, 255),
  )
  let value = @core.Light.color(@core.DisabledFill)
  assert_eq(
    (value.red(), value.green(), value.blue(), value.alpha()),
    (238, 240, 243, 255),
  )
  let value = @core.Light.color(@core.EnabledForeground)
  assert_eq(
    (value.red(), value.green(), value.blue(), value.alpha()),
    (25, 43, 62, 255),
  )
  let value = @core.Light.color(@core.DisabledForeground)
  assert_eq(
    (value.red(), value.green(), value.blue(), value.alpha()),
    (120, 128, 139, 255),
  )
  let value = @core.Dark.color(@core.NormalBorder)
  assert_eq(
    (value.red(), value.green(), value.blue(), value.alpha()),
    (102, 126, 150, 255),
  )
  let value = @core.Dark.color(@core.FocusedBorder)
  assert_eq(
    (value.red(), value.green(), value.blue(), value.alpha()),
    (98, 170, 255, 255),
  )
  let value = @core.Dark.color(@core.DisabledBorder)
  assert_eq(
    (value.red(), value.green(), value.blue(), value.alpha()),
    (100, 106, 114, 255),
  )
  let value = @core.Dark.color(@core.NormalFill)
  assert_eq(
    (value.red(), value.green(), value.blue(), value.alpha()),
    (42, 71, 101, 255),
  )
  let value = @core.Dark.color(@core.HoveredFill)
  assert_eq(
    (value.red(), value.green(), value.blue(), value.alpha()),
    (48, 91, 137, 255),
  )
  let value = @core.Dark.color(@core.PressedFill)
  assert_eq(
    (value.red(), value.green(), value.blue(), value.alpha()),
    (35, 77, 119, 255),
  )
  let value = @core.Dark.color(@core.LoadingFill)
  assert_eq(
    (value.red(), value.green(), value.blue(), value.alpha()),
    (55, 70, 88, 255),
  )
  let value = @core.Dark.color(@core.DisabledFill)
  assert_eq(
    (value.red(), value.green(), value.blue(), value.alpha()),
    (47, 52, 60, 255),
  )
  let value = @core.Dark.color(@core.EnabledForeground)
  assert_eq(
    (value.red(), value.green(), value.blue(), value.alpha()),
    (242, 246, 250, 255),
  )
  let value = @core.Dark.color(@core.DisabledForeground)
  assert_eq(
    (value.red(), value.green(), value.blue(), value.alpha()),
    (166, 171, 178, 255),
  )
}

///|
test "palette metadata is per @core.Button and legacy constructors remain None" {
  let key = @core.NodeKey::new("@core.button")
  for
    view in [
      @core.button(key, "A"),
      @core.text(key, "A"),
      @core.row(key, []),
      @core.column(key, []),
      @core.card(key, []),
    ] {
    assert_eq(view.button_palette(), None)
  }
  for token in [@core.Light, @core.Dark] {
    let view = @core.button_with_palette(
      key,
      "<literal>",
      token,
      disabled=true,
      loading=true,
    )
    assert_eq(view.button_palette(), Some(token))
    assert_eq(view.kind(), @core.Button)
    assert_eq(view.label(), "<literal>")
    assert_true(view.disabled() && view.loading())
    assert_eq(view.spacing(), None)
    assert_true(!view.is_card())
  }
}
