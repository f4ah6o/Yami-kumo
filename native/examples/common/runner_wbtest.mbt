///|
test "resize drops input routing until its stale pending frame is completed and relaid out" {
  let gate = PresentationGate::{ rendered: false, pending_stale: false, }
  gate.mark_presented()
  assert_true(gate.input_ready())

  gate.invalidate_layout(true)
  assert_true(!gate.input_ready())
  assert_true(!gate.completed_frame_is_current())
  assert_true(!gate.input_ready())

  gate.mark_presented()
  assert_true(gate.input_ready())
  assert_true(gate.completed_frame_is_current())
}

///|
test "native error details include the framework message" {
  let error = @diagnostics.FrameworkError::new(
    @diagnostics.NativeFailure,
    "run_native_loop",
    message="native sample timed out before closing",
  )
  assert_eq(
    format_framework_error(error),
    "run_native_loop: native_failure: native sample timed out before closing",
  )
}

///|
struct FakeNativeAXPortState {
  mut next_token : Int64
  published_snapshots : Array[@sample.NativeButtonAccessibilitySnapshot]
  published_with_tokens : Array[Int64]
  revoked_tokens : Array[Int64]
  requests : Array[Int64]
  mut next_request : Int
}

///|
fn fake_native_ax_port(
  state : Ref[FakeNativeAXPortState],
) -> NativeButtonAXPort {
  let publish : NativeButtonAXPublish = fn(_window, existing, snapshot) {
    let token = if existing == 0L {
      state.val.next_token += 1L
      state.val.next_token
    } else {
      existing
    }
    state.val.published_snapshots.push(snapshot)
    state.val.published_with_tokens.push(existing)
    Ok(token)
  }
  let revoke : NativeButtonAXRevoke = fn(_window, token) {
    state.val.revoked_tokens.push(token)
    Ok(())
  }
  let take_request : NativeButtonAXTakeRequest = fn(_window) {
    match state.val.requests.get(state.val.next_request) {
      None => Ok(None)
      Some(token) => {
        state.val.next_request += 1
        Ok(Some(token))
      }
    }
  }
  NativeButtonAXPort::new(publish, revoke, take_request)
}

///|
fn fake_native_ax_measure(
  value : String,
  size : Double,
) -> Result[@text_layout.TextMeasurement, @diagnostics.FrameworkError] {
  match @text.TextDocument::new(value) {
    Err(_) =>
      Err(
        @diagnostics.FrameworkError::new(
          @diagnostics.InvalidInput,
          "fake_native_ax_measure",
          message="invalid test document",
        ),
      )
    Ok(document) => {
      let width = value.length().to_double() * size * 0.6
      let logical = @primitives.Rect::new(0.0, 0.0, width, size * 1.25).unwrap()
      let ink = @primitives.Rect::new(
        -1.0,
        -2.0,
        width + 1.0,
        size * 1.25 + 2.0,
      ).unwrap()
      let carets : Array[@text_layout.CaretGeometry] = []
      let mut offset = 0
      let mut x = 0.0
      carets.push(
        @text_layout.CaretGeometry::new(
          offset,
          true,
          @primitives.Rect::new(x, 0.0, 1.0, size).unwrap(),
          @primitives.Rect::new(x, 0.0, 1.0, size).unwrap(),
        ).unwrap(),
      )
      for scalar in value.iter() {
        offset += if scalar.to_int() > 0xFFFF { 2 } else { 1 }
        x += size * 0.6
        carets.push(
          @text_layout.CaretGeometry::new(
            offset,
            true,
            @primitives.Rect::new(x, 0.0, 1.0, size).unwrap(),
            @primitives.Rect::new(x, 0.0, 1.0, size).unwrap(),
          ).unwrap(),
        )
      }
      match
        @text_layout.TextMeasurement::new(
          document,
          logical,
          ink,
          size * 0.8,
          1,
          0,
          carets,
        ) {
        Ok(value) => Ok(value)
        Err(_) =>
          Err(
            @diagnostics.FrameworkError::new(
              @diagnostics.InvalidInput,
              "fake_native_ax_measure",
              message="invalid test measurement",
            ),
          )
      }
    }
  }
}

///|
fn fake_native_ax_sample() -> @sample.NativeSample raise {
  match @sample.NativeSample::new() {
    Err(_) => fail("sample app and state should initialize")
    Ok(sample) =>
      match sample.render(800.0, 600.0, 1.0, fake_native_ax_measure) {
        Err(_) => fail("sample should render with fake native AX measurements")
        Ok(_) => sample
      }
  }
}

///|
fn snapshot_generation(state : FakeNativeAXPortState, index : Int) -> Int raise {
  match state.published_snapshots.get(index) {
    None => fail("expected a published native accessibility snapshot")
    Some(snapshot) => snapshot.activations()
  }
}

///|
test "native AX port revokes invalidated tokens, drops stale requests, and routes only the current snapshot" {
  let state = Ref({
    next_token: 40L,
    published_snapshots: [],
    published_with_tokens: [],
    revoked_tokens: [],
    requests: [],
    next_request: 0,
  })
  let port = fake_native_ax_port(state)
  let sample = fake_native_ax_sample()
  let window = @platform.WindowId::new(17L)
  let first_binding = match
    sync_native_button_accessibility(port, window, sample, None) {
    Err(_) => fail("initial sample snapshot should be published")
    Ok(None) => fail("initial sample snapshot should have a binding")
    Ok(Some(value)) => value
  }
  assert_eq(first_binding.transport_token, 41L)

  state.val.requests.push(first_binding.transport_token)
  sample.invalidate_layout()
  let (invalidated_binding, accepted_while_unavailable) = match
    take_native_button_accessibility_actions(
      port,
      window,
      sample,
      Some(first_binding),
    ) {
    Err(_) => fail("invalidated sample should safely drain its old request")
    Ok(value) => value
  }
  assert_true(invalidated_binding is None)
  assert_true(!accepted_while_unavailable)
  assert_eq(state.val.revoked_tokens.length(), 1)
  assert_eq(state.val.revoked_tokens[0], first_binding.transport_token)
  assert_true(sample.count() is Ok(0))

  let _ = match sample.render(800.0, 600.0, 1.0, fake_native_ax_measure) {
    Err(_) => fail("sample should render after invalidation")
    Ok(value) => value
  }
  let second_binding = match
    sync_native_button_accessibility(port, window, sample, invalidated_binding) {
    Err(_) => fail("rerendered sample snapshot should be published")
    Ok(None) => fail("rerendered sample snapshot should have a binding")
    Ok(Some(value)) => value
  }
  assert_eq(second_binding.transport_token, 42L)

  state.val.requests.push(first_binding.transport_token)
  state.val.requests.push(second_binding.transport_token)
  let (updated_binding, accepted) = match
    take_native_button_accessibility_actions(
      port,
      window,
      sample,
      Some(second_binding),
    ) {
    Err(_) => fail("current sample accessibility request should route")
    Ok(value) => value
  }
  assert_true(accepted)
  assert_sample_count_for_ax(sample, 1)
  match updated_binding {
    None => fail("accepted action should retain its current AX binding")
    Some(binding) => {
      assert_eq(binding.transport_token, second_binding.transport_token)
      assert_eq(binding.snapshot.activations(), 1)
    }
  }
  assert_eq(state.val.published_with_tokens.length(), 3)
  assert_eq(state.val.published_with_tokens[2], second_binding.transport_token)
  assert_eq(snapshot_generation(state.val, 2), 1)

  let revoked = match
    revoke_native_button_accessibility(port, window, updated_binding) {
    Err(_) => fail("current AX binding should revoke during teardown")
    Ok(value) => value
  }
  assert_true(revoked is None)
  assert_eq(state.val.revoked_tokens.length(), 2)
  assert_eq(state.val.revoked_tokens[1], second_binding.transport_token)
}

///|
fn assert_sample_count_for_ax(
  sample : @sample.NativeSample,
  expected : Int,
) -> Unit raise {
  match sample.count() {
    Err(_) => fail("sample entity state should remain readable")
    Ok(value) => assert_eq(value, expected)
  }
}
