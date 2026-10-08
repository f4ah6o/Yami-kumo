///|
fn component_test_rect(
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> @primitives.Rect {
  match @primitives.Rect::new(x, y, width, height) {
    Ok(value) => value
    Err(_) => abort("valid test rectangle rejected")
  }
}

///|
fn component_test_measure(
  value : String,
  size : Double,
) -> Result[@text_layout.TextMeasurement, @diagnostics.FrameworkError] {
  match @text.TextDocument::new(value) {
    Err(_) =>
      Err(
        @diagnostics.FrameworkError::new(
          @diagnostics.InvalidInput,
          "component_test_measure",
          message="test text document was invalid",
        ),
      )
    Ok(document) => {
      let width = value.length().to_double() * size * 0.6
      let logical = component_test_rect(0.0, 0.0, width, size * 1.25)
      let ink = component_test_rect(-2.0, -3.0, width + 2.0, size * 1.25 + 3.0)
      let carets : Array[@text_layout.CaretGeometry] = []
      let mut offset = 0
      let mut x = 0.0
      match
        @text_layout.CaretGeometry::new(
          offset,
          true,
          component_test_rect(x, 0.0, 1.0, size),
          component_test_rect(x, 0.0, 1.0, size),
        ) {
        Ok(caret) => carets.push(caret)
        Err(_) => abort("valid initial test caret rejected")
      }
      for scalar in value.iter() {
        offset += if scalar.to_int() > 0xFFFF { 2 } else { 1 }
        x += size * 0.6
        match
          @text_layout.CaretGeometry::new(
            offset,
            true,
            component_test_rect(x, 0.0, 1.0, size),
            component_test_rect(x, 0.0, 1.0, size),
          ) {
          Ok(caret) => carets.push(caret)
          Err(_) => abort("valid test caret rejected")
        }
      }
      match
        @text_layout.TextMeasurement::new(
          document,
          logical,
          ink,
          size * 0.8,
          1,
          0,
          carets,
        ) {
        Ok(measurement) => Ok(measurement)
        Err(_) =>
          Err(
            @diagnostics.FrameworkError::new(
              @diagnostics.InvalidInput,
              "component_test_measure",
              message="test measurement was invalid",
            ),
          )
      }
    }
  }
}

///|
test "NativeText places the full logical and ink union without clipping overhangs" {
  let text = match
    @components.NativeText::new(
      7,
      "Text",
      @yami_kumo.Body,
      @yami_kumo.Base,
      @components.Theme::light(),
      component_test_measure,
    ) {
    Ok(value) => value
    Err(_) => fail("test measurement should create NativeText")
  }
  let visual = text.visual_bounds()
  assert_eq(visual.left(), -2.0)
  assert_eq(visual.top(), -3.0)
  assert_eq(visual.size().width(), 35.6)
  assert_eq(visual.size().height(), 20.5)
  let container = component_test_rect(100.0, 50.0, 35.6, 20.5)
  match text.scene_item(container, @components.Start) {
    Err(_) => fail("scene should accept measured text")
    Ok(@scene.TextRunItem(bounds~, text_origin~, text~, font_size~, ..)) => {
      assert_eq(bounds.left(), 100.0)
      assert_eq(bounds.top(), 50.0)
      assert_eq(text_origin.x(), 102.0)
      assert_eq(text_origin.y(), 53.0)
      assert_eq(text, "Text")
      assert_eq(font_size, 14.0)
    }
    Ok(_) => fail("NativeText should lower to a text run")
  }
}

///|
test "NativeButton keeps Kumo size geometry and emits flat background border and label" {
  let button = match
    @components.NativeButton::new(
      20,
      "OK",
      @yami_kumo.Primary,
      @yami_kumo.Base,
      false,
      @components.Theme::light(),
      component_test_measure,
    ) {
    Ok(value) => value
    Err(_) => fail("test measurement should create NativeButton")
  }
  let size = button.intrinsic_size()
  assert_eq(size.height(), 36.0)
  assert_eq(size.width(), 42.8)
  let bounds = component_test_rect(10.0, 20.0, size.width(), size.height())
  match button.scene_items(bounds) {
    Err(_) => fail("scene should accept flat Button items")
    Ok(items) => {
      assert_eq(items.length(), 6)
      match items[0] {
        @scene.QuadItem(color~, ..) => {
          assert_eq(color.red(), 5)
          assert_eq(color.green(), 109)
          assert_eq(color.blue(), 255)
        }
        _ => fail("first Button item should be its background quad")
      }
      let label_bounds = match button.label_bounds(bounds) {
        Err(_) => fail("Button should expose its exact measured label bounds")
        Ok(value) => value
      }
      match items[5] {
        @scene.TextRunItem(bounds~, ..) => {
          assert_eq(bounds.left(), label_bounds.left())
          assert_eq(bounds.top(), label_bounds.top())
          assert_eq(bounds.size().width(), label_bounds.size().width())
          assert_eq(bounds.size().height(), label_bounds.size().height())
        }
        _ => fail("last Button item should be its centered TextRun label")
      }
      assert_true(button.element_node(bounds, None).is_focusable())
    }
  }
}

///|
test "disabled Button has no pointer route or focus acquisition" {
  let button = match
    @components.NativeButton::new(
      30,
      "Disabled",
      @yami_kumo.Secondary,
      @yami_kumo.Sm,
      true,
      @components.Theme::light(),
      component_test_measure,
    ) {
    Ok(value) => value
    Err(_) => fail("test measurement should create disabled NativeButton")
  }
  let node = button.element_node(
    component_test_rect(5.0, 6.0, button.intrinsic_size().width(), 26.0),
    None,
  )
  assert_true(!node.is_focusable())
  assert_true(!node.accepts_pointer_events())
}

///|
test "Card and AppShell emit square surfaces while preserving Kumo line alpha" {
  let bounds = component_test_rect(10.0, 12.0, 80.0, 48.0)
  let card = @components.NativeCard::new(60, @components.Theme::light(), false)
  match card.scene_items(bounds) {
    Err(_) => fail("Card should lower to flat surface quads")
    Ok(items) => {
      assert_eq(items.length(), 5)
      match items[0] {
        @scene.QuadItem(color~, ..) => assert_eq(color.red(), 255)
        _ => fail("Card should begin with its fill quad")
      }
      match items[1] {
        @scene.QuadItem(color~, ..) => assert_eq(color.alpha(), 26)
        _ =>
          fail("Card's first square border should preserve the Kumo line alpha")
      }
    }
  }
  let shell = @components.NativeAppShell::new(70, @components.Theme::dark())
  match shell.scene_item(bounds) {
    Err(_) => fail("AppShell should lower to its base canvas quad")
    Ok(@scene.QuadItem(color~, ..)) => assert_eq(color.red(), 15)
    Ok(_) => fail("AppShell should lower to one quad")
  }
}

///|
test "unsupported monospace Text fails explicitly rather than using a mismatched measurement face" {
  match
    @components.NativeText::new(
      40,
      "mono",
      @yami_kumo.Mono,
      @yami_kumo.Base,
      @components.Theme::light(),
      component_test_measure,
    ) {
    Ok(_) => fail("system-sans native Text must reject a monospace request")
    Err(error) =>
      assert_true(error.code() is @diagnostics.UnsupportedCapability)
  }
}

///|
test "Kumo 2.14 theme resolves light and dark system colors" {
  let light = @components.Theme::light()
  let dark = @components.Theme::dark()
  assert_eq(light.base().red(), 255)
  assert_eq(light.brand().red(), 5)
  assert_eq(light.default_text().red(), 23)
  assert_eq(dark.base().red(), 15)
  assert_eq(dark.brand().green(), 90)
  assert_eq(dark.default_text().red(), 245)
  match light.text_color(@yami_kumo.Success) {
    Err(_) =>
      fail(
        "light Success text should resolve from the pinned link token mapping",
      )
    Ok(color) => {
      assert_eq(color.red(), 25)
      assert_eq(color.green(), 60)
      assert_eq(color.blue(), 184)
    }
  }
  let secondary_destructive = light.button_colors(
    @yami_kumo.SecondaryDestructive,
    false,
  )
  assert_eq(secondary_destructive.foreground().red(), 193)
  assert_eq(secondary_destructive.foreground().green(), 0)
  assert_eq(secondary_destructive.foreground().blue(), 7)
  let destructive = light.button_colors(@yami_kumo.Destructive, false)
  assert_eq(destructive.background().red(), 251)
  assert_eq(destructive.background().green(), 44)
  assert_eq(destructive.background().blue(), 54)
  match dark.text_color(@yami_kumo.Error) {
    Err(_) =>
      fail("dark Error text should resolve from Kumo's danger text token")
    Ok(color) => {
      assert_eq(color.red(), 255)
      assert_eq(color.green(), 100)
      assert_eq(color.blue(), 103)
    }
  }
}

///|
test "disabled Button opacity preserves transparent fills and token line alpha" {
  let light = @components.Theme::light()
  let ghost = light.button_colors(@yami_kumo.Ghost, true)
  let outline = light.button_colors(@yami_kumo.Outline, true)
  let secondary = light.button_colors(@yami_kumo.Secondary, true)
  assert_eq(ghost.background().alpha(), 0)
  assert_eq(ghost.border().alpha(), 0)
  assert_eq(outline.background().alpha(), 0)
  assert_eq(outline.border().alpha(), 13)
  assert_eq(secondary.border().alpha(), 13)
}

///|
fn component_test_button_interaction(
  disabled? : Bool = false,
) -> @components.ButtonInteraction raise {
  let button = match
    @components.NativeButton::new(
      50,
      "Action",
      @yami_kumo.Primary,
      @yami_kumo.Base,
      disabled,
      @components.Theme::light(),
      component_test_measure,
    ) {
    Ok(value) => value
    Err(_) => fail("test measurement should create an interaction Button")
  }
  button.interaction()
}

///|
test "Button interaction activates only a matching primary down and up once" {
  let interaction = component_test_button_interaction()
  assert_true(interaction.pointer_down(Some(50), @primitives.Primary))
  assert_true(interaction.is_pointer_armed())
  assert_true(interaction.pointer_up(Some(50), @primitives.Primary))
  assert_true(!interaction.is_pointer_armed())
  assert_true(!interaction.pointer_up(Some(50), @primitives.Primary))
}

///|
test "outside primary release and non-primary down cancel pointer ownership" {
  let interaction = component_test_button_interaction()
  assert_true(interaction.pointer_down(Some(50), @primitives.Primary))
  assert_true(!interaction.pointer_up(None, @primitives.Primary))
  assert_true(!interaction.is_pointer_armed())
  assert_true(interaction.pointer_down(Some(50), @primitives.Primary))
  assert_true(!interaction.pointer_down(Some(50), @primitives.Secondary))
  assert_true(!interaction.pointer_up(Some(50), @primitives.Primary))
}

///|
test "disabled Button interaction cannot arm pointer or keyboard activation" {
  let interaction = component_test_button_interaction(disabled=true)
  assert_true(!interaction.pointer_down(Some(50), @primitives.Primary))
  assert_true(!interaction.pointer_up(Some(50), @primitives.Primary))
  interaction.key_down(Some(50), @primitives.Enter)
  assert_true(!interaction.key_up(Some(50), @primitives.Enter))
}

///|
test "keyboard activation needs a matching focused key release" {
  let interaction = component_test_button_interaction()
  interaction.key_down(Some(50), @primitives.Enter)
  assert_true(!interaction.key_up(Some(50), @primitives.Space))
  assert_true(!interaction.key_up(Some(50), @primitives.Enter))
  interaction.key_down(Some(50), @primitives.Space)
  assert_true(!interaction.key_up(None, @primitives.Space))
  interaction.key_down(Some(50), @primitives.Space)
  assert_true(interaction.key_up(Some(50), @primitives.Space))
}

///|
test "focus or layout cancellation clears pending Button gestures" {
  let interaction = component_test_button_interaction()
  assert_true(interaction.pointer_down(Some(50), @primitives.Primary))
  interaction.cancel()
  assert_true(!interaction.is_pointer_armed())
  assert_true(!interaction.pointer_up(Some(50), @primitives.Primary))
  interaction.key_down(Some(50), @primitives.Enter)
  interaction.cancel()
  assert_true(!interaction.key_up(Some(50), @primitives.Enter))
}

///|
test "AppShell lays out semantic header and main slots around a content child" {
  let viewport = match @primitives.Size::new(200.0, 160.0) {
    Ok(value) => value
    Err(_) => fail("test viewport should be valid")
  }
  let header_size = match @primitives.Size::new(40.0, 10.0) {
    Ok(value) => value
    Err(_) => fail("test header size should be valid")
  }
  let main_size = match @primitives.Size::new(80.0, 60.0) {
    Ok(value) => value
    Err(_) => fail("test main size should be valid")
  }
  let child_size = match @primitives.Size::new(40.0, 20.0) {
    Ok(value) => value
    Err(_) => fail("test content size should be valid")
  }
  let header = @layout.FlexItem::new(
    2,
    component_test_dimension(10.0),
    component_test_dimension(40.0),
    header_size,
  )
  let main = @layout.FlexItem::new(
    3,
    component_test_dimension(60.0),
    component_test_dimension(80.0),
    main_size,
  )
  let child = @layout.FlexItem::new(
    4,
    component_test_dimension(20.0),
    component_test_dimension(40.0),
    child_size,
  )
  let main_style = @layout.FlexTreeStyle::new(@layout.FlowDirection::column())
    .with_justify(@layout.JustifyContent::center())
    .with_align(@layout.AlignItems::center())
  let shell = @components.NativeAppShell::new(1, @components.Theme::light())
  let layout = match
    shell.layout_tree(
      viewport,
      header,
      main,
      main_style,
      [@layout.FlexTreeNode::new(child, 3)],
      10.0,
    ) {
    Ok(value) => value
    Err(_) => fail("AppShell should lay out its header and main slots")
  }
  let items = layout.items()
  assert_eq(items.length(), 3)
  assert_eq(items[0].id(), 2)
  assert_eq(items[0].bounds().left(), 80.0)
  assert_eq(items[0].bounds().top(), 40.0)
  assert_eq(items[1].id(), 3)
  assert_eq(items[1].bounds().left(), 60.0)
  assert_eq(items[1].bounds().top(), 60.0)
  assert_eq(items[2].id(), 4)
  assert_eq(items[2].bounds().left(), 80.0)
  assert_eq(items[2].bounds().top(), 80.0)
}

///|
fn component_test_dimension(value : Double) -> @layout.Dimension raise {
  match @layout.Dimension::points(value) {
    Ok(dimension) => dimension
    Err(_) => fail("test flex dimensions should be valid")
  }
}
