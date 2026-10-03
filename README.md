# Yami-kumo

A reusable application-shell template built with [Cloudflare Kumo](https://github.com/cloudflare/kumo) and [Vite+](https://viteplus.dev/).

Yami-kumo is intentionally a shell, not a dashboard template. It gives products a predictable frame while leaving product-specific content and optional regions to the application.

## Shell anatomy

```text
Top bar
├─ Left rail
├─ Navigation sidebar (optional/collapsible)
├─ Workspace
│  ├─ Tabs (optional)
│  └─ Main content
├─ Context panel (optional)
└─ Bottom status bar (optional)
```

The semantic roles matter more than the physical positions:

- **Rail / sidebar** — durable navigation: “where am I?” and “where can I go?”
- **Tabs** — sibling views inside the current workspace.
- **Main content** — the primary task. Required actions should live here.
- **Context panel** — secondary information or actions that are useful *right now*, but are not the task itself.
- **Bottom bar** — lightweight global status, progress, or environment information.

The context panel is deliberately **not** called an inspector. An inspector is one valid use, but the slot can also host filters, properties, activity, contextual help, or an AI assistant. If there is no useful secondary context, omit the panel entirely.

## UX guidance

A good Yami-kumo screen keeps the frame stable and makes optional UI earn its space.

Use the context panel for things such as selected-item details, page-specific filters, properties, related activity, or contextual AI help. Avoid putting primary navigation, required form fields, blocking actions, or long workflows there.

On wide screens the panel may remain visible when the task benefits from it. On narrow screens it becomes a dismissible drawer. The demo starts it closed to reinforce that the region is optional rather than permanent chrome.

See [docs/UX.md](./docs/UX.md) for the full guidance.

## Demo

GitHub Pages: https://f4ah6o.github.io/Yami-kumo/

The demo is both a visual example and a description of the shell. Open **UX guide** to see one example of a context panel; the shell API itself does not prescribe that content.

## AppShell API

```tsx
<AppShell
  brand={<Brand />}
  rail={<PrimaryRail />}
  sidebar={<WorkspaceNavigation />}
  tabs={<WorkspaceTabs />}
  contextPanel={<SelectionDetails />}
  contextPanelLabel="Selection details"
  contextPanelOpen={detailsOpen}
  onContextPanelDismiss={() => setDetailsOpen(false)}
  bottomBar={<StatusBar />}
>
  <Page />
</AppShell>
```

Every region except the brand, rail, and main content is optional. Product code owns when optional regions exist and when they open.

## Development

This repository uses Vite+ (`vp`) as the frontend toolchain.

```bash
vp install
vp dev
vp check
vp test
vp build
```

## Structure

- `src/shell/AppShell.tsx` — reusable semantic slot contract
- `src/shell/layout.ts` — layout-region model used by the shell and tests
- `src/App.tsx` — interactive shell demo and usage description
- `src/styles.css` — responsive shell/layout styling
- `docs/UX.md` — guidance for choosing and composing shell regions
- `ACKNOWLEDGEMENTS.md` — design references and upstream acknowledgements

## Acknowledgements

The shell structure was inspired by the UI layout references shared in these posts:

- https://x.com/thenanyu/status/2105704619704029435?s=46
- https://x.com/lawrluk/status/2105711205172273621?s=46

See [ACKNOWLEDGEMENTS.md](./ACKNOWLEDGEMENTS.md) for details.
