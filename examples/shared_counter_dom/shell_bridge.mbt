///|
/// Bounded DOM driver for the shared AppShell example. The model/view/update
/// are imported from the same portable package used by native consumers.
priv struct ShellFixture {
  mut model : @shared_counter.ShellModel
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
    model: @shared_counter.ShellModel::new(),
    mounted: None,
  }
  let result = @dom.mount(
    id,
    fixture.model.view(),
    fn() {
      match fixture.mounted {
        None => ()
        Some(mounted) =>
          while mounted.next_action() is Some(action) {
            fixture.model = fixture.model.update(action)
            mounted.update(fixture.model.view()) |> ignore
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
      let next = fixture.model.update(@core.Activate(@core.NodeKey::new(key)))
      match fixture.mounted.unwrap().update(next.view()) {
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
