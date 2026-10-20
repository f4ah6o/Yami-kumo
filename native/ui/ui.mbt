///|
priv struct Epoch {
  mut live : Bool
  mut marker : Bool
}

///|
fn fresh_epoch() -> Epoch {
  { live: true, marker: false, }
}

///|
/// UI-owner-thread only. No callbacks, suspension or user code can run between
/// these marker accesses. Restore both original markers before returning;
/// comparing either live or disposed epochs never changes their liveness.
/// physical_equal is only an optimization hint, not a semantic identity test.
fn same_epoch(left : Epoch, right : Epoch) -> Bool {
  let left_marker = left.marker
  let right_marker = right.marker
  left.marker = !right_marker
  let same = right.marker != right_marker
  left.marker = left_marker
  right.marker = right_marker
  same
}

///|
/// A retained host callback capability. Keys and native IDs alone never grant
/// activation; this capability belongs to one runtime and accepted geometry.
pub struct Activation {
  priv token : @runtime.InstanceToken
  priv epoch : Epoch
}

///|
/// Opaque destination for one asynchronous paste. It binds the requesting
/// field instance and its text revision so a delayed clipboard response cannot
/// land in a different field or a newer edit.
pub struct PasteRequest {
  priv binding : UInt64
  priv token : @runtime.InstanceToken
  priv revision : Int32
  priv generation : UInt64
  priv app_revision : UInt64
}

///|
/// Host clipboard work requested by the focused TextField. `Copy` carries the
/// exact text to write; `Paste` carries the request that `Mounted::paste`
/// must validate.
pub(all) enum ClipboardRequest {
  Copy(String)
  Paste(PasteRequest)
}

///|
priv struct Binding {
  view : @view.View
  id : UInt64
  token : @runtime.InstanceToken?
  text : @components.NativeText?
  button : @button.Button?
  field : @text_field.TextField?
  field_generation : UInt64
  /// Deepest open Dialog that contains this node, or -1 outside every Dialog.
  dialog_level : Int32
  visible : Bool
}

///|
/// One open modal level. `root_id` is the adapter-owned overlay root element and
/// stays stable while the same Dialog key occupies the level, so frame adoption
/// can retain the live session scope. `restore` is the focus observed in the
/// enclosing scope when this level opened; it is the expected focus after this
/// level is removed.
priv struct DialogState {
  key : String
  root_id : UInt64
  panel_id : UInt64
  restore : UInt64?
  dismissible : Bool
  handle : @element.FocusScopeHandle?
}

///|
/// One newly opened Dialog level in the accepted frame.
priv struct DialogOpenPlan {
  root : UInt64
  initial : UInt64
}

///|
/// The modal transition an accepted frame asks the live session to perform.
/// Removals are detected by frame adoption from a missing overlay root; `opens`
/// are applied outermost first. `reconcile` is false when a level was removed,
/// because the session owns the restored acquisition for that frame.
priv struct DialogPlan {
  adopt : UInt64?
  opens : Array[DialogOpenPlan]
  reconcile : Bool
}

///|
priv struct RegionObservation {
  region : @view.ShellRegion
  bounds : @primitives.Rect
}

///|
priv struct Observation {
  binding_id : UInt64
  key : @view.NodeKey
  bounds : @primitives.Rect
  label_bounds : @primitives.Rect?
  pressed : Bool
  focused : Bool
  hovered : Bool
  enabled : Bool
  loading : Bool
  palette : @view.ButtonPaletteToken?
}

///|
/// An immutable observation of a successfully committed native frame.
pub struct Frame {
  priv snapshot : @scene.SceneSnapshot
  priv revision : UInt64
  priv observations : Array[Observation]
  priv theme : @theme.Theme?
  priv shell_mode : @view.ShellMode?
  priv regions : Array[RegionObservation]
}

///|
pub fn Frame::snapshot(self : Frame) -> @scene.SceneSnapshot {
  self.snapshot
}

///|
pub fn Frame::revision(self : Frame) -> UInt64 {
  self.revision
}

///|
/// The accepted root Button theme. Explicit View palettes retain their overrides.
pub fn Frame::theme(self : Frame) -> @theme.Theme? {
  self.theme
}

///|
/// Accepted shell mode, or None for a non-shell root.
pub fn Frame::shell_mode(self : Frame) -> @view.ShellMode? {
  self.shell_mode
}

///|
/// Accepted bounds for one visible shell region. Absent or hidden regions have
/// no observation; callers must not treat that as a zero-sized success.
pub fn Frame::region_bounds(
  self : Frame,
  region : @view.ShellRegion,
) -> @primitives.Rect? {
  for observation in self.regions {
    if observation.region == region {
      return Some(observation.bounds)
    }
  }
  None
}

///|
pub fn Frame::root_bounds(self : Frame) -> @primitives.Rect {
  self.snapshot.viewport()
}

///|
pub fn Frame::bounds(self : Frame, key : @view.NodeKey) -> @primitives.Rect? {
  for observation in self.observations {
    if observation.key == key {
      return Some(observation.bounds)
    }
  }
  None
}

///|
/// Read-only identity observation, not an activation or focus capability.
pub fn Frame::binding_id(self : Frame, key : @view.NodeKey) -> UInt64? {
  for observation in self.observations {
    if observation.key == key {
      return Some(observation.binding_id)
    }
  }
  None
}

///|
pub fn Frame::label_bounds(
  self : Frame,
  key : @view.NodeKey,
) -> @primitives.Rect? {
  for observation in self.observations {
    if observation.key == key {
      return observation.label_bounds
    }
  }
  None
}

///|
pub fn Frame::pressed(self : Frame, key : @view.NodeKey) -> Bool {
  for observation in self.observations {
    if observation.key == key {
      return observation.pressed
    }
  }
  false
}

///|
pub fn Frame::focused(self : Frame, key : @view.NodeKey) -> Bool {
  for observation in self.observations {
    if observation.key == key {
      return observation.focused
    }
  }
  false
}

///|
pub fn Frame::hovered(self : Frame, key : @view.NodeKey) -> Bool {
  for observation in self.observations {
    if observation.key == key {
      return observation.hovered
    }
  }
  false
}

///|
pub fn Frame::enabled(self : Frame, key : @view.NodeKey) -> Bool {
  for observation in self.observations {
    if observation.key == key {
      return observation.enabled
    }
  }
  false
}

///|
pub fn Frame::loading(self : Frame, key : @view.NodeKey) -> Bool {
  for observation in self.observations {
    if observation.key == key {
      return observation.loading
    }
  }
  false
}

///|
pub fn Frame::button_palette(
  self : Frame,
  key : @view.NodeKey,
) -> @view.ButtonPaletteToken? {
  for observation in self.observations {
    if observation.key == key {
      return observation.palette
    }
  }
  None
}

///|
/// One explicit native root/window owner. The common runtime owns semantic
/// incarnation tokens; the adapter privately owns nonzero, never-reused ID
/// blocks. One existing GPUI Button owns each Button's interaction state.
/// All access and capability comparisons are confined to the owning UI thread.
pub struct Mounted {
  priv window : @platform.WindowId
  priv runtime : @runtime.Runtime
  priv mut bindings : Array[Binding]
  priv mut scope : @element.FocusScopeSession?
  priv mut current_frame : Frame?
  priv mut next_id : UInt64
  priv mut revision : UInt64
  priv mut epoch : Epoch
  priv mut change : Epoch
  priv mut last_dispatched_input : Int64
  priv mut last_sequence : Int64
  priv mut window_focused : Bool
  priv mut ready : Bool
  priv mut busy : Bool
  priv mut theme : @theme.Theme?
  priv mut measure : @components.TextMeasure?
  priv mut focus_return : UInt64?
  priv mut clipboard : Array[ClipboardRequest]
  priv mut next_field_generation : UInt64
  priv mut dialogs : Array[DialogState]
  priv mut text_epoch : UInt64
  priv mut last_text_sequence : Int64
}

///|
pub fn Mounted::new(
  window : @platform.WindowId,
  theme~ : @theme.Theme? = None,
) -> Mounted {
  {
    window,
    runtime: @runtime.Runtime::new(),
    bindings: [],
    scope: None,
    current_frame: None,
    next_id: 8,
    revision: 0,
    epoch: fresh_epoch(),
    change: fresh_epoch(),
    last_sequence: 0,
    last_dispatched_input: 0,
    window_focused: true,
    ready: false,
    busy: false,
    theme,
    measure: None,
    focus_return: None,
    clipboard: [],
    next_field_generation: 1UL,
    dialogs: [],
    text_epoch: 0UL,
    last_text_sequence: 0L,
  }
}

///|
/// Requested fallback Button colors. Frame::theme observes the accepted root theme.
pub fn Mounted::theme(self : Mounted) -> @theme.Theme? {
  self.theme
}

///|
/// Request fallback colors for the next commit. Explicit View palettes take
/// precedence; None restores legacy paint for Buttons without an override.
/// Pending gestures and accepted geometry remain valid across paint changes.
pub fn Mounted::set_theme(self : Mounted, theme : @theme.Theme?) -> Bool {
  if self.is_disposed() || self.busy {
    return false
  }
  if self.theme != theme {
    self.theme = theme
    self.change = fresh_epoch()
  }
  true
}

///|
pub fn Mounted::is_disposed(self : Mounted) -> Bool {
  self.runtime.is_disposed()
}

///|
pub fn Mounted::frame(self : Mounted) -> Frame? {
  self.current_frame
}

///|
pub fn Mounted::view(self : Mounted) -> @view.View? {
  self.runtime.view()
}

///|
fn adapter_error(message : String) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    @diagnostics.InvalidInput,
    "shared-native-ui",
    subsystem="shared-native-ui",
    message~,
  )
}

///|
const FIELD_FONT_SIZE : Double = 16.0

///|
const FIELD_LABEL_SIZE : Double = 12.0

///|
const FIELD_MIN_WIDTH : Double = 240.0

///|
const FIELD_HEIGHT : Double = 64.0

///|
fn field_measure(
  measure : @components.TextMeasure,
  document : @text.TextDocument,
) -> Result[@text_layout.TextMeasurement, @text_field.TextFieldError] {
  let measurement = match measure(document.text(), FIELD_FONT_SIZE) {
    Ok(value) => value
    Err(_) => return Err(@text_field.MeasurementFailed)
  }
  if measurement.document().text() != document.text() {
    return Err(@text_field.MeasurementFailed)
  }
  // A host's text measurement may place the final caret partly outside its
  // logical rect. The field contract requires every cursor stop to stay inside
  // the measured line, so widen the logical rect to the caret extent.
  let logical = measurement.logical_rect()
  let mut right = logical.right()
  for caret in measurement.carets() {
    let edge = caret.strong().right()
    if edge > right {
      right = edge
    }
  }
  let widened = if right <= logical.right() {
    logical
  } else {
    match
      @primitives.Rect::new(
        logical.left(),
        logical.top(),
        right - logical.left(),
        logical.size().height(),
      ) {
      Ok(value) => value
      Err(_) => return Err(@text_field.MeasurementFailed)
    }
  }
  match
    @text_layout.TextMeasurement::new(
      document,
      widened,
      measurement.ink_rect(),
      measurement.first_line_baseline(),
      measurement.line_count(),
      measurement.unknown_glyph_count(),
      measurement.carets(),
    ) {
    Ok(value) => Ok(value)
    Err(_) => Err(@text_field.MeasurementFailed)
  }
}

///|
fn field_admit(
  document : @text.TextDocument,
  measurement : @text_layout.TextMeasurement,
) -> Result[Unit, @text_field.TextFieldError] {
  if measurement.document() != document {
    return Err(@text_field.AdmissionFailed)
  }
  match @text_field.scene_text_run_geometry(measurement) {
    Ok(_) => Ok(())
    Err(_) => Err(@text_field.UnsupportedLayout)
  }
}

///|
/// Nearest caret boundary in the measured single line. This is a bounded
/// single-line hit test, not grapheme-aware selection.
fn field_hit(
  measure : @components.TextMeasure,
  document : @text.TextDocument,
  point : @primitives.Point,
) -> Result[@text_layout.TextHit, @text_field.TextFieldError] {
  let measurement = match field_measure(measure, document) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let carets = measurement.carets()
  if carets.length() == 0 {
    return Err(@text_field.HitTestFailed)
  }
  let mut nearest = carets[0].utf16_offset()
  let mut distance = 0.0
  let mut first = true
  for caret in carets {
    if caret.is_cursor_position() {
      let x = caret.strong().left()
      let current = if x >= point.x() { x - point.x() } else { point.x() - x }
      if first || current < distance {
        nearest = caret.utf16_offset()
        distance = current
        first = false
      }
    }
  }
  if first {
    return Err(@text_field.HitTestFailed)
  }
  match @text_layout.TextHit::new(document, nearest, 0, nearest, true, true) {
    Ok(value) => Ok(value)
    Err(_) => Err(@text_field.HitTestFailed)
  }
}

///|
fn field_box(
  bounds : @primitives.Rect,
) -> Result[@primitives.Rect, @diagnostics.FrameworkError] {
  let width = bounds.size().width() - 16.0
  let height = bounds.size().height() - 28.0
  if width < 1.0 || height < FIELD_FONT_SIZE {
    return Err(adapter_error("native TextField bounds are too small"))
  }
  match
    @primitives.Rect::new(
      bounds.left() + 8.0,
      bounds.top() + 24.0,
      width,
      height,
    ) {
    Ok(value) => Ok(value)
    Err(_) => Err(adapter_error("invalid native TextField bounds"))
  }
}

///|
fn create_field(
  measure : @components.TextMeasure,
  id : UInt64,
  bounds : @primitives.Rect,
  value : String,
  focused : Bool,
) -> Result[@text_field.TextField, @text_field.TextFieldError] {
  let document = match @text.TextDocument::new(value) {
    Ok(value) => value
    Err(_) => return Err(@text_field.MalformedText)
  }
  let field = match
    @text_field.TextField::new(
      id,
      bounds,
      FIELD_FONT_SIZE,
      document,
      fn(document) { field_measure(measure, document) },
      field_admit,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  field.with_focus(focused)
}

///|
fn field_editable(view : @view.View) -> Bool {
  match view.text_field_props() {
    Some(props) => !props.disabled() && !props.read_only()
    None => false
  }
}

///|
fn field_error_reason(error : @text_field.TextFieldError) -> String {
  match error {
    @text_field.InvalidFontSize => "font"
    @text_field.InvalidBounds => "bounds"
    @text_field.MalformedText => "text"
    @text_field.ForbiddenInput => "forbidden"
    @text_field.TextTooLarge => "large"
    @text_field.UnsupportedLayout => "layout"
    @text_field.InvalidSelection => "selection"
    @text_field.MeasurementFailed => "measure"
    @text_field.AdmissionFailed => "admit"
    @text_field.HitTestFailed => "hit"
    @text_field.InvalidHitResult => "hit-result"
    @text_field.RevisionExhausted => "revision"
    @text_field.CompositionActive => "composing"
    @text_field.NoComposition => "no-composition"
  }
}

///|
/// Read-only fields keep focus and selection but reject text mutation.
fn field_input_allowed(
  view : @view.View,
  input : @primitives.InputEvent,
) -> Bool {
  if field_editable(view) {
    return true
  }
  // A read-only field keeps selection, caret movement, copy and blur. Every
  // mutation path, including undo/redo and cut/paste shortcuts, stays closed.
  match input {
    @primitives.PointerButtonPressed(..)
    | @primitives.PointerButtonReleased(..)
    | @primitives.Scroll(..) => true
    @primitives.KeyPressed(key=@primitives.ArrowLeft, ..)
    | @primitives.KeyPressed(key=@primitives.ArrowRight, ..)
    | @primitives.KeyPressed(key=@primitives.Home, ..)
    | @primitives.KeyPressed(key=@primitives.End, ..)
    | @primitives.KeyPressed(key=@primitives.Escape, ..) => true
    @primitives.KeyPressed(key=@primitives.Character("a"), modifiers~, ..) =>
      modifiers.control() || modifiers.meta()
    @primitives.KeyPressed(key=@primitives.Character("c"), modifiers~, ..) =>
      modifiers.control() || modifiers.meta()
    _ => false
  }
}

///|
fn element_focusable(tree : @element.ElementTree, id : UInt64) -> Bool {
  match tree.node(id) {
    Some(node) => node.focusable
    None => false
  }
}

///|
fn binding_at_level(
  bindings : Array[Binding],
  id : UInt64,
  level : Int32,
) -> Bool {
  for binding in bindings {
    if binding.id == id {
      return binding.dialog_level == level
    }
  }
  false
}

///|
fn binding_for(bindings : Array[Binding], key : @view.NodeKey) -> Binding? {
  for binding in bindings {
    if binding.view.key() == key {
      return Some(binding)
    }
  }
  None
}

///|
fn flatten(
  view : @view.View,
  nodes : Array[@view.View],
  depth : Int32,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if depth >= 63 {
    return Err(adapter_error("view exceeds native layout depth"))
  }
  if depth > 0 && view.kind() == @view.AppShell {
    return Err(adapter_error("nested AppShell is unsupported"))
  }
  if view.kind() == @view.Dialog && !view.dialog_open() {
    return Ok(())
  }
  if view.key().value().is_empty() {
    return Err(adapter_error("empty view key"))
  }
  if view.is_shell() {
    for child in view.children() {
      match child.shell_region() {
        None => return Err(adapter_error("AppShell child has no region"))
        Some(_) => ()
      }
    }
  }
  for prior in nodes {
    if prior.key() == view.key() {
      return Err(adapter_error("duplicate root-wide view key"))
    }
  }
  nodes.push(view)
  for child in view.children() {
    match flatten(child, nodes, depth + 1) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
fn color(r : Int32, g : Int32, b : Int32) -> @primitives.Color {
  @primitives.Color::rgba(r, g, b, 255).unwrap()
}

///|
fn theme_color(value : @theme.Color) -> @primitives.Color {
  @primitives.Color::rgba(value.red(), value.green(), value.blue(), 255).unwrap()
}

///|
fn palette_color(
  token : @view.ButtonPaletteToken,
  role : @view.ButtonPaintRole,
) -> @primitives.Color {
  let value = token.color(role)
  @primitives.Color::rgba(
    value.red(),
    value.green(),
    value.blue(),
    value.alpha(),
  ).unwrap()
}

///|
fn button_palette(
  token : @view.ButtonPaletteToken,
) -> @button.ButtonPaintPalette {
  @button.ButtonPaintPalette::new(
    normal_border=palette_color(token, @view.NormalBorder),
    focused_border=palette_color(token, @view.FocusedBorder),
    disabled_border=palette_color(token, @view.DisabledBorder),
    normal_fill=palette_color(token, @view.NormalFill),
    hovered_fill=palette_color(token, @view.HoveredFill),
    pressed_fill=palette_color(token, @view.PressedFill),
    loading_fill=palette_color(token, @view.LoadingFill),
    disabled_fill=palette_color(token, @view.DisabledFill),
    enabled_foreground=palette_color(token, @view.EnabledForeground),
    disabled_foreground=palette_color(token, @view.DisabledForeground),
  )
}

///|
fn shell_colors(theme : @theme.Theme?) -> @theme.ShellColors {
  match theme {
    Some(theme) => theme.shell_colors()
    None => @theme.Light.shell_colors()
  }
}

///|
fn mark_visible(
  view : @view.View,
  visible : Bool,
  keys : Map[String, Bool],
) -> Unit {
  keys.set(view.key().value(), visible)
  for child in view.children() {
    mark_visible(child, visible, keys)
  }
}

///|
fn visible_keys(
  view : @view.View,
  mode : @view.ShellMode?,
) -> Map[String, Bool] {
  let keys : Map[String, Bool] = Map([])
  if view.is_shell() {
    mark_visible(view, true, keys)
    let state = view.shell().unwrap()
    let mode = mode.unwrap()
    for child in view.children() {
      let visible = match child.shell_region() {
        Some(region) => region.visible(state, mode)
        None => false
      }
      mark_visible(child, visible, keys)
    }
  } else {
    mark_visible(view, true, keys)
  }
  keys
}

///|
fn style(kind : @view.NodeKind) -> @layout.FlexTreeStyle {
  @layout.FlexTreeStyle::new(
    if kind == @view.Row {
      @layout.FlowDirection::row()
    } else {
      @layout.FlowDirection::column()
    },
  )
  .with_gap(12.0)
  .unwrap()
}

///|
fn make_element(
  view : @view.View,
  bindings : Array[Binding],
) -> @element.Element {
  let binding = binding_for(bindings, view.key()).unwrap()
  let size = if view.kind() == @view.TextField {
    @primitives.Size::new(FIELD_MIN_WIDTH, FIELD_HEIGHT).unwrap()
  } else {
    match binding.text {
      Some(text) => {
        let size = text.intrinsic_size()
        if view.kind() == @view.Button {
          @primitives.Size::new(
            max(24.0, size.width() + 24.0),
            max(32.0, size.height() + 12.0),
          ).unwrap()
        } else {
          size
        }
      }
      None => @primitives.Size::new(0.0, 0.0).unwrap()
    }
  }
  let item = @layout.FlexItem::new(
      binding.id,
      @layout.Dimension::auto(),
      @layout.Dimension::auto(),
      size,
    )
    .with_flex(0.0, 0.0)
    .unwrap()
  let mut element = @element.Element::new(item)
    .with_pointer_events(
      (view.kind() == @view.Button && !view.disabled() && !view.loading()) ||
      (view.kind() == @view.TextField && !view.disabled()),
    )
    .with_focusable(
      (view.kind() == @view.Button && !view.disabled()) ||
      (view.kind() == @view.TextField && !view.disabled()),
    )
    .with_tab_stop(
      (view.kind() == @view.Button && !view.disabled()) ||
      (view.kind() == @view.TextField && !view.disabled()),
    )
  if view.kind() == @view.Column || view.kind() == @view.Row {
    let children_style = if view.is_card() {
      style(view.kind()).with_insets(
        @layout.Insets::all(16.0).unwrap(),
        @layout.Insets::all(1.0).unwrap(),
      )
    } else {
      match view.spacing() {
        Some(spacing) =>
          style(view.kind())
          .with_gap(spacing.gap().pixels())
          .unwrap()
          .with_insets(
            @layout.Insets::all(spacing.padding().pixels()).unwrap(),
            @layout.Insets::zero(),
          )
        None => style(view.kind())
      }
    }
    element = element.with_children_style(children_style)
    for child in view.children() {
      if child.kind() != @view.Dialog {
        element = element.with_child(make_element(child, bindings))
      }
    }
  }
  element
}

///|
fn make_dialog_panel(
  view : @view.View,
  bindings : Array[Binding],
) -> @element.Element {
  let binding = binding_for(bindings, view.key()).unwrap()
  let item = @layout.FlexItem::new(
      binding.id,
      @layout.Dimension::auto(),
      points(420.0),
      @primitives.Size::new(420.0, 0.0).unwrap(),
    )
    .with_flex(0.0, 0.0)
    .unwrap()
  let mut panel = @element.Element::new(item)
    .with_pointer_events(true)
    .with_focusable(false)
    .with_children_style(
      style(@view.Column)
      .with_gap(12.0)
      .unwrap()
      .with_insets(
        @layout.Insets::new(20.0, 20.0, 20.0, 52.0).unwrap(),
        @layout.Insets::zero(),
      ),
    )
  for child in view.children() {
    // Each open Dialog owns its own overlay; a nested Dialog is never laid out
    // inside its parent's panel.
    if child.kind() != @view.Dialog {
      panel = panel.with_child(make_element(child, bindings))
    }
  }
  panel
}

///|
fn points(value : Double) -> @layout.Dimension {
  @layout.Dimension::points(value).unwrap()
}

///|
fn shell_box(
  id : UInt64,
  main : @layout.Dimension,
  cross : @layout.Dimension,
  grow : Double,
) -> @element.Element {
  let size = @primitives.Size::new(0.0, 0.0).unwrap()
  let item = @layout.FlexItem::new(id, main, cross, size)
    .with_flex(grow, 0.0)
    .unwrap()
  @element.Element::new(item).with_pointer_events(false)
}

///|
fn region_view(view : @view.View, region : @view.ShellRegion) -> @view.View? {
  for child in view.children() {
    if child.shell_region() == Some(region) {
      return Some(child)
    }
  }
  None
}

///|
/// Build the bounded shell flex tree. Only regions that are visible in the
/// selected mode are laid out; hidden slot bindings remain in the runtime but
/// have no host element and cannot receive input or focus.
fn make_shell_element(
  view : @view.View,
  bindings : Array[Binding],
  mode : @view.ShellMode,
) -> @element.Element {
  let binding = binding_for(bindings, view.key()).unwrap()
  let base = binding.id
  let state = view.shell().unwrap()
  fn visible(region : @view.ShellRegion) -> Bool {
    region.visible(state, mode)
  }
  fn slot(region : @view.ShellRegion) -> @element.Element? {
    match region_view(view, region) {
      Some(child) => Some(make_element(child, bindings))
      None => None
    }
  }
  let header = shell_box(
    base + 1UL,
    points(60.0),
    @layout.Dimension::auto(),
    0.0,
  ).with_children_style(
    @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
    .with_gap(18.0)
    .unwrap()
    .with_align(@layout.AlignItems::center())
    .with_insets(
      @layout.Insets::new(10.0, 14.0, 10.0, 14.0).unwrap(),
      @layout.Insets::zero(),
    ),
  )
  let brand_group_children : Array[@element.Element] = []
  if visible(@view.NavigationTrigger) {
    let nav = shell_box(
      base + 3UL,
      @layout.Dimension::auto(),
      @layout.Dimension::auto(),
      0.0,
    ).with_children_style(
      @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_align(
        @layout.AlignItems::center(),
      ),
    )
    match slot(@view.NavigationTrigger) {
      Some(child) => brand_group_children.push(nav.with_child(child))
      None => ()
    }
  }
  match slot(@view.Brand) {
    Some(child) => brand_group_children.push(child)
    None => ()
  }
  let brand_group = shell_box(
    base + 2UL,
    @layout.Dimension::auto(),
    @layout.Dimension::auto(),
    0.0,
  ).with_children_style(
    @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
    .with_gap(8.0)
    .unwrap()
    .with_align(@layout.AlignItems::center()),
  )
  let mut brand_group = brand_group
  for child in brand_group_children {
    brand_group = brand_group.with_child(child)
  }
  let header_children : Array[@element.Element] = [brand_group]
  if visible(@view.GlobalSearch) {
    let search = shell_box(
      base + 4UL,
      @layout.Dimension::auto(),
      @layout.Dimension::auto(),
      1.0,
    ).with_children_style(
      @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_align(
        @layout.AlignItems::center(),
      ),
    )
    match slot(@view.GlobalSearch) {
      Some(child) => header_children.push(search.with_child(child))
      None => ()
    }
  }
  let end_children : Array[@element.Element] = []
  if visible(@view.HeaderActions) {
    let actions = shell_box(
      base + 6UL,
      @layout.Dimension::auto(),
      @layout.Dimension::auto(),
      0.0,
    ).with_children_style(
      @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
      .with_gap(8.0)
      .unwrap()
      .with_align(@layout.AlignItems::center()),
    )
    match slot(@view.HeaderActions) {
      Some(child) => end_children.push(actions.with_child(child))
      None => ()
    }
  }
  if visible(@view.AccountMenu) {
    let account = shell_box(
      base + 7UL,
      @layout.Dimension::auto(),
      @layout.Dimension::auto(),
      0.0,
    ).with_children_style(
      @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_align(
        @layout.AlignItems::center(),
      ),
    )
    match slot(@view.AccountMenu) {
      Some(child) => end_children.push(account.with_child(child))
      None => ()
    }
  }
  if end_children.length() > 0 {
    let end = shell_box(
      base + 5UL,
      @layout.Dimension::auto(),
      @layout.Dimension::auto(),
      1.0,
    ).with_children_style(
      @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
      .with_gap(10.0)
      .unwrap()
      .with_justify(@layout.JustifyContent::end())
      .with_align(@layout.AlignItems::center()),
    )
    let mut end = end
    for child in end_children {
      end = end.with_child(child)
    }
    header_children.push(end)
  }
  let mut header = header
  for child in header_children {
    header = header.with_child(child)
  }
  let main_column_children : Array[@element.Element] = []
  if visible(@view.Tabs) {
    let tabs = shell_box(
      base + 12UL,
      points(45.0),
      @layout.Dimension::auto(),
      0.0,
    ).with_children_style(
      @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_align(
        @layout.AlignItems::stretch(),
      ),
    )
    match slot(@view.Tabs) {
      Some(child) => main_column_children.push(tabs.with_child(child))
      None => ()
    }
  }
  let main = shell_box(
    base + 13UL,
    @layout.Dimension::auto(),
    @layout.Dimension::auto(),
    1.0,
  ).with_children_style(
    @layout.FlexTreeStyle::new(@layout.FlowDirection::column())
    .with_align(@layout.AlignItems::stretch())
    .with_insets(@layout.Insets::all(24.0).unwrap(), @layout.Insets::zero()),
  )
  let main = match slot(@view.Main) {
    Some(child) => main.with_child(child)
    None => main
  }
  main_column_children.push(main)
  let main_column = shell_box(
    base + 11UL,
    @layout.Dimension::auto(),
    @layout.Dimension::auto(),
    1.0,
  ).with_children_style(
    @layout.FlexTreeStyle::new(@layout.FlowDirection::column()).with_align(
      @layout.AlignItems::stretch(),
    ),
  )
  let mut main_column = main_column
  for child in main_column_children {
    main_column = main_column.with_child(child)
  }
  let shell_children : Array[@element.Element] = [header]
  if mode == @view.Wide {
    let workspace_children : Array[@element.Element] = []
    if visible(@view.Rail) {
      let rail = shell_box(
        base + 8UL,
        points(58.0),
        @layout.Dimension::auto(),
        0.0,
      ).with_children_style(
        @layout.FlexTreeStyle::new(@layout.FlowDirection::column())
        .with_gap(8.0)
        .unwrap()
        .with_insets(
          @layout.Insets::new(10.0, 8.0, 10.0, 8.0).unwrap(),
          @layout.Insets::zero(),
        ),
      )
      match slot(@view.Rail) {
        Some(child) => workspace_children.push(rail.with_child(child))
        None => ()
      }
    }
    if visible(@view.Sidebar) {
      let sidebar = shell_box(
        base + 9UL,
        points(240.0),
        @layout.Dimension::auto(),
        0.0,
      ).with_children_style(
        @layout.FlexTreeStyle::new(@layout.FlowDirection::column())
        .with_gap(8.0)
        .unwrap()
        .with_insets(
          @layout.Insets::new(14.0, 12.0, 14.0, 12.0).unwrap(),
          @layout.Insets::zero(),
        ),
      )
      match slot(@view.Sidebar) {
        Some(child) => workspace_children.push(sidebar.with_child(child))
        None => ()
      }
    }
    workspace_children.push(main_column)
    if visible(@view.ContextPanel) {
      let context = shell_box(
        base + 14UL,
        points(288.0),
        @layout.Dimension::auto(),
        0.0,
      ).with_children_style(
        @layout.FlexTreeStyle::new(@layout.FlowDirection::column())
        .with_gap(8.0)
        .unwrap()
        .with_insets(
          @layout.Insets::new(14.0, 12.0, 14.0, 12.0).unwrap(),
          @layout.Insets::zero(),
        ),
      )
      match slot(@view.ContextPanel) {
        Some(child) => workspace_children.push(context.with_child(child))
        None => ()
      }
    }
    let workspace = shell_box(
      base + 10UL,
      @layout.Dimension::auto(),
      @layout.Dimension::auto(),
      1.0,
    ).with_children_style(
      @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_align(
        @layout.AlignItems::stretch(),
      ),
    )
    let mut workspace = workspace
    for child in workspace_children {
      workspace = workspace.with_child(child)
    }
    shell_children.push(workspace)
  } else {
    if visible(@view.Sidebar) {
      let sidebar = shell_box(
        base + 9UL,
        points(240.0),
        @layout.Dimension::auto(),
        0.0,
      ).with_children_style(
        @layout.FlexTreeStyle::new(@layout.FlowDirection::column())
        .with_gap(8.0)
        .unwrap()
        .with_insets(
          @layout.Insets::new(14.0, 12.0, 14.0, 12.0).unwrap(),
          @layout.Insets::zero(),
        ),
      )
      match slot(@view.Sidebar) {
        Some(child) => shell_children.push(sidebar.with_child(child))
        None => ()
      }
    }
    let workspace = shell_box(
        base + 10UL,
        @layout.Dimension::auto(),
        @layout.Dimension::auto(),
        1.0,
      )
      .with_children_style(
        @layout.FlexTreeStyle::new(@layout.FlowDirection::column()).with_align(
          @layout.AlignItems::stretch(),
        ),
      )
      .with_child(main_column)
    shell_children.push(workspace)
    if visible(@view.ContextPanel) {
      let context = shell_box(
        base + 14UL,
        points(200.0),
        @layout.Dimension::auto(),
        0.0,
      ).with_children_style(
        @layout.FlexTreeStyle::new(@layout.FlowDirection::column())
        .with_gap(8.0)
        .unwrap()
        .with_insets(
          @layout.Insets::new(14.0, 12.0, 14.0, 12.0).unwrap(),
          @layout.Insets::zero(),
        ),
      )
      match slot(@view.ContextPanel) {
        Some(child) => shell_children.push(context.with_child(child))
        None => ()
      }
    }
  }
  if visible(@view.BottomBar) {
    let bottom = shell_box(
      base + 15UL,
      points(32.0),
      @layout.Dimension::auto(),
      0.0,
    ).with_children_style(
      @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
      .with_align(@layout.AlignItems::center())
      .with_insets(
        @layout.Insets::new(0.0, 12.0, 0.0, 12.0).unwrap(),
        @layout.Insets::zero(),
      ),
    )
    match slot(@view.BottomBar) {
      Some(child) => shell_children.push(bottom.with_child(child))
      None => ()
    }
  }
  let shell = shell_box(
    base,
    @layout.Dimension::auto(),
    @layout.Dimension::auto(),
    1.0,
  ).with_children_style(
    @layout.FlexTreeStyle::new(@layout.FlowDirection::column()).with_align(
      @layout.AlignItems::stretch(),
    ),
  )
  let mut shell = shell
  for child in shell_children {
    shell = shell.with_child(child)
  }
  shell
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
fn scene_rect(
  left : Double,
  top : Double,
  width : Double,
  height : Double,
) -> @primitives.Rect {
  @primitives.Rect::new(left, top, max(0.0, width), max(0.0, height)).unwrap()
}

///|
fn push_quad(
  items : Array[@scene.SceneItem],
  id : UInt64,
  rect : @primitives.Rect,
  fill : @primitives.Color,
) -> Result[Unit, @diagnostics.FrameworkError] {
  match
    @scene.SceneItem::quad(
      id,
      rect,
      fill,
      @scene.AffineTransform::identity(),
      1.0,
      None,
    ) {
    Ok(item) => {
      items.push(item)
      Ok(())
    }
    Err(_) => Err(adapter_error("native shell paint failed"))
  }
}

///|
fn paint_shell(
  items : Array[@scene.SceneItem],
  tree : @element.ElementTree,
  base : UInt64,
  colors : @theme.ShellColors,
) -> Result[Array[RegionObservation], @diagnostics.FrameworkError] {
  let background = theme_color(colors.background)
  let panel = theme_color(colors.panel)
  let subtle = theme_color(colors.subtle)
  let border = theme_color(colors.border)
  let shell_rect = match tree.node(base) {
    Some(node) => node.bounds()
    None => return Err(adapter_error("native shell root has no bounds"))
  }
  match push_quad(items, base + 16UL, shell_rect, background) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match tree.node(base + 1UL) {
    Some(node) => {
      let b = node.bounds()
      match push_quad(items, base + 17UL, b, panel) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      match
        push_quad(
          items,
          base + 23UL,
          scene_rect(b.left(), b.bottom() - 1.0, b.size().width(), 1.0),
          border,
        ) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    }
    None => ()
  }
  match tree.node(base + 8UL) {
    Some(node) => {
      let b = node.bounds()
      match push_quad(items, base + 18UL, b, subtle) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      match
        push_quad(
          items,
          base + 24UL,
          scene_rect(b.right() - 1.0, b.top(), 1.0, b.size().height()),
          border,
        ) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    }
    None => ()
  }
  match tree.node(base + 9UL) {
    Some(node) => {
      let b = node.bounds()
      match push_quad(items, base + 19UL, b, panel) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      match
        push_quad(
          items,
          base + 25UL,
          scene_rect(b.right() - 1.0, b.top(), 1.0, b.size().height()),
          border,
        ) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    }
    None => ()
  }
  match tree.node(base + 13UL) {
    Some(node) =>
      match push_quad(items, base + 20UL, node.bounds(), panel) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    None => ()
  }
  match tree.node(base + 14UL) {
    Some(node) => {
      let b = node.bounds()
      match push_quad(items, base + 21UL, b, subtle) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      match
        push_quad(
          items,
          base + 26UL,
          scene_rect(b.left(), b.top(), 1.0, b.size().height()),
          border,
        ) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    }
    None => ()
  }
  match tree.node(base + 15UL) {
    Some(node) => {
      let b = node.bounds()
      match push_quad(items, base + 22UL, b, subtle) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      match
        push_quad(
          items,
          base + 27UL,
          scene_rect(b.left(), b.top(), b.size().width(), 1.0),
          border,
        ) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    }
    None => ()
  }
  let regions : Array[RegionObservation] = []
  for
    (region, offset) in [
      (@view.Brand, 2UL),
      (@view.NavigationTrigger, 3UL),
      (@view.GlobalSearch, 4UL),
      (@view.HeaderActions, 6UL),
      (@view.AccountMenu, 7UL),
      (@view.Rail, 8UL),
      (@view.Sidebar, 9UL),
      (@view.Tabs, 12UL),
      (@view.Main, 13UL),
      (@view.ContextPanel, 14UL),
      (@view.BottomBar, 15UL),
    ] {
    match tree.node(base + offset) {
      Some(node) => regions.push({ region, bounds: node.bounds(), })
      None => ()
    }
  }
  Ok(regions)
}

///|
priv struct Candidate {
  bindings : Array[Binding]
  tree : @element.ElementTree
  frame : Frame
  next_id : UInt64
  next_field_generation : UInt64
  dialogs : Array[DialogState]
  focused : UInt64?
  plan : DialogPlan
  cancel_pending : Bool
}

///|
/// Collect open Dialogs outermost first. A closed Dialog hides its whole
/// subtree, so an open child of a closed ancestor is not reachable.
fn collect_open_dialogs(view : @view.View, dialogs : Array[@view.View]) -> Unit {
  if view.kind() == @view.Dialog {
    if !view.dialog_open() {
      return
    }
    dialogs.push(view)
  }
  for child in view.children() {
    collect_open_dialogs(child, dialogs)
  }
}

///|
/// Deepest open Dialog containing `key`, or -1 outside every Dialog.
fn dialog_level_for(dialogs : Array[@view.View], key : String) -> Int32 {
  let mut level = -1
  for index in 0..<dialogs.length() {
    if view_contains_key(dialogs[index], key) {
      level = index
    }
  }
  level
}

///|
fn view_contains_key(view : @view.View, key : String) -> Bool {
  if view.key().value() == key {
    return true
  }
  for child in view.children() {
    if view_contains_key(child, key) {
      return true
    }
  }
  false
}

///|
/// First focusable stop that belongs to exactly this Dialog level. Deeper
/// Dialogs own their own stops, so an inner field is never an outer initial.
fn dialog_focus_id(
  dialog : @view.View,
  bindings : Array[Binding],
  level : Int32,
) -> Result[UInt64, @diagnostics.FrameworkError] {
  let props = match dialog.dialog_props() {
    Some(value) => value
    None => return Err(adapter_error("native Dialog has no props"))
  }
  match props.initial_focus() {
    Some(key) => {
      for binding in bindings {
        if binding.dialog_level == level && binding.view.key() == key {
          if binding.view.kind() == @view.Button ||
            binding.view.kind() == @view.TextField {
            if binding.view.disabled() {
              return Err(adapter_error("Dialog initial focus is disabled"))
            }
            return Ok(binding.id)
          }
          return Err(adapter_error("Dialog initial focus is not focusable"))
        }
      }
      Err(adapter_error("Dialog initial focus target is absent"))
    }
    None => {
      for binding in bindings {
        if binding.dialog_level == level &&
          (
            binding.view.kind() == @view.Button ||
            binding.view.kind() == @view.TextField
          ) &&
          !binding.view.disabled() {
          return Ok(binding.id)
        }
      }
      Err(adapter_error("Dialog has no focusable child"))
    }
  }
}

///|
fn Mounted::prepare(
  self : Mounted,
  view : @view.View,
  width : Double,
  height : Double,
  scale : Double,
  measure : @components.TextMeasure,
) -> Result[Candidate, @diagnostics.FrameworkError] {
  let dialog_views : Array[@view.View] = []
  collect_open_dialogs(view, dialog_views)
  if width <= 0.0 || height <= 0.0 || scale <= 0.0 {
    return Err(adapter_error("positive viewport and scale required"))
  }
  if self.revision == 18446744073709551615UL {
    return Err(adapter_error("revision exhausted"))
  }
  let viewport = match @primitives.Rect::new(0.0, 0.0, width, height) {
    Ok(value) => value
    Err(_) => return Err(adapter_error("invalid viewport"))
  }
  let nodes = []
  match flatten(view, nodes, 0) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let is_shell = view.is_shell()
  let mode = if is_shell {
    Some(@view.ShellMode::for_width(width))
  } else {
    None
  }
  let visibility = visible_keys(view, mode)
  let colors = shell_colors(self.theme)
  let text_color = if is_shell {
    theme_color(colors.text)
  } else {
    color(30, 36, 45)
  }
  let bindings : Array[Binding] = []
  let mut next_id = self.next_id
  let mut next_field_generation = self.next_field_generation
  for node in nodes {
    let previous = match binding_for(self.bindings, node.key()) {
      Some(binding) if binding.view.kind() == node.kind() => Some(binding)
      _ => None
    }
    let visible = visibility.get(node.key().value()).unwrap_or(false)
    let id = match previous {
      Some(binding) => binding.id
      None => {
        if next_id > 18446744073709551560UL {
          return Err(adapter_error("native identity space exhausted"))
        }
        let id = next_id
        next_id += if node.kind() == @view.AppShell ||
          node.kind() == @view.Dialog {
          40UL
        } else if node.kind() == @view.TextField {
          24UL
        } else {
          8UL
        }
        id
      }
    }
    let text = if visible &&
      (
        node.kind() == @view.Text ||
        node.kind() == @view.Button ||
        node.kind() == @view.TextField ||
        node.kind() == @view.Dialog
      ) {
      let foreground = if node.kind() == @view.Text ||
        node.kind() == @view.TextField {
        text_color
      } else {
        // Measurement is color-independent; core resolves paint below.
        color(242, 246, 250)
      }
      let size = if node.kind() == @view.TextField {
        FIELD_LABEL_SIZE
      } else if node.kind() == @view.Dialog {
        18.0
      } else {
        16.0
      }
      match
        @components.NativeText::for_button(
          if node.kind() == @view.TextField {
            id + 12UL
          } else {
            id + 3UL
          },
          node.label(),
          size,
          foreground,
          measure,
        ) {
        Err(error) => return Err(error)
        Ok(value) => Some(value)
      }
    } else {
      None
    }
    bindings.push({
      view: node,
      id,
      token: None,
      text,
      button: if visible {
        match previous {
          Some(binding) => binding.button
          None => None
        }
      } else {
        None
      },
      field: if visible {
        match previous {
          Some(binding) => binding.field
          None => None
        }
      } else {
        None
      },
      field_generation: if visible {
        match previous {
          Some(binding) => binding.field_generation
          None => 0UL
        }
      } else {
        0UL
      },
      dialog_level: dialog_level_for(dialog_views, node.key().value()),
      visible,
    })
  }
  let root_style = if view.is_shell() {
    @layout.FlexTreeStyle::new(@layout.FlowDirection::column()).with_align(
      @layout.AlignItems::stretch(),
    )
  } else {
    style(@view.Column).with_insets(
      @layout.Insets::all(24.0).unwrap(),
      @layout.Insets::zero(),
    )
  }
  let mut root = @element.Element::root(1UL, root_style).with_pointer_events(
    false,
  )
  if view.is_shell() {
    root = root.with_child(make_shell_element(view, bindings, mode.unwrap()))
  } else if view.kind() != @view.Dialog {
    root = root.with_child(make_element(view, bindings))
  }
  let requested = match
    root.request_layout_with_device_scale(viewport.size(), scale) {
    Err(_) => return Err(adapter_error("native flex layout failed"))
    Ok(value) => value
  }
  let painted = match requested.prepaint() {
    Err(_) => return Err(adapter_error("native element prepaint failed"))
    Ok(value) => value
  }
  let main_tree = painted.tree()
  let old_focus = match self.scope {
    Some(scope) => scope.focused()
    None => None
  }
  let previous_dialogs = self.dialogs
  let mut common = 0
  while common < previous_dialogs.length() &&
        common < dialog_views.length() &&
        previous_dialogs[common].key == dialog_views[common].key().value() {
    common += 1
  }
  let removal = common < previous_dialogs.length()
  let all_nodes = main_tree.nodes()
  let next_dialogs : Array[DialogState] = []
  let opens : Array[DialogOpenPlan] = []
  for level in 0..<dialog_views.length() {
    let dialog = dialog_views[level]
    let panel = make_dialog_panel(dialog, bindings)
    let retained = level < common
    let root_id = if retained {
      previous_dialogs[level].root_id
    } else {
      let id = next_id
      next_id += 8UL
      id
    }
    let overlay = @element.Element::root(
        root_id,
        @layout.FlexTreeStyle::new(@layout.FlowDirection::column())
        .with_align(@layout.AlignItems::center())
        .with_justify(@layout.JustifyContent::center()),
      )
      .with_pointer_events(true)
      .with_child(panel)
    let dialog_painted = match
      overlay.request_layout_with_device_scale(viewport.size(), scale) {
      Err(_) => return Err(adapter_error("native Dialog layout failed"))
      Ok(requested) =>
        match requested.prepaint() {
          Err(_) => return Err(adapter_error("native Dialog prepaint failed"))
          Ok(value) => value
        }
    }
    for node in dialog_painted.tree().nodes() {
      all_nodes.push(node)
    }
    let initial = match dialog_focus_id(dialog, bindings, level) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    let panel_id = match binding_for(bindings, dialog.key()) {
      Some(binding) => binding.id
      None => return Err(adapter_error("native Dialog binding is absent"))
    }
    next_dialogs.push({
      key: dialog.key().value(),
      root_id,
      panel_id,
      restore: if retained {
        previous_dialogs[level].restore
      } else {
        None
      },
      dismissible: match dialog.dialog_props() {
        Some(props) => props.dismissible()
        None => false
      },
      handle: if retained {
        previous_dialogs[level].handle
      } else {
        None
      },
    })
    if !retained {
      opens.push({ root: root_id, initial, })
    }
  }
  let tree = match @element.ElementTree::new(all_nodes) {
    Err(_) => return Err(adapter_error("native Dialog tree rejected"))
    Ok(value) => value
  }
  // Expected acquisition per level. Retained levels keep a live focus that
  // still belongs to that level; otherwise the level's initial stop wins.
  let level_focus : Array[UInt64?] = []
  let mut enclosing : UInt64? = if common == 0 && previous_dialogs.length() > 0 {
    match previous_dialogs[0].restore {
      Some(id) if element_focusable(tree, id) &&
        binding_at_level(bindings, id, -1) => Some(id)
      _ => None
    }
  } else {
    match old_focus {
      Some(id) if element_focusable(tree, id) &&
        binding_at_level(bindings, id, -1) => Some(id)
      _ => None
    }
  }
  for level in 0..<next_dialogs.length() {
    let retained = level < common
    let initial = match dialog_focus_id(dialog_views[level], bindings, level) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    let expected = if retained {
      match old_focus {
        Some(id) if element_focusable(tree, id) &&
          binding_at_level(bindings, id, level) => Some(id)
        _ => Some(initial)
      }
    } else {
      Some(initial)
    }
    if !retained {
      next_dialogs[level] = { ..next_dialogs[level], restore: enclosing, }
    }
    level_focus.push(expected)
    enclosing = expected
  }
  let top = next_dialogs.length() - 1
  let mut focus : UInt64? = if top < 0 {
    match old_focus {
      Some(id) if element_focusable(tree, id) => Some(id)
      _ => None
    }
  } else {
    level_focus[top]
  }
  if removal && opens.length() == 0 {
    focus = match previous_dialogs[common].restore {
      Some(id) if element_focusable(tree, id) &&
        binding_at_level(bindings, id, common - 1) => Some(id)
      _ => None
    }
  }
  if !self.window_focused {
    focus = None
  }
  let adopt = if removal {
    None
  } else {
    match old_focus {
      Some(id) if element_focusable(tree, id) &&
        (
          previous_dialogs.length() == 0 ||
          binding_at_level(bindings, id, previous_dialogs.length() - 1)
        ) => Some(id)
      _ => None
    }
  }
  let reconcile = !(removal && opens.length() == 0)
  let plan : DialogPlan = { adopt, opens, reconcile, }
  let mut cancel_pending = match self.current_frame {
    Some(frame) =>
      frame.snapshot.viewport() != viewport || frame.snapshot.scale() != scale
    None => !self.ready
  }
  let items = []
  let clip_chains : Array[@scene.ClipChain] = []
  let mut next_clip : Int32 = 1
  let background = if is_shell {
    theme_color(colors.background)
  } else {
    color(245, 247, 250)
  }
  match
    @scene.SceneItem::quad(
      1UL,
      viewport,
      background,
      @scene.AffineTransform::identity(),
      1.0,
      None,
    ) {
    Ok(item) => items.push(item)
    Err(_) => return Err(adapter_error("background scene rejected"))
  }
  let mut regions : Array[RegionObservation] = []
  if is_shell {
    let base = binding_for(bindings, view.key()).unwrap().id
    regions = match paint_shell(items, tree, base, colors) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
  }
  let card_border = if is_shell && self.theme is Some(_) {
    theme_color(colors.border)
  } else {
    color(166, 171, 178)
  }
  let card_fill = if is_shell && self.theme is Some(_) {
    theme_color(colors.panel)
  } else {
    color(245, 247, 250)
  }
  let observations = []
  // Main content first, then each Dialog level in stack order: its backdrop,
  // panel and level-local content. A deeper backdrop therefore covers the
  // entire enclosing level.
  let paint_order : Array[Int32] = []
  for index in 0..<bindings.length() {
    if bindings[index].dialog_level < 0 {
      paint_order.push(index)
    }
  }
  for level in 0..<next_dialogs.length() {
    for index in 0..<bindings.length() {
      if bindings[index].dialog_level == level {
        paint_order.push(index)
      }
    }
  }
  for index in paint_order {
    let binding = bindings[index]
    if binding.visible {
      let bounds = match tree.node(binding.id) {
        Some(node) => node.bounds()
        None => return Err(adapter_error("visible binding has no layout node"))
      }
      if binding.view.kind() == @view.Dialog {
        let level = binding.dialog_level
        let dialog = if level >= 0 && level < next_dialogs.length() {
          next_dialogs[level]
        } else {
          return Err(adapter_error("native Dialog state is absent"))
        }
        match
          @scene.SceneItem::quad(
            dialog.root_id,
            viewport,
            @primitives.Color::rgba(10, 12, 16, 140).unwrap(),
            @scene.AffineTransform::identity(),
            1.0,
            None,
          ) {
          Ok(item) => items.push(item)
          Err(_) => return Err(adapter_error("Dialog backdrop paint failed"))
        }
        let panel_fill = if self.theme is Some(_) {
          theme_color(colors.panel)
        } else {
          color(255, 255, 255)
        }
        let panel_border = if self.theme is Some(_) {
          theme_color(colors.border)
        } else {
          color(166, 171, 178)
        }
        for
          (item_id, rect, fill) in [
            (dialog.panel_id, bounds, panel_border),
            (
              dialog.panel_id + 1UL,
              @primitives.Rect::new(
                bounds.left() + 1.0,
                bounds.top() + 1.0,
                bounds.size().width() - 2.0,
                bounds.size().height() - 2.0,
              ).unwrap(),
              panel_fill,
            ),
          ] {
          match
            @scene.SceneItem::quad(
              item_id,
              rect,
              fill,
              @scene.AffineTransform::identity(),
              1.0,
              None,
            ) {
            Ok(item) => items.push(item)
            Err(_) => return Err(adapter_error("Dialog panel paint failed"))
          }
        }
      }
      if binding.view.is_card() {
        // Flat bindings are preorder: paint both Card quads before descendants.
        let inner = @primitives.Rect::new(
          bounds.left() + 1.0,
          bounds.top() + 1.0,
          bounds.size().width() - 2.0,
          bounds.size().height() - 2.0,
        ).unwrap()
        for
          (id, rect, fill) in [
            (binding.id + 1UL, bounds, card_border),
            (binding.id + 2UL, inner, card_fill),
          ] {
          match
            @scene.SceneItem::quad(
              id,
              rect,
              fill,
              @scene.AffineTransform::identity(),
              1.0,
              None,
            ) {
            Ok(item) => items.push(item)
            Err(_) => return Err(adapter_error("native Card paint failed"))
          }
        }
      }
      let mut field = binding.field
      let mut field_generation = binding.field_generation
      if binding.view.kind() == @view.TextField {
        let props = binding.view.text_field_props().unwrap()
        let content = match field_box(bounds) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        let focused = focus == Some(binding.id)
        let model = match binding.field {
          Some(old) if old.is_composing() ||
            old.document().text() == props.value() => old.with_bounds(content)
          _ => {
            let generation = next_field_generation
            next_field_generation += 1UL
            field_generation = generation
            create_field(measure, binding.id, content, props.value(), focused)
          }
        }
        let mut model = match model {
          Ok(value) => value
          Err(error) =>
            return Err(
              adapter_error(
                "native TextField model rejected: " + field_error_reason(error),
              ),
            )
        }
        model = match model.with_focus(focused) {
          Ok(value) => value
          Err(_) => return Err(adapter_error("native TextField focus rejected"))
        }
        match model.paint_items(binding.id, next_clip) {
          Ok((clip, painted)) => {
            clip_chains.push(clip)
            next_clip += 1
            for item in painted {
              items.push(item)
            }
          }
          Err(_) => return Err(adapter_error("native TextField paint failed"))
        }
        field = Some(model)
      }
      let mut button = binding.button
      let mut text = binding.text
      if binding.view.kind() == @view.Button {
        let previous = binding.button
        let model = match previous {
          Some(old) if old.label() == binding.view.label() =>
            old.with_bounds(bounds)
          _ => @button.Button::new(binding.id, bounds, binding.view.label())
        }
        let mut model = match model {
          Err(_) =>
            return Err(
              adapter_error(
                "native Button requires bounds of at least 24 by 24",
              ),
            )
          Ok(value) => value
        }
        match previous {
          Some(old) =>
            if old.bounds() != bounds ||
              old.label() != binding.view.label() ||
              old.is_enabled() == binding.view.disabled() ||
              old.is_loading() != binding.view.loading() {
              cancel_pending = true
            }
          None => ()
        }
        model = model
          .with_enabled(!binding.view.disabled())
          .with_loading(binding.view.loading())
          .with_focus(focus == Some(binding.id))
        if !self.ready ||
          (match self.current_frame {
            Some(frame) =>
              frame.snapshot.viewport() != viewport ||
              frame.snapshot.scale() != scale
            None => true
          }) {
          model = model.cancel_press()
        }
        let palette = match binding.view.button_palette() {
          Some(token) => Some(token)
          None =>
            self.theme.map(theme => {
              match theme {
                @theme.Light => @view.Light
                @theme.Dark => @view.Dark
              }
            })
        }
        let painted_button = match palette {
          None => model.paint_items(binding.id + 1UL)
          Some(token) =>
            model.paint_items_with_palette(
              binding.id + 1UL,
              button_palette(token),
            )
        }
        let paint = match painted_button {
          Ok(value) => value
          Err(_) => return Err(adapter_error("native Button paint failed"))
        }
        // Reuse GPUI border/fill, replacing only its unmeasured label with the
        // existing NativeText path and the host's actual measurement callback.
        items.push(paint[0])
        items.push(paint[1])
        // GPUI owns foreground precedence too; choosing it here from View flags
        // would diverge from the controller when states overlap.
        match paint[2] {
          @scene.TextItem(color~, ..) =>
            text = text.map(text => text.recolored(text.id(), color))
          _ =>
            return Err(adapter_error("native Button label paint is not text"))
        }
        button = Some(model)
      }
      match text {
        Some(text) => {
          let align = if binding.view.kind() == @view.Button {
            @components.Center
          } else {
            @components.Start
          }
          let text_box = if binding.view.kind() == @view.Dialog {
            @primitives.Rect::new(
              bounds.left() + 20.0,
              bounds.top() + 16.0,
              bounds.size().width() - 40.0,
              26.0,
            ).unwrap()
          } else if binding.view.kind() == @view.TextField {
            @primitives.Rect::new(
              bounds.left(),
              bounds.top(),
              bounds.size().width(),
              20.0,
            ).unwrap()
          } else {
            bounds
          }
          match text.scene_item(text_box, align) {
            Err(error) => return Err(error)
            Ok(item) => items.push(item)
          }
        }
        None => ()
      }
      let label_bounds = binding.text.map(text => {
        let size = text.intrinsic_size()
        let x = if binding.view.kind() == @view.Button {
          bounds.left() + (bounds.size().width() - size.width()) / 2.0
        } else {
          bounds.left()
        }
        let y = if binding.view.kind() == @view.TextField ||
          binding.view.kind() == @view.Dialog {
          if binding.view.kind() == @view.Dialog {
            bounds.top() + 16.0
          } else {
            bounds.top()
          }
        } else {
          bounds.top() + (bounds.size().height() - size.height()) / 2.0
        }
        @primitives.Rect::new(x, y, size.width(), size.height()).unwrap()
      })
      observations.push({
        binding_id: binding.id,
        key: binding.view.key(),
        bounds,
        label_bounds,
        pressed: button.map(model => model.is_pressed()).unwrap_or(false),
        focused: field
        .map(model => model.is_focused())
        .unwrap_or(button.map(model => model.is_focused()).unwrap_or(false)),
        hovered: button.map(model => model.is_hovered()).unwrap_or(false),
        enabled: if binding.view.kind() == @view.TextField {
          !binding.view.disabled()
        } else {
          button.map(model => model.is_enabled()).unwrap_or(false)
        },
        loading: button.map(model => model.is_loading()).unwrap_or(false),
        palette: binding.view.button_palette(),
      })
      bindings[index] = { ..binding, button, text, field, field_generation, }
    } else {
      bindings[index] = {
        ..binding,
        button: None,
        text: None,
        field: None,
        field_generation: 0UL,
      }
    }
  }
  let snapshot = match
    @scene.SceneSnapshot::new(viewport, scale, [], clip_chains, items) {
    Err(_) => return Err(adapter_error("native scene validation failed"))
    Ok(value) => value
  }
  Ok({
    bindings,
    tree,
    next_id,
    next_field_generation,
    dialogs: next_dialogs,
    focused: focus,
    plan,
    cancel_pending,
    frame: {
      snapshot,
      revision: self.revision + 1UL,
      observations,
      theme: self.theme,
      shell_mode: mode,
      regions,
    },
  })
}

///|
/// Opaque, single-publication candidate, bound to one exact owner state.
/// All host-fallible work is complete; callers may update their App Entity
/// before publishing, provided they do not mutate this mount in between.
pub struct Prepared {
  priv view : @view.View
  priv candidate : Candidate
  priv change : Epoch
  priv measure : @components.TextMeasure
}

///|
pub fn Mounted::stage(
  self : Mounted,
  view : @view.View,
  width : Double,
  height : Double,
  scale : Double,
  measure : @components.TextMeasure,
) -> Result[Prepared, @diagnostics.FrameworkError] {
  if self.is_disposed() || self.busy {
    return Err(adapter_error("disposed or reentrant native staging"))
  }
  let change = self.change
  self.busy = true
  let prepared = self.prepare(view, width, height, scale, measure)
  self.busy = false
  let candidate = match prepared {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  // Measurement is caller code and can dispose/invalidate this root.
  if self.is_disposed() || !same_epoch(change, self.change) {
    return Err(adapter_error("native root changed during preparation"))
  }
  Ok({ view, candidate, change, measure, })
}

///|
/// Adopt the rebuilt tree, then open the new Dialog suffix outermost first.
/// Frame adoption owns removals: a missing overlay root revokes that suffix and
/// restores once, so this only re-opens levels the target view added.
fn Mounted::apply_dialog_plan(
  self : Mounted,
  scope : @element.FocusScopeSession,
  tree : @element.ElementTree,
  plan : DialogPlan,
) -> Result[Array[@element.FocusScopeHandle], @diagnostics.FrameworkError] {
  let hook : (@element.FocusScopeBoundary) -> Result[
    Unit,
    @element.FocusScopeError,
  ] = boundary => self.cancel_interactions(boundary)
  match scope.adopt_tree(scope.target(), tree, plan.adopt, hook) {
    Err(_) => return Err(adapter_error("native focus scope publication failed"))
    Ok(_) => ()
  }
  let handles : Array[@element.FocusScopeHandle] = []
  for open in plan.opens {
    match
      scope.open_scope(scope.target(), open.root, hook, initial=open.initial) {
      Err(_) => {
        // A partial publication would leave scopes the owner never received.
        // Revoke the whole newly opened suffix before reporting failure.
        if handles.length() > 0 {
          ignore(scope.close_scope(scope.target(), handles[0], hook))
        }
        return Err(adapter_error("native Dialog scope open failed"))
      }
      Ok(handle) => handles.push(handle)
    }
  }
  Ok(handles)
}

///|
/// Publish the staged runtime and accepted host geometry together. Rejected
/// foreign, reused or stale preparations leave both unchanged. No fallible
/// layout/measurement/scene work runs after the common runtime commit.
pub fn Mounted::publish(
  self : Mounted,
  prepared : Prepared,
) -> Result[Frame, @diagnostics.FrameworkError] {
  if self.is_disposed() ||
    self.busy ||
    !same_epoch(prepared.change, self.change) {
    return Err(adapter_error("stale, foreign or disposed native preparation"))
  }
  match self.runtime.commit(prepared.view) {
    Err(_) => return Err(adapter_error("common view commit rejected"))
    Ok(_) => ()
  }
  let candidate = prepared.candidate
  if candidate.cancel_pending {
    self.cancel_pending()
  }
  let tree = candidate.tree
  let scope = match self.scope {
    Some(value) => value
    None => {
      let created = match @element.FocusScopeSession::new(tree) {
        Err(_) => {
          self.ready = false
          return Err(adapter_error("native focus scope rejected"))
        }
        Ok(value) => value
      }
      self.scope = Some(created)
      created
    }
  }
  let scopes_before = scope.scope_count()
  let handles = match self.apply_dialog_plan(scope, tree, candidate.plan) {
    Err(error) => {
      self.ready = false
      return Err(error)
    }
    Ok(value) => value
  }
  let revoked = scope.scope_count() < scopes_before
  // New levels are the tail of the stack and are opened outermost first.
  let first_open = candidate.dialogs.length() - handles.length()
  for index in 0..<handles.length() {
    let level = first_open + index
    candidate.dialogs[level] = {
      ..candidate.dialogs[level],
      handle: Some(handles[index]),
    }
  }
  // A frame that adopted a live scope removal already restored exactly once
  // inside the session and stays as is. Every other frame, including a removal
  // whose scope was closed earlier (for example by Escape), reconciles to the
  // painted acquisition.
  if (candidate.plan.reconcile || !revoked) &&
    scope.focused() != candidate.focused {
    let reconciled = match candidate.focused {
      Some(id) => scope.request_focus(scope.target(), id)
      None => scope.clear_focus(scope.target())
    }
    match reconciled {
      Err(_) => {
        self.ready = false
        return Err(adapter_error("native focus scope reconciliation failed"))
      }
      Ok(_) => ()
    }
  }
  if !self.window_focused {
    match scope.clear_focus(scope.target()) {
      Err(_) => {
        self.ready = false
        return Err(adapter_error("native focus scope blur failed"))
      }
      Ok(_) => ()
    }
  }
  for index = 0; index < candidate.bindings.length(); index = index + 1 {
    let binding = candidate.bindings[index]
    candidate.bindings[index] = {
      ..binding,
      token: self.runtime.token(binding.view.key()),
    }
  }
  self.bindings = candidate.bindings
  self.scope = Some(scope)
  self.measure = Some(prepared.measure)
  self.dialogs = candidate.dialogs
  let focused_now = scope.focused()
  let observations = []
  for observation in candidate.frame.observations {
    observations.push({
      ..observation,
      focused: focused_now == Some(observation.binding_id),
    })
  }
  let frame = { ..candidate.frame, observations, }
  self.current_frame = Some(frame)
  self.next_id = candidate.next_id
  self.next_field_generation = candidate.next_field_generation
  self.revision = frame.revision
  self.ready = true
  self.change = fresh_epoch()
  self.sync_focus()
  Ok(frame)
}

///|
/// Rejected updates leave the old runtime, geometry and presses untouched.
pub fn Mounted::commit(
  self : Mounted,
  view : @view.View,
  width : Double,
  height : Double,
  scale : Double,
  measure : @components.TextMeasure,
) -> Result[Frame, @diagnostics.FrameworkError] {
  match self.stage(view, width, height, scale, measure) {
    Err(error) => Err(error)
    Ok(prepared) => self.publish(prepared)
  }
}

///|
fn Mounted::cancel_pending(self : Mounted) -> Unit {
  self.epoch.live = false
  self.epoch = fresh_epoch()
  while self.runtime.next_action() is Some(_) {

  }
}

///|
fn Mounted::sync_focus(self : Mounted) -> Unit {
  let focused_id = match self.scope {
    Some(scope) => scope.focused()
    None => None
  }
  for index = 0; index < self.bindings.length(); index = index + 1 {
    let binding = self.bindings[index]
    let focused = focused_id == Some(binding.id)
    match binding.button {
      Some(button) =>
        self.bindings[index] = {
          ..binding,
          button: Some(button.with_focus(focused)),
        }
      None => ()
    }
    match binding.field {
      Some(field) =>
        match field.with_focus(focused) {
          Ok(value) => self.bindings[index] = { ..binding, field: Some(value), }
          Err(_) => ()
        }
      None => ()
    }
  }
}

///|
/// A resize/scale event makes old geometry unusable until a successful commit.
pub fn Mounted::invalidate_layout(self : Mounted) -> Unit {
  self.change = fresh_epoch()
  self.cancel_pending()
  for index in 0..<self.bindings.length() {
    let binding = self.bindings[index]
    self.bindings[index] = {
      ..binding,
      button: binding.button.map(button => button.cancel_press()),
    }
  }
  self.ready = false
  self.current_frame = None
}

///|
/// A background binding is frozen under an open Dialog stack; only the
/// innermost level admits semantic actions, focus and controller input.
fn Mounted::admits_binding(self : Mounted, binding : Binding) -> Bool {
  self.dialogs.length() == 0 ||
  binding.dialog_level == self.dialogs.length() - 1
}

///|
pub fn Mounted::callback(self : Mounted, key : @view.NodeKey) -> Activation? {
  if !self.ready || self.is_disposed() {
    return None
  }
  match binding_for(self.bindings, key) {
    Some(binding) if binding.visible =>
      if !self.admits_binding(binding) {
        return None
      }
    _ => return None
  }
  match self.current_frame {
    Some(frame) =>
      if frame.shell_mode() is Some(_) && frame.bounds(key) is None {
        return None
      }
    None => return None
  }
  self.runtime.token(key).map(token => { token, epoch: self.epoch, })
}

///|
pub fn Mounted::activate(self : Mounted, callback : Activation) -> Bool {
  if self.busy ||
    !self.ready ||
    !self.window_focused ||
    !callback.epoch.live ||
    !same_epoch(callback.epoch, self.epoch) {
    return false
  }
  match binding_for(self.bindings, callback.token.key()) {
    Some(binding) => if !self.admits_binding(binding) { return false }
    None => return false
  }
  match self.current_frame {
    Some(frame) =>
      if frame.shell_mode() is Some(_) &&
        frame.bounds(callback.token.key()) is None {
        return false
      }
    None => return false
  }
  self.runtime.enqueue_activate(callback.token)
}

///|
pub fn Mounted::next_action(self : Mounted) -> @view.SemanticAction? {
  if self.busy || !self.ready || !self.window_focused {
    return None
  }
  let shell = match self.current_frame {
    Some(frame) => frame.shell_mode() is Some(_)
    None => false
  }
  while self.runtime.next_action() is Some(action) {
    let key = match action {
      @view.Activate(key) => key
      @view.TextChanged(key, _) => key
      @view.Submitted(key) => key
      @view.Dismissed(key) => key
      @view.Confirmed(key) => key
    }
    let visible = match self.current_frame {
      Some(frame) => frame.bounds(key) is Some(_)
      None => false
    }
    let allowed = match binding_for(self.bindings, key) {
      Some(binding) => self.admits_binding(binding)
      None => false
    }
    if visible && allowed && (!shell || self.current_frame is Some(_)) {
      return Some(action)
    }
  }
  None
}

///|
pub fn Mounted::focus(self : Mounted, key : @view.NodeKey) -> Bool {
  if self.busy || !self.ready || !self.window_focused {
    return false
  }
  let binding = match binding_for(self.bindings, key) {
    None => return false
    Some(value) => if value.visible { value } else { return false }
  }
  if !self.admits_binding(binding) {
    return false
  }
  match self.current_frame {
    Some(frame) =>
      if frame.shell_mode() is Some(_) && frame.bounds(key) is None {
        return false
      }
    None => return false
  }
  let token = match binding.token {
    None => return false
    Some(value) => value
  }
  let request = match self.runtime.request_focus(token) {
    Err(_) => return false
    Ok(value) => value
  }
  let scope = match self.scope {
    None => return false
    Some(value) => value
  }
  let previous = scope.focused()
  let outcome = match scope.request_focus(scope.target(), binding.id) {
    Err(_) => @view.Rejected
    Ok(_) => {
      if previous != Some(binding.id) {
        self.focus_return = previous
      }
      self.sync_focus()
      self.change = fresh_epoch()
      @view.Focused
    }
  }
  ignore(self.runtime.complete_focus(request, outcome))
  outcome == @view.Focused
}

///|
/// Drain one clipboard request without calling the OS.
pub fn Mounted::next_clipboard(self : Mounted) -> ClipboardRequest? {
  if self.clipboard.length() == 0 {
    return None
  }
  Some(self.clipboard.remove(0))
}

///|
/// Apply host clipboard text to the exact field that requested it. The request
/// is rejected when the field instance, focus, or text revision moved while the
/// host was reading its clipboard.
pub fn Mounted::paste(
  self : Mounted,
  request : PasteRequest,
  text : String,
) -> Bool {
  if !self.ready || self.is_disposed() || text.length() == 0 {
    return false
  }
  let measure = match self.measure {
    Some(value) => value
    None => return false
  }
  let focused = match self.scope {
    Some(scope) => scope.focused()
    None => return false
  }
  let mut found : Binding? = None
  let mut found_index = -1
  for index in 0..<self.bindings.length() {
    if self.bindings[index].id == request.binding {
      found = Some(self.bindings[index])
      found_index = index
    }
  }
  let binding = match found {
    Some(value) => value
    None => return false
  }
  match binding.token {
    Some(token) if token == request.token => ()
    _ => return false
  }
  if focused != Some(binding.id) ||
    !field_editable(binding.view) ||
    binding.field_generation != request.generation {
    return false
  }
  match binding.view.text_field_props() {
    Some(props) if props.revision() == request.app_revision => ()
    _ => return false
  }
  let field = match binding.field {
    Some(value) => value
    None => return false
  }
  if field.revision() != request.revision {
    return false
  }
  let next = match
    field.replace_selection(
      text,
      fn(document) { field_measure(measure, document) },
      field_admit,
    ) {
    Ok(value) => value
    Err(_) => return false
  }
  if next.document().text() != field.document().text() {
    match binding.token {
      Some(token) =>
        ignore(self.runtime.enqueue_text_changed(token, next.document().text()))
      None => ()
    }
  }
  if found_index >= 0 {
    self.bindings[found_index] = { ..binding, field: Some(next), }
  }
  true
}

///|
/// Absolute logical caret rectangle for the focused or named TextField. Hosts
/// use this for candidate-window placement; no platform call is made here.
pub fn Mounted::text_caret(
  self : Mounted,
  key : @view.NodeKey,
) -> @primitives.Rect? {
  if !self.ready || self.is_disposed() {
    return None
  }
  let binding = match binding_for(self.bindings, key) {
    Some(value) => value
    None => return None
  }
  match binding.field {
    Some(field) =>
      match field.caret_rect() {
        Ok(value) => Some(value)
        Err(_) => None
      }
    None => None
  }
}

///|
pub fn Mounted::next_focus_result(self : Mounted) -> @runtime.FocusResult? {
  self.runtime.next_focus_result()
}

///|
fn subtree_removed(
  tree : @element.ElementTree,
  roots : Array[UInt64],
  id : UInt64,
) -> Bool {
  let mut current = Some(id)
  while current is Some(value) {
    if roots.contains(value) {
      return true
    }
    current = match tree.node(value) {
      Some(node) => node.parent
      None => None
    }
  }
  false
}

///|
/// Synchronous cancellation for a scope transition. It runs under the session
/// reentrancy guard, so it cancels owned controllers and never re-enters the
/// session; the previous authoritative snapshot stays readable.
fn Mounted::cancel_interactions(
  self : Mounted,
  boundary : @element.FocusScopeBoundary,
) -> Result[Unit, @element.FocusScopeError] {
  self.cancel_pending()
  let removed = boundary.removed_roots()
  if removed.length() == 0 {
    return Ok(())
  }
  let scope = match self.scope {
    Some(value) => value
    None => return Ok(())
  }
  let tree = scope.snapshot()
  let measure = self.measure
  for index = 0; index < self.bindings.length(); index = index + 1 {
    let binding = self.bindings[index]
    if !subtree_removed(tree, removed, binding.id) {
      continue
    }
    match binding.button {
      Some(button) =>
        self.bindings[index] = {
          ..binding,
          button: Some(button.cancel_press()),
        }
      None => ()
    }
    match binding.field {
      Some(field) if field.is_composing() => {
        let measure = match measure {
          Some(value) => value
          None => return Err(@element.InteractionBoundaryRejected)
        }
        let next = match
          field.cancel_composition(
            fn(document) { field_measure(measure, document) },
            field_admit,
          ) {
          Ok(value) => value
          Err(_) => return Err(@element.InteractionBoundaryRejected)
        }
        self.bindings[index] = { ..binding, field: Some(next), }
      }
      _ => ()
    }
  }
  let mut index = 0
  while index < self.clipboard.length() {
    let drop = match self.clipboard[index] {
      Copy(_) => false
      Paste(value) => subtree_removed(tree, removed, value.binding)
    }
    if drop {
      ignore(self.clipboard.remove(index))
    } else {
      index += 1
    }
  }
  Ok(())
}

///|
/// Route one input record through the live scope. The callback only observes the
/// admitted target: a dispatch callback runs under the session guard, so focus
/// acquisition and any other mutation happen after it returns.
fn Mounted::route(
  self : Mounted,
  input : @primitives.InputEvent,
) -> Result[UInt64?, @diagnostics.FrameworkError] {
  let scope = match self.scope {
    Some(value) => value
    None => return Ok(None)
  }
  let admitted : Ref[UInt64?] = Ref(None)
  let outcome = scope.dispatch_input_with(scope.target(), input, (
    context,
    _event,
  ) => {
    admitted.val = Some(context.target())
    context.stop_propagation()
    Ok(())
  })
  match outcome {
    Err(_) => Err(adapter_error("native focus-scope input admission failed"))
    Ok(_) => Ok(admitted.val)
  }
}

///|
fn Mounted::close_dialog(
  self : Mounted,
  level : Int32,
  key : @primitives.Key?,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if level < 0 || level >= self.dialogs.length() {
    return Ok(())
  }
  let dialog = self.dialogs[level]
  let scope = match self.scope {
    Some(value) => value
    None => return Ok(())
  }
  let handle = match dialog.handle {
    Some(value) => value
    None => return Ok(())
  }
  let hook : (@element.FocusScopeBoundary) -> Result[
    Unit,
    @element.FocusScopeError,
  ] = boundary => self.cancel_interactions(boundary)
  // Closing an outer level revokes every deeper level in the session suffix.
  let closed = match key {
    Some(value) =>
      scope.close_scope(scope.target(), handle, hook, dismissal_key=value)
    None => scope.close_scope(scope.target(), handle, hook)
  }
  match closed {
    Ok(_) => ()
    Err(@element.StaleHandle) => ()
    Err(_) => return Err(adapter_error("native Dialog scope close failed"))
  }
  self.sync_focus()
  Ok(())
}

///|
/// Close one level and report exactly that Dialog as dismissed. A deeper level
/// revoked by the same close is removed silently.
fn Mounted::dismiss_dialog(
  self : Mounted,
  level : Int32,
  key : @primitives.Key?,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if level < 0 || level >= self.dialogs.length() {
    return Ok(())
  }
  let dialog = self.dialogs[level]
  match self.close_dialog(level, key) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match binding_for(self.bindings, @view.NodeKey::new(dialog.key)) {
    Some(binding) =>
      match binding.token {
        Some(token) => ignore(self.runtime.enqueue_dismissed(token))
        None => ()
      }
    None => ()
  }
  Ok(())
}

///|
/// Input dispatch only queues actions. It never enters the application model.
/// Strict ordering is per owned window; foreign events cannot consume sequence.
pub fn Mounted::handle_event(
  self : Mounted,
  event : @platform.Event,
) -> Result[Bool, @diagnostics.FrameworkError] {
  if self.is_disposed() ||
    self.busy ||
    event.window() != self.window ||
    event.sequence() <= self.last_sequence ||
    event.sequence() <= 0L {
    return Ok(false)
  }
  self.last_sequence = event.sequence()
  self.change = fresh_epoch()
  match event.kind() {
    @platform.Destroyed | @platform.CloseRequested | @platform.ExitRequested => {
      self.dispose()
      Ok(true)
    }
    @platform.Resized(..) | @platform.ScaleChanged => {
      self.invalidate_layout()
      Ok(true)
    }
    @platform.FocusChanged(focused) => {
      self.window_focused = focused
      if !focused {
        self.cancel_pending()
        match self.scope {
          Some(scope) => ignore(scope.clear_focus(scope.target()))
          None => ()
        }
        self.sync_focus()
      }
      Ok(true)
    }
    @platform.VisibilityChanged(false) => {
      self.invalidate_layout()
      Ok(true)
    }
    @platform.Composition(composition) => {
      if !self.ready || !self.window_focused {
        return Ok(false)
      }
      self.dispatch_composition(composition)
    }
    @platform.Input(input) => {
      if !self.ready || !self.window_focused {
        return Ok(false)
      }
      let frame = self.current_frame.unwrap()
      if event.scale() != frame.snapshot.scale() {
        self.invalidate_layout()
        return Ok(false)
      }
      let top = self.dialogs.length() - 1
      let admitted = match self.route(input) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      let result = if top < 0 {
        self.dispatch(input, admitted)
      } else {
        let dialog = self.dialogs[top]
        match input {
          @primitives.KeyPressed(key=@primitives.Escape, repeat~, ..) => {
            if repeat {
              return Ok(true)
            }
            let focused = match self.scope {
              Some(scope) => scope.focused()
              None => None
            }
            let mut composing = false
            for index = 0; index < self.bindings.length(); index = index + 1 {
              let binding = self.bindings[index]
              let dialog_field = binding.dialog_level == top &&
                (match focused {
                  Some(id) => binding.id == id
                  None => false
                })
              if dialog_field {
                match binding.field {
                  Some(field) if field.is_composing() => {
                    let measure = match self.measure {
                      Some(value) => value
                      None => return Ok(false)
                    }
                    let next = match
                      field.cancel_composition(
                        fn(document) { field_measure(measure, document) },
                        field_admit,
                      ) {
                      Ok(value) => value
                      Err(_) => return Ok(false)
                    }
                    self.bindings[index] = { ..binding, field: Some(next), }
                    composing = true
                  }
                  _ => ()
                }
              }
            }
            if composing {
              return Ok(true)
            }
            if dialog.dismissible {
              match self.dismiss_dialog(top, Some(@primitives.Escape)) {
                Err(error) => return Err(error)
                Ok(_) => ()
              }
            }
            Ok(true)
          }
          @primitives.PointerButtonPressed(button=@primitives.Primary, ..) =>
            if admitted == Some(dialog.root_id) {
              // The innermost backdrop owns the press. A non-dismissible level
              // consumes it instead of falling through to an outer Dialog.
              if dialog.dismissible {
                match self.dismiss_dialog(top, None) {
                  Err(error) => return Err(error)
                  Ok(_) => ()
                }
              }
              Ok(true)
            } else {
              self.dispatch(input, admitted)
            }
          _ => self.dispatch(input, admitted)
        }
      }
      if result is Ok(_) {
        self.last_dispatched_input = event.sequence()
      }
      result
    }
    _ => Ok(false)
  }
}

///|
/// Host composition is owner-routed, not hit-tested. The focused editable field
/// is the only target; disabled or read-only fields ignore the transaction.
fn Mounted::dispatch_composition(
  self : Mounted,
  composition : @primitives.CompositionEvent,
) -> Result[Bool, @diagnostics.FrameworkError] {
  let measure = match self.measure {
    Some(value) => value
    None => return Ok(false)
  }
  let focused = match self.scope {
    Some(scope) => scope.focused()
    None => return Ok(false)
  }
  for index = 0; index < self.bindings.length(); index = index + 1 {
    let binding = self.bindings[index]
    if focused != Some(binding.id) || !field_editable(binding.view) {
      continue
    }
    if !self.admits_binding(binding) {
      continue
    }
    let field = match binding.field {
      Some(value) => value
      None => return Ok(false)
    }
    let updated = match composition {
      @primitives.Start => Ok(field)
      @primitives.Update(text~, cursor_utf16~) => {
        let selection = match
          @text.TextSelection::new(cursor_utf16, cursor_utf16) {
          Ok(value) => value
          Err(_) => return Ok(false)
        }
        field.update_composition(
          text,
          selection,
          fn(document) { field_measure(measure, document) },
          field_admit,
        )
      }
      @primitives.Commit(text~) =>
        field.commit_composition(
          text,
          fn(document) { field_measure(measure, document) },
          field_admit,
        )
      @primitives.Cancel =>
        field.cancel_composition(
          fn(document) { field_measure(measure, document) },
          field_admit,
        )
    }
    let next = match updated {
      Ok(value) => value
      Err(error) =>
        return Err(
          adapter_error(
            "native TextField composition rejected: " +
            field_error_reason(error),
          ),
        )
    }
    let changed = !next.is_composing() &&
      next.committed_document().text() != field.committed_document().text()
    if changed {
      match binding.token {
        Some(token) =>
          ignore(
            self.runtime.enqueue_text_changed(token, next.document().text()),
          )
        None => ()
      }
    }
    self.bindings[index] = { ..binding, field: Some(next), }
    return Ok(true)
  }
  Ok(false)
}

///|
/// Apply one ordered observation from an armed portable text-input session.
/// The runner owns begin/update/cancel/end; this adapter maps the portable
/// preview/commit/cancel onto the focused editable field. A rejected field
/// transaction is an adapter error, never a rewritten host event.
pub fn Mounted::text_input(
  self : Mounted,
  epoch : UInt64,
  event : @text_host.TextInputEvent,
) -> Result[Bool, @diagnostics.FrameworkError] {
  if !self.ready || self.is_disposed() || event.window() != self.window {
    return Ok(false)
  }
  if event.epoch() != epoch {
    return Ok(false)
  }
  if self.text_epoch != epoch {
    self.text_epoch = epoch
    self.last_text_sequence = 0L
  }
  if event.sequence() <= 0L || event.sequence() <= self.last_text_sequence {
    return Ok(false)
  }
  let kind = event.kind()
  if kind is @text_host.Geometry(..) {
    self.last_text_sequence = event.sequence()
    return Ok(true)
  }
  let measure = match self.measure {
    Some(value) => value
    None => return Ok(false)
  }
  let focused = match self.scope {
    Some(scope) => scope.focused()
    None => return Ok(false)
  }
  for index = 0; index < self.bindings.length(); index = index + 1 {
    let binding = self.bindings[index]
    if focused != Some(binding.id) || !field_editable(binding.view) {
      continue
    }
    let field = match binding.field {
      Some(value) => value
      None => return Ok(false)
    }
    match kind {
      @text_host.Preedit(text~, cursor~) => {
        if text.length() > 16_384 {
          return Err(adapter_error("native TextField preedit is too long"))
        }
        let offset = if cursor < 0 { text.length() } else { cursor }
        let selection = match @text.TextSelection::new(offset, offset) {
          Err(_) =>
            return Err(
              adapter_error("native TextField preedit cursor is outside the text"),
            )
          Ok(value) => value
        }
        let next = match
          field.update_composition(
            text,
            selection,
            fn(document) { field_measure(measure, document) },
            field_admit,
          ) {
          Err(error) =>
            return Err(
              adapter_error(
                "native TextField preedit rejected: " +
                field_error_reason(error),
              ),
            )
          Ok(value) => value
        }
        self.bindings[index] = { ..binding, field: Some(next), }
      }
      @text_host.Commit(text~) => {
        let next = match
          field.commit_composition(
            text,
            fn(document) { field_measure(measure, document) },
            field_admit,
          ) {
          Err(error) =>
            return Err(
              adapter_error(
                "native TextField commit rejected: " +
                field_error_reason(error),
              ),
            )
          Ok(value) => value
        }
        if next.document().text() != field.document().text() {
          match binding.token {
            Some(token) =>
              ignore(
                self.runtime.enqueue_text_changed(token, next.document().text()),
              )
            None => ()
          }
        }
        self.bindings[index] = { ..binding, field: Some(next), }
      }
      @text_host.Cancel =>
        match
          field.cancel_composition(
            fn(document) { field_measure(measure, document) },
            field_admit,
          ) {
          Err(error) =>
            return Err(
              adapter_error(
                "native TextField cancel rejected: " +
                field_error_reason(error),
              ),
            )
          Ok(next) => self.bindings[index] = { ..binding, field: Some(next), }
        }
      @text_host.FocusLost =>
        if field.is_composing() {
          match
            field.cancel_composition(
              fn(document) { field_measure(measure, document) },
              field_admit,
            ) {
            Err(error) =>
              return Err(
                adapter_error(
                  "native TextField focus-loss cancel rejected: " +
                  field_error_reason(error),
                ),
              )
            Ok(next) => self.bindings[index] = { ..binding, field: Some(next), }
          }
        }
      @text_host.Geometry(..) => ()
    }
    self.last_text_sequence = event.sequence()
    self.change = fresh_epoch()
    return Ok(true)
  }
  Ok(false)
}

///|
fn Mounted::dispatch(
  self : Mounted,
  input : @primitives.InputEvent,
  target : UInt64?,
) -> Result[Bool, @diagnostics.FrameworkError] {
  let measure = match self.measure {
    Some(value) => value
    None => return Err(adapter_error("native TextField measure is unavailable"))
  }
  let scope = match self.scope {
    Some(value) => value
    None => return Ok(false)
  }
  match input {
    @primitives.KeyPressed(key=@primitives.Tab, modifiers~, repeat=false) if !modifiers.control() &&
      !modifiers.alt() &&
      !modifiers.meta() => {
      let traversed = if modifiers.shift() {
        scope.focus_prev(scope.target())
      } else {
        scope.focus_next(scope.target())
      }
      match traversed {
        Err(_) => return Err(adapter_error("native focus traversal failed"))
        Ok(_) => ()
      }
      self.sync_focus()
      return Ok(true)
    }
    @primitives.PointerButtonPressed(button=@primitives.Primary, ..) => {
      let previous = scope.focused()
      match target {
        Some(id) =>
          match scope.request_focus(scope.target(), id) {
            Ok(_) => ()
            Err(_) =>
              if self.dialogs.length() == 0 {
                ignore(scope.clear_focus(scope.target()))
              }
          }
        None =>
          if self.dialogs.length() == 0 {
            ignore(scope.clear_focus(scope.target()))
          }
      }
      if self.dialogs.length() == 0 && target is Some(_) && previous != target {
        self.focus_return = previous
      }
      self.sync_focus()
    }
    _ => ()
  }
  let mut consumed = false
  let modal = self.dialogs.length() > 0
  for index = 0; index < self.bindings.length(); index = index + 1 {
    let binding = self.bindings[index]
    // Scope admission already rejects background targets. This filter only keeps
    // background controller state (hover, held press) frozen under an open Dialog.
    if modal && !self.admits_binding(binding) {
      continue
    }
    match binding.field {
      Some(field) => {
        let route = match input {
          @primitives.PointerMoved(..) => false
          @primitives.PointerButtonPressed(..)
          | @primitives.PointerButtonReleased(..) => target == Some(binding.id)
          _ => field.is_focused()
        }
        if route && field_input_allowed(binding.view, input) {
          let outcome = match
            field.handle_input(
              input,
              fn(document) { field_measure(measure, document) },
              field_admit,
              fn(document, point) { field_hit(measure, document, point) },
            ) {
            Ok(value) => value
            Err(error) =>
              return Err(
                adapter_error(
                  "native TextField input rejected: " +
                  field_error_reason(error),
                ),
              )
          }
          let (next, action) = outcome
          let mut next = next
          let editable = field_editable(binding.view)
          match action {
            Some(@text_field.Submit) =>
              if editable {
                match binding.token {
                  Some(token) => ignore(self.runtime.enqueue_submitted(token))
                  None => ()
                }
              }
            Some(@text_field.Blur) => {
              match self.focus_return {
                Some(id) => ignore(scope.request_focus(scope.target(), id))
                None => ignore(scope.clear_focus(scope.target()))
              }
              self.focus_return = None
              self.sync_focus()
            }
            Some(@text_field.Cut(text~, candidate~)) =>
              if editable {
                next = candidate
                self.clipboard.push(Copy(text))
              }
            Some(@text_field.Paste) =>
              if editable {
                match binding.token {
                  Some(token) =>
                    self.clipboard.push(
                      Paste({
                        binding: binding.id,
                        token,
                        revision: field.revision(),
                        generation: binding.field_generation,
                        app_revision: match binding.view.text_field_props() {
                          Some(props) => props.revision()
                          None => 0UL
                        },
                      }),
                    )
                  None => ()
                }
              }
            Some(@text_field.Copy(text)) =>
              if text.length() > 0 {
                self.clipboard.push(Copy(text))
              }
            None => ()
          }
          let changed = next.document().text() != field.document().text()
          if changed && editable {
            match binding.token {
              Some(token) =>
                ignore(
                  self.runtime.enqueue_text_changed(
                    token,
                    next.document().text(),
                  ),
                )
              None => ()
            }
          }
          self.bindings[index] = { ..binding, field: Some(next), }
          consumed = true
        }
      }
      None => ()
    }
    match binding.button {
      Some(button) => {
        let route = match input {
          @primitives.PointerMoved(..) => true
          // The existing Button owns arming. Deliver an outside primary release
          // to pressed Buttons so it can cancel; there is no third recognizer.
          @primitives.PointerButtonReleased(button=@primitives.Primary, ..) =>
            target == Some(binding.id) || button.is_pressed()
          _ => target == Some(binding.id)
        }
        if route {
          let (next, result) = button.handle_input(input)
          self.bindings[index] = { ..binding, button: Some(next), }
          consumed = consumed || result.consumed()
          if result.effect() == @button.Activated {
            match binding.token {
              Some(token) => ignore(self.runtime.enqueue_activate(token))
              None => ()
            }
          }
        }
      }
      None => ()
    }
  }
  Ok(consumed)
}

///|
pub fn Mounted::dispose(self : Mounted) -> Unit {
  self.change = fresh_epoch()
  self.epoch.live = false
  self.runtime.dispose()
  self.bindings = []
  match self.scope {
    Some(scope) =>
      ignore(
        scope.close(scope.target(), fn(boundary) {
          self.cancel_interactions(boundary)
        }),
      )
    None => ()
  }
  self.scope = None
  self.current_frame = None
  self.clipboard = []
  self.dialogs = []
  self.text_epoch = 0UL
  self.last_text_sequence = 0L
  self.ready = false
}

///|
/// Last sequence successfully dispatched through all input admission gates.
/// Includes unconsumed input (Ok(false)); ignored or failed events do not advance it.
/// Compare before/after a call to distinguish a newly dispatched event from replay.
pub fn Mounted::last_dispatched_input_sequence(self : Mounted) -> Int64 {
  self.last_dispatched_input
}
