///|
/// The sole application state. The JS and native consumers import this package
/// unchanged; hosts own no parallel counter model and there are no OS branches.
pub struct Model {
  priv value : Int
} derive(Eq, @debug.Debug)

///|
pub fn Model::new() -> Model {
  { value: 0, }
}

///|
pub fn Model::value(self : Model) -> Int {
  self.value
}

///|
pub fn Model::update(self : Model, action : @core.SemanticAction) -> Model {
  match action {
    @core.Activate(key) if key == @core.NodeKey::new("increment") =>
      { value: self.value + 1, }
    _ => self
  }
}

///|
pub fn Model::view(self : Model) -> @core.View {
  @core.column(@core.NodeKey::new("counter"), [
    @core.text(@core.NodeKey::new("heading"), "Shared counter"),
    @core.text(@core.NodeKey::new("value"), "Count: \{self.value}"),
    @core.button(@core.NodeKey::new("increment"), "Increment"),
  ])
}

///|
pub extend Model with Eq::{equal, not_equal}

///|
pub extend Model with @debug.Debug::{to_repr}

///|
/// Same counter model, actions, keys and children with the fixed Card container.
pub fn Model::card_view(self : Model) -> @core.View {
  let view = self.view()
  @core.card(view.key(), view.children())
}
