///|
/// The bounded shared AppShell demo. One application owner holds the existing
/// counter and the shell's open state; the shell itself owns no state and emits
/// no dismiss actions.
pub struct ShellModel {
  priv palette : PaletteModel
  priv sidebar_open : Bool
  priv context_open : Bool
} derive(Eq, @debug.Debug)

///|
pub fn ShellModel::new() -> ShellModel {
  { palette: PaletteModel::new(), sidebar_open: false, context_open: false, }
}

///|
pub fn ShellModel::value(self : ShellModel) -> Int {
  self.palette.value()
}

///|
pub fn ShellModel::sidebar_open(self : ShellModel) -> Bool {
  self.sidebar_open
}

///|
pub fn ShellModel::context_open(self : ShellModel) -> Bool {
  self.context_open
}

///|
fn counter_action(action : @core.SemanticAction) -> @core.SemanticAction {
  match action {
    @core.Activate(key) if key == @core.NodeKey::new("sidebar-increment") ||
      key == @core.NodeKey::new("increment") =>
      @core.Activate(@core.NodeKey::new("increment"))
    _ => action
  }
}

///|
pub fn ShellModel::update(
  self : ShellModel,
  action : @core.SemanticAction,
) -> ShellModel {
  match action {
    @core.Activate(key) if key == @core.NodeKey::new("toggle-sidebar") =>
      { ..self, sidebar_open: !self.sidebar_open, }
    @core.Activate(key) if key == @core.NodeKey::new("toggle-context") =>
      { ..self, context_open: !self.context_open, }
    _ =>
      { ..self, palette: self.palette.update_counter(counter_action(action)), }
  }
}

///|
pub fn ShellModel::update_counter(
  self : ShellModel,
  action : @core.SemanticAction,
) -> ShellModel {
  { ..self, palette: self.palette.update_counter(counter_action(action)), }
}

///|
/// The same model/view/update is compiled by the DOM and native consumers.
/// Optional regions are always present so tests can exercise open/close without
/// changing the keyed tree; visibility is a shared state decision.
pub fn ShellModel::view(self : ShellModel) -> @core.View {
  let main = @core.column(@core.NodeKey::new("counter"), [
    @core.text(@core.NodeKey::new("heading"), "Shared AppShell"),
    @core.text(@core.NodeKey::new("value"), "Count: \{self.value()}"),
    @core.button(@core.NodeKey::new("increment"), "Increment"),
  ])
  @core.app_shell(
    @core.NodeKey::new("shell"),
    @core.text(@core.NodeKey::new("brand"), "Yami-kumo"),
    main,
    navigation_trigger=@core.button(
      @core.NodeKey::new("navigation-trigger"),
      "Menu",
    ),
    global_search=@core.text(@core.NodeKey::new("global-search"), "Search"),
    header_actions=@core.button(
      @core.NodeKey::new("toggle-context"),
      "Toggle context",
    ),
    account_menu=@core.text(@core.NodeKey::new("account-menu"), "Account"),
    rail=@core.text(@core.NodeKey::new("rail"), "Rail"),
    sidebar=@core.column(@core.NodeKey::new("sidebar"), [
      @core.text(@core.NodeKey::new("sidebar-heading"), "Workspace"),
      @core.button(@core.NodeKey::new("sidebar-increment"), "Sidebar increment"),
    ]),
    tabs=@core.text(@core.NodeKey::new("tabs"), "Overview"),
    context_panel=@core.text(@core.NodeKey::new("context-panel"), "Context"),
    bottom_bar=@core.text(@core.NodeKey::new("bottom-bar"), "Ready"),
    sidebar_collapsed=false,
    mobile_sidebar_open=self.sidebar_open,
    context_panel_open=self.context_open,
    primary_navigation_label="Primary",
    workspace_navigation_label="Workspace navigation",
    context_panel_label="Context panel",
  )
}

///|
pub extend ShellModel with Eq::{equal, not_equal}

///|
pub extend ShellModel with @debug.Debug::{to_repr}
