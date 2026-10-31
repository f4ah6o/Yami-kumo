# Retained release: scoped native-adapter handoff candidate

The opt-in Ubuntu entry owns its fresh Host, claims the retained route before
creating its first window, and has no other event reader in that branch. For an
unsupported head it holds the original opaque GPUI receipt and the Yami owner.
An explicit sequence-bound request captures the current local prefix within
one synchronous operation, guards the owner against reentry, rechecks GPUI's
physical release evidence for the same native window/sequence/epoch/seat/proxy,
requires claim-before-window, first window/focus and `NoPressObservedSinceFocus`,
and only then invokes the exact retained ACK continuation. The common API
requires the host adapter to be trusted: an arbitrary callback is not native
proof, and the adapter's ACK must leave its record owned on error. Previously
saved local snapshots do not authorize the operation. This policy is limited to
the opt-in fresh entry; it is not a general release policy for other focus
owners, old hosts, another input path, or an arbitrary untrusted adapter.

Scripted fixtures test an unused/escaped continuation, reentry, double ACK,
stale epoch/seat, failure before ACK, ACK error/retry, and an adapter error
after ACK. Receipt, owner and active preedit remain held where appropriate; a
completed native ACK is recorded before later failure. These tests use a fake
adapter, not native physical-key evidence or live IME.

Against explicit unpublished GPUI candidate
`b28cff9a8a92a155e67421a397a1030dedac9301` (#195), both native and shared UI
source-test pins select that SHA (this is **not** a published registry pin):

```sh
env TMPDIR=/workspace/scratch/yami-owned-tmp PATH="/workspace/yami-tools/bin:$PATH" MOON_HOME=/workspace/yami-tools GPUI_SOURCE=/workspace/gpui-keymap-generation sh scripts/native_ui_workspace.sh sh -c 'moon test "$YAMI_NATIVE_MODULE_ROOT/examples/common" "$YAMI_NATIVE_MODULE_ROOT/ui" --target native --deny-warn --no-parallelize'
python3 -m unittest discover -s tests/native-ui -p 'test_settings_control.py'
```

Native UI + common 163/163 PASS, including the existing known-failure
characterization; checked-in `common-ui.log` SHA-256
`5b7858a4c494fc602de3368e257408e021a95d39903d11260eb554da57ab27ec`.
Socket tests 10/10 PASS. A native build and a new live run must use the exact
final source combination and record the app source and binary separately.

The full product P1, general IME composition handoff, resize/scene/host
transaction, ledger retirement, normal entrypoint, safe stop, clean registry
consumer and Linux live race remain incomplete. No candidate-table or Apple
Silicon result is implied. CI and independent review of the exact combined
head and native candidate are required before any acceptance claim.
