///|
test "Linux transport marker reports host-selected route or unknown" {
  let port = NativeTextInputPort::new(
    fn(_, _) { Ok(7UL) }, fn(epoch, _) { Ok(epoch) }, fn(epoch) { Ok(epoch) },
    fn(_) { Ok(()) }, fn(_) { Ok(None) },
  )
  assert_eq(settings_transport_label(Linux, port), "unknown")
  assert_eq(settings_transport_label(Linux, port.with_linux_transport(fn() { WaylandIme })), "text-input-v1")
  assert_eq(settings_transport_label(Linux, port.with_linux_transport(fn() { DirectKeyboard })), "direct-keyboard")
  assert_eq(settings_transport_label(Linux, port.with_linux_transport(fn() { UnknownLinuxTransport })), "unknown")
  assert_eq(settings_transport_label(Windows, port), "imm32")
  assert_eq(settings_transport_label(Macos, port), "appkit")
}
