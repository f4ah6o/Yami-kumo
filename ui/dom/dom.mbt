///|
#external
priv type DomNode

///|
#external
priv type RootRegistry

///|
extern "js" fn new_registry() -> RootRegistry =
  #| () => new Set()

///|
let roots : RootRegistry = new_registry()

///|
extern "js" fn document_available() -> Bool =
  #| () => typeof document !== "undefined" && typeof document.getElementById === "function"

///|
extern "js" fn find_root(id : String) -> DomNode =
  #| (id) => document.getElementById(id)

///|
extern "js" fn node_present(node : DomNode) -> Bool =
  #| (node) => node !== null

///|
extern "js" fn claim_root(registry : RootRegistry, root : DomNode) -> Int =
  #| (registry, root) => {
  #|   for (const other of registry) {
  #|     if (other === root) return 1;
  #|     if (other.contains(root) || root.contains(other)) return 2;
  #|   }
  #|   if (root.childNodes.length !== 0) return 3;
  #|   registry.add(root);
  #|   return 0;
  #| }

///|
extern "js" fn release_root(registry : RootRegistry, root : DomNode) -> Unit =
  #| (registry, root) => { registry.delete(root); }

///|
extern "js" fn contains_node(root : DomNode, node : DomNode) -> Bool =
  #| (root, node) => root.contains(node)

///|
extern "js" fn accepts_events(root : DomNode, node : DomNode) -> Bool =
  #| (root, node) => root.isConnected && root.contains(node) &&
  #|   node.getClientRects().length > 0

///|
#external
priv type RootThemeState

///|
extern "js" fn root_theme_state(root : DomNode) -> RootThemeState =
  #| (root) => ({
  #|   previousName: root.getAttribute("data-yk-theme"),
  #|   previousClass: root.classList.contains("yk-ui-root"),
  #|   previousClassAttribute: root.hasAttribute("class"),
  #|   current: null
  #| })

///|
extern "js" fn root_theme_unchanged(
  state : RootThemeState,
  root : DomNode,
) -> Bool =
  #| (state, root) => state.current === null ||
  #|   (root.getAttribute("data-yk-theme") === state.current && root.classList.contains("yk-ui-root"))

///|
extern "js" fn apply_root_theme(
  state : RootThemeState,
  root : DomNode,
  name : String,
) -> Unit =
  #| (state, root, name) => {
  #|   if (name !== "") {
  #|     if (state.current === null) {
  #|       state.previousName = root.getAttribute("data-yk-theme");
  #|       state.previousClass = root.classList.contains("yk-ui-root");
  #|       state.previousClassAttribute = root.hasAttribute("class");
  #|     }
  #|     root.classList.add("yk-ui-root");
  #|     root.setAttribute("data-yk-theme", name);
  #|     state.current = name;
  #|     return;
  #|   }
  #|   if (state.current === null) return;
  #|   // A host edit is no longer ours to overwrite during teardown.
  #|   if (root.getAttribute("data-yk-theme") === state.current) {
  #|     if (state.previousName === null) root.removeAttribute("data-yk-theme");
  #|     else root.setAttribute("data-yk-theme", state.previousName);
  #|   }
  #|   if (!state.previousClass) {
  #|     root.classList.remove("yk-ui-root");
  #|     if (!state.previousClassAttribute && root.getAttribute("class") === "") root.removeAttribute("class");
  #|   }
  #|   state.current = null;
  #| }

///|
#external
priv type ShellNodes

///|
/// Build the fixed semantic skeleton once per mounted shell. Optional wrappers
/// stay in the DOM and are hidden with data-present=false so slot identity and
/// wrapper order never depend on the current open state.
extern "js" fn create_shell_nodes(shell : DomNode) -> ShellNodes =
  #| (shell) => {
  #|   const make = (tag, cls) => {
  #|     const node = document.createElement(tag);
  #|     node.className = cls;
  #|     node.setAttribute("data-present", "false");
  #|     return node;
  #|   };
  #|   const header = make("header", "yk-ui-topbar");
  #|   const brandGroup = make("div", "yk-ui-brand-group");
  #|   const navigationTrigger = make("div", "yk-ui-navigation-trigger");
  #|   const globalSearch = make("div", "yk-ui-global-search");
  #|   const headerEnd = make("div", "yk-ui-header-end");
  #|   const headerActions = make("div", "yk-ui-header-actions");
  #|   const accountMenu = make("div", "yk-ui-account-menu");
  #|   const rail = make("nav", "yk-ui-rail");
  #|   const sidebar = make("aside", "yk-ui-sidebar");
  #|   const workspace = make("section", "yk-ui-workspace");
  #|   const mainColumn = make("div", "yk-ui-main-column");
  #|   const tabs = make("nav", "yk-ui-tabs");
  #|   const main = make("main", "yk-ui-main");
  #|   const context = make("aside", "yk-ui-context-panel");
  #|   const bottom = make("footer", "yk-ui-bottom-bar");
  #|   header.setAttribute("data-present", "true");
  #|   brandGroup.setAttribute("data-present", "true");
  #|   headerEnd.setAttribute("data-present", "false");
  #|   workspace.setAttribute("data-present", "true");
  #|   mainColumn.setAttribute("data-present", "true");
  #|   main.setAttribute("data-present", "true");
  #|   brandGroup.append(navigationTrigger);
  #|   header.append(brandGroup, globalSearch, headerEnd);
  #|   headerEnd.append(headerActions, accountMenu);
  #|   mainColumn.append(tabs, main);
  #|   workspace.append(rail, sidebar, mainColumn, context);
  #|   shell.append(header, workspace, bottom);
  #|   return {
  #|     header, brandGroup, navigationTrigger, globalSearch, headerEnd,
  #|     headerActions, accountMenu, rail, sidebar, workspace, mainColumn,
  #|     tabs, main, context, bottom,
  #|   };
  #| }

///|
extern "js" fn shell_wrapper(nodes : ShellNodes, name : String) -> DomNode =
  #| (nodes, name) => nodes[name]

///|
extern "js" fn update_shell_nodes(
  nodes : ShellNodes,
  has_navigation_trigger : Bool,
  has_global_search : Bool,
  has_header_actions : Bool,
  has_account_menu : Bool,
  has_rail : Bool,
  has_sidebar : Bool,
  has_tabs : Bool,
  has_context_panel : Bool,
  has_bottom_bar : Bool,
  sidebar_collapsed : Bool,
  mobile_sidebar_open : Bool,
  context_panel_open : Bool,
  primary_label : String,
  workspace_label : String,
  context_label : String,
) -> Unit =
  #| (nodes, hasNavigationTrigger, hasGlobalSearch, hasHeaderActions,
  #|   hasAccountMenu, hasRail, hasSidebar, hasTabs, hasContextPanel,
  #|   hasBottomBar, sidebarCollapsed, mobileSidebarOpen, contextPanelOpen,
  #|   primaryLabel, workspaceLabel, contextLabel) => {
  #|   const present = (node, value) => node.setAttribute("data-present", value ? "true" : "false");
  #|   present(nodes.navigationTrigger, hasNavigationTrigger);
  #|   present(nodes.globalSearch, hasGlobalSearch);
  #|   present(nodes.headerActions, hasHeaderActions);
  #|   present(nodes.accountMenu, hasAccountMenu);
  #|   present(nodes.headerEnd, hasHeaderActions || hasAccountMenu);
  #|   present(nodes.rail, hasRail);
  #|   present(nodes.sidebar, hasSidebar);
  #|   present(nodes.tabs, hasTabs);
  #|   present(nodes.context, hasContextPanel);
  #|   present(nodes.bottom, hasBottomBar);
  #|   const shell = nodes.header.parentNode;
  #|   shell.setAttribute("data-has-rail", hasRail ? "true" : "false");
  #|   shell.setAttribute("data-has-sidebar", hasSidebar ? "true" : "false");
  #|   shell.setAttribute("data-sidebar-collapsed", sidebarCollapsed ? "true" : "false");
  #|   shell.setAttribute("data-mobile-sidebar-open", mobileSidebarOpen ? "true" : "false");
  #|   shell.setAttribute("data-has-context-panel", hasContextPanel ? "true" : "false");
  #|   shell.setAttribute("data-context-panel-open", contextPanelOpen ? "true" : "false");
  #|   shell.setAttribute("data-has-bottom-bar", hasBottomBar ? "true" : "false");
  #|   shell.setAttribute("data-has-tabs", hasTabs ? "true" : "false");
  #|   nodes.rail.setAttribute("aria-label", primaryLabel);
  #|   nodes.sidebar.setAttribute("aria-label", workspaceLabel);
  #|   nodes.context.setAttribute("aria-label", contextLabel);
  #|   nodes.tabs.setAttribute("aria-label", "Workspace tabs");
  #| }

///|
extern "js" fn node_visible(node : DomNode) -> Bool =
  #| (node) => !!node && node.isConnected && node.getClientRects().length > 0

///|
extern "js" fn create_node(
  kind : Int,
  key : String,
  label : String,
) -> DomNode =
  #| (kind, key, label) => {
  #|   // One element per semantic child keeps adjacent Text views distinct flex items.
  #|   if (kind === 5) {
  #|     const wrapper = document.createElement("div");
  #|     wrapper.className = "yk-ui-field";
  #|     wrapper.setAttribute("data-yk-key", key);
  #|     const labelNode = document.createElement("label");
  #|     labelNode.className = "yk-ui-field-label";
  #|     const labelText = document.createElement("span");
  #|     labelText.className = "yk-ui-field-label-text";
  #|     labelText.textContent = label;
  #|     const input = document.createElement("input");
  #|     input.type = "text";
  #|     input.className = "yk-ui-field-input";
  #|     labelNode.append(labelText, input);
  #|     const description = document.createElement("span");
  #|     description.className = "yk-ui-field-description";
  #|     wrapper.append(labelNode, description);
  #|     return wrapper;
  #|   }
  #|   const node = document.createElement(kind === 0 ? "span" : kind === 1 ? "button" : "div");
  #|   node.setAttribute("data-yk-key", key);
  #|   if (kind === 0) {
  #|     node.className = "yk-ui-text";
  #|     node.textContent = label;
  #|   } else if (kind === 1) {
  #|     node.type = "button";
  #|     node.className = "yk-ui-button";
  #|     node.textContent = label;
  #|   } else {
  #|     node.className = kind === 2 ? "yk-ui-column" : kind === 3 ? "yk-ui-row" : "yk-ui-shell";
  #|   }
  #|   return node;
  #| }

///|
extern "js" fn update_node(
  node : DomNode,
  kind : Int,
  label : String,
  disabled : Bool,
  loading : Bool,
  card : Bool,
) -> Unit =
  #| (node, kind, label, disabled, loading, card) => {
  #|   if (kind === 2) node.classList.toggle("yk-ui-card", card);
  #|   if (kind === 0) { if (node.textContent !== label) node.textContent = label; return; }
  #|   if (kind !== 1) return;
  #|   if (node.textContent !== label) node.textContent = label;
  #|   if (node.disabled !== disabled) node.disabled = disabled;
  #|   if (loading) {
  #|     if (node.getAttribute("aria-busy") !== "true") node.setAttribute("aria-busy", "true");
  #|     if (node.getAttribute("aria-disabled") !== "true") node.setAttribute("aria-disabled", "true");
  #|   } else {
  #|     node.removeAttribute("aria-busy");
  #|     node.removeAttribute("aria-disabled");
  #|   }
  #| }

///|
/// Closed token classes only: no inline style, stylesheet injection or coercion.
extern "js" fn update_spacing(
  node : DomNode,
  gap : Int,
  padding : Int,
) -> Unit =
  #| (node, gap, padding) => {
  #|   for (const value of [0, 4, 8, 12, 16, 24]) {
  #|     node.classList.toggle(`yk-ui-gap-${value}`, gap === value);
  #|     node.classList.toggle(`yk-ui-padding-${value}`, padding === value);
  #|   }
  #| }

///|
/// Paint-only closed classes; removal restores the unstyled legacy control.
extern "js" fn update_button_palette(node : DomNode, palette : Int) -> Unit =
  #| (node, palette) => {
  #|   node.classList.toggle("yk-ui-button-light", palette === 1);
  #|   node.classList.toggle("yk-ui-button-dark", palette === 2);
  #| }

///|
#external
priv type ButtonEvents

///|
/// Browser click remains the only Activate source. These listeners only cancel
/// browser defaults/admission when an observed gesture crosses a gate change;
/// they never synthesize clicks, capture a pointer, or implement key activation.
extern "js" fn add_button_events(
  node : DomNode,
  callback : () -> Unit,
) -> ButtonEvents =
  #| (node, callback) => {
  #|   let disabled = false, loading = false;
  #|   const pointers = new Map();
  #|   const keys = new Map();
  #|   const unavailable = () => disabled || loading;
  #|   const cancel = () => {
  #|     for (const key of keys.keys()) keys.set(key, true);
  #|     for (const pointer of pointers.values()) pointer.cancelled = true;
  #|   };
  #|   const activationKey = event => event.key === " " || event.key === "Enter";
  #|   const keydown = event => {
  #|     if (!activationKey(event)) return;
  #|     if (!event.repeat) keys.set(event.key, unavailable());
  #|     if (unavailable() || keys.get(event.key)) event.preventDefault();
  #|   };
  #|   const keyup = event => {
  #|     if (!activationKey(event)) return;
  #|     // In particular, cancel Space's browser-generated click synchronously.
  #|     if (unavailable() || keys.get(event.key)) event.preventDefault();
  #|     keys.delete(event.key);
  #|   };
  #|   const pointerdown = event => {
  #|     if (event.button !== 0 || !event.isPrimary) return;
  #|     // At most one latest primary gesture per browser pointer type. A new
  #|     // primary down replaces even an old release delivered outside this node.
  #|     pointers.set(event.pointerType, {id: event.pointerId, cancelled: unavailable()});
  #|   };
  #|   const pointercancel = event => {
  #|     const pointer = pointers.get(event.pointerType);
  #|     if (pointer?.id === event.pointerId) pointer.cancelled = true;
  #|   };
  #|   const click = event => {
  #|     // Independent detail=0 clicks (including AT-like/programmatic input)
  #|     // need no preceding keyboard event. Key cancellation lives in keyup.
  #|     const pointer = event.detail > 0 ? pointers.get(event.pointerType) : undefined;
  #|     const matches = pointer && pointer.id === event.pointerId;
  #|     if (matches) pointers.delete(event.pointerType);
  #|     if (unavailable() || (matches && pointer.cancelled)) {
  #|       event.preventDefault();
  #|       return;
  #|     }
  #|     callback();
  #|   };
  #|   const listeners = {click, keydown, keyup, pointerdown, pointercancel, blur: cancel};
  #|   for (const [type, listener] of Object.entries(listeners)) node.addEventListener(type, listener);
  #|   return {
  #|     update(nextDisabled, nextLoading) {
  #|       if (disabled !== nextDisabled || loading !== nextLoading) cancel();
  #|       disabled = nextDisabled;
  #|       loading = nextLoading;
  #|     },
  #|     dispose() {
  #|       for (const [type, listener] of Object.entries(listeners)) node.removeEventListener(type, listener);
  #|       keys.clear();
  #|       pointers.clear();
  #|     }
  #|   };
  #| }

///|
extern "js" fn update_button_events(
  events : ButtonEvents,
  disabled : Bool,
  loading : Bool,
) -> Unit =
  #| (events, disabled, loading) => events.update(disabled, loading)

///|
extern "js" fn remove_button_events(events : ButtonEvents) -> Unit =
  #| events => events.dispose()

///|
#external
priv type TextFieldEvents

///|
/// The browser input is the editing surface; the common TextField value is the
/// only committed document. Composition events are not published as
/// TextChanged. Enter submits only when no composition is active.
extern "js" fn add_text_field_events(
  node : DomNode,
  on_change : (String) -> Unit,
  on_submit : () -> Unit,
) -> TextFieldEvents =
  #| (node, on_change, on_submit) => {
  #|   const input = node.querySelector("input");
  #|   node._ykLastPublished = input.value;
  #|   const setComposing = value => {
  #|     if (value) node.dataset.ykComposing = "true";
  #|     else delete node.dataset.ykComposing;
  #|   };
  #|   const publish = value => {
  #|     if (value === node._ykLastPublished) return;
  #|     node._ykLastPublished = value;
  #|     on_change(value);
  #|   };
  #|   const inputHandler = event => {
  #|     if (event.isComposing || node.dataset.ykComposing === "true") return;
  #|     publish(input.value);
  #|   };
  #|   const compositionStart = () => setComposing(true);
  #|   const compositionEnd = () => {
  #|     setComposing(false);
  #|     const pending = node._ykPendingValue;
  #|     const pendingRevision = node._ykPendingRevision;
  #|     delete node._ykPendingValue;
  #|     delete node._ykPendingRevision;
  #|     if (pending !== undefined) {
  #|       if (input.value !== pending) {
  #|         input.value = pending;
  #|         input.setSelectionRange(pending.length, pending.length);
  #|       }
  #|       if (pendingRevision !== undefined) node._ykExternalRevision = pendingRevision;
  #|       node._ykLastPublished = input.value;
  #|       return;
  #|     }
  #|     publish(input.value);
  #|   };
  #|   const keydown = event => {
  #|     if (event.key === "Enter" && !event.isComposing &&
  #|         node.dataset.ykComposing !== "true") {
  #|       event.preventDefault();
  #|       on_submit();
  #|     }
  #|   };
  #|   const listeners = {input: inputHandler, compositionstart: compositionStart,
  #|     compositionend: compositionEnd, keydown};
  #|   for (const [type, listener] of Object.entries(listeners)) input.addEventListener(type, listener);
  #|   return {
  #|     dispose() {
  #|       for (const [type, listener] of Object.entries(listeners)) input.removeEventListener(type, listener);
  #|       setComposing(false);
  #|     },
  #|   };
  #| }

///|
extern "js" fn remove_text_field_events(events : TextFieldEvents) -> Unit =
  #| events => events.dispose()

///|
extern "js" fn update_text_field(
  node : DomNode,
  value : String,
  revision : UInt64,
  label : String,
  description : String,
  error : String,
  required : Bool,
  disabled : Bool,
  read_only : Bool,
) -> Unit =
  #| (node, value, revision, label, description, error, required, disabled, readOnly) => {
  #|   const input = node.querySelector("input");
  #|   const labelText = node.querySelector(".yk-ui-field-label-text");
  #|   const desc = node.querySelector(".yk-ui-field-description");
  #|   if (labelText && labelText.textContent !== label) labelText.textContent = label;
  #|   const composing = node.dataset.ykComposing === "true";
  #|   const lastExternal = node._ykExternalRevision;
  #|   const newerExternal = lastExternal === undefined || revision > lastExternal;
  #|   if (composing && input && newerExternal) {
  #|     if (node._ykPendingRevision === undefined || revision >= node._ykPendingRevision) {
  #|       node._ykPendingValue = value;
  #|       node._ykPendingRevision = revision;
  #|     }
  #|   }
  #|   if (input && !composing) {
  #|     const focused = document.activeElement === input;
  #|     const sameRevision = node._ykExternalRevision === revision;
  #|     // A focused, same-revision render is a stale echo of the value the app
  #|     // already received; writing it back would roll the input backwards.
  #|     if (!sameRevision || !focused) {
  #|       if (input.value !== value) {
  #|         const start = input.selectionStart;
  #|         const end = input.selectionEnd;
  #|         input.value = value;
  #|         if (focused) {
  #|           const limit = value.length;
  #|           input.setSelectionRange(Math.min(start ?? limit, limit), Math.min(end ?? limit, limit));
  #|         }
  #|       }
  #|       node._ykExternalRevision = revision;
  #|       node._ykLastPublished = value;
  #|     }
  #|   }
  #|   if (desc) {
  #|     desc.textContent = error !== "" ? error : description;
  #|     desc.classList.toggle("yk-ui-field-error", error !== "");
  #|   }
  #|   if (input) {
  #|     input.required = required;
  #|     input.disabled = disabled;
  #|     input.readOnly = readOnly;
  #|     input.setAttribute("aria-label", label);
  #|     if (error !== "") input.setAttribute("aria-invalid", "true");
  #|     else input.removeAttribute("aria-invalid");
  #|     const help = error !== "" ? error : description;
  #|     if (help !== "") input.setAttribute("aria-description", help);
  #|     else input.removeAttribute("aria-description");
  #|   }
  #| }

///|
extern "js" fn enqueue_microtask(callback : () -> Unit) -> Unit =
  #| (callback) => queueMicrotask(callback)

///|
extern "js" fn position_child(
  parent : DomNode,
  node : DomNode,
  index : Int,
) -> Unit =
  #| (parent, node, index) => {
  #|   const before = parent.childNodes[index] || null;
  #|   if (before === node) return;
  #|   if (typeof parent.moveBefore === "function" && node.parentNode &&
  #|       node.isConnected === parent.isConnected) parent.moveBefore(node, before);
  #|   else parent.insertBefore(node, before);
  #| }

///|
extern "js" fn remove_owned_node(root : DomNode, node : DomNode) -> Unit =
  #| (root, node) => { if (root.contains(node)) node.remove(); }

///|
extern "js" fn active_element() -> DomNode =
  #| () => document.activeElement

///|
extern "js" fn restore_focus(root : DomNode, node : DomNode) -> Unit =
  #| (root, node) => {
  #|   if (node && root.contains(node) && node.getClientRects().length > 0 && !node.disabled &&
  #|       document.activeElement !== node && typeof node.focus === "function") node.focus({preventScroll: true});
  #| }

///|
extern "js" fn focus_observed(root : DomNode, node : DomNode) -> Bool =
  #| (root, node) => {
  #|   const target = node.classList && node.classList.contains("yk-ui-field")
  #|     ? node.querySelector("input") : node;
  #|   if (!target || !root.isConnected || !root.contains(node) ||
  #|       node.getClientRects().length === 0 || target.disabled ||
  #|       typeof target.focus !== "function") return false;
  #|   target.focus({preventScroll: true});
  #|   return document.activeElement === target;
  #| }

///|
pub(all) enum DomError {
  MissingDocument
  MissingRoot
  RootAlreadyMounted
  OverlappingRoot
  RootNotEmpty
  Disposed
  HostTreeChanged
  InvalidShell
  InvalidView(@runtime.CommitError)
} derive(Eq, @debug.Debug)

///|
priv struct MountedNode {
  token : @runtime.InstanceToken
  node : DomNode
  events : ButtonEvents?
  text_events : TextFieldEvents?
  shell : ShellNodes?
}

///|
/// An explicitly mounted DOM root. No DOM listeners are installed by import.
/// The application owns its model; this object owns only host nodes/lifetimes.
pub struct DomRoot {
  priv root : DomNode
  priv root_theme : RootThemeState
  priv runtime : @runtime.Runtime
  priv nodes : Map[String, MountedNode]
  priv scheduled : Ref[Bool]
  priv mut shell_root : Bool
  priv on_actions : () -> Unit
}

///|
/// Mount into an empty element addressed by its literal document ID. Existing
/// content, another mounted root and ancestor/descendant root overlap are rejected.
pub fn mount(
  root_id : String,
  view : @core.View,
  on_actions : () -> Unit,
  theme~ : @theme.Theme? = None,
) -> Result[DomRoot, DomError] {
  if !document_available() {
    return Err(MissingDocument)
  }
  let root = find_root(root_id)
  if !node_present(root) {
    return Err(MissingRoot)
  }
  match claim_root(roots, root) {
    1 => return Err(RootAlreadyMounted)
    2 => return Err(OverlappingRoot)
    3 => return Err(RootNotEmpty)
    _ => ()
  }
  let mounted : DomRoot = {
    root,
    root_theme: root_theme_state(root),
    runtime: @runtime.Runtime::new(),
    nodes: {},
    scheduled: Ref(false),
    shell_root: false,
    on_actions,
  }
  match mounted.update(view) {
    Ok(_) =>
      match mounted.set_theme(theme) {
        Ok(_) => Ok(mounted)
        Err(error) => {
          mounted.dispose()
          Err(error)
        }
      }
    Err(error) => {
      mounted.dispose()
      Err(error)
    }
  }
}

///|
/// Change only the root's scoped palette. No view commit, node replacement,
/// focus operation or input-controller update is needed for a paint change.
/// An explicit per-Button palette retains its colors and focus-visible style.
/// None removes this root's opt-in and restores its original host attributes.
pub fn DomRoot::set_theme(
  self : DomRoot,
  theme : @theme.Theme?,
) -> Result[Unit, DomError] {
  if self.runtime.is_disposed() {
    return Err(Disposed)
  }
  for _, mounted in self.nodes {
    if !contains_node(self.root, mounted.node) {
      return Err(HostTreeChanged)
    }
  }
  if !root_theme_unchanged(self.root_theme, self.root) {
    return Err(HostTreeChanged)
  }
  apply_root_theme(
    self.root_theme,
    self.root,
    match theme {
      Some(theme) => theme.name()
      None => ""
    },
  )
  Ok(())
}

///|
fn kind_number(kind : @core.NodeKind) -> Int {
  match kind {
    Text => 0
    Button => 1
    Column => 2
    Row => 3
    AppShell => 4
    TextField => 5
  }
}

///|
fn DomRoot::schedule_actions(self : DomRoot) -> Unit {
  if self.scheduled.val {
    return
  }
  self.scheduled.val = true
  enqueue_microtask(fn() {
    self.scheduled.val = false
    if !self.runtime.is_disposed() {
      (self.on_actions)()
    }
  })
}

///|
fn DomRoot::render_node(
  self : DomRoot,
  view : @core.View,
  parent : DomNode,
  index : Int,
) -> Unit {
  let key = view.key().value()
  let kind = view.kind()
  let token = self.runtime.token(view.key()).unwrap()
  let mut mounted = match self.nodes.get(key) {
    Some(existing) => existing
    None => {
      let node = create_node(kind_number(kind), key, view.label())
      let events = if kind == @core.Button {
        let callback = fn() {
          if accepts_events(self.root, node) &&
            self.runtime.enqueue_activate(token) {
            self.schedule_actions()
          }
        }
        Some(add_button_events(node, callback))
      } else {
        None
      }
      let text_events = if kind == @core.TextField {
        let on_change = fn(value : String) {
          if accepts_events(self.root, node) &&
            self.runtime.enqueue_text_changed(token, value) {
            self.schedule_actions()
          }
        }
        let on_submit = fn() {
          if accepts_events(self.root, node) &&
            self.runtime.enqueue_submitted(token) {
            self.schedule_actions()
          }
        }
        Some(add_text_field_events(node, on_change, on_submit))
      } else {
        None
      }
      let item = { token, node, events, text_events, shell: None, }
      self.nodes.set(key, item)
      item
    }
  }
  match mounted.events {
    Some(events) =>
      update_button_events(events, view.disabled(), view.loading())
    None => ()
  }
  update_node(
    mounted.node,
    kind_number(kind),
    view.label(),
    view.disabled(),
    view.loading(),
    view.is_card(),
  )
  if kind == @core.TextField {
    match view.text_field_props() {
      Some(props) =>
        update_text_field(
          mounted.node,
          props.value(),
          props.revision(),
          props.label(),
          props.description(),
          match props.error() {
            Some(error) => error
            None => ""
          },
          props.required(),
          props.disabled(),
          props.read_only(),
        )
      None => ()
    }
  }
  if kind == @core.Button {
    update_button_palette(
      mounted.node,
      match view.button_palette() {
        None => 0
        Some(Light) => 1
        Some(Dark) => 2
      },
    )
  }
  if kind == @core.Row || kind == @core.Column {
    match view.spacing() {
      Some(spacing) =>
        update_spacing(
          mounted.node,
          spacing.gap().pixels().to_int(),
          spacing.padding().pixels().to_int(),
        )
      None => update_spacing(mounted.node, -1, -1)
    }
  }
  // Place parents before children. A retained former descendant can become an
  // ancestor in the next tree; detach its old ancestry before moving children.
  position_child(parent, mounted.node, index)
  if kind == @core.AppShell {
    let shell = match mounted.shell {
      Some(nodes) => nodes
      None => {
        let nodes = create_shell_nodes(mounted.node)
        mounted = { ..mounted, shell: Some(nodes), }
        self.nodes.set(key, mounted)
        nodes
      }
    }
    let children = view.children()
    let mut has_navigation_trigger = false
    let mut has_global_search = false
    let mut has_header_actions = false
    let mut has_account_menu = false
    let mut has_rail = false
    let mut has_sidebar = false
    let mut has_tabs = false
    let mut has_context_panel = false
    let mut has_bottom_bar = false
    for child in children {
      match child.shell_region() {
        Some(NavigationTrigger) => has_navigation_trigger = true
        Some(GlobalSearch) => has_global_search = true
        Some(HeaderActions) => has_header_actions = true
        Some(AccountMenu) => has_account_menu = true
        Some(Rail) => has_rail = true
        Some(Sidebar) => has_sidebar = true
        Some(Tabs) => has_tabs = true
        Some(ContextPanel) => has_context_panel = true
        Some(BottomBar) => has_bottom_bar = true
        Some(_) | None => ()
      }
    }
    let state = view.shell().unwrap()
    update_shell_nodes(
      shell,
      has_navigation_trigger,
      has_global_search,
      has_header_actions,
      has_account_menu,
      has_rail,
      has_sidebar,
      has_tabs,
      has_context_panel,
      has_bottom_bar,
      state.sidebar_collapsed(),
      state.mobile_sidebar_open(),
      state.context_panel_open(),
      state.primary_navigation_label(),
      state.workspace_navigation_label(),
      state.context_panel_label(),
    )
    for child in children {
      match child.shell_region() {
        Some(region) => {
          let (target, child_index) = match region {
            Brand =>
              (
                shell_wrapper(shell, "brandGroup"),
                if has_navigation_trigger {
                  1
                } else {
                  0
                },
              )
            NavigationTrigger => (shell_wrapper(shell, "brandGroup"), 0)
            GlobalSearch => (shell_wrapper(shell, "globalSearch"), 0)
            HeaderActions => (shell_wrapper(shell, "headerActions"), 0)
            AccountMenu => (shell_wrapper(shell, "accountMenu"), 0)
            Rail => (shell_wrapper(shell, "rail"), 0)
            Sidebar => (shell_wrapper(shell, "sidebar"), 0)
            Tabs => (shell_wrapper(shell, "tabs"), 0)
            Main => (shell_wrapper(shell, "main"), 0)
            ContextPanel => (shell_wrapper(shell, "context"), 0)
            BottomBar => (shell_wrapper(shell, "bottom"), 0)
          }
          self.render_node(child, target, child_index)
        }
        None => ()
      }
    }
    return
  }
  let children = view.children()
  for child_index = 0
      child_index < children.length()
      child_index = child_index + 1 {
    self.render_node(children[child_index], mounted.node, child_index)
  }
}

///|
/// A shell owns the root; nested shells and shell children without a region are
/// rejected before any runtime/DOM state changes. Non-shell roots remain valid.
fn validate_shell_tree(
  view : @core.View,
  depth : Int,
) -> Result[Unit, DomError] {
  if view.kind() == @core.AppShell {
    if depth != 0 {
      return Err(InvalidShell)
    }
    for child in view.children() {
      match child.shell_region() {
        None => return Err(InvalidShell)
        Some(_) => ()
      }
      match validate_shell_tree(child, depth + 1) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    }
  } else {
    for child in view.children() {
      match validate_shell_tree(child, depth + 1) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    }
  }
  Ok(())
}

///|
/// Validate the whole view before changing runtime ownership or DOM nodes.
/// Equal-key/equal-kind nodes and their click listener are retained.
pub fn DomRoot::update(
  self : DomRoot,
  view : @core.View,
) -> Result[Unit, DomError] {
  if self.runtime.is_disposed() {
    return Err(Disposed)
  }
  match validate_shell_tree(view, 0) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  for _, mounted in self.nodes {
    if !contains_node(self.root, mounted.node) {
      return Err(HostTreeChanged)
    }
  }
  match self.runtime.commit(view) {
    Err(error) => return Err(InvalidView(error))
    Ok(_) => ()
  }
  self.shell_root = view.is_shell()
  let focused = active_element()
  let removed : Array[String] = []
  for key, mounted in self.nodes {
    if !self.runtime.is_current(mounted.token) {
      match mounted.events {
        Some(events) => remove_button_events(events)
        None => ()
      }
      match mounted.text_events {
        Some(events) => remove_text_field_events(events)
        None => ()
      }
      remove_owned_node(self.root, mounted.node)
      removed.push(key)
    }
  }
  for key in removed {
    self.nodes.remove(key) |> ignore
  }
  self.render_node(view, self.root, 0)
  restore_focus(self.root, focused)
  Ok(())
}

///|
pub fn DomRoot::next_action(self : DomRoot) -> @core.SemanticAction? {
  if !self.shell_root {
    return self.runtime.next_action()
  }
  while self.runtime.next_action() is Some(action) {
    let key = match action {
      Activate(key) => key
      TextChanged(key, _) => key
      Submitted(key) => key
    }
    let visible = match self.nodes.get(key.value()) {
      Some(mounted) => node_visible(mounted.node)
      None => false
    }
    if visible {
      return Some(action)
    }
  }
  None
}

///|
/// Ask for focus and record the actual host outcome. A request never marks the
/// application focused before the DOM confirms it.
pub fn DomRoot::focus(self : DomRoot, key : @core.NodeKey) -> Bool {
  match self.nodes.get(key.value()) {
    None => false
    Some(mounted) =>
      match self.runtime.request_focus(mounted.token) {
        Err(_) => false
        Ok(request) => {
          let focused = focus_observed(self.root, mounted.node)
          self.runtime.complete_focus(
            request,
            if focused {
              @core.Focused
            } else {
              @core.Rejected
            },
          )
          |> ignore
          focused
        }
      }
  }
}

///|
pub fn DomRoot::next_focus_result(self : DomRoot) -> @runtime.FocusResult? {
  self.runtime.next_focus_result()
}

///|
/// Remove owned listeners and owned in-root nodes, then revoke the root. Already
/// queued microtasks become inert. Repeated calls do nothing.
pub fn DomRoot::dispose(self : DomRoot) -> Unit {
  if self.runtime.is_disposed() {
    return
  }
  self.runtime.dispose()
  for _, mounted in self.nodes {
    match mounted.events {
      Some(events) => remove_button_events(events)
      None => ()
    }
    match mounted.text_events {
      Some(events) => remove_text_field_events(events)
      None => ()
    }
    remove_owned_node(self.root, mounted.node)
  }
  self.nodes.clear()
  apply_root_theme(self.root_theme, self.root, "")
  release_root(roots, self.root)
}

///|
pub fn DomRoot::is_disposed(self : DomRoot) -> Bool {
  self.runtime.is_disposed()
}

///|
pub extend DomError with Eq::{equal, not_equal}

///|
pub extend DomError with @debug.Debug::{to_repr}
