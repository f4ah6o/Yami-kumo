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
`Commit("日本")` -> Destroyed. After the structural error the model remains
unchanged, the commit remains in the owner buffer, Destroyed remains inflight,
the original window and epoch/binding are retained, and the fake host has not
been stopped. Re-entering `drive` cannot silently replay either record. This is
retention, **not** successful application to the model or final recovery.

## Unresolved P1

The legacy one-shot wrapper and Ubuntu main still discard the owner on an error
and stop the host. The owner does not yet expose a validated same-owner resume,
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
