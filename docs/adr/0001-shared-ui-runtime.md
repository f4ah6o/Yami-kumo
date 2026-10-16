# ADR 0001: additive, host-neutral shared UI

Status: accepted for the bounded Text/Button/container development slice.
Date: 2026-10-17 JST.
Plan: [four-platform roadmap](../roadmaps/20261017-four-platform-gui/ROADMAP.md).

## Decision and scope

The common application owns one model, one update function and one semantic
View. The new `ui/` packages describe Text, Button and container identity and
lifetime. They do not carry HTML strings, DOM objects, GPUI windows/scenes or
React nodes in public types. The root module stays independent of GPUI and
JavaScript UI frameworks. A leaf DOM adapter uses real DOM text and button
nodes; a later native adapter will reuse existing GPUI primitives. The existing
GPUI Canvas browser backend remains a separate renderer and is not used to
reverse-engineer semantic HTML from scenes.

This first slice is additive and source-workspace-only. It does not publish a
package, change the existing private starter, select another default branch,
rename anything, or qualify the four-platform MVP. The Mooncakes allowlist and
npm preview exports retain their existing scope. Standalone source consumers
are deliberately distinguished from registry consumers.

## Vocabulary and dependency boundary

- Platform: Web, Linux, Windows or macOS. A platform is not a compiler target.
- Backend kind: DOM, GPUI native, existing GPUI Canvas, or pure model test.
- Compiler target: MoonBit JS/native initially. Pure tests may additionally run
  on Wasm/WasmGC; that does not establish browser support on those targets.
- Runtime dependency: code required by the installed application. The common
  slice uses MoonBit core; DOM uses browser APIs; the later native adapter uses
  GPUI and its OS host. None of these is described as dependency-free.
- Build/test dependency: MoonBit, Node, Python, browser automation, the existing
  Vite+ toolchain and legacy Kumo extraction. They do not enter the new common
  runtime simply because the repository uses them.
- Standard theme: a future bounded, independent light/dark theme. This slice
  uses browser-default controls. Legacy Kumo CSS/theme remains supported by its
  existing APIs and is not a dependency of the new path.

## Relationship to earlier work

| Existing contract or asset                                                                                                                                   | Treatment                                                                                                     |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------- |
| [20261015 shared UX](../../issues/open/20261015-ecosystem-web-native-ux-integration.md): one operation has one meaning, state/focus/semantics are observable | Inherited; evidence remains separated by profile and observation layer                                        |
| [20261005 plan](../../issues/open/20261005-kumo-gpui-shared-ux.md): pinned Kumo extraction and variant parity                                                | Maintained for the legacy API; not the completion criterion for the additive API                              |
| Existing HTML escaping, attributes, Input/form reset and npm preview                                                                                         | Retained unchanged with their consumer regression tests                                                       |
| Existing native Button repaint/cancel fixes and OS-qualified evidence                                                                                        | Retained; no completed item is reopened, and historical evidence is not relabeled as proof of the new adapter |
| AppShell role boundaries and familiar native control behavior                                                                                                | Inherited; new shared AppShell is deferred to YK-05                                                           |
| Native input/IME/AX gaps                                                                                                                                     | Remain open and profile-specific; a compiled pure consumer cannot close them                                  |

## Lifecycle and ordering

A stable key identifies a node within a root. A mounted instance also has an
opaque root and incarnation identity. Duplicate or empty keys are rejected
before a runtime update changes any mounted state. An unchanged key and node
kind keeps its incarnation. Removal, type replacement and disposal revoke old
event identities. Different roots cannot use each other's event identities.

The runtime receives already normalized semantic actions. It does not create a
third low-level pointer/key Button controller. Actions are queued and checked
against current ownership and enabled/loading state before delivery to the
application. The application drains one action, updates its single model and commits its
next View before accepting the next queued action. Focus has a separate channel:
one outstanding request per root; a newer accepted request supersedes older
requests and undelivered outcomes. No total cross-channel ordering is promised. Host callbacks must not recursively update that model.
Browser `preventDefault` decisions belong to the synchronous DOM boundary and
must not wait for that queue.

A focus request is an intention. A host observation or typed rejection is a
separate result. Unsupported focus/IME/AX is never an optimistic success.
Dispose is idempotent. DOM-owned callbacks/listeners must be revoked with their
root; pure runtime teardown is not itself a browser resource-leak proof.

## Decisions reserved before later controls

The initial counter accepts semantic Activate events only. Its DOM Button uses
native `click` as the sole activation source, including accessibility-generated
clicks. It does not synthesize another activation from keydown/keyup.

| Question                                     | Bounded decision / next gate                                                                                                                                                                                         |
| -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Enter repeat                                 | Preserve browser-native click behavior in DOM. Compare existing Yami and GPUI controllers under GP-00 before choosing a native common policy; do not alter legacy repeat behavior implicitly                         |
| Loading and focus                            | Runtime suppresses activation while loading. DOM retains the same button and expresses loading with `aria-busy`; no autofocus or invented focus-success state. General cross-host focus/loading policy remains YK-04 |
| TextField external values during composition | Deferred to YK-06 after GP-01; no input, IME or composition implementation/claim in this slice                                                                                                                       |
| Dialog Escape while composing                | Deferred to YK-07 after the text host contract; no modal/IME policy guessed from Button evidence                                                                                                                     |

## Fixture and result contract

[contract-v1.json](../../fixtures/shared-ui/contract-v1.json) fixes fixture IDs,
expected domain traces and the intentionally empty profile-difference allowlist
before runtime measurements. The executable result-schema validator is
[evidence.mjs](../../tests/shared-ui/evidence.mjs). Its negative tests cover
unsupported-as-pass, missing artifacts/profiles, stale source identity and domain
mismatches. Result records separate capability from execution status and carry
candidate/dependency identity, profile, command, exit code and artifact hashes.
A successful model or package result cannot substitute for a DOM, native
window, physical input, IME, accessibility or visual result.

## Completion boundary

YK-01 establishes portable models and lifetime contracts. YK-02 additionally
needs real-browser keyed updates and isolation evidence. YK-03 additionally
needs each declared native host. This ADR does not claim those later gates are
already complete, and the full roadmap's M1/M4 checkboxes remain open until their
required profiles actually run.
