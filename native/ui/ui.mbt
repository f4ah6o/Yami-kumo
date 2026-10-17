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
}

///|
priv struct Observation {
  binding_id : UInt64
  key : @view.NodeKey
  bounds : @primitives.Rect
  label_bounds : @primitives.Rect?
  pressed : Bool
  focused : Bool
}

///|
/// An immutable observation of a successfully committed native frame.
pub struct Frame {
  priv snapshot : @scene.SceneSnapshot
  priv revision : UInt64
  priv observations : Array[Observation]
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
  priv mut last_sequence : Int64
  priv mut window_focused : Bool
  priv mut ready : Bool
  priv mut busy : Bool
}

///|
pub fn Mounted::new(window : @platform.WindowId) -> Mounted {
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
    window_focused: true,
    ready: false,
    busy: false,
  }
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
  if view.key().value().is_empty() {
    return Err(adapter_error("empty view key"))
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
fn max(left : Double, right : Double) -> Double {
  if left > right {
    left
  } else {
    right
  }
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
fn Mounted::prepare(
  self : Mounted,
  view : @view.View,
  width : Double,
  height : Double,
  scale : Double,
  measure : @components.TextMeasure,
) -> Result[Candidate, @diagnostics.FrameworkError] {
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
  let bindings : Array[Binding] = []
  let mut next_id = self.next_id
  for node in nodes {
    let previous = match binding_for(self.bindings, node.key()) {
      Some(binding) if binding.view.kind() == node.kind() => Some(binding)
      _ => None
    }
    let id = match previous {
      Some(binding) => binding.id
      None => {
        if next_id > 18446744073709551600UL {
          return Err(adapter_error("native identity space exhausted"))
        }
        let id = next_id
        next_id += 8UL
        id
      }
    }
    let text = if node.kind() == @view.Text || node.kind() == @view.Button {
      let foreground = if node.kind() == @view.Text {
        color(30, 36, 45)
      } else if node.disabled() {
        color(166, 171, 178)
      } else {
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
      button: match previous {
        Some(binding) => binding.button
        None => None
      },
    })
  }
  let root_style = style(@view.Column).with_insets(
    @layout.Insets::all(24.0).unwrap(),
    @layout.Insets::zero(),
  )
  let root = @element.Element::root(1UL, root_style)
    .with_pointer_events(false)
    .with_child(make_element(view, bindings))
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
  match
    @scene.SceneItem::quad(
      1UL,
      viewport,
      color(245, 247, 250),
      @scene.AffineTransform::identity(),
      1.0,
      None,
    ) {
    Ok(item) => items.push(item)
    Err(_) => return Err(adapter_error("background scene rejected"))
  }
  let observations = []
  for index in 0..<bindings.length() {
    let binding = bindings[index]
    let bounds = tree.node(binding.id).unwrap().bounds()
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
          (binding.id + 1UL, bounds, color(166, 171, 178)),
          (binding.id + 2UL, inner, color(245, 247, 250)),
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
            adapter_error("native Button requires bounds of at least 24 by 24"),
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
      let paint = match model.paint_items(binding.id + 1UL) {
        Ok(value) => value
        Err(_) => return Err(adapter_error("native Button paint failed"))
      }
      // Reuse GPUI border/fill, replacing only its unmeasured label with the
      // existing NativeText path and the host's actual measurement callback.
      items.push(paint[0])
      items.push(paint[1])
      button = Some(model)
    }
    match binding.text {
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
    })
    bindings[index] = { ..binding, button, }
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
    frame: { snapshot, revision: self.revision + 1UL, observations, },
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
  self.runtime.enqueue_activate(callback.token)
}

///|
pub fn Mounted::next_action(self : Mounted) -> @view.SemanticAction? {
  if self.busy || !self.ready || !self.window_focused {
    return None
  }
  self.runtime.next_action()
}

///|
pub fn Mounted::focus(self : Mounted, key : @view.NodeKey) -> Bool {
  if self.busy || !self.ready || !self.window_focused {
    return false
  }
  let binding = match binding_for(self.bindings, key) {
    None => return false
    Some(value) => value
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
      self.dispatch(input)
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
