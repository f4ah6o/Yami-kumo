///|
struct Case {
  id : String
  disabled : Bool
  loading : Bool
  steps : Array[String]
} derive(FromJson)

///|
fn[T, E] unwrap(result : Result[T, E]) -> T {
  match result {
    Ok(value) => value
    Err(_) => abort("Button contract consumer failed")
  }
}

///|
fn rect(
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> @primitives.Rect {
  unwrap(@primitives.Rect::new(x, y, width, height))
}

///|
// Deterministic metrics keep this consumer independent of OS fonts; they cannot
// qualify native glyph rasterization or GPU presentation.
fn measure(
  value : String,
  size : Double,
) -> Result[@text_layout.TextMeasurement, @diagnostics.FrameworkError] {
  let document = unwrap(@text.TextDocument::new(value))
  let carets : Array[@text_layout.CaretGeometry] = []
  let mut offset = 0
  let mut x = 0.0
  carets.push(
    unwrap(
      @text_layout.CaretGeometry::new(
        0,
        true,
        rect(0.0, 0.0, 1.0, size),
        rect(0.0, 0.0, 1.0, size),
      ),
    ),
  )
  for scalar in value.iter() {
    offset += if scalar.to_int() > 0xffff { 2 } else { 1 }
    x += size * 0.6
    let caret = rect(x, 0.0, 1.0, size)
    carets.push(
      unwrap(@text_layout.CaretGeometry::new(offset, true, caret, caret)),
    )
  }
  Ok(
    unwrap(
      @text_layout.TextMeasurement::new(
        document,
        rect(0.0, 0.0, x, size * 1.25),
        rect(0.0, 0.0, x, size * 1.25),
        size * 0.8,
        1,
        0,
        carets,
      ),
    ),
  )
}

///|
fn main {
  let specification : Case = @json.from_json(
    @json.parse(@env.get_env_var("YAMI_BUTTON_CASE").unwrap()),
  ) catch {
    _ => abort("Invalid YAMI_BUTTON_CASE")
  }
  if specification.loading {
    println(
      "{\"status\":\"unsupported\",\"reason\":\"NativeSample has no loading API\"}",
    )
    return
  }
  let sample = unwrap(
    @sample.NativeSample::new(disabled=specification.disabled),
  )
  let mut frame = unwrap(sample.render(800.0, 600.0, 1.0, measure))
  let phases : Array[Json] = []
  let phases_to_run = ["initial"] + specification.steps
  for index, phase in phases_to_run {
    let bounds = frame.button_bounds()
    let point = unwrap(
      @primitives.Point::new(
        bounds.left() + bounds.size().width() / 2.0,
        bounds.top() + bounds.size().height() / 2.0,
      ),
    )
    let outside = unwrap(@primitives.Point::new(790.0, 590.0))
    let before = unwrap(sample.count())
    let mut activated = false
    let modifiers = @primitives.Modifiers::none()
    match phase {
      "initial" | "repaint" => ()
      "pointer-hover" | "pointer-away" =>
        activated = unwrap(
          sample.handle_input(
            @primitives.PointerMoved(
              position=if phase == "pointer-hover" { point } else { outside },
            ),
          ),
        )
      "keyboard-focus" => {
        activated = unwrap(
          sample.handle_input(
            @primitives.KeyPressed(
              key=@primitives.ArrowLeft,
              modifiers~,
              repeat=false,
            ),
          ),
        )
        ignore(
          unwrap(
            sample.handle_input(
              @primitives.KeyReleased(key=@primitives.ArrowLeft, modifiers~),
            ),
          ),
        )
      }
      "focus-loss" => sample.focus_changed(false)
      "pointer-down" =>
        activated = unwrap(
          sample.handle_input(
            @primitives.PointerButtonPressed(
              position=point,
              button=@primitives.Primary,
              modifiers~,
            ),
          ),
        )
      "pointer-up" | "pointer-up-outside" =>
        activated = unwrap(
          sample.handle_input(
            @primitives.PointerButtonReleased(
              position=if phase == "pointer-up" { point } else { outside },
              button=@primitives.Primary,
              modifiers~,
            ),
          ),
        )
      "enter-down" | "enter-repeat" | "space-down" | "space-repeat" =>
        activated = unwrap(
          sample.handle_input(
            @primitives.KeyPressed(
              key=if phase.has_prefix("enter") {
                @primitives.Enter
              } else {
                @primitives.Space
              },
              modifiers~,
              repeat=phase.has_suffix("repeat"),
            ),
          ),
        )
      "enter-up" | "space-up" =>
        activated = unwrap(
          sample.handle_input(
            @primitives.KeyReleased(
              key=if phase == "enter-up" {
                @primitives.Enter
              } else {
                @primitives.Space
              },
              modifiers~,
            ),
          ),
        )
      _ => abort("Unsupported Button fixture phase")
    }
    frame = unwrap(sample.render(800.0, 600.0, 1.0, measure))
    let snapshot = unwrap(sample.button_accessibility_snapshot()).unwrap()
    let scene = @json.parse(frame.canonical_scene()) catch {
      _ => abort("Invalid native scene")
    }
    phases.push({
      "index": index,
      "phase": phase,
      "activation_count": frame.count(),
      "activation_delta": frame.count() - before,
      "activation_event": activated,
      "focused": snapshot.focused(),
      "pressed": frame.button_pressed(),
      "hovered": frame.button_hovered(),
      "focus_visible": frame.button_focus_visible(),
      "disabled": !snapshot.enabled(),
      "loading": snapshot.loading(),
      "scene": scene,
      "bounds": [
        bounds.left(),
        bounds.top(),
        bounds.size().width(),
        bounds.size().height(),
      ],
    })
  }
  unwrap(sample.shutdown())
  let result : Json = {
    "id": specification.id,
    "status": "observed",
    "layer": "native-consumer-scene",
    "phases": phases,
  }
  println(result.stringify())
}
