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
priv struct Binding {
  view : @view.View
  id : UInt64
  token : @runtime.InstanceToken?
  text : @components.NativeText?
  button : @button.Button?
  visible : Bool
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
  priv mut tree : @element.ElementTree?
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
    tree: None,
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
  let size = match binding.text {
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
      view.kind() == @view.Button && !view.disabled() && !view.loading(),
    )
    .with_focusable(view.kind() == @view.Button && !view.disabled())
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
      element = element.with_child(make_element(child, bindings))
    }
  }
  element
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
    .with_insets(
      @layout.Insets::all(24.0).unwrap(),
      @layout.Insets::zero(),
    ),
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
  cancel_pending : Bool
}

///|
/// The native TextField adapter is not implemented in this slice. Reject the
/// whole staged tree instead of painting the label as a read-only Text.
fn reject_unsupported_text_field(
  view : @view.View,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if view.kind() == @view.TextField {
    return Err(
      @diagnostics.FrameworkError::new(
        @diagnostics.UnsupportedCapability,
        "shared-native-ui",
        subsystem="shared-native-ui",
        message="TextField native adapter is not implemented",
      ),
    )
  }
  for child in view.children() {
    match reject_unsupported_text_field(child) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  Ok(())
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
  match reject_unsupported_text_field(view) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
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
        next_id += if node.kind() == @view.AppShell { 40UL } else { 8UL }
        id
      }
    }
    let text = if visible &&
      (node.kind() == @view.Text || node.kind() == @view.Button) {
      let foreground = if node.kind() == @view.Text {
        text_color
      } else {
        // Measurement is color-independent; core resolves paint below.
        color(242, 246, 250)
      }
      match
        @components.NativeText::for_button(
          id + 3UL,
          node.label(),
          16.0,
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
  let child = if view.is_shell() {
    make_shell_element(view, bindings, mode.unwrap())
  } else {
    make_element(view, bindings)
  }
  let root = @element.Element::root(1UL, root_style)
    .with_pointer_events(false)
    .with_child(child)
  let requested = match
    root.request_layout_with_device_scale(viewport.size(), scale) {
    Err(_) => return Err(adapter_error("native flex layout failed"))
    Ok(value) => value
  }
  let painted = match requested.prepaint() {
    Err(_) => return Err(adapter_error("native element prepaint failed"))
    Ok(value) => value
  }
  let mut tree = painted.tree()
  // Preserve the exact GPUI focus owner for unchanged topology; rebuilds may
  // retain focus only when the private native ID still belongs to this token.
  match self.tree {
    Some(old_tree) => {
      tree = match old_tree.with_layout_bounds(painted) {
        Ok(value) => value
        Err(_) => tree
      }
      match old_tree.focused() {
        Some(id) =>
          match tree.with_focus(id) {
            Ok(value) => tree = value
            Err(_) => ()
          }
        None => ()
      }
    }
    None => ()
  }
  if !self.window_focused {
    tree = tree.clear_focus()
  }
  let mut cancel_pending = match self.current_frame {
    Some(frame) =>
      frame.snapshot.viewport() != viewport || frame.snapshot.scale() != scale
    None => !self.ready
  }
  let items = []
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
  for index in 0..<bindings.length() {
    let binding = bindings[index]
    if binding.visible {
      let bounds = match tree.node(binding.id) {
        Some(node) => node.bounds()
        None => return Err(adapter_error("visible binding has no layout node"))
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
          .with_focus(tree.is_focused(binding.id))
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
          match text.scene_item(bounds, align) {
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
        @primitives.Rect::new(
          x,
          bounds.top() + (bounds.size().height() - size.height()) / 2.0,
          size.width(),
          size.height(),
        ).unwrap()
      })
      observations.push({
        binding_id: binding.id,
        key: binding.view.key(),
        bounds,
        label_bounds,
        pressed: button.map(model => model.is_pressed()).unwrap_or(false),
        focused: button.map(model => model.is_focused()).unwrap_or(false),
        hovered: button.map(model => model.is_hovered()).unwrap_or(false),
        enabled: button.map(model => model.is_enabled()).unwrap_or(false),
        loading: button.map(model => model.is_loading()).unwrap_or(false),
        palette: binding.view.button_palette(),
      })
      bindings[index] = { ..binding, button, text, }
    } else {
      bindings[index] = { ..binding, button: None, text: None, }
    }
  }
  let snapshot = match
    @scene.SceneSnapshot::new(viewport, scale, [], [], items) {
    Err(_) => return Err(adapter_error("native scene validation failed"))
    Ok(value) => value
  }
  Ok({
    bindings,
    tree,
    next_id,
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
  Ok({ view, candidate, change, })
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
  for index in 0..<candidate.bindings.length() {
    let binding = candidate.bindings[index]
    candidate.bindings[index] = {
      ..binding,
      token: self.runtime.token(binding.view.key()),
    }
  }
  self.bindings = candidate.bindings
  self.tree = Some(candidate.tree)
  self.current_frame = Some(candidate.frame)
  self.next_id = candidate.next_id
  self.revision = candidate.frame.revision
  self.ready = true
  self.change = fresh_epoch()
  Ok(candidate.frame)
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
  for index in 0..<self.bindings.length() {
    let binding = self.bindings[index]
    match binding.button {
      Some(button) => {
        let focused = self.tree
          .map(tree => tree.is_focused(binding.id))
          .unwrap_or(false)
        self.bindings[index] = {
          ..binding,
          button: Some(button.with_focus(focused)),
        }
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
pub fn Mounted::callback(self : Mounted, key : @view.NodeKey) -> Activation? {
  if !self.ready || self.is_disposed() {
    return None
  }
  match binding_for(self.bindings, key) {
    Some(binding) if binding.visible => ()
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
  if !shell {
    return self.runtime.next_action()
  }
  while self.runtime.next_action() is Some(action) {
    let key = match action {
      @view.Activate(key) => key
      @view.TextChanged(key, _) => key
      @view.Submitted(key) => key
    }
    let visible = match self.current_frame {
      Some(frame) => frame.bounds(key) is Some(_)
      None => false
    }
    if visible {
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
  let tree = match self.tree {
    None => return false
    Some(value) => value
  }
  let outcome = match tree.with_focus(binding.id) {
    Err(_) => @view.Rejected
    Ok(next) => {
      self.tree = Some(next)
      self.sync_focus()
      self.change = fresh_epoch()
      @view.Focused
    }
  }
  ignore(self.runtime.complete_focus(request, outcome))
  outcome == @view.Focused
}

///|
pub fn Mounted::next_focus_result(self : Mounted) -> @runtime.FocusResult? {
  self.runtime.next_focus_result()
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
        self.tree = self.tree.map(tree => tree.clear_focus())
        self.sync_focus()
      }
      Ok(true)
    }
    @platform.VisibilityChanged(false) => {
      self.invalidate_layout()
      Ok(true)
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
      let result = self.dispatch(input)
      if result is Ok(_) {
        self.last_dispatched_input = event.sequence()
      }
      result
    }
    _ => Ok(false)
  }
}

///|
fn Mounted::dispatch(
  self : Mounted,
  input : @primitives.InputEvent,
) -> Result[Bool, @diagnostics.FrameworkError] {
  let mut tree = self.tree.unwrap()
  match input {
    @primitives.KeyPressed(key=@primitives.Tab, modifiers~, repeat=false) if !modifiers.control() &&
      !modifiers.alt() &&
      !modifiers.meta() => {
      let next = if modifiers.shift() {
        tree.focus_prev()
      } else {
        tree.focus_next()
      }
      match next {
        Err(_) => return Err(adapter_error("native focus traversal failed"))
        Ok(value) => tree = value
      }
      self.tree = Some(tree)
      self.sync_focus()
      return Ok(true)
    }
    @primitives.PointerButtonPressed(button=@primitives.Primary, ..) => {
      let target = tree.dispatch_input(input).target()
      tree = match target {
        Some(id) =>
          match tree.with_focus(id) {
            Ok(value) => value
            Err(_) => tree.clear_focus()
          }
        None => tree.clear_focus()
      }
      self.tree = Some(tree)
      self.sync_focus()
    }
    _ => ()
  }
  let target = tree.dispatch_input(input).target()
  let mut consumed = false
  for index in 0..<self.bindings.length() {
    let binding = self.bindings[index]
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
  self.tree = None
  self.current_frame = None
  self.ready = false
}

///|
/// Last sequence successfully dispatched through all input admission gates.
/// Includes unconsumed input (Ok(false)); ignored or failed events do not advance it.
/// Compare before/after a call to distinguish a newly dispatched event from replay.
pub fn Mounted::last_dispatched_input_sequence(self : Mounted) -> Int64 {
  self.last_dispatched_input
}
