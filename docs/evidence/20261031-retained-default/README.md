# Ubuntu Settings retained-entry selector

Ubuntu `--settings-e2e`, `YAMI_NATIVE_UI_SETTINGS_E2E=1`, and the existing
explicit control flag now enter the same retained Settings path. That path
keeps the original host and owner and exposes a same-UID private control socket
when interrupted. It does not call the legacy outer `host.stop()` after a
retained run returns with an unresolved owner. Ordinary non-Settings native
entry remains routed through its existing entrypoint.

Against unpublished GPUI source
`b28cff9a8a92a155e67421a397a1030dedac9301`, Ubuntu entry tests passed 3/3 and
its native executable built successfully. Local test log SHA-256
`3545dbeaaaea4fd474e2940de420ab472bdefe3454dca526d8127f5ae53b8976`, build log
`21d6551cd925e7042aa6eba0104787235ea7b855a77463df52ef90545684b3c9`, binary
`90a602dc76b93c7f254b694a5886299297066c5c98b8ddf00415f409c30c8e77`. The
binary was built before this evidence-only edit. No runtime/live result for the
new selector is asserted here.

This narrow change does not implement automatic GUI recovery, no-IME host
fallback, fully bounded receipt retirement or safe shutdown. The control socket
requires explicit bounded steps and does not persist the owner across process
exit. It does not establish that CI, Linux live IME, public registry consumer,
or the product P1 pass.
