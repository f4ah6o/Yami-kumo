///|
test "shell demo owns one counter and bounded open state" {
  let initial = @shared_counter.ShellModel::new()
  assert_eq(initial.value(), 0)
  assert_true(!initial.sidebar_open())
  assert_true(!initial.context_open())
  let incremented = initial.update(
    @core.Activate(@core.NodeKey::new("increment")),
  )
  assert_eq(incremented.value(), 1)
  let sidebar = incremented.update(
    @core.Activate(@core.NodeKey::new("sidebar-increment")),
  )
  assert_eq(sidebar.value(), 2)
  let opened = sidebar.update(
    @core.Activate(@core.NodeKey::new("toggle-sidebar")),
  )
  assert_true(opened.sidebar_open())
  assert_eq(opened.value(), 2)
  let context = opened.update(
    @core.Activate(@core.NodeKey::new("toggle-context")),
  )
  assert_true(context.context_open())
  assert_eq(context.value(), 2)
  let closed = context.update(
    @core.Activate(@core.NodeKey::new("toggle-sidebar")),
  )
  assert_true(!closed.sidebar_open())
  assert_true(closed.context_open())
}

///|
test "shell demo view has the required regions and one increment key" {
  let view = @shared_counter.ShellModel::new().view()
  assert_eq(view.kind(), @core.AppShell)
  assert_eq(view.key(), @core.NodeKey::new("shell"))
  let children = view.children()
  assert_eq(children.length(), 11)
  let regions = children.map(fn(child) { child.shell_region().unwrap() })
  assert_eq(regions[0], @core.Brand)
  assert_eq(regions[1], @core.NavigationTrigger)
  assert_eq(regions[2], @core.GlobalSearch)
  assert_eq(regions[3], @core.HeaderActions)
  assert_eq(regions[4], @core.AccountMenu)
  assert_eq(regions[5], @core.Rail)
  assert_eq(regions[6], @core.Sidebar)
  assert_eq(regions[7], @core.Tabs)
  assert_eq(regions[8], @core.Main)
  assert_eq(regions[9], @core.ContextPanel)
  assert_eq(regions[10], @core.BottomBar)
  assert_eq(children[8].children().length(), 3)
  assert_eq(children[8].children()[2].key(), @core.NodeKey::new("increment"))
  assert_eq(
    children[6].children()[1].key(),
    @core.NodeKey::new("sidebar-increment"),
  )
}

///|
test "shell demo state reaches the view without a second model" {
  let model = @shared_counter.ShellModel::new()
    .update(@core.Activate(@core.NodeKey::new("toggle-sidebar")))
    .update(@core.Activate(@core.NodeKey::new("toggle-context")))
    .update(@core.Activate(@core.NodeKey::new("increment")))
  assert_eq(model.value(), 1)
  let state = model.view().shell().unwrap()
  assert_true(state.mobile_sidebar_open())
  assert_true(state.context_panel_open())
  assert_true(!state.sidebar_collapsed())
  assert_eq(model.view().children()[8].children()[1].label(), "Count: 1")
}
