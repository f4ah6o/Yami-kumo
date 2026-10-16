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
  #| (root, node) => root.isConnected && root.contains(node)

///|
extern "js" fn create_node(
  kind : Int,
  key : String,
  label : String,
) -> DomNode =
  #| (kind, key, label) => {
  #|   if (kind === 0) return document.createTextNode(label);
  #|   const node = document.createElement(kind === 1 ? "button" : "div");
  #|   node.setAttribute("data-yk-key", key);
  #|   if (kind === 1) {
  #|     node.type = "button";
  #|     node.textContent = label;
  #|   } else {
  #|     node.className = kind === 2 ? "yk-ui-column" : "yk-ui-row";
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
) -> Unit =
  #| (node, kind, label, disabled, loading) => {
  #|   if (kind === 0) { if (node.data !== label) node.data = label; return; }
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
extern "js" fn add_click(node : DomNode, callback : () -> Unit) -> Unit =
  #| (node, callback) => node.addEventListener("click", callback)

///|
extern "js" fn remove_click(node : DomNode, callback : () -> Unit) -> Unit =
  #| (node, callback) => node.removeEventListener("click", callback)

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
  #|   if (node && root.contains(node) && !node.disabled && document.activeElement !== node &&
  #|       typeof node.focus === "function") node.focus({preventScroll: true});
  #| }

///|
extern "js" fn focus_observed(root : DomNode, node : DomNode) -> Bool =
  #| (root, node) => {
  #|   if (!root.isConnected || !root.contains(node) || node.disabled || typeof node.focus !== "function") return false;
  #|   node.focus({preventScroll: true});
  #|   return document.activeElement === node;
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
  InvalidView(@runtime.CommitError)
} derive(Eq, @debug.Debug)

///|
priv struct MountedNode {
  token : @runtime.InstanceToken
  node : DomNode
  click : (() -> Unit)?
}

///|
/// An explicitly mounted DOM root. No DOM listeners are installed by import.
/// The application owns its model; this object owns only host nodes/lifetimes.
pub struct DomRoot {
  priv root : DomNode
  priv runtime : @runtime.Runtime
  priv nodes : Map[String, MountedNode]
  priv scheduled : Ref[Bool]
  priv on_actions : () -> Unit
}

///|
/// Mount into an empty element addressed by its literal document ID. Existing
/// content, another mounted root and ancestor/descendant root overlap are rejected.
pub fn mount(
  root_id : String,
  view : @core.View,
  on_actions : () -> Unit,
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
    runtime: @runtime.Runtime::new(),
    nodes: {},
    scheduled: Ref(false),
    on_actions,
  }
  match mounted.update(view) {
    Ok(_) => Ok(mounted)
    Err(error) => {
      mounted.dispose()
      Err(error)
    }
  }
}

///|
fn kind_number(kind : @core.NodeKind) -> Int {
  match kind {
    Text => 0
    Button => 1
    Column => 2
    Row => 3
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
  let mounted = match self.nodes.get(key) {
    Some(existing) => existing
    None => {
      let node = create_node(kind_number(kind), key, view.label())
      let click = if kind == @core.Button {
        let callback = fn() {
          if accepts_events(self.root, node) &&
            self.runtime.enqueue_activate(token) {
            self.schedule_actions()
          }
        }
        add_click(node, callback)
        Some(callback)
      } else {
        None
      }
      let item = { token, node, click, }
      self.nodes.set(key, item)
      item
    }
  }
  update_node(
    mounted.node,
    kind_number(kind),
    view.label(),
    view.disabled(),
    view.loading(),
  )
  // Place parents before children. A retained former descendant can become an
  // ancestor in the next tree; detach its old ancestry before moving children.
  position_child(parent, mounted.node, index)
  let children = view.children()
  for child_index = 0
      child_index < children.length()
      child_index = child_index + 1 {
    self.render_node(children[child_index], mounted.node, child_index)
  }
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
  for _, mounted in self.nodes {
    if !contains_node(self.root, mounted.node) {
      return Err(HostTreeChanged)
    }
  }
  match self.runtime.commit(view) {
    Err(error) => return Err(InvalidView(error))
    Ok(_) => ()
  }
  let focused = active_element()
  let removed : Array[String] = []
  for key, mounted in self.nodes {
    if !self.runtime.is_current(mounted.token) {
      match mounted.click {
        Some(callback) => remove_click(mounted.node, callback)
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
  self.runtime.next_action()
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
    match mounted.click {
      Some(callback) => remove_click(mounted.node, callback)
      None => ()
    }
    remove_owned_node(self.root, mounted.node)
  }
  self.nodes.clear()
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
