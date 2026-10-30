# Suspended Settings owner experiment — DO NOT MERGE

The Settings loop now has an explicit `SettingsRunOwner` that retains the host
reference, original window and `Mounted` editing authority, model, session
binding/epoch, frame gate, pending focus intent, bounded event buffers and an
inflight record after `drive` returns an error. The caller can inspect these
observations; `drive` refuses to replay an unresolved inflight record or a
successful host cutoff whose subsequent held-owner completion failed. The
owner stores a TextSession receipt separately from whether its model action was
enqueued; model application, scene publication and cutoff are not implied by
that receipt. It stops polling before fetching an additional source event when
its deferred buffers reach 64.

A scripted regression reproduces frame-pending -> resize -> original-epoch
`Commit("日本")` -> Destroyed. After the structural error the commit remains
buffered, Destroyed remains inflight, the original window and epoch/binding are
retained, and the fake host has not been stopped. An explicit experimental
terminal operation then applies this commit once to the original mounted field
and its model; the model becomes `日本`. Geometry is **not published**, the
terminal record remains inflight, and this is not full recovery or shutdown.
Repeated application fails. An ordered preedit prefix is applied to the same
field before its commit; an observed cancel rolls back the preview without a
model action. A held TextSession, missing sequence, wrong mounted owner, and
reentrant invalidation all fail closed in fixtures. Reentrant failure leaves
the original commit retryable.

The opaque field lease is captured immediately after a successful host begin;
the capture API relies on its caller to supply that host-issued epoch. A live
lease cannot be replaced by another epoch because queue completion has not been
proved. The terminal operation handles an ordered preedit, commit, or observed
cancel at the buffer head; it does not authenticate forged host events.
Before normal delivery, the runner checks the original binding and the exact
next sequence; a gap or foreign epoch stays inflight rather than being
discarded. Terminal field publication invalidates old staged views. These two
regressions were identified by independent review of `af16aa8`.
Normal field delivery also checks the original binding again after measurement
and checks action enqueue before publishing the field. Nested input is
rejected while measurement is in progress. Reentrant layout invalidation
leaves the original record unapplied. With an armed owner,
observed focus loss keeps an active preview until a later observed cancel.
The experimental terminal text cutoff requires empty local buffers, no pending
action, and an uncomposed original field. Busy retains the owner; in a scripted
fixture later admitted text is applied before retry. A successful fake cutoff
still leaves `can_stop` false. This does not prove the real native host can cut
off a destroyed window, retain records freed by native destroy/close, or
account for stale records skipped by its reader.

## Unresolved P1

The new `run_native_settings_retained` returns `Suspended(owner, error)` when a
run fails. The owner retains the backend reference and port closures, but the
caller must keep the underlying host alive. A failed drive cannot be restarted
implicitly, even with no inflight record. The legacy one-shot wrapper refuses
an ordered route before opening a window or polling input because it cannot
transfer ownership on failure.

Ubuntu main has not been adapted to retain this outcome. Since main is the
final process caller, simply returning without `host.stop()` would still lose
the owner on process exit. A live control/recovery policy is needed before
enabling this path. The owner does not yet expose a validated same-owner resume,
atomic geometry/scene republish, a caller acknowledgement for accepted actions,
or a terminal policy when the real window or field is destroyed. A successful
ordered exit does not establish a complete native-queue terminal receipt; the
new `can_stop` deliberately remains false for ordered runs. The legacy input
path and externally stopped hosts have not been adapted. No safe product entry,
registry consumer or live IME acceptance is claimed.

Candidate source: gpui `74d182c6368ca382f697023c5d3690b6c0c2dfbf`, Yami base
`064a2e6f6c654347ad2d2efeb59bef15fe31005d`. The native manifest still points to
published dependencies lacking the candidate API. Tests use a local source
workspace and do not establish published-package compatibility.

Local combined native UI and common fixture suite: **124/124 PASS** using
`GPUI_SOURCE=/workspace/gpui-ordered-fence` and
`scripts/native_ui_workspace.sh ... moon test <ui> <examples/common> --target
native --deny-warn --no-parallelize`. This is scripted evidence only; no
production main, live IME, or public-registry consumer was tested.
Local raw log SHA-256:
`dd272ad6bcd0b45a80808518ea53e57cbd9fc9d1e0c89f8c2870e3776f4f0bdb`.
