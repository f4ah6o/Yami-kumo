///|
/// One common fixture Model is owned by App; GPUI owns every input state.
pub struct NativeTheme {
  priv app : @app.App
  priv state : @app.Entity[@fixture.Model]
  priv mount : @ui.Mounted
  priv actions : Array[@view.SemanticAction]
  priv mut disposed : Bool
  priv mut draining : Bool
}

///|
pub struct ThemeFrame {
  priv frame : @ui.Frame
  priv model : @fixture.Model
  priv action_keys : Array[String]
}

///|
pub fn ThemeFrame::frame(self : ThemeFrame) -> @ui.Frame {
  self.frame
}

///|
pub fn ThemeFrame::model(self : ThemeFrame) -> @fixture.Model {
  self.model
}

///|
pub fn ThemeFrame::action_keys(self : ThemeFrame) -> Array[String] {
  self.action_keys.copy()
}

///|
pub fn NativeTheme::new(
  window : @platform.WindowId,
) -> Result[NativeTheme, @diagnostics.FrameworkError] {
  let app = match @app.App::new() {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  match app.start() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let model = @fixture.Model::new()
  let state = match app.create_entity(model) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  Ok({
    app,
    state,
    mount: @ui.Mounted::new(window, theme=Some(model.theme())),
    actions: [],
    disposed: false,
    draining: false,
  })
}

///|
pub fn NativeTheme::render(
  self : NativeTheme,
  width : Double,
  height : Double,
  scale : Double,
  measure : @components.TextMeasure,
) -> Result[ThemeFrame, @diagnostics.FrameworkError] {
  if self.disposed || self.draining {
    return Err(counter_error("disposed or reentrant theme render"))
  }
  let model = match self.app.read(self.state, model => model) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  ignore(self.mount.set_theme(Some(model.theme())))
  match self.mount.commit(model.view(), width, height, scale, measure) {
    Err(error) => Err(error)
    Ok(frame) =>
      Ok({
        frame,
        model,
        action_keys: self.actions.map(action => {
          match action {
            @view.Activate(key) => key.value()
            @view.TextChanged(key, _) => key.value()
            @view.Submitted(key) => key.value()
            @view.Dismissed(key) => key.value()
            @view.Confirmed(key) => key.value()
          }
        }),
      })
  }
}

///|
pub fn NativeTheme::handle_event(
  self : NativeTheme,
  event : @platform.Event,
) -> Result[Bool, @diagnostics.FrameworkError] {
  if self.disposed || self.draining {
    return Ok(false)
  }
  let result = self.mount.handle_event(event)
  if self.mount.is_disposed() {
    self.dispose()
  }
  result
}

///|
fn NativeTheme::apply_model(
  self : NativeTheme,
  next : @fixture.Model,
  width : Double,
  height : Double,
  scale : Double,
  measure : @components.TextMeasure,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let previous_theme = self.mount.theme()
  ignore(self.mount.set_theme(Some(next.theme())))
  let prepared = match
    self.mount.stage(next.view(), width, height, scale, measure) {
    Err(error) => {
      ignore(self.mount.set_theme(previous_theme))
      return Err(error)
    }
    Ok(value) => value
  }
  if self.disposed {
    return Err(counter_error("theme fixture disposed while measuring"))
  }
  match
    self.app.update(self.state, context => {
      match context.set(next) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      context.notify()
    }) {
    Err(error) => {
      ignore(self.mount.set_theme(previous_theme))
      return Err(error)
    }
    Ok(_) => ()
  }
  match self.mount.publish(prepared) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let budget = self.app.pending_work()
  if budget > 0 {
    match self.app.run_ready(budget) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    if self.app.pending_work() != 0 {
      return Err(counter_error("unexpected private theme notification work"))
    }
  }
  Ok(())
}

///|
pub fn NativeTheme::drain_one(
  self : NativeTheme,
  width : Double,
  height : Double,
  scale : Double,
  measure : @components.TextMeasure,
) -> Result[Bool, @diagnostics.FrameworkError] {
  if self.disposed || self.draining {
    return Ok(false)
  }
  let action = match self.mount.next_action() {
    None => return Ok(false)
    Some(value) => value
  }
  let next = match self.app.read(self.state, model => model.update(action)) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  self.draining = true
  let result = self.apply_model(next, width, height, scale, measure)
  self.draining = false
  match result {
    Err(error) => Err(error)
    Ok(_) => {
      self.actions.push(action)
      Ok(true)
    }
  }
}

///|
/// Test-host controls change application props or request existing focus only.
/// They never synthesize controller states, gestures, releases or activations.
pub fn NativeTheme::control(
  self : NativeTheme,
  key : String,
  width : Double,
  height : Double,
  scale : Double,
  measure : @components.TextMeasure,
) -> Result[Bool, @diagnostics.FrameworkError] {
  if self.disposed || self.draining {
    return Err(counter_error("disposed or reentrant theme control"))
  }
  if key == "f" {
    return Ok(self.mount.focus(@view.NodeKey::new("increment")))
  }
  let model = match self.app.read(self.state, model => model) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let next = match key {
    "t" =>
      model.with_theme(
        match model.theme() {
          @theme.Light => @theme.Dark
          @theme.Dark => @theme.Light
        },
      )
    "n" => model.with_mode(@fixture.Normal)
    "d" => model.with_mode(@fixture.Disabled)
    "l" => model.with_mode(@fixture.Loading)
    "b" => model.with_mode(@fixture.DisabledLoading)
    _ => return Ok(false)
  }
  match self.apply_model(next, width, height, scale, measure) {
    Err(error) => Err(error)
    Ok(_) => Ok(true)
  }
}

///|
pub fn NativeTheme::invalidate_layout(self : NativeTheme) -> Unit {
  self.mount.invalidate_layout()
}

///|
pub fn NativeTheme::dispose(self : NativeTheme) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.mount.dispose()
  ignore(self.app.destroy_entity(self.state))
  ignore(self.app.request_stop())
  let budget = self.app.pending_work()
  if budget > 0 {
    ignore(self.app.run_ready(budget))
  }
}
