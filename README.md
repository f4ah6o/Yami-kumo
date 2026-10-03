# Yami-kumo

A copy-ready application-shell starter built with [Cloudflare Kumo](https://github.com/cloudflare/kumo) and [Vite+](https://viteplus.dev/).

The default `main` branch is intentionally small enough to use as a new application's starting point. The richer showcase lives on the [`demo` branch](https://github.com/f4ah6o/Yami-kumo/tree/demo) and is published at https://f4ah6o.github.io/Yami-kumo/.

## Use as a starter

Use GitHub's **Use this template** action to create a new independent repository from `main`. A template copy starts with the starter rather than the showcase branch.

After copying:

```bash
vp install
vp dev
```

Then replace `src/App.tsx` with your product's navigation and primary task.

## Shell anatomy

Every region except the top bar/brand and main content is optional.

```text
Top bar
├─ navigation trigger (optional)
├─ brand
├─ global search (optional)
├─ header actions (optional)
└─ account menu (optional)

Workspace
├─ left rail (optional)
├─ navigation sidebar (optional/collapsible)
├─ tabs (optional)
├─ main content
├─ context panel (optional)
└─ bottom status bar (optional)
```

The semantic roles matter more than the physical positions:

- **Rail / sidebar** — durable navigation: “where am I?” and “where can I go?”
- **Tabs** — sibling views inside the current workspace.
- **Main content** — the primary task. Required actions should live here.
- **Context panel** — secondary information or actions that are useful _right now_, but are not the task itself.
- **Account menu** — identity/account affordance; the starter uses a person silhouette instead of fake initials.
- **Bottom bar** — lightweight global status, progress, or environment information.

The context panel is deliberately **not** called an inspector. An inspector is one valid use, but the slot can also host filters, properties, activity, contextual help, or an AI assistant. If there is no useful secondary context, omit the panel entirely.

## AppShell API

A minimal shell only needs a brand and main content:

```tsx
<AppShell brand={<Brand />}>
  <Page />
</AppShell>
```

Add regions only when the product benefits from them:

```tsx
<AppShell
  navigationTrigger={<MobileNavigationButton />}
  brand={<Brand />}
  globalSearch={<GlobalSearch />}
  headerActions={<PageActions />}
  accountMenu={<AccountMenu />}
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

Product code owns whether optional regions exist, their content, and when they open. The shell owns their spatial/responsive relationship.

## Responsive convention

On phones, durable navigation becomes a left drawer. Contextual support becomes a right drawer. They should start closed unless the current task explicitly requires one, and opening one should normally dismiss the other.

See [docs/UX.md](./docs/UX.md) for the full composition guidance.

## Branches

- **`main`** — copy-ready starter; no GitHub Pages deployment.
- **`demo`** — showcase/description source; GitHub Pages deploys from this branch through Actions.

This keeps template copies free of showcase content and Pages-specific configuration.

## Development

The starter uses Vite+ (`vp`) for install, checks, tests, and builds.

```bash
vp install
vp check
vp exec tsc --noEmit
vp test
vp build
```

## Structure

- `src/shell/AppShell.tsx` — reusable semantic slot contract
- `src/shell/layout.ts` — layout-region model and tests
- `src/App.tsx` — small starter application
- `src/styles.css` — responsive shell plus starter styles
- `docs/UX.md` — guidance for choosing and composing shell regions
- `ACKNOWLEDGEMENTS.md` — upstream and layout-reference acknowledgements

## Acknowledgements

The shell structure was inspired by the UI layout references shared in these posts:

- https://x.com/thenanyu/status/2105704619704029435?s=46
- https://x.com/lawrluk/status/2105711205172273621?s=46

See [ACKNOWLEDGEMENTS.md](./ACKNOWLEDGEMENTS.md) for details.
