///|
/// Test-host protocol only. A send API's success is never a dispatch witness.
priv struct ThemePointerReceipt {
  window : @platform.WindowId
  mut request : Int32
  mut phase : Int32
  mut armed_at : Int64
  mut scale : Double
  mut x : Double
  mut y : Double
  mut waiting : Bool
}

///|
fn ThemePointerReceipt::new(window : @platform.WindowId) -> ThemePointerReceipt {
  {
    window,
    request: 0,
    phase: 0,
    armed_at: 0L,
    scale: 1.0,
    x: 0.0,
    y: 0.0,
    waiting: false,
  }
}

///|
fn ThemePointerReceipt::arm(
  self : ThemePointerReceipt,
  event : @platform.Event,
  phase : Int32,
  x : Double,
  y : Double,
) -> Bool {
  if self.waiting ||
    event.window() != self.window ||
    event.sequence() <= self.armed_at {
    return false
  }
  self.request += 1
  self.phase = phase
  self.armed_at = event.sequence()
  self.scale = event.scale()
  self.x = x
  self.y = y
  self.waiting = true
  true
}

///|
fn ThemePointerReceipt::identity_json(self : ThemePointerReceipt) -> String {
  "{\"request\":\{self.request},\"phase\":\{self.phase},\"windowId\":\{self.window.value()},\"armSequence\":\{self.armed_at},\"scale\":\{self.scale},\"x\":\{self.x},\"y\":\{self.y}}"
}

///|
fn ThemePointerReceipt::observe(
  self : ThemePointerReceipt,
  event : @platform.Event,
  before_dispatch : Int64,
  dispatched : Int64,
) -> String? {
  if !self.waiting ||
    event.window() != self.window ||
    event.sequence() <= self.armed_at ||
    event.scale() != self.scale ||
    dispatched != event.sequence() ||
    before_dispatch >= dispatched {
    return None
  }
  match event.kind() {
    @platform.Input(@primitives.PointerMoved(position~)) => {
      let tolerance = 0.51 / self.scale
      if (position.x() - self.x).abs() > tolerance ||
        (position.y() - self.y).abs() > tolerance {
        return None
      }
      self.waiting = false
      Some(
        "{\"request\":\{self.request},\"phase\":\{self.phase},\"windowId\":\{self.window.value()},\"armSequence\":\{self.armed_at},\"scale\":\{self.scale},\"sequence\":\{event.sequence()},\"dispatchedSequence\":\{dispatched},\"x\":\{position.x()},\"y\":\{position.y()}}",
      )
    }
    _ => None
  }
}
