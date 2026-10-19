///|
/// Semantic regions of one shared application shell. These are layout roles,
/// not a second widget hierarchy: each slot remains an ordinary View.
pub(all) enum ShellRegion {
  Brand
  NavigationTrigger
  GlobalSearch
  HeaderActions
  AccountMenu
  Rail
  Sidebar
  Tabs
  Main
  ContextPanel
  BottomBar
} derive(Eq, @debug.Debug)

///|
pub fn ShellRegion::name(self : ShellRegion) -> String {
  match self {
    Brand => "brand"
    NavigationTrigger => "navigation-trigger"
    GlobalSearch => "global-search"
    HeaderActions => "header-actions"
    AccountMenu => "account-menu"
    Rail => "rail"
    Sidebar => "sidebar"
    Tabs => "tabs"
    Main => "main"
    ContextPanel => "context-panel"
    BottomBar => "bottom-bar"
  }
}

///|
/// The single shared breakpoint. 820.0 and below are compact; the browser CSS
/// uses the same max-width boundary. This is a logical-width comparison.
pub const SHELL_COMPACT_MAX_WIDTH : Double = 820.0

///|
pub(all) enum ShellMode {
  Wide
  Compact
} derive(Eq, @debug.Debug)

///|
pub fn ShellMode::for_width(width : Double) -> ShellMode {
  if width <= SHELL_COMPACT_MAX_WIDTH {
    Compact
  } else {
    Wide
  }
}

///|
/// Application-owned shell state. The shell never owns opening/closing state or
/// emits dismiss actions; the application passes the next state in its View.
pub struct ShellState {
  priv sidebar_collapsed : Bool
  priv mobile_sidebar_open : Bool
  priv context_panel_open : Bool
  priv primary_navigation_label : String
  priv workspace_navigation_label : String
  priv context_panel_label : String
} derive(Eq, @debug.Debug)

///|
pub fn ShellState::sidebar_collapsed(self : ShellState) -> Bool {
  self.sidebar_collapsed
}

///|
pub fn ShellState::mobile_sidebar_open(self : ShellState) -> Bool {
  self.mobile_sidebar_open
}

///|
pub fn ShellState::context_panel_open(self : ShellState) -> Bool {
  self.context_panel_open
}

///|
pub fn ShellState::primary_navigation_label(self : ShellState) -> String {
  self.primary_navigation_label
}

///|
pub fn ShellState::workspace_navigation_label(self : ShellState) -> String {
  self.workspace_navigation_label
}

///|
pub fn ShellState::context_panel_label(self : ShellState) -> String {
  self.context_panel_label
}

///|
fn tag_region(view : View, region : ShellRegion) -> View {
  { ..view, region: Some(region), }
}

///|
/// Build the additive shared AppShell. Brand and main are required; every other
/// region is optional. The slot Views are copied and tagged without changing
/// their own kind, labels, gates or children. The application owns the shell
/// state and every action; this constructor adds no new SemanticAction.
pub fn app_shell(
  key : NodeKey,
  brand : View,
  main : View,
  navigation_trigger? : View,
  global_search? : View,
  header_actions? : View,
  account_menu? : View,
  rail? : View,
  sidebar? : View,
  tabs? : View,
  context_panel? : View,
  bottom_bar? : View,
  sidebar_collapsed~ : Bool = false,
  mobile_sidebar_open~ : Bool = false,
  context_panel_open~ : Bool = false,
  primary_navigation_label~ : String = "Primary",
  workspace_navigation_label~ : String = "Workspace navigation",
  context_panel_label~ : String = "Context panel",
) -> View {
  let children : Array[View] = [tag_region(brand, Brand)]
  match navigation_trigger {
    Some(view) => children.push(tag_region(view, NavigationTrigger))
    None => ()
  }
  match global_search {
    Some(view) => children.push(tag_region(view, GlobalSearch))
    None => ()
  }
  match header_actions {
    Some(view) => children.push(tag_region(view, HeaderActions))
    None => ()
  }
  match account_menu {
    Some(view) => children.push(tag_region(view, AccountMenu))
    None => ()
  }
  match rail {
    Some(view) => children.push(tag_region(view, Rail))
    None => ()
  }
  match sidebar {
    Some(view) => children.push(tag_region(view, Sidebar))
    None => ()
  }
  match tabs {
    Some(view) => children.push(tag_region(view, Tabs))
    None => ()
  }
  children.push(tag_region(main, Main))
  match context_panel {
    Some(view) => children.push(tag_region(view, ContextPanel))
    None => ()
  }
  match bottom_bar {
    Some(view) => children.push(tag_region(view, BottomBar))
    None => ()
  }
  {
    key,
    kind: AppShell,
    label: "",
    disabled: false,
    loading: false,
    card: false,
    spacing: None,
    button_palette: None,
    region: None,
    text_field_props: None,
    dialog_props: None,
    shell: Some({
      sidebar_collapsed,
      mobile_sidebar_open,
      context_panel_open,
      primary_navigation_label,
      workspace_navigation_label,
      context_panel_label,
    }),
    children,
  }
}

///|
pub fn View::is_shell(self : View) -> Bool {
  self.kind == AppShell
}

///|
pub fn View::shell(self : View) -> ShellState? {
  self.shell
}

///|
pub fn View::shell_region(self : View) -> ShellRegion? {
  self.region
}

///|
/// Region visibility for one viewport mode. This is the shared contract used by
/// the DOM (through the same CSS boundary) and the GPUI adapter. A hidden
/// region keeps its View identity but must not receive focus or activation.
pub fn ShellRegion::visible(
  self : ShellRegion,
  state : ShellState,
  mode : ShellMode,
) -> Bool {
  match (self, mode) {
    (Brand, _) | (GlobalSearch, _) | (HeaderActions, _) | (AccountMenu, _) =>
      true
    (NavigationTrigger, Wide) => false
    (NavigationTrigger, Compact) => true
    (Rail, Wide) => true
    (Rail, Compact) => false
    (Sidebar, Wide) => !state.sidebar_collapsed
    (Sidebar, Compact) => state.mobile_sidebar_open
    (Tabs, _) | (Main, _) | (BottomBar, _) => true
    (ContextPanel, _) => state.context_panel_open
  }
}

///|
pub extend ShellRegion with Eq::{equal, not_equal}

///|
pub extend ShellRegion with @debug.Debug::{to_repr}

///|
pub extend ShellMode with Eq::{equal, not_equal}

///|
pub extend ShellMode with @debug.Debug::{to_repr}

///|
pub extend ShellState with Eq::{equal, not_equal}

///|
pub extend ShellState with @debug.Debug::{to_repr}
