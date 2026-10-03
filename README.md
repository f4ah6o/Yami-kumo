# Yami-kumo

A reusable application-shell template built with [Cloudflare Kumo](https://github.com/cloudflare/kumo) and [Vite+](https://viteplus.dev/).

The canonical layout is:

```text
Top bar
├─ Left rail
├─ Sidebar
├─ Workspace
│  ├─ Tabs
│  └─ Main content
├─ Right sidebar (optional)
└─ Bottom status bar (optional)
```

The shell is intentionally slot-based so product-specific content stays outside the layout primitive.

## Demo

GitHub Pages: https://f4ah6o.github.io/Yami-kumo/

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

- `src/shell/AppShell.tsx` — reusable slot contract
- `src/shell/layout.ts` — layout-region model used by the shell and tests
- `src/App.tsx` — interactive demo based on the reference layout
- `src/styles.css` — responsive shell/layout styling
- `ACKNOWLEDGEMENTS.md` — design references and upstream acknowledgements

## Acknowledgements

The shell structure was inspired by the UI layout references shared in these posts:

- https://x.com/thenanyu/status/2105704619704029435?s=46
- https://x.com/lawrluk/status/2105711205172273621?s=46

See [ACKNOWLEDGEMENTS.md](./ACKNOWLEDGEMENTS.md) for details.
