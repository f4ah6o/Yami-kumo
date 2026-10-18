///|
/// Bounded DOM driver for the shared AppShell example. The model/view/update
/// are imported from the same portable package used by native consumers.
priv struct ShellFixture {
  mut model : @shared_counter.PaletteModel
  mut mounted : @dom.DomRoot?
}

///|
let shell_fixtures : Map[String, ShellFixture] = Map([])

///|
fn shell_theme(name : String) -> @theme.Theme? {
  match name {
    "light" => Some(@theme.Light)
    "dark" => Some(@theme.Dark)
    _ => None
  }
}

///|
#export_name("mountShell")
pub fn mount_shell(id : String, theme_name : String) -> String {
  if shell_fixtures.contains(id) {
    return "already-mounted"
  }
  let fixture : ShellFixture = {
    model: @shared_counter.PaletteModel::new(),
    mounted: None,
  }
  let result = @dom.mount(
    id,
    fixture.model.shell_view(),
    fn() {
      match fixture.mounted {
        None => ()
        Some(mounted) =>
          while mounted.next_action() is Some(action) {
            fixture.model = fixture.model.update_shell(action)
            mounted.update(fixture.model.shell_view()) |> ignore
          }
      }
    },
    theme=shell_theme(theme_name),
  )
  match result {
    Err(error) => error_name(error)
    Ok(mounted) => {
      fixture.mounted = Some(mounted)
      shell_fixtures.set(id, fixture)
      "mounted"
    }
  }
}

///|
#export_name("shellValue")
pub fn shell_value(id : String) -> Int {
  match shell_fixtures.get(id) {
    Some(fixture) => fixture.model.value()
    None => -1
  }
}

///|
#export_name("shellSidebarOpen")
pub fn shell_sidebar_open(id : String) -> Bool {
  match shell_fixtures.get(id) {
    Some(fixture) => fixture.model.sidebar_open()
    None => false
  }
}

///|
#export_name("shellContextOpen")
pub fn shell_context_open(id : String) -> Bool {
  match shell_fixtures.get(id) {
    Some(fixture) => fixture.model.context_open()
    None => false
  }
}

///|
/// Deterministic bounded control for state that has no visible button in a
/// given viewport. Input-driven tests still exercise the real DOM buttons.
#export_name("shellAction")
pub fn shell_action(id : String, key : String) -> String {
  match shell_fixtures.get(id) {
    None => "missing-shell"
    Some(fixture) => {
      let next = fixture.model.update_shell(@core.Activate(@core.NodeKey::new(key)))
      match fixture.mounted.unwrap().update(next.shell_view()) {
        Err(error) => error_name(error)
        Ok(_) => {
          fixture.model = next
          "updated"
        }
      }
    }
  }
}

///|
#export_name("focusShell")
pub fn focus_shell(id : String, key : String) -> Bool {
  match shell_fixtures.get(id) {
    None => false
    Some(fixture) => fixture.mounted.unwrap().focus(@core.NodeKey::new(key))
  }
}

///|
#export_name("setShellTheme")
pub fn set_shell_theme(id : String, name : String) -> String {
  match shell_fixtures.get(id) {
    None => "missing-shell"
    Some(fixture) =>
      match fixture.mounted.unwrap().set_theme(shell_theme(name)) {
        Err(error) => error_name(error)
        Ok(_) => "updated"
      }
  }
}

///|
#export_name("disposeShell")
pub fn dispose_shell(id : String) -> Unit {
  match shell_fixtures.get(id) {
    None => ()
    Some(fixture) => {
      fixture.mounted.unwrap().dispose()
      fixture.mounted = None
      shell_fixtures.remove(id) |> ignore
    }
  }
}

///|
let minimal_shells : Map[String, @dom.DomRoot] = Map([])

///|
/// Bounded parity fixture: brand + global search + main, with no header-end
/// slots. The empty header-end group must not consume flex space.
#export_name("mountShellMinimal")
pub fn mount_shell_minimal(id : String) -> String {
  if minimal_shells.contains(id) {
    return "already-mounted"
  }
  let view = @core.app_shell(
    @core.NodeKey::new("minimal-shell"),
    @core.text(@core.NodeKey::new("minimal-brand"), "Brand"),
    @core.column(@core.NodeKey::new("minimal-main"), [
      @core.text(@core.NodeKey::new("minimal-value"), "Value"),
    ]),
    global_search=@core.text(@core.NodeKey::new("minimal-search"), "Search"),
  )
  match @dom.mount(id, view, fn() {}) {
    Err(error) => error_name(error)
    Ok(mounted) => {
      minimal_shells.set(id, mounted)
      "mounted"
    }
  }
}

///|
#export_name("disposeMinimalShell")
pub fn dispose_minimal_shell(id : String) -> Unit {
  match minimal_shells.get(id) {
    None => ()
    Some(mounted) => {
      mounted.dispose()
      minimal_shells.remove(id) |> ignore
    }
  }
}
