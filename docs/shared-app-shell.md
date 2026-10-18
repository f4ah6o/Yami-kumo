# Shared AppShell: bounded YK-05 slice

The additive `ui/core` AppShell composes one application screen from a required
brand and main region plus optional navigation, header, rail, sidebar, tabs,
context-panel and bottom-bar regions. The same immutable View is consumed by the
DOM adapter and the GPUI adapter; the application still owns one model, one
update function and all open/close state.

This slice is source-workspace only. It does not change the legacy React
AppShell, the Kumo HTML API, the legacy native components or the npm preview.

## API

```moonbit
let view = @core.app_shell(
  @core.NodeKey::new("shell"),
  @core.text(@core.NodeKey::new("brand"), "Yami-kumo"),
  main,
  navigation_trigger=@core.button(@core.NodeKey::new("menu"), "Menu"),
  global_search=@core.text(@core.NodeKey::new("search"), "Search"),
  header_actions=@core.button(@core.NodeKey::new("context"), "Context"),
  account_menu=@core.text(@core.NodeKey::new("account"), "Account"),
  rail=rail,
  sidebar=sidebar,
  tabs=tabs,
  context_panel=context,
  bottom_bar=@core.text(@core.NodeKey::new("status"), "Ready"),
  mobile_sidebar_open=sidebar_open,
  context_panel_open=context_open,
)
```

`brand` and `main` are required. Every slot is an ordinary View; the shell only
tags its region and does not change the slot's own kind, children, labels or
gates. Slot keys must be unique across the whole root and are rejected
atomically if empty or duplicated.

`ShellMode::for_width` is the only breakpoint source:

- `width <= 820.0` is `Compact`.
- `width > 820.0` is `Wide`.
- The mounted shell is a CSS container (`container-type: inline-size`) and the
  compact rules use `@container yk-shell (max-width: 820px)`. The breakpoint
  therefore follows the shell's own width, not the browser viewport; an
  embedded 700px shell is compact inside a wide page. The outer line is an inset
  box-shadow so it does not reduce the query width.
- A shell must be the root View. Nested shells are rejected before a commit.
- The mounted DOM root must have a definite size; the shell fills it with
  `width: 100%` and `height: 100%`.

## Region behavior

| Region                      | Required | Wide                           | Compact                            |
| --------------------------- | -------- | ------------------------------ | ---------------------------------- |
| Brand                       | yes      | header left                    | header left                        |
| NavigationTrigger           | no       | hidden                         | visible                            |
| GlobalSearch                | no       | header middle                  | header middle                      |
| HeaderActions / AccountMenu | no       | header right                   | header right                       |
| Rail                        | no       | 58 logical px inline           | hidden                             |
| Sidebar                     | no       | 240 px inline unless collapsed | stacked when `mobile_sidebar_open` |
| Tabs                        | no       | 45 px above main               | same                               |
| Main                        | yes      | remaining space, 24 px padding | remaining space, 24 px padding     |
| ContextPanel                | no       | 288 px inline when open        | stacked 200 px when open           |
| BottomBar                   | no       | 32 px footer                   | same                               |

The compact branch is a **stacked panel** layout. It is not an overlay drawer:
there is no scrim, animation, focus trap or automatic background selection.
`sidebar_collapsed` applies to Wide; compact Sidebar visibility is controlled by
`mobile_sidebar_open`. Those overlay concerns remain later Shell/Dialog work.

## Theme

`ui/theme` is the single numeric source for `ShellColors`:
`background`, `panel`, `subtle`, `border`, `strong_border`, `text` and `muted`.
Light and dark tokens are generated into `styles/shared-ui.css` and checked
against `fixtures/shared-ui/app-shell-v1.json`. The existing Button RGB tokens
are unchanged.

- A shell without a selected theme uses the light shell surface colors and keeps
  the existing unthemed Button path.
- `mount(..., theme=Some(theme))` and `Mounted::new(..., theme=Some(theme))`
  opt in to the root theme.
- `set_theme` changes paint only. It must not recreate a visible slot, change its
  keyed identity, cancel a held gesture or move focus.
- Text uses the shell text token and Card uses the panel/border tokens inside a
  themed shell. This is bounded to the shell surface; it is not a general Text
  or Card API change.
- An explicit per-Button palette still takes precedence over the root theme.

## Focus, activation and visibility

A hidden region keeps its View identity but has no live host target:

- DOM hides the region with scoped CSS; native omits the region from the element
  tree while keeping the common runtime token.
- A focus request to a hidden region returns `false`/rejected, never an
  optimistic success.
- Hidden slots are not an automatic focus fallback. If the focused region
  disappears after a resize or open-state change, focus is cleared and the
  application must request a valid target.
- Activations queued from a region that becomes hidden are dropped when the
  application drains actions. Visible regions keep their normal queued-action
  ordering.
- Resizing across the breakpoint or changing a region's visibility invalidates
  old geometry and cancels held input where the adapter observes it. A
  theme-only change retains the accepted frame and input controller.

DOM keeps inert nodes for hidden responsive regions so visible DOM identity is
stable. Native does not lay out hidden slot descendants; it retains their
runtime keys/tokens but not a host control. Applications must not depend on host
node identity across visibility changes.

## Host ownership

- DOM owns the semantic `header`/`nav`/`aside`/`main`/`footer` wrappers, scoped
  classes, data attributes and aria labels. It does not write to the document
  body or another root.
- Native owns a nested flex layout with the same region order and the retained
  GPUI Button controller for each visible Button. It paints shell surfaces and
  borders from `ShellColors`.
- Native exposes `Frame::shell_mode()` and `Frame::region_bounds(region)` for
  observable geometry. Absent or hidden regions return `None`.

## Verification

```sh
moon test ui/core ui/runtime ui/theme examples/shared_counter --target all --deny-warn
moon test ui/core ui/runtime ui/theme examples/shared_counter --target all --deny-warn --release
pnpm run check:shared-theme
pnpm run build:shared-ui
node --test tests/shared-ui/*.test.mjs
```

The native portable shell tests exercise wide/compact geometry, region
visibility, theme retention, slot identity, hidden focus rejection, nested-shell
rejection and queued activation. They run with the same pinned GPUI workspace as
the other shared native tests.

### macOS visible-window and external-AX evidence

Local macOS host evidence was executed against runtime candidate
`22b699e` and pinned GPUI
`4c2e525f02c00a9c1a560152a914f523a4c2fe47`:

- `scripts/native_ui_macos.sh --shared-counter-render-proof` launched the
  visible native window and captured the wide and compact shell frames. Both
  render-only contract fixtures passed, including region bounds, root size,
  Button enclosure and captured text pixels.
- `scripts/native_ui_macos.sh --shared-counter-ax-proof` launched the shared
  shell as a registered temporary `.app`, performed
  `AXUIElementPerformAction(kAXPressAction)` on the published `Increment`
  Button, observed the model count change from `0` to `1`, and closed the
  window. The AX report confirms the exact PID/title and the completed action.
- The local evidence directories are
  `_build/native-ui/macos-shared-render-22b699e/`,
  `_build/native-ui/macos-shared-input-final2/` and
  `_build/native-ui/macos-shared-ax-22b699e/`. They are generated artifacts and
  are not committed.
- `scripts/native_ui_macos.sh --shared-counter-ui-proof` **passed** for the
  wide and compact shell fixtures. Guarded global CGEvent mouse move/down/up at
  the published AX frame produced two accepted increments per fixture and
  retained the shell mode/region observations. The pointer path uses an
  explicit AX-frame target mode because macOS AX hit testing does not return the
  custom GPUI element; it still requires the exact frontmost PID/title, an
  enabled AX Button, the activation baseline and a point inside the visible
  window.
- CI at `7dc51cf` passed the shared native `ubuntu-wayland` and
  `windows-d3d11` jobs with the shell pointer/render fixtures. The Linux
  compositor clamps the outer window request to `800x600`, so the driver
  validates the observed compact mode and region set against the actual content
  width. Windows ran its host-clamped wide/compact fixtures. This is synthetic
  XTest/SendInput host input, not physical hardware.
- Physical hardware input cannot be automated by this harness.

**Not claimed:** physical hardware input, a complete shell AX tree, IME,
TextField, Dialog, drawer animation/scrim/focus trap, general layout and
packaged distribution. The macOS AX and pointer results cover only the main
`Increment` Button and are local, not CI, evidence. Browser coverage here is
Chromium; Firefox/WebKit/Safari need their own profiles.
