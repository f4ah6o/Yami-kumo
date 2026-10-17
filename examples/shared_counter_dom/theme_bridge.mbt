///|
priv struct ThemeFixture {
  mut model : @shared_button_theme.Model
  mut mounted : @dom.DomRoot?
}

///|
let theme_fixtures : Map[String, ThemeFixture] = Map([])

///|
fn fixture_theme(name : String) -> @theme.Theme? {
  match name {
    "light" => Some(@theme.Light)
    "dark" => Some(@theme.Dark)
    _ => None
  }
}

///|
#export_name("mountThemeFixture")
pub fn mount_theme_fixture(id : String, theme_name : String) -> String {
  if theme_fixtures.contains(id) {
    return "already-mounted"
  }
  let theme = match fixture_theme(theme_name) {
    Some(theme) => theme
    None => return "invalid-theme"
  }
  let fixture : ThemeFixture = {
    model: @shared_button_theme.Model::new().with_theme(theme),
    mounted: None,
  }
  match
    @dom.mount(
      id,
      fixture.model.view(),
      fn() {
        match fixture.mounted {
          None => ()
          Some(mounted) =>
            while mounted.next_action() is Some(action) {
              fixture.model = fixture.model.update(action)
              mounted.update(fixture.model.view()) |> ignore
              mounted.set_theme(Some(fixture.model.theme())) |> ignore
            }
        }
      },
      theme=Some(theme),
    ) {
    Err(error) => error_name(error)
    Ok(mounted) => {
      fixture.mounted = Some(mounted)
      theme_fixtures.set(id, fixture)
      "mounted"
    }
  }
}

///|
#export_name("setThemeFixtureTheme")
pub fn set_theme_fixture_theme(id : String, name : String) -> String {
  let theme = match fixture_theme(name) {
    Some(theme) => theme
    None => return "invalid-theme"
  }
  match theme_fixtures.get(id) {
    None => "missing-fixture"
    Some(fixture) =>
      match fixture.mounted.unwrap().set_theme(Some(theme)) {
        Err(error) => error_name(error)
        Ok(_) => {
          fixture.model = fixture.model.with_theme(theme)
          "updated"
        }
      }
  }
}

///|
#export_name("clearThemeFixtureTheme")
pub fn clear_theme_fixture_theme(id : String) -> String {
  match theme_fixtures.get(id) {
    None => "missing-fixture"
    Some(fixture) =>
      match fixture.mounted.unwrap().set_theme(None) {
        Err(error) => error_name(error)
        Ok(_) => "updated"
      }
  }
}

///|
#export_name("setThemeFixtureMode")
pub fn set_theme_fixture_mode(id : String, name : String) -> String {
  let mode = match name {
    "normal" => @shared_button_theme.Normal
    "disabled" => @shared_button_theme.Disabled
    "loading" => @shared_button_theme.Loading
    "disabled-loading" => @shared_button_theme.DisabledLoading
    _ => return "invalid-mode"
  }
  match theme_fixtures.get(id) {
    None => "missing-fixture"
    Some(fixture) => {
      let next = fixture.model.with_mode(mode)
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
#export_name("themeFixtureValue")
pub fn theme_fixture_value(id : String) -> Int {
  match theme_fixtures.get(id) {
    Some(fixture) => fixture.model.value()
    None => -1
  }
}

///|
#export_name("themeFixtureTheme")
pub fn theme_fixture_theme(id : String) -> String {
  match theme_fixtures.get(id) {
    Some(fixture) => fixture.model.theme().name()
    None => "missing-fixture"
  }
}

///|
#export_name("disposeThemeFixture")
pub fn dispose_theme_fixture(id : String) -> String {
  match theme_fixtures.get(id) {
    None => "missing-fixture"
    Some(fixture) => {
      let mounted = fixture.mounted.unwrap()
      mounted.dispose()
      fixture.mounted = None
      theme_fixtures.remove(id) |> ignore
      match mounted.set_theme(Some(@theme.Dark)) {
        Err(error) => error_name(error)
        Ok(_) => "unexpected-disposed-update"
      }
    }
  }
}
