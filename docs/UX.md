# Yami-kumo UX guide

Yami-kumo is a frame for application UX. It should make frequently repeated spatial decisions predictable without turning every screen into the same dashboard.

## 1. Keep the main task in the main region

The center workspace is where users should complete the task that brought them to the screen. Required fields, confirmation actions, errors, and the primary result belong here.

A useful rule is: if hiding a region would make the current task impossible, that content probably does not belong in an optional region.

## 2. Navigation should be durable

The left rail and navigation sidebar are for durable location and movement across the product.

Good uses:

- top-level product areas
- workspace/project navigation
- saved destinations and favorites
- account- or environment-level entry points

Avoid using navigation space for temporary properties of the selected object or page-specific controls.

On small screens the navigation sidebar becomes a drawer. Selecting a destination should normally close it.

## 3. Tabs are local navigation

Tabs represent sibling views of the same working context. They are useful when switching views should preserve the user's sense of place.

Good examples:

- Overview / Activity / Settings for one project
- Preview / Source / History for one document
- Details / Logs / Metrics for one deployment

Do not use tabs simply because there is available horizontal space.

## 4. The context panel is optional

`contextPanel` is deliberately generic. It is not permanent application chrome and it is not always an inspector.

Good uses:

- details for the currently selected item
- contextual properties or formatting controls
- page-specific filters
- related activity or history
- contextual help
- an AI assistant grounded in the current page or selection

Poor uses:

- primary navigation
- required form fields
- the only place to perform a critical action
- multi-step workflows
- content that every user needs to see before proceeding

The product decides whether a context panel exists at all. Prefer no panel to an empty or low-value panel.

## 5. Responsive behavior should preserve hierarchy

On a wide desktop, a useful context panel can remain beside the workspace. On narrower screens it should become a dismissible overlay/drawer instead of permanently shrinking the primary task.

For phone layouts:

- navigation opens from the left
- contextual content opens from the right
- opening one dismisses the other
- both start closed unless the task explicitly requires otherwise
- background tap and a visible close control dismiss the drawer

The physical left/right placement is an implementation convention; the semantic distinction is durable navigation vs contextual support.

## 6. Bottom status is for ambient information

The bottom bar works well for status that users may want to glance at without interrupting work:

- connectivity
- environment
- sync/build/background-job state
- lightweight version/status links

Blocking errors and required decisions should not be relegated to this bar.

## 7. Stable shell, product-owned content

The shell should own responsive layout behavior and semantic slots. Product code should own:

- whether optional regions exist
- their content
- when they open or close
- labels and accessible names
- product-specific state

This keeps Yami-kumo reusable without making products feel identical.
