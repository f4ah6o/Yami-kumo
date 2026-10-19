///|
/// The bootstrap owns exactly one App Entity containing the common PaletteModel,
/// which composes unchanged SpacingModel and shared counter Model. Native host state and
/// bounded fixture props contain no counter or expanded-state copy.
pub struct NativeCounter {
  priv app : @app.App
  priv state : @app.Entity[@model.PaletteModel]
  priv mount : @ui.Mounted
  priv spacing : Bool
  priv palette : Bool
  priv card : Bool
  priv shell : Bool
  priv mut disabled : Bool
  priv mut loading : Bool
  priv mut draining : Bool
  priv mut disposed : Bool
  priv actions : Array[@view.SemanticAction]
}

///|
pub struct CounterFrame {
  priv frame : @ui.Frame
  priv count : Int32
  priv spacing : Bool
  priv palette : Bool
  priv expanded : Bool
  priv action_keys : Array[String]
}

///|
pub fn CounterFrame::snapshot(self : CounterFrame) -> @scene.SceneSnapshot {
  self.frame.snapshot()
}

///|
pub fn CounterFrame::canonical_scene(self : CounterFrame) -> String {
  self.frame.snapshot().canonical_json()
}

///|
pub fn CounterFrame::button_label_bounds(
  self : CounterFrame,
) -> @primitives.Rect {
  self.frame.label_bounds(@view.NodeKey::new("increment")).unwrap()
}

///|
pub fn CounterFrame::count(self : CounterFrame) -> Int32 {
  self.count
}

///|
pub fn CounterFrame::revision(self : CounterFrame) -> UInt64 {
  self.frame.revision()
}

///|
pub fn CounterFrame::root_bounds(self : CounterFrame) -> @primitives.Rect {
  self.frame.root_bounds()
}

///|
pub fn CounterFrame::button_bounds(self : CounterFrame) -> @primitives.Rect {
  self.frame.bounds(@view.NodeKey::new("increment")).unwrap()
}

///|
pub fn CounterFrame::counter_bounds(self : CounterFrame) -> @primitives.Rect {
  self.frame.bounds(@view.NodeKey::new("value")).unwrap()
}

///|
pub fn CounterFrame::button_pressed(self : CounterFrame) -> Bool {
  self.frame.pressed(@view.NodeKey::new("increment"))
}

///|
pub fn CounterFrame::button_focused(self : CounterFrame) -> Bool {
  self.frame.focused(@view.NodeKey::new("increment"))
}

///|
pub fn CounterFrame::button_enabled(self : CounterFrame) -> Bool {
  self.frame.enabled(@view.NodeKey::new("increment"))
}

///|
pub fn CounterFrame::button_loading(self : CounterFrame) -> Bool {
  self.frame.loading(@view.NodeKey::new("increment"))
}

///|
pub fn NativeCounter::new(
  window : @platform.WindowId,
  card~ : Bool = false,
  spacing~ : Bool = false,
  palette~ : Bool = false,
  shell~ : Bool = false,
  disabled~ : Bool = false,
  loading~ : Bool = false,
) -> Result[NativeCounter, @diagnostics.FrameworkError] {
  if (card && spacing) || (palette && (card || spacing)) {
    return Err(counter_error("Card and spacing fixtures cannot be combined"))
  }
  if shell && (card || spacing || palette) {
    return Err(counter_error("Shell cannot be combined with other view fixtures"))
  }
  let app = match @app.App::new() {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  match app.start() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let state = match app.create_entity(@model.PaletteModel::new()) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  Ok({
    app,
    state,
    mount: @ui.Mounted::new(window),
    card,
    spacing,
    palette,
    shell,
    disabled,
    loading,
    draining: false,
    disposed: false,
    actions: [],
  })
}

///|
pub fn NativeCounter::count(
  self : NativeCounter,
) -> Result[Int32, @diagnostics.FrameworkError] {
  self.app.read(self.state, model => model.value())
}

///|
pub fn NativeCounter::model_revision(
  self : NativeCounter,
) -> Result[UInt64, @diagnostics.FrameworkError] {
  self.app.revision(self.state)
}

///|
/// Queue one semantic activation of the main increment through the retained
/// common callback. The host loop drains the action through the normal path.
pub fn NativeCounter::activate_increment(
  self : NativeCounter,
) -> Result[Bool, @diagnostics.FrameworkError] {
  if self.disposed || self.draining {
    return Ok(false)
  }
  match self.mount.callback(@view.NodeKey::new("increment")) {
    None => Ok(false)
    Some(callback) => Ok(self.mount.activate(callback))
  }
}

///|
/// Copied observations of actions actually applied to the App-owned model.
pub fn NativeCounter::actions(
  self : NativeCounter,
) -> Array[@view.SemanticAction] {
  self.actions.copy()
}

///|
fn shell_slot(view : @view.View, region : @view.ShellRegion) -> @view.View? {
  for child in view.children() {
    if child.shell_region() == Some(region) {
      return Some(child)
    }
  }
  None
}

///|
/// Rebuild the shell with bounded adapter gates applied to its slot contents.
/// The application still owns the state and labels.
fn shell_mode_view(
  view : @view.View,
  disabled : Bool,
  loading : Bool,
) -> @view.View {
  let state = view.shell().unwrap()
  let brand = match shell_slot(view, @view.Brand) {
    Some(child) => mode_view(child, disabled, loading)
    None => return view
  }
  let main = match shell_slot(view, @view.Main) {
    Some(child) => mode_view(child, disabled, loading)
    None => return view
  }
  fn transformed(region : @view.ShellRegion) -> @view.View? {
    match shell_slot(view, region) {
      Some(child) => Some(mode_view(child, disabled, loading))
      None => None
    }
  }
  @view.app_shell(
    view.key(),
    brand,
    main,
    navigation_trigger?=transformed(@view.NavigationTrigger),
    global_search?=transformed(@view.GlobalSearch),
    header_actions?=transformed(@view.HeaderActions),
    account_menu?=transformed(@view.AccountMenu),
    rail?=transformed(@view.Rail),
    sidebar?=transformed(@view.Sidebar),
    tabs?=transformed(@view.Tabs),
    context_panel?=transformed(@view.ContextPanel),
    bottom_bar?=transformed(@view.BottomBar),
    sidebar_collapsed=state.sidebar_collapsed(),
    mobile_sidebar_open=state.mobile_sidebar_open(),
    context_panel_open=state.context_panel_open(),
    primary_navigation_label=state.primary_navigation_label(),
    workspace_navigation_label=state.workspace_navigation_label(),
    context_panel_label=state.context_panel_label(),
  )
}

///|
fn mode_view(view : @view.View, disabled : Bool, loading : Bool) -> @view.View {
  match view.kind() {
    @view.Button =>
      match view.button_palette() {
        None => @view.button(view.key(), view.label(), disabled~, loading~)
        Some(token) =>
          @view.button_with_palette(
            view.key(),
            view.label(),
            token,
            disabled~,
            loading~,
          )
      }
    @view.Row => {
      let children = view
        .children()
        .map(child => mode_view(child, disabled, loading))
      match view.spacing() {
        Some(spacing) => @view.row_with_spacing(view.key(), children, spacing)
        None => @view.row(view.key(), children)
      }
    }
    @view.Column => {
      let children = view
        .children()
        .map(child => mode_view(child, disabled, loading))
      if view.is_card() {
        @view.card(view.key(), children)
      } else {
        match view.spacing() {
          Some(spacing) =>
            @view.column_with_spacing(view.key(), children, spacing)
          None => @view.column(view.key(), children)
        }
      }
    }
    @view.Text | @view.TextField => view
    @view.AppShell => shell_mode_view(view, disabled, loading)
  }
}

///|
fn counter_error(message : String) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    @diagnostics.InvalidInput,
    "NativeCounter",
    message~,
  )
}

///|
pub fn NativeCounter::render(
  self : NativeCounter,
  width : Double,
  height : Double,
  scale : Double,
  measure : @components.TextMeasure,
) -> Result[CounterFrame, @diagnostics.FrameworkError] {
  if self.disposed || self.draining {
    return Err(counter_error("disposed or reentrant counter render"))
  }
  let model = match self.app.read(self.state, model => model) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  match
    self.mount.commit(
      mode_view(self.common_view(model), self.disabled, self.loading),
      width,
      height,
      scale,
      measure,
    ) {
    Err(error) => Err(error)
    Ok(frame) =>
      Ok({
        frame,
        count: model.value(),
        spacing: self.spacing,
        palette: self.palette,
        expanded: model.expanded(),
        action_keys: self.actions.map(action => {
          match action {
            @view.Activate(key) => key.value()
          }
        }),
      })
  }
}

///|
/// This call only dispatches host input and queues common semantic activation.
/// The host must return from it before draining an action.
pub fn NativeCounter::handle_event(
  self : NativeCounter,
  event : @platform.Event,
) -> Result[Bool, @diagnostics.FrameworkError] {
  if self.disposed || self.draining {
    return Ok(false)
  }
  let result = self.mount.handle_event(event)
  if self.mount.is_disposed() {
    self.dispose()
  }
  result
}

///|
/// Stage all fallible host work, then use App.update/Context.set+notify and
/// publish the next view before another action can drain. No duplicate raw
/// model is retained. A failed staging leaves the Entity and accepted frame
/// unchanged; the attempted action is consumed and reported as an error.
pub fn NativeCounter::drain_one(
  self : NativeCounter,
  width : Double,
  height : Double,
  scale : Double,
  measure : @components.TextMeasure,
) -> Result[Bool, @diagnostics.FrameworkError] {
  if self.disposed || self.draining {
    return Ok(false)
  }
  let action = match self.mount.next_action() {
    None => return Ok(false)
    Some(value) => value
  }
  self.draining = true
  let result = self.apply_action(action, width, height, scale, measure)
  self.draining = false
  result
}

///|
fn NativeCounter::apply_action(
  self : NativeCounter,
  action : @view.SemanticAction,
  width : Double,
  height : Double,
  scale : Double,
  measure : @components.TextMeasure,
) -> Result[Bool, @diagnostics.FrameworkError] {
  let next = match
    self.app.read(self.state, model => {
      if self.shell {
        model.update_shell(action)
      } else if self.palette {
        model.update_palette(action)
      } else if self.spacing {
        model.update(action)
      } else {
        model.update_counter(action)
      }
    }) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let prepared = match
    self.mount.stage(
      mode_view(self.common_view(next), self.disabled, self.loading),
      width,
      height,
      scale,
      measure,
    ) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if self.disposed {
    return Err(counter_error("counter disposed while measuring"))
  }
  match
    self.app.update(self.state, context => {
      match context.set(next) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      context.notify()
    }) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  // No user callback or concurrent host dispatch occurs between the staged
  // preparation and this publication. Publication is ownership validation only.
  match self.mount.publish(prepared) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  self.actions.push(action)
  // Context.notify queues a Changed notification even without listeners. Pump
  // only after publishing, so observers can never see a new model paired with
  // the previous accepted native geometry.
  match self.drain_app_work() {
    Err(error) => Err(error)
    Ok(_) => Ok(true)
  }
}

///|
/// Bounded regression fixture control. The shared Model.view/update sources
/// remain unchanged; mode gates are adapter props applied to that View.
pub fn NativeCounter::set_mode(
  self : NativeCounter,
  disabled : Bool,
  loading : Bool,
  width : Double,
  height : Double,
  scale : Double,
  measure : @components.TextMeasure,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if self.disposed || self.draining {
    return Err(counter_error("disposed or reentrant mode change"))
  }
  let model = match self.app.read(self.state, model => model) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  match
    self.mount.commit(
      mode_view(self.common_view(model), disabled, loading),
      width,
      height,
      scale,
      measure,
    ) {
    Err(error) => Err(error)
    Ok(_) => {
      self.disabled = disabled
      self.loading = loading
      Ok(())
    }
  }
}

///|
pub fn NativeCounter::dispose(self : NativeCounter) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.mount.dispose()
  ignore(self.app.destroy_entity(self.state))
  ignore(self.app.request_stop())
  // Released delivery clears the retained Entity value and lets Stopping reach
  // Stopped. The App and Entity are private; no external callbacks are installed.
  ignore(self.drain_app_work())
}

///|
/// Revoke accepted input geometry and pending activations when the host cannot
/// yet present a newly committed layout. The next successful render reopens
/// input; a release received while unavailable can never replay afterward.
pub fn NativeCounter::invalidate_layout(self : NativeCounter) -> Unit {
  self.mount.invalidate_layout()
}

///|
fn NativeCounter::drain_app_work(
  self : NativeCounter,
) -> Result[Unit, @diagnostics.FrameworkError] {
  // A snapshot-sized budget is finite and drains all work owned by this
  // bootstrap: one Entity's Changed/Released notifications, with no timers,
  // subscriptions or recursive tasks. Do not spin an unbounded executor loop.
  let budget = self.app.pending_work()
  if budget == 0 {
    return Ok(())
  }
  match self.app.run_ready(budget) {
    Err(error) => Err(error)
    Ok(_) =>
      if self.app.pending_work() == 0 {
        Ok(())
      } else {
        Err(
          counter_error("unexpected work after private App notification drain"),
        )
      }
  }
}

///|
fn NativeCounter::common_view(
  self : NativeCounter,
  model : @model.PaletteModel,
) -> @view.View {
  if self.shell {
    model.shell_view()
  } else if self.palette {
    model.palette_view()
  } else if self.spacing {
    model.view()
  } else if self.card {
    model.counter().card_view()
  } else {
    model.counter().view()
  }
}

///|
pub fn CounterFrame::card_bounds(self : CounterFrame) -> @primitives.Rect {
  self.frame
  .bounds(@view.NodeKey::new(if self.spacing { "preview" } else { "counter" }))
  .unwrap()
}

///|
pub fn CounterFrame::shell_mode(self : CounterFrame) -> @view.ShellMode? {
  self.frame.shell_mode()
}

///|
pub fn CounterFrame::shell_region_bounds(
  self : CounterFrame,
  region : @view.ShellRegion,
) -> @primitives.Rect? {
  self.frame.region_bounds(region)
}

///|
pub fn CounterFrame::heading_bounds(self : CounterFrame) -> @primitives.Rect {
  self.frame.bounds(@view.NodeKey::new("heading")).unwrap()
}

///|
/// Copied model and geometry observations; no host-owned spacing state.
pub fn CounterFrame::expanded(self : CounterFrame) -> Bool {
  self.expanded
}

///|
pub fn CounterFrame::action_keys(self : CounterFrame) -> Array[String] {
  self.action_keys.copy()
}

///|
pub fn CounterFrame::stack_bounds(self : CounterFrame) -> @primitives.Rect {
  self.frame.bounds(@view.NodeKey::new("counter")).unwrap()
}

///|
pub fn CounterFrame::row_bounds(self : CounterFrame) -> @primitives.Rect {
  self.frame.bounds(@view.NodeKey::new("actions")).unwrap()
}

///|
pub fn CounterFrame::toggle_bounds(self : CounterFrame) -> @primitives.Rect {
  self.frame
  .bounds(
    @view.NodeKey::new(
      if self.palette {
        "palette-toggle"
      } else {
        "spacing-toggle"
      },
    ),
  )
  .unwrap()
}

///|
pub fn CounterFrame::toggle_label_bounds(
  self : CounterFrame,
) -> @primitives.Rect {
  self.frame
  .label_bounds(
    @view.NodeKey::new(
      if self.palette {
        "palette-toggle"
      } else {
        "spacing-toggle"
      },
    ),
  )
  .unwrap()
}

///|
pub fn CounterFrame::card_label_bounds(self : CounterFrame) -> @primitives.Rect {
  self.frame.bounds(@view.NodeKey::new("card-label")).unwrap()
}

///|
pub fn CounterFrame::toggle_pressed(self : CounterFrame) -> Bool {
  self.frame.pressed(
    @view.NodeKey::new(
      if self.palette {
        "palette-toggle"
      } else {
        "spacing-toggle"
      },
    ),
  )
}

///|
pub fn CounterFrame::toggle_focused(self : CounterFrame) -> Bool {
  self.frame.focused(
    @view.NodeKey::new(
      if self.palette {
        "palette-toggle"
      } else {
        "spacing-toggle"
      },
    ),
  )
}

///|
pub fn CounterFrame::button_binding_id(self : CounterFrame) -> UInt64 {
  self.frame.binding_id(@view.NodeKey::new("increment")).unwrap()
}

///|
pub fn CounterFrame::toggle_binding_id(self : CounterFrame) -> UInt64 {
  self.frame
  .binding_id(
    @view.NodeKey::new(
      if self.palette {
        "palette-toggle"
      } else {
        "spacing-toggle"
      },
    ),
  )
  .unwrap()
}

///|
pub fn CounterFrame::button_hovered(self : CounterFrame) -> Bool {
  self.frame.hovered(@view.NodeKey::new("increment"))
}

///|
pub fn CounterFrame::toggle_hovered(self : CounterFrame) -> Bool {
  self.frame.hovered(@view.NodeKey::new("palette-toggle"))
}

///|
pub fn CounterFrame::button_palette(
  self : CounterFrame,
) -> @view.ButtonPaletteToken? {
  self.frame.button_palette(@view.NodeKey::new("increment"))
}

///|
pub fn CounterFrame::toggle_palette(
  self : CounterFrame,
) -> @view.ButtonPaletteToken? {
  self.frame.button_palette(@view.NodeKey::new("palette-toggle"))
}

///|
pub fn CounterFrame::toggle_enabled(self : CounterFrame) -> Bool {
  self.frame.enabled(@view.NodeKey::new("palette-toggle"))
}

///|
pub fn CounterFrame::toggle_loading(self : CounterFrame) -> Bool {
  self.frame.loading(@view.NodeKey::new("palette-toggle"))
}

///|
/// Read-only successful input dispatch witness; see Mounted's admission contract.
pub fn NativeCounter::last_dispatched_input_sequence(
  self : NativeCounter,
) -> Int64 {
  self.mount.last_dispatched_input_sequence()
}
