///|
/// Stable sample element identities shared by the three native host mains.
pub const SAMPLE_ROOT_ID : UInt64 = 1

///|
pub const SAMPLE_HEADER_ID : UInt64 = 2

///|
pub const SAMPLE_MAIN_ID : UInt64 = 3

///|
pub const SAMPLE_CARD_ID : UInt64 = 10

///|
pub const SAMPLE_HEADING_ID : UInt64 = 20

///|
pub const SAMPLE_COUNTER_ID : UInt64 = 30

///|
pub const SAMPLE_BUTTON_ID : UInt64 = 40

///|
pub const SAMPLE_BUTTON_LABEL_ID : UInt64 = 41

///|
const SAMPLE_CARD_WIDTH : Double = 416.0

///|
const SAMPLE_CARD_HEIGHT : Double = 268.0

///|
const SAMPLE_CONTENT_WIDTH : Double = 352.0

///|
const SAMPLE_COUNTER_ROI_WIDTH : Double = 240.0

///|
struct SampleState {
  count : Int
}

///|
/// Shared sample controller. The state update is an App-owned Entity update;
/// input routing, focus and layout remain common across all native hosts.
pub struct NativeSample {
  app : @core.App
  state : @core.Entity[SampleState]
  theme : @components.Theme
  disabled : Bool
  mut interaction : @components.ButtonInteraction?
  mut tree : @element.ElementTree?
}

///|
/// One measured, laid-out and painted frame of the native sample.
pub struct SampleFrame {
  snapshot : @scene.SceneSnapshot
  count : Int
  counter_text : String
  button_bounds : @primitives.Rect
  button_label_bounds : @primitives.Rect
  counter_bounds : @primitives.Rect
  counter_background : @primitives.Color
  button_background : @primitives.Color
  root_bounds : @primitives.Rect
  tree : @element.ElementTree
}

///|
pub fn SampleFrame::snapshot(self : SampleFrame) -> @scene.SceneSnapshot {
  self.snapshot
}

///|
pub fn SampleFrame::count(self : SampleFrame) -> Int {
  self.count
}

///|
pub fn SampleFrame::counter_text(self : SampleFrame) -> String {
  self.counter_text
}

///|
pub fn SampleFrame::button_bounds(self : SampleFrame) -> @primitives.Rect {
  self.button_bounds
}

///|
/// Button interior bounds, excluding its border and horizontal padding.
pub fn SampleFrame::button_label_bounds(self : SampleFrame) -> @primitives.Rect {
  self.button_label_bounds
}

///|
/// Fixed-width counter ROI; it excludes the Button while remaining identical
/// before and after the counter's one-character value change.
pub fn SampleFrame::counter_bounds(self : SampleFrame) -> @primitives.Rect {
  self.counter_bounds
}

///|
pub fn SampleFrame::counter_background(self : SampleFrame) -> @primitives.Color {
  self.counter_background
}

///|
pub fn SampleFrame::button_background(self : SampleFrame) -> @primitives.Color {
  self.button_background
}

///|
pub fn SampleFrame::root_bounds(self : SampleFrame) -> @primitives.Rect {
  self.root_bounds
}

///|
pub fn SampleFrame::canonical_scene(self : SampleFrame) -> String {
  self.snapshot.canonical_json()
}

///|
/// Start the framework App and create state through the ordinary entity model.
pub fn NativeSample::new(
  theme? : @components.Theme = @components.Theme::light(),
  disabled? : Bool = false,
) -> Result[NativeSample, @diagnostics.FrameworkError] {
  match @core.App::new() {
    Err(error) => Err(error)
    Ok(app) =>
      match app.start() {
        Err(error) => Err(error)
        Ok(_) =>
          match app.create_entity(SampleState::{ count: 0, }) {
            Err(error) => Err(error)
            Ok(state) =>
              Ok({ app, state, theme, disabled, interaction: None, tree: None, })
          }
      }
  }
}

///|
pub fn NativeSample::count(
  self : NativeSample,
) -> Result[Int, @diagnostics.FrameworkError] {
  self.app.read(self.state, state => state.count)
}

///|
/// Regenerate the view at the latest window size and measurement provider.
/// This clears old gesture ownership so a resize cannot complete a stale
/// press against newly laid out geometry.
pub fn NativeSample::render(
  self : NativeSample,
  width : Double,
  height : Double,
  scale : Double,
  measure : @components.TextMeasure,
) -> Result[SampleFrame, @diagnostics.FrameworkError] {
  let restore_button_focus = match self.tree {
    None => false
    Some(tree) => tree.focused() == Some(SAMPLE_BUTTON_ID)
  }
  self.cancel_gesture()
  self.tree = None
  self.interaction = None
  if !finite(width) || !finite(height) || width <= 0.0 || height <= 0.0 {
    return Err(
      sample_error(
        "NativeSample::render", "window dimensions must be finite and positive",
      ),
    )
  }
  if !finite(scale) || scale <= 0.0 {
    return Err(
      sample_error(
        "NativeSample::render", "window scale must be finite and positive",
      ),
    )
  }
  let count = match self.count() {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let brand = match
    @components.NativeText::new(
      SAMPLE_HEADER_ID,
      "Yami-kumo",
      @yami_kumo.Heading,
      @yami_kumo.Lg,
      self.theme,
      measure,
    ) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let heading = match
    @components.NativeText::new(
      SAMPLE_HEADING_ID,
      "Native Text and Button",
      @yami_kumo.Heading,
      @yami_kumo.Base,
      self.theme,
      measure,
    ) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let counter_text = "Clicks: \{count}"
  let counter = match
    @components.NativeText::new(
      SAMPLE_COUNTER_ID,
      counter_text,
      @yami_kumo.Heading,
      @yami_kumo.Lg,
      self.theme,
      measure,
    ) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let button = match
    @components.NativeButton::new(
      SAMPLE_BUTTON_ID,
      "Click me",
      @yami_kumo.Primary,
      @yami_kumo.Base,
      self.disabled,
      self.theme,
      measure,
    ) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let viewport_size = match @primitives.Size::new(width, height) {
    Err(_) =>
      return Err(
        sample_error("NativeSample::render", "viewport geometry is invalid"),
      )
    Ok(value) => value
  }
  let viewport = match @primitives.Rect::new(0.0, 0.0, width, height) {
    Err(_) =>
      return Err(
        sample_error("NativeSample::render", "viewport bounds are invalid"),
      )
    Ok(value) => value
  }
  let card_size = match
    @primitives.Size::new(SAMPLE_CARD_WIDTH, SAMPLE_CARD_HEIGHT) {
    Err(_) =>
      return Err(sample_error("NativeSample::render", "Card size is invalid"))
    Ok(value) => value
  }
  let card_width = match @layout.Dimension::points(SAMPLE_CARD_WIDTH) {
    Err(_) =>
      return Err(sample_error("NativeSample::render", "Card width is invalid"))
    Ok(value) => value
  }
  let card_height = match @layout.Dimension::points(SAMPLE_CARD_HEIGHT) {
    Err(_) =>
      return Err(sample_error("NativeSample::render", "Card height is invalid"))
    Ok(value) => value
  }
  let content_width = match @layout.Dimension::points(SAMPLE_CONTENT_WIDTH) {
    Err(_) =>
      return Err(
        sample_error("NativeSample::render", "content width is invalid"),
      )
    Ok(value) => value
  }
  let heading_height = match
    @layout.Dimension::points(heading.intrinsic_size().height()) {
    Err(_) =>
      return Err(
        sample_error("NativeSample::render", "heading height is invalid"),
      )
    Ok(value) => value
  }
  let brand_width = match
    @layout.Dimension::points(brand.intrinsic_size().width()) {
    Err(_) =>
      return Err(
        sample_error("NativeSample::render", "AppShell brand width is invalid"),
      )
    Ok(value) => value
  }
  let brand_height = match
    @layout.Dimension::points(brand.intrinsic_size().height()) {
    Err(_) =>
      return Err(
        sample_error("NativeSample::render", "AppShell brand height is invalid"),
      )
    Ok(value) => value
  }
  let counter_height = match
    @layout.Dimension::points(counter.intrinsic_size().height()) {
    Err(_) =>
      return Err(
        sample_error("NativeSample::render", "counter height is invalid"),
      )
    Ok(value) => value
  }
  let card_item = @layout.FlexItem::new(
    SAMPLE_CARD_ID,
    card_height,
    card_width,
    card_size,
  )
  let brand_item = @layout.FlexItem::new(
    SAMPLE_HEADER_ID,
    brand_height,
    brand_width,
    brand.intrinsic_size(),
  )
  let main_item = @layout.FlexItem::new(
    SAMPLE_MAIN_ID,
    card_height,
    card_width,
    card_size,
  )
  let heading_item = @layout.FlexItem::new(
    SAMPLE_HEADING_ID,
    heading_height,
    content_width,
    heading.intrinsic_size(),
  )
  let counter_width = match
    @layout.Dimension::points(SAMPLE_COUNTER_ROI_WIDTH) {
    Err(_) =>
      return Err(
        sample_error("NativeSample::render", "counter ROI width is invalid"),
      )
    Ok(value) => value
  }
  let counter_size = match
    @primitives.Size::new(
      SAMPLE_COUNTER_ROI_WIDTH,
      counter.intrinsic_size().height(),
    ) {
    Err(_) =>
      return Err(
        sample_error("NativeSample::render", "counter ROI size is invalid"),
      )
    Ok(value) => value
  }
  let counter_item = @layout.FlexItem::new(
    SAMPLE_COUNTER_ID,
    counter_height,
    counter_width,
    counter_size,
  )
  let card_padding = match @layout.Insets::all(32.0) {
    Err(_) =>
      return Err(
        sample_error("NativeSample::render", "Card padding is invalid"),
      )
    Ok(value) => value
  }
  let card_gap = match
    @layout.FlexTreeStyle::new(@layout.FlowDirection::column()).with_gap(18.0) {
    Err(_) =>
      return Err(
        sample_error("NativeSample::render", "Card child gap is invalid"),
      )
    Ok(value) => value
  }
  let card_style = card_gap
    .with_insets(card_padding, @layout.Insets::zero())
    .with_justify(@layout.JustifyContent::center())
    .with_align(@layout.AlignItems::center())
  let main_style = @layout.FlexTreeStyle::new(@layout.FlowDirection::column())
    .with_justify(@layout.JustifyContent::center())
    .with_align(@layout.AlignItems::center())
  let button_item = match button.layout_item(@layout.FlowDirection::column()) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let main_children = [
    @layout.FlexTreeNode::new(card_item, SAMPLE_MAIN_ID).with_children(
      card_style,
    ),
    @layout.FlexTreeNode::new(heading_item, SAMPLE_CARD_ID),
    @layout.FlexTreeNode::new(counter_item, SAMPLE_CARD_ID),
    @layout.FlexTreeNode::new(button_item, SAMPLE_CARD_ID),
  ]
  let shell = @components.NativeAppShell::new(SAMPLE_ROOT_ID, self.theme)
  let layout = match
    shell.layout_tree(
      viewport_size, brand_item, main_item, main_style, main_children, 24.0,
    ) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let header_bounds = match layout_box(layout, SAMPLE_HEADER_ID) {
    None =>
      return Err(
        sample_error("NativeSample::render", "layout omitted AppShell header"),
      )
    Some(value) => value
  }
  let main_bounds = match layout_box(layout, SAMPLE_MAIN_ID) {
    None =>
      return Err(
        sample_error(
          "NativeSample::render", "layout omitted AppShell main slot",
        ),
      )
    Some(value) => value
  }
  let card_bounds = match layout_box(layout, SAMPLE_CARD_ID) {
    None =>
      return Err(
        sample_error("NativeSample::render", "layout omitted the Card"),
      )
    Some(value) => value
  }
  let heading_bounds = match layout_box(layout, SAMPLE_HEADING_ID) {
    None =>
      return Err(
        sample_error("NativeSample::render", "layout omitted the heading"),
      )
    Some(value) => value
  }
  let counter_bounds = match layout_box(layout, SAMPLE_COUNTER_ID) {
    None =>
      return Err(
        sample_error("NativeSample::render", "layout omitted the counter"),
      )
    Some(value) => value
  }
  let button_bounds = match layout_box(layout, SAMPLE_BUTTON_ID) {
    None =>
      return Err(
        sample_error("NativeSample::render", "layout omitted the Button"),
      )
    Some(value) => value
  }
  let button_label_bounds = match button.label_bounds(button_bounds) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let card = @components.NativeCard::new(SAMPLE_CARD_ID, self.theme, true)
  let items : Array[@scene.SceneItem] = []
  match shell.scene_item(viewport) {
    Err(error) => return Err(error)
    Ok(item) => items.push(item)
  }
  match brand.scene_item(header_bounds, @components.Center) {
    Err(error) => return Err(error)
    Ok(item) => items.push(item)
  }
  match card.scene_items(card_bounds) {
    Err(error) => return Err(error)
    Ok(card_items) =>
      for item in card_items {
        items.push(item)
      }
  }
  match heading.scene_item(heading_bounds, @components.Center) {
    Err(error) => return Err(error)
    Ok(item) => items.push(item)
  }
  match counter.scene_item(counter_bounds, @components.Center) {
    Err(error) => return Err(error)
    Ok(item) => items.push(item)
  }
  match button.scene_items(button_bounds) {
    Err(error) => return Err(error)
    Ok(button_items) =>
      for item in button_items {
        items.push(item)
      }
  }
  let snapshot = match
    @scene.SceneSnapshot::new(viewport, scale, [], [], items) {
    Err(_) =>
      return Err(
        sample_error(
          "NativeSample::render", "scene rejected the native sample frame",
        ),
      )
    Ok(value) => value
  }
  let root_node = @element.ElementNode::new(SAMPLE_ROOT_ID, None, viewport).with_pointer_events(
    false,
  )
  let header_node = @element.ElementNode::new(
    SAMPLE_HEADER_ID,
    Some(SAMPLE_ROOT_ID),
    header_bounds,
  ).with_pointer_events(false)
  let main_node = @element.ElementNode::new(
    SAMPLE_MAIN_ID,
    Some(SAMPLE_ROOT_ID),
    main_bounds,
  ).with_pointer_events(false)
  let card_node = @element.ElementNode::new(
    SAMPLE_CARD_ID,
    Some(SAMPLE_MAIN_ID),
    card_bounds,
  ).with_pointer_events(false)
  let heading_node = @element.ElementNode::new(
    SAMPLE_HEADING_ID,
    Some(SAMPLE_CARD_ID),
    heading_bounds,
  ).with_pointer_events(false)
  let counter_node = @element.ElementNode::new(
    SAMPLE_COUNTER_ID,
    Some(SAMPLE_CARD_ID),
    counter_bounds,
  ).with_pointer_events(false)
  let element_nodes = [
    root_node,
    header_node,
    main_node,
    card_node,
    heading_node,
    counter_node,
    button.element_node(button_bounds, Some(SAMPLE_CARD_ID)),
  ]
  let tree = match @element.ElementTree::new(element_nodes) {
    Err(_) =>
      return Err(
        sample_error("NativeSample::render", "element tree rejected the sample"),
      )
    Ok(value) => value
  }
  let tree = if restore_button_focus {
    match tree.with_focus(SAMPLE_BUTTON_ID) {
      Err(_) =>
        return Err(
          sample_error(
            "NativeSample::render", "focused Button could not be restored after rendering",
          ),
        )
      Ok(value) => value
    }
  } else {
    tree
  }
  self.tree = Some(tree)
  self.interaction = Some(button.interaction())
  Ok({
    snapshot,
    count,
    counter_text,
    button_bounds,
    button_label_bounds,
    counter_bounds,
    counter_background: self.theme.elevated(),
    button_background: self.theme
    .button_colors(@yami_kumo.Primary, self.disabled)
    .background(),
    root_bounds: viewport,
    tree,
  })
}

///|
/// Route one platform-neutral input event. A primary pointer gesture activates
/// only when down and up hit the same enabled Button. Key activation follows
/// the same matching-key rule for an explicitly focused Button.
pub fn NativeSample::handle_input(
  self : NativeSample,
  event : @primitives.InputEvent,
) -> Result[Bool, @diagnostics.FrameworkError] {
  let tree = match self.tree {
    None =>
      return Err(
        sample_error(
          "NativeSample::handle_input", "sample has not been rendered",
        ),
      )
    Some(value) => value
  }
  let interaction = match self.interaction {
    None =>
      return Err(
        sample_error(
          "NativeSample::handle_input", "sample Button interaction is not ready",
        ),
      )
    Some(value) => value
  }
  let outcome = match
    tree.dispatch_input_with(event, (_context, _event) => Ok(())) {
    Err(_) =>
      return Err(
        sample_error(
          "NativeSample::handle_input", "element input dispatch failed",
        ),
      )
    Ok(value) => value
  }
  let target = outcome.target()
  match event {
    @primitives.PointerButtonPressed(button~, ..) =>
      if interaction.pointer_down(target, button) {
        match tree.with_focus(SAMPLE_BUTTON_ID) {
          Ok(focused) => self.tree = Some(focused)
          Err(_) =>
            return Err(
              sample_error(
                "NativeSample::handle_input", "enabled Button could not acquire focus",
              ),
            )
        }
      }
    @primitives.PointerButtonReleased(button~, ..) =>
      if interaction.pointer_up(target, button) {
        match self.increment() {
          Err(error) => return Err(error)
          Ok(_) => return Ok(true)
        }
      }
    @primitives.KeyPressed(key~, ..) => interaction.key_down(target, key)
    @primitives.KeyReleased(key~, ..) =>
      if interaction.key_up(target, key) {
        match self.increment() {
          Err(error) => return Err(error)
          Ok(_) => return Ok(true)
        }
      }
    _ => ()
  }
  Ok(false)
}

///|
/// Cancel pointer/key ownership on a native focus loss.
pub fn NativeSample::focus_changed(self : NativeSample, focused : Bool) -> Unit {
  if !focused {
    self.cancel_gesture()
    self.tree = self.tree.map(tree => tree.clear_focus())
  }
}

///|
/// Invalidate active gestures before rebuilding after a resize or scale change.
pub fn NativeSample::invalidate_layout(self : NativeSample) -> Unit {
  self.cancel_gesture()
  self.tree = None
}

///|
pub fn NativeSample::shutdown(
  self : NativeSample,
) -> Result[Unit, @diagnostics.FrameworkError] {
  match self.app.request_stop() {
    Err(error) => Err(error)
    Ok(_) =>
      match self.app.run_ready(64) {
        Err(error) => Err(error)
        Ok(_) => Ok(())
      }
  }
}

///|
fn NativeSample::increment(
  self : NativeSample,
) -> Result[Unit, @diagnostics.FrameworkError] {
  self.app.update(self.state, context => {
    match context.get() {
      Err(error) => Err(error)
      Ok(state) if state.count >= 2147483647 =>
        Err(
          sample_error(
            "NativeSample::increment", "sample click count exhausted",
          ),
        )
      Ok(state) =>
        match context.set({ count: state.count + 1, }) {
          Err(error) => Err(error)
          Ok(_) => context.notify()
        }
    }
  })
}

///|
fn NativeSample::cancel_gesture(self : NativeSample) -> Unit {
  match self.interaction {
    None => ()
    Some(interaction) => interaction.cancel()
  }
}

///|
fn layout_box(
  layout : @layout.FlexTreeLayout,
  id : UInt64,
) -> @primitives.Rect? {
  let mut result : @primitives.Rect? = None
  for item in layout.items() {
    if item.id() == id {
      result = Some(item.bounds())
    }
  }
  result
}

///|
fn finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn sample_error(
  operation : String,
  message : String,
) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    @diagnostics.InvalidInput,
    operation,
    subsystem="native-sample",
    message~,
  )
}
