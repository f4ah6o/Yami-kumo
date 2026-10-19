///|
/// Square-geometry native Button, with a copied measured label and stable
/// caller-owned element identity.
pub struct NativeButton {
  id : UInt64
  label : NativeText
  variant : @yami_kumo.ButtonVariant
  size : @yami_kumo.ControlSize
  disabled : Bool
  theme : Theme
  bounds : @primitives.Rect
}

///|
/// Portable pointer/key activation state for a caller-owned Button ID.
pub struct ButtonInteraction {
  id : UInt64
  disabled : Bool
  mut pointer_armed : Bool
  mut key_armed : @primitives.Key?
}

///|
pub fn NativeButton::new(
  id : UInt64,
  label : String,
  variant : @yami_kumo.ButtonVariant,
  size : @yami_kumo.ControlSize,
  disabled : Bool,
  theme : Theme,
  measure : TextMeasure,
) -> Result[NativeButton, @diagnostics.FrameworkError] {
  let max_id : UInt64 = 0xffff_ffff_ffff_ffff
  if id > max_id - 5 {
    return Err(
      button_error("NativeButton::new", "Button ID range overflows UInt64"),
    )
  }
  let colors = theme.button_colors(variant, disabled)
  let font_size = button_font_size(size)
  match
    NativeText::for_button(
      id + 1,
      label,
      font_size,
      colors.foreground(),
      measure,
    ) {
    Err(error) => Err(error)
    Ok(measured_label) => {
      let (height, horizontal_padding) = button_metrics(size)
      let label_size = measured_label.intrinsic_size()
      let width = label_size.width() + horizontal_padding * 2.0
      match @primitives.Rect::new(0.0, 0.0, width, height) {
        Err(_) =>
          Err(button_error("NativeButton::new", "button bounds are invalid"))
        Ok(bounds) =>
          Ok({
            id,
            label: measured_label,
            variant,
            size,
            disabled,
            theme,
            bounds,
          })
      }
    }
  }
}

///|
pub fn NativeButton::id(self : NativeButton) -> UInt64 {
  self.id
}

///|
pub fn NativeButton::label(self : NativeButton) -> NativeText {
  self.label
}

///|
pub fn NativeButton::variant(self : NativeButton) -> @yami_kumo.ButtonVariant {
  self.variant
}

///|
pub fn NativeButton::size(self : NativeButton) -> @yami_kumo.ControlSize {
  self.size
}

///|
pub fn NativeButton::disabled(self : NativeButton) -> Bool {
  self.disabled
}

///|
/// Create independent event state for this Button. The caller routes input
/// through ElementTree, then passes the resulting target to these methods.
pub fn NativeButton::interaction(self : NativeButton) -> ButtonInteraction {
  {
    id: self.id,
    disabled: self.disabled,
    pointer_armed: false,
    key_armed: None,
  }
}

///|
/// Arm a primary pointer gesture only when its down target is this enabled
/// Button. A non-primary down cancels prior ownership.
pub fn ButtonInteraction::pointer_down(
  self : ButtonInteraction,
  target : UInt64?,
  button : @primitives.MouseButton,
) -> Bool {
  self.key_armed = None
  self.pointer_armed = !self.disabled &&
    button is @primitives.Primary &&
    target == Some(self.id)
  self.pointer_armed
}

///|
/// Activate only when a primary up targets the same Button that owned down.
/// Every primary release consumes the prior press, including an outside up.
pub fn ButtonInteraction::pointer_up(
  self : ButtonInteraction,
  target : UInt64?,
  button : @primitives.MouseButton,
) -> Bool {
  let activate = self.pointer_armed &&
    !self.disabled &&
    button is @primitives.Primary &&
    target == Some(self.id)
  if button is @primitives.Primary {
    self.pointer_armed = false
  }
  activate
}

///|
/// Handle an activation-key down on the focused Button.
/// Enter activates on every key down, including repeats. Space remains armed
/// until its matching key release and reports no action on key down. The
/// return value is true only for a focused, enabled Enter key down. Enter
/// clears any older held gesture before activating.
pub fn ButtonInteraction::key_down(
  self : ButtonInteraction,
  target : UInt64?,
  key : @primitives.Key,
) -> Bool {
  if self.disabled || target != Some(self.id) {
    return false
  }
  match key {
    @primitives.Enter => {
      self.pointer_armed = false
      self.key_armed = None
      true
    }
    @primitives.Space => {
      self.pointer_armed = false
      self.key_armed = Some(@primitives.Space)
      false
    }
    _ => false
  }
}

///|
/// Activate only when Space is released while the Button still owns keyboard
/// focus. A mismatched release cancels the held Space gesture.
pub fn ButtonInteraction::key_up(
  self : ButtonInteraction,
  target : UInt64?,
  key : @primitives.Key,
) -> Bool {
  let activate = match self.key_armed {
    Some(armed) => armed == key && target == Some(self.id) && !self.disabled
    None => false
  }
  self.key_armed = None
  activate
}

///|
/// Cancel all pending activation on focus loss, resize or gesture invalidation.
pub fn ButtonInteraction::cancel(self : ButtonInteraction) -> Unit {
  self.pointer_armed = false
  self.key_armed = None
}

///|
pub fn ButtonInteraction::is_pointer_armed(self : ButtonInteraction) -> Bool {
  self.pointer_armed
}

///|
/// Whether a matching pointer or activation key is currently held.
pub fn ButtonInteraction::is_pressed(self : ButtonInteraction) -> Bool {
  self.pointer_armed || self.key_armed is Some(_)
}

///|
pub fn NativeButton::intrinsic_size(self : NativeButton) -> @primitives.Size {
  self.bounds.size()
}

///|
/// Exact centered TextRun bounds used by native frame probes and adapters.
pub fn NativeButton::label_bounds(
  self : NativeButton,
  bounds : @primitives.Rect,
) -> Result[@primitives.Rect, @diagnostics.FrameworkError] {
  let horizontal_padding = button_metrics(self.size).1
  let label_size = self.label.intrinsic_size()
  let container_width = max(
    0.0,
    bounds.size().width() - 2.0 * horizontal_padding,
  )
  match
    @primitives.Rect::new(
      bounds.left() +
      horizontal_padding +
      (container_width - label_size.width()) / 2.0,
      bounds.top() + (bounds.size().height() - label_size.height()) / 2.0,
      label_size.width(),
      label_size.height(),
    ) {
    Ok(value) => Ok(value)
    Err(_) =>
      Err(
        button_error(
          "NativeButton::label_bounds", "button label bounds are invalid",
        ),
      )
  }
}

///|
pub fn NativeButton::element_node(
  self : NativeButton,
  bounds : @primitives.Rect,
  parent : UInt64?,
) -> @element.ElementNode {
  let node = @element.ElementNode::new(self.id, parent, bounds)
  if self.disabled {
    node.with_pointer_events(false)
  } else {
    node.with_focusable(true)
  }
}

///|
/// Lower a flat background, an outset square ring and centered label. The
/// scene item IDs are stable offsets owned by this Button instance.
pub fn NativeButton::scene_items(
  self : NativeButton,
  bounds : @primitives.Rect,
  hovered? : Bool = false,
  focus_visible? : Bool = false,
) -> Result[Array[@scene.SceneItem], @diagnostics.FrameworkError] {
  let colors = self.theme.button_colors(self.variant, self.disabled, hovered~)
  let items : Array[@scene.SceneItem] = []
  match
    @scene.SceneItem::quad(
      self.id,
      bounds,
      colors.background(),
      @scene.AffineTransform::identity(),
      1.0,
      None,
    ) {
    Err(_) =>
      return Err(
        button_error(
          "NativeButton::scene_items", "scene rejected button background",
        ),
      )
    Ok(item) => items.push(item)
  }
  let border = if focus_visible &&
    !self.disabled &&
    !(self.variant is @yami_kumo.Primary ||
    self.variant is @yami_kumo.Destructive) {
    self.theme.brand()
  } else {
    colors.border()
  }
  if border.alpha() > 0 {
    let width = bounds.size().width()
    let height = bounds.size().height()
    let ring_width = if focus_visible && !self.disabled { 2.0 } else { 1.0 }
    let strips = [
      rect(
        bounds.left() - ring_width,
        bounds.top() - ring_width,
        width + 2.0 * ring_width,
        ring_width,
      ),
      rect(
        bounds.left() - ring_width,
        bounds.bottom(),
        width + 2.0 * ring_width,
        ring_width,
      ),
      rect(bounds.left() - ring_width, bounds.top(), ring_width, height),
      rect(bounds.right(), bounds.top(), ring_width, height),
    ]
    let mut index = 0
    while index < strips.length() {
      match
        @scene.SceneItem::quad(
          self.id + 2 + index.to_uint64(),
          strips[index],
          border,
          @scene.AffineTransform::identity(),
          1.0,
          None,
        ) {
        Err(_) =>
          return Err(
            button_error(
              "NativeButton::scene_items", "scene rejected button border",
            ),
          )
        Ok(item) => items.push(item)
      }
      index += 1
    }
  }
  let label_container = match self.label_bounds(bounds) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  // Replace the label semantic color with the resolved Button foreground.
  let label = self.label.recolored(self.id + 1, colors.foreground())
  match label.scene_item(label_container, Center) {
    Err(error) => Err(error)
    Ok(item) => {
      items.push(item)
      Ok(items)
    }
  }
}

///|
pub fn NativeButton::layout_item(
  self : NativeButton,
  direction : @layout.FlowDirection,
) -> Result[@layout.FlexItem, @diagnostics.FrameworkError] {
  let size = self.intrinsic_size()
  let width = match @layout.Dimension::points(size.width()) {
    Ok(value) => value
    Err(_) =>
      return Err(
        button_error("NativeButton::layout_item", "button width is invalid"),
      )
  }
  let height = match @layout.Dimension::points(size.height()) {
    Ok(value) => value
    Err(_) =>
      return Err(
        button_error("NativeButton::layout_item", "button height is invalid"),
      )
  }
  match direction {
    @layout.Row | @layout.RowReverse =>
      Ok(@layout.FlexItem::new(self.id, width, height, size))
    @layout.Column | @layout.ColumnReverse =>
      Ok(@layout.FlexItem::new(self.id, height, width, size))
  }
}

///|
fn button_font_size(size : @yami_kumo.ControlSize) -> Double {
  match size {
    @yami_kumo.Xs | @yami_kumo.Sm => 12.0
    @yami_kumo.Base | @yami_kumo.Lg => 14.0
  }
}

///|
fn button_metrics(size : @yami_kumo.ControlSize) -> (Double, Double) {
  match size {
    @yami_kumo.Xs => (20.0, 6.0)
    @yami_kumo.Sm => (26.0, 8.0)
    @yami_kumo.Base => (36.0, 12.0)
    @yami_kumo.Lg => (40.0, 16.0)
  }
}

///|
fn rect(
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> @primitives.Rect {
  match @primitives.Rect::new(x, y, width, height) {
    Ok(value) => value
    Err(_) => abort("valid button sub-rectangle rejected")
  }
}

///|
fn max(left : Double, right : Double) -> Double {
  if left > right {
    left
  } else {
    right
  }
}

///|
fn button_error(
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
