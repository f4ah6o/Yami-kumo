///|
test "palette cycle composes one counter and leaves spacing unchanged" {
  let mut model = @shared_counter.PaletteModel::new()
  let actions = [
    "increment", "palette-toggle", "increment", "palette-toggle", "palette-toggle",
  ]
  let counts = [0, 1, 1, 2, 2, 2]
  let palettes = [
    None,
    None,
    Some(@core.Light),
    Some(@core.Light),
    Some(@core.Dark),
    None,
  ]
  for phase in 0..<6 {
    assert_eq(model.value(), counts[phase])
    assert_eq(model.palette(), palettes[phase])
    assert_true(!model.expanded())
    let children = model.palette_view().children()[2].children()
    assert_eq(children[0].button_palette(), palettes[phase])
    assert_eq(children[1].button_palette(), palettes[phase])
    assert_eq(children[0].key(), @core.NodeKey::new("increment"))
    assert_eq(children[1].label(), "Palette")
    if phase < 5 {
      model = model.update_palette(
        @core.Activate(@core.NodeKey::new(actions[phase])),
      )
    }
  }
  assert_eq(model.counter().value(), 2)
  assert_eq(
    model
    .update(@core.Activate(@core.NodeKey::new("spacing-toggle")))
    .expanded(),
    true,
  )
  assert_eq(
    model.update_counter(@core.Activate(@core.NodeKey::new("palette-toggle"))),
    model,
  )
}
