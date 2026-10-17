///|
priv struct ThemeFixture {
  mut model : @shared_button_theme.Model
  mut mounted : @dom.DomRoot?
  mut palette : @core.ButtonPaletteToken?
}

///|
fn ThemeFixture::view_for(
  self : ThemeFixture,
  model : @shared_button_theme.Model,
) -> @core.View {
  let view = model.view()
  match self.palette {
    None => view
    Some(palette) =>
      @core.column(
        view.key(),
        view.children().map(fn(child) {
          if child.key() == @core.NodeKey::new("increment") {
            @core.button_with_palette(
              child.key(),
              child.label(),
              palette,
              disabled=child.disabled(),
              loading=child.loading(),
            )
          } else {
            child
          }
        }),
      )
  }
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
    palette: None,
  }
  match
    @dom.mount(
      id,
      fixture.view_for(fixture.model),
      fn() {
        match fixture.mounted {
          None => ()
          Some(mounted) =>
            while mounted.next_action() is Some(action) {
              let previous_theme = fixture.model.theme()
              fixture.model = fixture.model.update(action)
              mounted.update(fixture.view_for(fixture.model)) |> ignore
              if fixture.model.theme() != previous_theme {
                mounted.set_theme(Some(fixture.model.theme())) |> ignore
              }
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
      match fixture.mounted.unwrap().update(fixture.view_for(next)) {
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
#export_name("setThemeFixturePalette")
pub fn set_theme_fixture_palette(id : String, name : String) -> String {
  let palette = match name {
    "none" => None
    "light" => Some(@core.Light)
    "dark" => Some(@core.Dark)
    _ => return "invalid-palette"
  }
  match theme_fixtures.get(id) {
    None => "missing-fixture"
    Some(fixture) => {
      let previous = fixture.palette
      fixture.palette = palette
      match fixture.mounted.unwrap().update(fixture.view_for(fixture.model)) {
        Ok(_) => "updated"
        Err(error) => {
          fixture.palette = previous
          error_name(error)
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
