///|
/// A rectangular semantic Card surface. Kumo's native visual subset retains
/// its light/dark fill and line token without claiming radius or shadow.
pub struct NativeCard {
  id : UInt64
  fill : @primitives.Color
  line : @primitives.Color
}

///|
pub fn NativeCard::new(
  id : UInt64,
  theme : Theme,
  layered : Bool,
) -> NativeCard {
  {
    id,
    fill: if layered {
      theme.elevated()
    } else {
      theme.base()
    },
    line: if layered {
      theme.hairline()
    } else {
      theme.line()
    },
  }
}

///|
pub fn NativeCard::id(self : NativeCard) -> UInt64 {
  self.id
}

///|
/// Emit the filled surface and a square one-pixel border.
pub fn NativeCard::scene_items(
  self : NativeCard,
  bounds : @primitives.Rect,
) -> Result[Array[@scene.SceneItem], @diagnostics.FrameworkError] {
  let max_id : UInt64 = 0xffff_ffff_ffff_ffff
  if self.id > max_id - 4 {
    return Err(
      surface_error("NativeCard::scene_items", "Card ID range overflows UInt64"),
    )
  }
  let items : Array[@scene.SceneItem] = []
  match
    @scene.SceneItem::quad(
      self.id,
      bounds,
      self.fill,
      @scene.AffineTransform::identity(),
      1.0,
      None,
    ) {
    Err(_) =>
      Err(surface_error("NativeCard::scene_items", "scene rejected Card fill"))
    Ok(item) => {
      items.push(item)
      match add_border(items, self.id + 1, bounds, self.line) {
        Err(error) => Err(error)
        Ok(_) => Ok(items)
      }
    }
  }
}

///|
/// A semantic application shell surface for the native sample and host apps.
pub struct NativeAppShell {
  id : UInt64
  background : @primitives.Color
}

///|
pub fn NativeAppShell::new(id : UInt64, theme : Theme) -> NativeAppShell {
  { id, background: theme.base(), }
}

///|
pub fn NativeAppShell::scene_item(
  self : NativeAppShell,
  bounds : @primitives.Rect,
) -> Result[@scene.SceneItem, @diagnostics.FrameworkError] {
  match
    @scene.SceneItem::quad(
      self.id,
      bounds,
      self.background,
      @scene.AffineTransform::identity(),
      1.0,
      None,
    ) {
    Ok(item) => Ok(item)
    Err(_) =>
      Err(
        surface_error(
          "NativeAppShell::scene_item", "scene rejected AppShell background",
        ),
      )
  }
}

///|
/// Lay out the semantic AppShell header and main slots. `main_children` is a
/// preorder subtree rooted at `main.id()` and can contain a Card and its own
/// flex children. The shell always centers its header/main column and applies
/// the caller-selected gap.
pub fn NativeAppShell::layout_tree(
  self : NativeAppShell,
  viewport : @primitives.Size,
  header : @layout.FlexItem,
  main : @layout.FlexItem,
  main_style : @layout.FlexTreeStyle,
  main_children : Array[@layout.FlexTreeNode],
  gap : Double,
) -> Result[@layout.FlexTreeLayout, @diagnostics.FrameworkError] {
  if header.id() == main.id() || header.id() == self.id || main.id() == self.id {
    return Err(
      surface_error(
        "NativeAppShell::layout_tree", "AppShell slot IDs must be distinct",
      ),
    )
  }
  let root_gap = match
    @layout.FlexTreeStyle::new(@layout.FlowDirection::column()).with_gap(gap) {
    Err(_) =>
      return Err(
        surface_error("NativeAppShell::layout_tree", "AppShell gap is invalid"),
      )
    Ok(style) => style
  }
  let root_style = root_gap
    .with_justify(@layout.JustifyContent::center())
    .with_align(@layout.AlignItems::center())
  let nodes : Array[@layout.FlexTreeNode] = [
    @layout.FlexTreeNode::new(header, self.id),
    @layout.FlexTreeNode::new(main, self.id).with_children(main_style),
  ]
  for node in main_children {
    nodes.push(node)
  }
  match @layout.layout_flex_tree(self.id, viewport, root_style, nodes) {
    Ok(layout) => Ok(layout)
    Err(_) =>
      Err(
        surface_error(
          "NativeAppShell::layout_tree", "AppShell Flex layout rejected its slots",
        ),
      )
  }
}

///|
fn add_border(
  items : Array[@scene.SceneItem],
  id : UInt64,
  bounds : @primitives.Rect,
  color : @primitives.Color,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if color.alpha() == 0 {
    return Ok(())
  }
  let width = bounds.size().width()
  let height = bounds.size().height()
  let strips = [
    surface_rect(bounds.left(), bounds.top(), width, 1.0),
    surface_rect(bounds.left(), bounds.bottom() - 1.0, width, 1.0),
    surface_rect(
      bounds.left(),
      bounds.top() + 1.0,
      1.0,
      surface_max(0.0, height - 2.0),
    ),
    surface_rect(
      bounds.right() - 1.0,
      bounds.top() + 1.0,
      1.0,
      surface_max(0.0, height - 2.0),
    ),
  ]
  let mut index = 0
  while index < strips.length() {
    match
      @scene.SceneItem::quad(
        id + index.to_uint64(),
        strips[index],
        color,
        @scene.AffineTransform::identity(),
        1.0,
        None,
      ) {
      Err(_) =>
        return Err(
          surface_error("NativeCard::scene_items", "scene rejected Card border"),
        )
      Ok(item) => items.push(item)
    }
    index += 1
  }
  Ok(())
}

///|
fn surface_rect(
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> @primitives.Rect {
  match @primitives.Rect::new(x, y, width, height) {
    Ok(value) => value
    Err(_) => abort("valid surface sub-rectangle rejected")
  }
}

///|
fn surface_max(left : Double, right : Double) -> Double {
  if left > right {
    left
  } else {
    right
  }
}

///|
fn surface_error(
  operation : String,
  message : String,
) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    @diagnostics.ConversionFailed,
    operation,
    subsystem="native-components",
    message~,
  )
}
