///|
/// A browser bootstrap and bounded test driver. The actual model/view/update
/// come from the same portable package used by the independent native consumer.
priv struct Counter {
  mut model : @shared_counter.Model
  mut mounted : @dom.DomRoot?
  mut mode : String
  mut label : String
}

///|
let counters : Map[String, Counter] = Map([])

///|
fn Counter::test_view(self : Counter, view : @core.View) -> @core.View {
  if view.key().value() == "increment" {
    match self.mode {
      "removed" =>
        return @core.text(@core.NodeKey::new("placeholder"), "Removed")
      "text" => return @core.text(view.key(), self.label)
      _ =>
        return @core.button(
          view.key(),
          self.label,
          disabled=self.mode == "disabled" || self.mode == "disabled-loading",
          loading=self.mode == "loading" || self.mode == "disabled-loading",
        )
    }
  }
  match view.kind() {
    Text | Button => view
    Column => {
      let children = view.children().map(fn(child) { self.test_view(child) })
      if view.is_card() {
        @core.card(view.key(), children)
      } else {
        @core.column(view.key(), children)
      }
    }
    Row =>
      @core.row(
        view.key(),
        view.children().map(fn(child) { self.test_view(child) }),
      )
  }
}

///|
fn Counter::view(self : Counter) -> @core.View {
  let common = if self.mode == "card" || self.mode == "nested-card" {
    self.model.card_view()
  } else {
    self.model.view()
  }
  let view = self.test_view(common)
  if self.mode == "nested-card" {
    return @core.card(@core.NodeKey::new("outer-card"), [view])
  }
  if self.mode == "nested-a" {
    @core.column(@core.NodeKey::new("ancestor-a"), [
      @core.column(@core.NodeKey::new("ancestor-b"), [view]),
    ])
  } else if self.mode == "nested-b" {
    @core.column(@core.NodeKey::new("ancestor-b"), [
      @core.column(@core.NodeKey::new("ancestor-a"), [view]),
    ])
  } else if self.mode == "row" {
    @core.row(view.key(), view.children())
  } else if self.mode == "duplicate" {
    @core.column(@core.NodeKey::new("counter"), [view])
  } else {
    view
  }
}

///|
fn error_name(error : @dom.DomError) -> String {
  match error {
    MissingDocument => "missing-document"
    MissingRoot => "missing-root"
    RootAlreadyMounted => "already-mounted"
    OverlappingRoot => "overlapping-root"
    RootNotEmpty => "root-not-empty"
    Disposed => "disposed"
    HostTreeChanged => "host-tree-changed"
    InvalidView(_) => "invalid-view"
  }
}

///|
#export_name("mountCounter")
pub fn mount_counter(id : String) -> String {
  if counters.contains(id) {
    return "already-mounted"
  }
  let counter : Counter = {
    model: @shared_counter.Model::new(),
    mounted: None,
    mode: "normal",
    label: "Increment",
  }
  let result = @dom.mount(id, counter.view(), fn() {
    match counter.mounted {
      None => ()
      Some(mounted) =>
        while mounted.next_action() is Some(action) {
          counter.model = counter.model.update(action)
          // Publish each state transition before accepting the next queued action.
          mounted.update(counter.view()) |> ignore
        }
    }
  })
  match result {
    Err(error) => error_name(error)
    Ok(mounted) => {
      counter.mounted = Some(mounted)
      counters.set(id, counter)
      "mounted"
    }
  }
}

///|
#export_name("counterValue")
pub fn counter_value(id : String) -> Int {
  match counters.get(id) {
    Some(counter) => counter.model.value()
    None => -1
  }
}

///|
#export_name("updateCounter")
pub fn update_counter(id : String, mode : String, label : String) -> String {
  match counters.get(id) {
    None => "missing-counter"
    Some(counter) => {
      let previous_mode = counter.mode
      let previous_label = counter.label
      counter.mode = mode
      counter.label = label
      match counter.mounted.unwrap().update(counter.view()) {
        Ok(_) => "updated"
        Err(error) => {
          counter.mode = previous_mode
          counter.label = previous_label
          error_name(error)
        }
      }
    }
  }
}

///|
#export_name("focusCounter")
pub fn focus_counter(id : String) -> Bool {
  match counters.get(id) {
    None => false
    Some(counter) =>
      counter.mounted.unwrap().focus(@core.NodeKey::new("increment"))
  }
}

///|
#export_name("focusOutcome")
pub fn focus_outcome(id : String) -> String {
  match counters.get(id) {
    None => "missing-counter"
    Some(counter) =>
      match counter.mounted.unwrap().next_focus_result() {
        None => "none"
        Some(result) =>
          match result.outcome() {
            Focused => "focused"
            Rejected => "rejected"
            Unsupported => "unsupported"
          }
      }
  }
}

///|
#export_name("disposeCounter")
pub fn dispose_counter(id : String) -> Unit {
  match counters.get(id) {
    None => ()
    Some(counter) => {
      counter.mounted.unwrap().dispose()
      counter.mounted = None
      counters.remove(id) |> ignore
    }
  }
}
