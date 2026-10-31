///|
test "geometry arrival equality retains native target and full preedit payload" {
  let target : @ubuntu_host.TextSessionTarget = {
    window: @platform.WindowId::new(3L), sequence: 12L, epoch: 7,
    seat: 11L, proxy_generation: 4, serial: 9,
  }
  assert_true(same_geometry_target(target, target))
  assert_false(same_geometry_target(target, { ..target, serial: 10 }))
  assert_false(same_geometry_target(target, { ..target, seat: 12L }))
  assert_false(same_geometry_target(target, { ..target, proxy_generation: 5 }))
  let range = @text.TextRange::new(0, 1).unwrap()
  let style : @ubuntu_host.TextSessionStyle = { range, style: 1 }
  let changed_style : @ubuntu_host.TextSessionStyle = { range, style: 2 }
  let original : @ubuntu_host.TextSessionEvent = @ubuntu_host.Preedit(
    text="に", fallback="日", cursor_utf16=Some(1), styles=[style],
  )
  let different_fallback : @ubuntu_host.TextSessionEvent = @ubuntu_host.Preedit(
    text="に", fallback="二", cursor_utf16=Some(1), styles=[style],
  )
  let different_style : @ubuntu_host.TextSessionEvent = @ubuntu_host.Preedit(
    text="に", fallback="日", cursor_utf16=Some(1), styles=[changed_style],
  )
  assert_true(same_geometry_source(original, original))
  assert_false(same_geometry_source(original, different_fallback))
  assert_false(same_geometry_source(original, different_style))
  assert_false(same_geometry_source(original, @ubuntu_host.Commit(text="に", deletion=None, position=None)))
  let portable = @text_host.TextInputEvent::new(target.window, 12L, 8UL, @text_host.Preedit(text="に", cursor=1))
  let changed = @text_host.TextInputEvent::new(target.window, 12L, 8UL, @text_host.Preedit(text="に", cursor=0))
  assert_true(same_geometry_portable(portable, portable))
  assert_false(same_geometry_portable(portable, changed))
}
