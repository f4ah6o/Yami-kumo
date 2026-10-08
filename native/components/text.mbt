///|
/// Synchronous, display-independent measurement supplied by the selected OS
/// entrypoint. The callback and TextRunItem must use the same fixed sans face.
pub type TextMeasure = (String, Double) -> Result[
  @text_layout.TextMeasurement,
  @diagnostics.FrameworkError,
]

///|
pub(all) enum TextAlign {
  Start
  Center
  End
} derive(Eq)

///|
pub extend TextAlign with Eq::{not_equal, equal}

///|
/// Measured plain system-sans text with its full copied measurement retained.
pub struct NativeText {
  id : UInt64
  text : String
  font_size : Double
  color : @primitives.Color
  measurement : @text_layout.TextMeasurement
  visual_bounds : @primitives.Rect
}

///|
/// Measure a root TextVariant. Mono variants are rejected because the bounded
/// native pipeline uses a fixed system-sans face on every supported OS.
pub fn NativeText::new(
  id : UInt64,
  text : String,
  variant : @yami_kumo.TextVariant,
  size : @yami_kumo.ControlSize,
  theme : Theme,
  measure : TextMeasure,
) -> Result[NativeText, @diagnostics.FrameworkError] {
  let font_size = match text_font_size(variant, size) {
    Some(value) => value
    None =>
      return Err(
        @diagnostics.FrameworkError::new(
          @diagnostics.UnsupportedCapability,
          "NativeText::new",
          subsystem="native-components",
          message="monospace text is not supported by the system-sans native subset",
        ),
      )
  }
  match theme.text_color(variant) {
    Err(error) => Err(error)
    Ok(color) =>
      match measure(text, font_size) {
        Err(error) => Err(error)
        Ok(measurement) =>
          match visual_rect(measurement) {
            Err(error) => Err(error)
            Ok(bounds) =>
              Ok({
                id,
                text,
                font_size,
                color,
                measurement,
                visual_bounds: bounds,
              })
          }
      }
  }
}

///|
/// Create a premeasured text run for a Button label, which uses the Button's
/// foreground color instead of a semantic TextVariant color.
pub fn NativeText::for_button(
  id : UInt64,
  text : String,
  font_size : Double,
  color : @primitives.Color,
  measure : TextMeasure,
) -> Result[NativeText, @diagnostics.FrameworkError] {
  match measure(text, font_size) {
    Err(error) => Err(error)
    Ok(measurement) =>
      match visual_rect(measurement) {
        Err(error) => Err(error)
        Ok(bounds) =>
          Ok({ id, text, font_size, color, measurement, visual_bounds: bounds, })
      }
  }
}

///|
pub fn NativeText::id(self : NativeText) -> UInt64 {
  self.id
}

///|
pub fn NativeText::text(self : NativeText) -> String {
  self.text
}

///|
pub fn NativeText::font_size(self : NativeText) -> Double {
  self.font_size
}

///|
pub fn NativeText::measurement(
  self : NativeText,
) -> @text_layout.TextMeasurement {
  self.measurement
}

///|
pub fn NativeText::visual_bounds(self : NativeText) -> @primitives.Rect {
  self.visual_bounds
}

///|
pub fn NativeText::intrinsic_size(self : NativeText) -> @primitives.Size {
  self.visual_bounds.size()
}

///|
pub fn NativeText::color(self : NativeText) -> @primitives.Color {
  self.color
}

///|
pub fn NativeText::recolored(
  self : NativeText,
  id : UInt64,
  color : @primitives.Color,
) -> NativeText {
  {
    id,
    text: self.text,
    font_size: self.font_size,
    color,
    measurement: self.measurement,
    visual_bounds: self.visual_bounds,
  }
}

///|
/// Place this text in a container and create an item-local TextRunItem origin.
/// The union of logical and ink rectangles determines the visible bounds, so
/// negative glyph overhangs cannot be clipped at the item's top/left edge.
pub fn NativeText::scene_item(
  self : NativeText,
  container : @primitives.Rect,
  align : TextAlign,
) -> Result[@scene.SceneItem, @diagnostics.FrameworkError] {
  let size = self.intrinsic_size()
  let width = size.width()
  let height = size.height()
  let x = match align {
    Start => container.left()
    Center => container.left() + (container.size().width() - width) / 2.0
    End => container.right() - width
  }
  let y = container.top() + (container.size().height() - height) / 2.0
  match @primitives.Rect::new(x, y, width, height) {
    Err(_) =>
      Err(component_error("NativeText::scene_item", "text bounds are invalid"))
    Ok(bounds) => {
      let logical = self.measurement.logical_rect()
      let ink = self.measurement.ink_rect()
      let visual_left = min(logical.left(), ink.left())
      let visual_top = min(logical.top(), ink.top())
      // GPUI text origins and item bounds share pre-transform scene space.
      // Preserve the origin's absolute placement while shifting negative ink
      // overhangs back inside the union-sized clip rectangle.
      match @primitives.Point::new(x - visual_left, y - visual_top) {
        Err(_) =>
          Err(
            component_error("NativeText::scene_item", "text origin is invalid"),
          )
        Ok(origin) =>
          match
            @scene.SceneItem::text_run(
              self.id,
              bounds,
              origin,
              self.text,
              self.font_size,
              self.color,
              @scene.AffineTransform::identity(),
              1.0,
              None,
            ) {
            Ok(item) => Ok(item)
            Err(_) =>
              Err(
                component_error(
                  "NativeText::scene_item", "scene rejected measured text",
                ),
              )
          }
      }
    }
  }
}

///|
fn visual_rect(
  measurement : @text_layout.TextMeasurement,
) -> Result[@primitives.Rect, @diagnostics.FrameworkError] {
  let logical = measurement.logical_rect()
  let ink = measurement.ink_rect()
  match logical.union(ink) {
    Ok(bounds) => Ok(bounds)
    Err(_) =>
      Err(
        component_error(
          "NativeText::visual_rect", "measurement geometry could not be combined",
        ),
      )
  }
}

///|
fn text_font_size(
  variant : @yami_kumo.TextVariant,
  size : @yami_kumo.ControlSize,
) -> Double? {
  match variant {
    @yami_kumo.Mono | @yami_kumo.MonoSecondary => None
    @yami_kumo.Heading =>
      match size {
        @yami_kumo.Lg => Some(20.0)
        _ => Some(16.0)
      }
    _ =>
      match size {
        @yami_kumo.Xs => Some(12.0)
        @yami_kumo.Sm => Some(13.0)
        @yami_kumo.Base => Some(14.0)
        @yami_kumo.Lg => Some(16.0)
      }
  }
}

///|
fn min(left : Double, right : Double) -> Double {
  if left < right {
    left
  } else {
    right
  }
}

///|
fn component_error(
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
