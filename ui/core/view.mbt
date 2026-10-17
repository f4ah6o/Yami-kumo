///|
/// A stable, application-chosen identity within one mounted tree. The runtime
/// rejects empty or duplicate keys before changing any committed state.
pub struct NodeKey {
  priv value : String
} derive(Eq, @debug.Debug)

///|
pub fn NodeKey::new(value : String) -> NodeKey {
  { value, }
}

///|
pub fn NodeKey::value(self : NodeKey) -> String {
  self.value
}

///|
pub(all) enum NodeKind {
  Text
  Button
  Column
  Row
} derive(Eq, @debug.Debug)

///|
/// Immutable semantic tree. Constructors and accessors copy child arrays;
/// neither a caller nor a host can mutate an already-built view indirectly.
/// Text and labels are literal content, never markup.
pub struct View {
  priv key : NodeKey
  priv kind : NodeKind
  priv label : String
  priv disabled : Bool
  priv loading : Bool
  priv card : Bool
  priv children : Array[View]
} derive(Eq, @debug.Debug)

///|
pub fn text(key : NodeKey, value : String) -> View {
  {
    key,
    kind: Text,
    label: value,
    disabled: false,
    loading: false,
    card: false,
    children: [],
  }
}

///|
/// Describes a semantic button. Low-level pointer/key behavior belongs to the
/// host control; this package does not introduce another button state machine.
/// Disabled and loading both reject Activate. Loading alone retains eligible
/// focus; disabled removes focus eligibility even when loading is also true.
/// Labels are literal. Browser repeat/focus-visible and GPUI focus paint are
/// separate profiles; see docs/shared-button-states.md for cancellation limits.
pub fn button(
  key : NodeKey,
  label : String,
  disabled~ : Bool = false,
  loading~ : Bool = false,
) -> View {
  { key, kind: Button, label, disabled, loading, card: false, children: [], }
}

///|
pub fn column(key : NodeKey, children : Array[View]) -> View {
  {
    key,
    kind: Column,
    label: "",
    disabled: false,
    loading: false,
    card: false,
    children: children.copy(),
  }
}

///|
pub fn row(key : NodeKey, children : Array[View]) -> View {
  {
    key,
    kind: Row,
    label: "",
    disabled: false,
    loading: false,
    card: false,
    children: children.copy(),
  }
}

///|
pub fn View::key(self : View) -> NodeKey {
  self.key
}

///|
pub fn View::kind(self : View) -> NodeKind {
  self.kind
}

///|
/// Text contents or button label; empty for containers.
pub fn View::label(self : View) -> String {
  self.label
}

///|
pub fn View::disabled(self : View) -> Bool {
  self.disabled
}

///|
pub fn View::loading(self : View) -> Bool {
  self.loading
}

///|
pub fn View::children(self : View) -> Array[View] {
  self.children.copy()
}

///|
/// Semantic input consumed by the single application model owner.
pub(all) enum SemanticAction {
  Activate(NodeKey)
} derive(Eq, @debug.Debug)

///|
/// The host reports the observed outcome of a focus request. Request creation
/// alone does not set or claim focused state.
pub(all) enum FocusOutcome {
  Focused
  Rejected
  Unsupported
} derive(Eq, @debug.Debug)

///|
pub extend NodeKey with Eq::{equal, not_equal}

///|
pub extend NodeKey with @debug.Debug::{to_repr}

///|
pub extend NodeKind with Eq::{equal, not_equal}

///|
pub extend NodeKind with @debug.Debug::{to_repr}

///|
pub extend View with Eq::{equal, not_equal}

///|
pub extend View with @debug.Debug::{to_repr}

///|
pub extend SemanticAction with Eq::{equal, not_equal}

///|
pub extend SemanticAction with @debug.Debug::{to_repr}

///|
pub extend FocusOutcome with Eq::{equal, not_equal}

///|
pub extend FocusOutcome with @debug.Debug::{to_repr}

///|
/// A fixed, noninteractive Card decoration on a compatible Column. Border 1,
/// padding 16, gap 12 logical pixels; see docs/shared-card.md. Same-key changes
/// between Column and Card preserve semantic identity and descendant lifetimes.
pub fn card(key : NodeKey, children : Array[View]) -> View {
  { ..column(key, children), card: true, }
}

///|
pub fn View::is_card(self : View) -> Bool {
  self.card
}
