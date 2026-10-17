///|
fn shell_mount(theme~ : @theme.Theme? = None) -> @ui.Mounted {
  @ui.Mounted::new(@platform.WindowId::new(1L), theme~)
}

///|
test "shared shell lays out wide regions and hides compact-only controls" {
  let mounted = shell_mount()
  let frame = mounted
    .commit(@model.ShellModel::new().view(), 1000.0, 700.0, 1.0, measure)
    .unwrap()
  assert_eq(frame.shell_mode(), Some(@view.Wide))
  for
    region in [
      @view.Brand,
      @view.GlobalSearch,
      @view.HeaderActions,
      @view.AccountMenu,
      @view.Rail,
      @view.Sidebar,
      @view.Tabs,
      @view.Main,
      @view.BottomBar,
    ] {
    assert_true(frame.region_bounds(region) is Some(_))
  }
  assert_true(frame.region_bounds(@view.NavigationTrigger) is None)
  assert_true(frame.region_bounds(@view.ContextPanel) is None)
  assert_true(frame.bounds(@view.NodeKey::new("navigation-trigger")) is None)
  assert_true(frame.bounds(@view.NodeKey::new("context-panel")) is None)
  assert_true(frame.bounds(@view.NodeKey::new("counter")) is Some(_))
  let main = frame.region_bounds(@view.Main).unwrap()
  let rail = frame.region_bounds(@view.Rail).unwrap()
  assert_true(rail.right() <= main.left())
  let header = frame.region_bounds(@view.Brand).unwrap()
  assert_true(header.top() < main.top())
}

///|
test "shared shell compact mode stacks open sidebar and context" {
  let mounted = shell_mount()
  let initial = @model.ShellModel::new()
  let frame = mounted
    .commit(initial.view(), 700.0, 700.0, 1.0, measure)
    .unwrap()
  assert_eq(frame.shell_mode(), Some(@view.Compact))
  assert_true(frame.region_bounds(@view.Rail) is None)
  assert_true(frame.region_bounds(@view.NavigationTrigger) is Some(_))
  assert_true(frame.region_bounds(@view.Sidebar) is None)
  assert_true(frame.region_bounds(@view.ContextPanel) is None)
  assert_true(frame.bounds(@view.NodeKey::new("sidebar-increment")) is None)
  let open = initial
    .update(@view.Activate(@view.NodeKey::new("toggle-sidebar")))
    .update(@view.Activate(@view.NodeKey::new("toggle-context")))
  let frame = mounted.commit(open.view(), 700.0, 700.0, 1.0, measure).unwrap()
  assert_true(frame.region_bounds(@view.Sidebar) is Some(_))
  assert_true(frame.region_bounds(@view.ContextPanel) is Some(_))
  assert_true(frame.bounds(@view.NodeKey::new("sidebar-increment")) is Some(_))
  let main = frame.region_bounds(@view.Main).unwrap()
  let sidebar = frame.region_bounds(@view.Sidebar).unwrap()
  let context = frame.region_bounds(@view.ContextPanel).unwrap()
  assert_true(sidebar.bottom() <= main.top())
  assert_true(main.bottom() <= context.top())
}

///|
test "shared shell theme changes paint without replacing slot identity" {
  let mounted = shell_mount(theme=Some(@theme.Light))
  let model = @model.ShellModel::new()
  let light = mounted.commit(model.view(), 1000.0, 700.0, 1.0, measure).unwrap()
  let increment_before = light
    .binding_id(@view.NodeKey::new("increment"))
    .unwrap()
  let main_before = light.region_bounds(@view.Main).unwrap()
  assert_eq(light.theme(), Some(@theme.Light))
  let shell_id = light.binding_id(@view.NodeKey::new("shell")).unwrap()
  let light_colors = @theme.Light.shell_colors()
  assert_theme_color(
    theme_item_color(light, shell_id + 16UL),
    light_colors.background,
  )
  assert_theme_color(
    theme_item_color(light, shell_id + 17UL),
    light_colors.panel,
  )
  assert_theme_color(
    theme_item_color(light, shell_id + 18UL),
    light_colors.subtle,
  )
  assert_theme_color(
    theme_item_color(light, shell_id + 19UL),
    light_colors.panel,
  )
  assert_theme_color(
    theme_item_color(light, shell_id + 20UL),
    light_colors.panel,
  )
  assert_theme_color(
    theme_item_color(light, shell_id + 22UL),
    light_colors.subtle,
  )
  assert_true(mounted.set_theme(Some(@theme.Dark)))
  let dark = mounted.commit(model.view(), 1000.0, 700.0, 1.0, measure).unwrap()
  assert_eq(dark.theme(), Some(@theme.Dark))
  let dark_colors = @theme.Dark.shell_colors()
  assert_theme_color(
    theme_item_color(dark, shell_id + 16UL),
    dark_colors.background,
  )
  assert_theme_color(theme_item_color(dark, shell_id + 17UL), dark_colors.panel)
  assert_eq(
    dark.binding_id(@view.NodeKey::new("increment")).unwrap(),
    increment_before,
  )
  assert_true(dark.region_bounds(@view.Main).unwrap() == main_before)
}

///|
test "shared shell rejects nested shells and hidden focus targets" {
  let mounted = shell_mount()
  let nested = @view.column(@view.NodeKey::new("outer"), [
    @model.ShellModel::new().view(),
  ])
  assert_true(mounted.commit(nested, 1000.0, 700.0, 1.0, measure) is Err(_))
  let model = @model.ShellModel::new()
  let frame = mounted.commit(model.view(), 700.0, 700.0, 1.0, measure).unwrap()
  assert_true(frame.bounds(@view.NodeKey::new("sidebar-increment")) is None)
  assert_true(!mounted.focus(@view.NodeKey::new("sidebar-increment")))
}

///|
test "shared shell drops activation queued from a region that becomes hidden" {
  let mounted = shell_mount()
  let model = @model.ShellModel::new().update(
    @view.Activate(@view.NodeKey::new("toggle-sidebar")),
  )
  let wide = mounted.commit(model.view(), 1000.0, 700.0, 1.0, measure).unwrap()
  let button = wide.bounds(@view.NodeKey::new("sidebar-increment")).unwrap()
  assert_true(mounted.handle_event(event(1L, down(button))).unwrap())
  assert_true(mounted.handle_event(event(2L, up(button))).unwrap())
  assert_eq(
    mounted.next_action(),
    Some(@view.Activate(@view.NodeKey::new("sidebar-increment"))),
  )
  assert_true(mounted.handle_event(event(3L, down(button))).unwrap())
  assert_true(mounted.handle_event(event(4L, up(button))).unwrap())
  let compact = mounted
    .commit(@model.ShellModel::new().view(), 700.0, 700.0, 1.0, measure)
    .unwrap()
  assert_true(compact.bounds(@view.NodeKey::new("sidebar-increment")) is None)
  assert_true(mounted.next_action() is None)
}
