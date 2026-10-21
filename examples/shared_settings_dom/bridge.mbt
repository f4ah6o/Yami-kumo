///|
/// One browser Settings root. The portable model owns every transition; this
/// bridge only drains DOM actions, republishes the view and delivers the
/// simulated-save completion from a timer.
priv struct SettingsApp {
  id : String
  mut model : @shared_settings.Model
  mut mounted : @dom.DomRoot?
  mut finish_scheduled : Bool
}

///|
let apps : Map[String, SettingsApp] = Map([])

///|
extern "js" fn schedule_finish(finish : () -> Unit) -> Unit =
  #| (finish) => { setTimeout(finish, 0); }

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
    InvalidShell => "invalid-shell"
    InvalidDialogFocus => "invalid-dialog-focus"
    InvalidView(_) => "invalid-view"
  }
}

///|
fn SettingsApp::drain(self : SettingsApp) -> Unit {
  match self.mounted {
    None => ()
    Some(mounted) => {
      while mounted.next_action() is Some(action) {
        self.model = self.model.update(@shared_settings.Ui(action))
        mounted.update(self.model.view()) |> ignore
      }
      if self.model.saving() && !self.finish_scheduled {
        self.finish_scheduled = true
        let id = self.id
        schedule_finish(fn() { finish_by_id(id) })
      }
    }
  }
}

///|
fn SettingsApp::republish(self : SettingsApp) -> Unit {
  match self.mounted {
    None => ()
    Some(mounted) => mounted.update(self.model.view()) |> ignore
  }
}

///|
#export_name("mountSettings")
pub fn mount_settings(id : String) -> String {
  if apps.contains(id) {
    return "already-mounted"
  }
  let app : SettingsApp = {
    id,
    model: @shared_settings.Model::new(),
    mounted: None,
    finish_scheduled: false,
  }
  let result = @dom.mount(id, app.model.view(), fn() { app.drain() })
  match result {
    Err(error) => error_name(error)
    Ok(mounted) => {
      app.mounted = Some(mounted)
      apps.set(id, app)
      "mounted"
    }
  }
}

///|
fn finish_by_id(id : String) -> Unit {
  match apps.get(id) {
    None => ()
    Some(app) => {
      app.finish_scheduled = false
      if app.model.saving() {
        app.model = app.model.update(@shared_settings.SaveFinished)
        app.republish()
      }
    }
  }
}

///|
#export_name("settingsName")
pub fn name(id : String) -> String {
  match apps.get(id) {
    Some(app) => app.model.name()
    None => ""
  }
}

///|
#export_name("settingsError")
pub fn error(id : String) -> String {
  match apps.get(id) {
    Some(app) =>
      match app.model.error() {
        Some(value) => value
        None => ""
      }
    None => ""
  }
}

///|
#export_name("settingsSaving")
pub fn saving(id : String) -> Bool {
  match apps.get(id) {
    Some(app) => app.model.saving()
    None => false
  }
}

///|
#export_name("settingsSaved")
pub fn saved(id : String) -> Bool {
  match apps.get(id) {
    Some(app) => app.model.saved()
    None => false
  }
}

///|
#export_name("settingsDialogOpen")
pub fn dialog_open(id : String) -> Bool {
  match apps.get(id) {
    Some(app) => app.model.dialog_open()
    None => false
  }
}

///|
#export_name("disposeSettings")
pub fn dispose_settings(id : String) -> Unit {
  match apps.get(id) {
    None => ()
    Some(app) => {
      match app.mounted {
        Some(mounted) => mounted.dispose()
        None => ()
      }
      app.mounted = None
      apps.remove(id) |> ignore
    }
  }
}
