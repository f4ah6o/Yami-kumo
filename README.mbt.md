# Yami-kumo MoonBit components

Yami-kumo is a pure MoonBit library for rendering safe HTML with a semantic
application shell and a pinned subset of Cloudflare Kumo components. The root
package has no React or npm dependency.

Install the module with:

```sh
moon add f4ah6o/yami_kumo
```

## Render an application shell

```moonbit
let brand = @yami_kumo.text("Workspace")
let main = @yami_kumo.text_component(
  @yami_kumo.text("Project settings"),
  variant=@yami_kumo.Heading,
  size=@yami_kumo.Lg,
)
let shell = @yami_kumo.app_shell(brand, main)
let html = @yami_kumo.render_html(shell)
```

The HTML API validates element and attribute names, rejects unsafe URL schemes,
and escapes text and attribute values. It has no raw-HTML or inline-style escape
hatch.

The component API currently includes Button, Input, Text, and LayerCard. Input
requires a caller-provided stable `id`; generated labels and helper/error
references remain unique when fields are composed together.

## Styles and browser input state

Serve both checked-in stylesheets with your application, loading
`styles/kumo-standalone.css` before `styles/yami-kumo-components.css`. They are
generated from the pinned Cloudflare Kumo 2.14.0 package. The emphasis button
classes keep primary and destructive variants compatible with a strict
`style-src 'self'` Content Security Policy.

For browser input state markers, import `f4ah6o/yami_kumo/dom` and call
`@dom.enhance()` after inserting the rendered markup. The adapter tracks focus,
dirty, filled, touched, and Enter-triggered validity state from native input
events. Disabled controls include `data-disabled` in their rendered markup.

The library source is MIT licensed; the redistributed Kumo stylesheet retains
its upstream license in [`licenses/cloudflare-kumo-LICENSE`](licenses/cloudflare-kumo-LICENSE).
