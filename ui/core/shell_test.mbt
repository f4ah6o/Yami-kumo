///|
test "app shell requires brand and main and preserves canonical region order" {
  let brand = @core.text(@core.NodeKey::new("brand"), "Yami-kumo")
  let main = @core.column(@core.NodeKey::new("main"), [
    @core.text(@core.NodeKey::new("heading"), "Settings"),
  ])
  let nav = @core.button(@core.NodeKey::new("nav"), "Menu")
  let search = @core.text(@core.NodeKey::new("search"), "Search")
  let actions = @core.button(@core.NodeKey::new("actions"), "Save")
  let account = @core.text(@core.NodeKey::new("account"), "Account")
  let rail = @core.text(@core.NodeKey::new("rail"), "Rail")
  let sidebar = @core.text(@core.NodeKey::new("sidebar"), "Sidebar")
  let tabs = @core.text(@core.NodeKey::new("tabs"), "Tabs")
  let context = @core.text(@core.NodeKey::new("context"), "Context")
  let bottom = @core.text(@core.NodeKey::new("bottom"), "Ready")
  let shell = @core.app_shell(
    @core.NodeKey::new("shell"),
    brand,
    main,
    navigation_trigger=nav,
    global_search=search,
    header_actions=actions,
    account_menu=account,
    rail~,
    sidebar~,
    tabs~,
    context_panel=context,
    bottom_bar=bottom,
  )
  assert_eq(shell.kind(), @core.AppShell)
  assert_true(shell.is_shell())
  assert_eq(shell.label(), "")
  let children = shell.children()
  assert_eq(children.map(fn(child) { child.shell_region().unwrap() }), [
    @core.Brand,
    @core.NavigationTrigger,
    @core.GlobalSearch,
    @core.HeaderActions,
    @core.AccountMenu,
    @core.Rail,
    @core.Sidebar,
    @core.Tabs,
    @core.Main,
    @core.ContextPanel,
    @core.BottomBar,
  ])
  assert_eq(children[0].key(), @core.NodeKey::new("brand"))
  assert_eq(children[8].key(), @core.NodeKey::new("main"))
  assert_eq(children[0].kind(), @core.Text)
  assert_eq(children[8].kind(), @core.Column)
}

///|
test "optional shell regions are omitted without changing required slots" {
  let shell = @core.app_shell(
    @core.NodeKey::new("shell"),
    @core.text(@core.NodeKey::new("brand"), "Brand"),
    @core.text(@core.NodeKey::new("main"), "Main"),
  )
  assert_eq(shell.children().length(), 2)
  assert_eq(shell.children()[0].shell_region(), Some(@core.Brand))
  assert_eq(shell.children()[1].shell_region(), Some(@core.Main))
  assert_eq(shell.children()[0].kind(), @core.Text)
  assert_eq(shell.children()[1].kind(), @core.Text)
  assert_eq(
    @core.text(@core.NodeKey::new("plain"), "Plain").shell_region(),
    None,
  )
  assert_eq(@core.text(@core.NodeKey::new("plain"), "Plain").shell(), None)
}

///|
test "shell state is application data and is copied into the view" {
  let shell = @core.app_shell(
    @core.NodeKey::new("shell"),
    @core.text(@core.NodeKey::new("brand"), "Brand"),
    @core.text(@core.NodeKey::new("main"), "Main"),
    sidebar_collapsed=true,
    mobile_sidebar_open=true,
    context_panel_open=true,
    primary_navigation_label="Primary navigation",
    workspace_navigation_label="Workspace",
    context_panel_label="Details",
  )
  let state = shell.shell().unwrap()
  assert_true(state.sidebar_collapsed())
  assert_true(state.mobile_sidebar_open())
  assert_true(state.context_panel_open())
  assert_eq(state.primary_navigation_label(), "Primary navigation")
  assert_eq(state.workspace_navigation_label(), "Workspace")
  assert_eq(state.context_panel_label(), "Details")
  let other = @core.app_shell(
    @core.NodeKey::new("shell"),
    @core.text(@core.NodeKey::new("brand"), "Brand"),
    @core.text(@core.NodeKey::new("main"), "Main"),
    sidebar_collapsed=true,
    mobile_sidebar_open=true,
    context_panel_open=true,
    primary_navigation_label="Primary navigation",
    workspace_navigation_label="Workspace",
    context_panel_label="Details",
  )
  assert_eq(shell, other)
}

///|
test "shell breakpoint and region visibility use one shared boundary" {
  assert_eq(@core.SHELL_COMPACT_MAX_WIDTH, 820.0)
  assert_eq(@core.ShellMode::for_width(819.999), @core.Compact)
  assert_eq(@core.ShellMode::for_width(820.0), @core.Compact)
  assert_eq(@core.ShellMode::for_width(820.001), @core.Wide)
  let wide = @core.app_shell(
      @core.NodeKey::new("wide-shell"),
      @core.text(@core.NodeKey::new("wide-brand"), "Brand"),
      @core.text(@core.NodeKey::new("wide-main"), "Main"),
    )
    .shell()
    .unwrap()
  assert_true(@core.Brand.visible(wide, @core.Wide))
  assert_true(@core.Main.visible(wide, @core.Compact))
  assert_true(!@core.NavigationTrigger.visible(wide, @core.Wide))
  assert_true(@core.NavigationTrigger.visible(wide, @core.Compact))
  assert_true(@core.Rail.visible(wide, @core.Wide))
  assert_true(!@core.Rail.visible(wide, @core.Compact))
  assert_true(@core.Sidebar.visible(wide, @core.Wide))
  assert_true(!@core.Sidebar.visible(wide, @core.Compact))
  assert_true(@core.Tabs.visible(wide, @core.Wide))
  assert_true(!@core.ContextPanel.visible(wide, @core.Wide))
  assert_true(@core.BottomBar.visible(wide, @core.Compact))
  let collapsed = @core.app_shell(
      @core.NodeKey::new("shell"),
      @core.text(@core.NodeKey::new("brand"), "Brand"),
      @core.text(@core.NodeKey::new("main"), "Main"),
      sidebar_collapsed=true,
    )
    .shell()
    .unwrap()
  assert_true(!@core.Sidebar.visible(collapsed, @core.Wide))
  let mobile = @core.app_shell(
      @core.NodeKey::new("shell"),
      @core.text(@core.NodeKey::new("brand"), "Brand"),
      @core.text(@core.NodeKey::new("main"), "Main"),
      mobile_sidebar_open=true,
    )
    .shell()
    .unwrap()
  assert_true(@core.Sidebar.visible(mobile, @core.Compact))
}
