///|
/// Render Yami-kumo's semantic application shell. Optional slots are omitted
/// when absent; localized aria labels and current drawer state are explicit.
pub fn app_shell(
  brand : Html,
  main : Html,
  navigation_trigger? : Html,
  global_search? : Html,
  header_actions? : Html,
  account_menu? : Html,
  rail? : Html,
  sidebar? : Html,
  tabs? : Html,
  context_panel? : Html,
  context_panel_label? : String = "Context panel",
  bottom_bar? : Html,
  sidebar_collapsed? : Bool = false,
  mobile_sidebar_open? : Bool = false,
  context_panel_open? : Bool = false,
  primary_navigation_label? : String = "Primary",
  workspace_navigation_label? : String = "Workspace navigation",
  close_workspace_navigation_label? : String = "Close workspace navigation",
  close_context_panel_label? : String = "Close Context panel",
) -> Html {
  let brand_group_children : Array[Html] = []
  match navigation_trigger {
    Some(trigger) =>
      brand_group_children.push(
        raw_element("div", [text_attribute("class", "yk-navigation-trigger")], [
          trigger,
        ]),
      )
    None => ()
  }
  brand_group_children.push(
    raw_element("div", [text_attribute("class", "yk-brand")], [brand]),
  )
  let header_children : Array[Html] = [
    raw_element(
      "div",
      [text_attribute("class", "yk-brand-group")],
      brand_group_children,
    ),
    raw_element(
      "div",
      [text_attribute("class", "yk-global-search")],
      optional_children(global_search),
    ),
  ]
  let header_end_children : Array[Html] = []
  match header_actions {
    Some(actions) =>
      header_end_children.push(
        raw_element("div", [text_attribute("class", "yk-header-actions")], [
          actions,
        ]),
      )
    None => ()
  }
  match account_menu {
    Some(account) =>
      header_end_children.push(
        raw_element("div", [text_attribute("class", "yk-account-menu")], [
          account,
        ]),
      )
    None => ()
  }
  header_children.push(
    raw_element(
      "div",
      [text_attribute("class", "yk-header-end")],
      header_end_children,
    ),
  )
  let shell_children : Array[Html] = [
    raw_element(
      "header",
      [text_attribute("class", "yk-topbar")],
      header_children,
    ),
  ]
  match rail {
    Some(rail_node) =>
      shell_children.push(
        raw_element(
          "nav",
          [
            text_attribute("class", "yk-rail"),
            text_attribute("aria-label", primary_navigation_label),
          ],
          [rail_node],
        ),
      )
    None => ()
  }
  match sidebar {
    Some(sidebar_node) => {
      shell_children.push(
        raw_element(
          "button",
          [
            text_attribute("type", "button"),
            text_attribute("class", "yk-drawer-scrim yk-sidebar-scrim"),
            text_attribute("aria-label", close_workspace_navigation_label),
          ],
          [],
        ),
      )
      shell_children.push(
        raw_element(
          "aside",
          [
            text_attribute("id", "yk-mobile-navigation"),
            text_attribute("class", "yk-sidebar"),
            text_attribute("aria-label", workspace_navigation_label),
          ],
          [sidebar_node],
        ),
      )
    }
    None => ()
  }
  let workspace_children : Array[Html] = []
  match tabs {
    Some(tab_node) =>
      workspace_children.push(
        raw_element(
          "nav",
          [
            text_attribute("class", "yk-tabs"),
            text_attribute("aria-label", "Workspace tabs"),
          ],
          [tab_node],
        ),
      )
    None => ()
  }
  workspace_children.push(
    raw_element("main", [text_attribute("class", "yk-main")], [main]),
  )
  shell_children.push(
    raw_element(
      "section",
      [
        text_attribute("class", "yk-workspace"),
        text_attribute("data-has-tabs", bool_name(tabs is Some(_))),
      ],
      workspace_children,
    ),
  )
  match context_panel {
    Some(panel_node) => {
      shell_children.push(
        raw_element(
          "button",
          [
            text_attribute("type", "button"),
            text_attribute("class", "yk-drawer-scrim yk-context-panel-scrim"),
            text_attribute("aria-label", close_context_panel_label),
          ],
          [],
        ),
      )
      shell_children.push(
        raw_element(
          "aside",
          [
            text_attribute("id", "yk-context-panel"),
            text_attribute("class", "yk-context-panel"),
            text_attribute("aria-label", context_panel_label),
          ],
          [panel_node],
        ),
      )
    }
    None => ()
  }
  match bottom_bar {
    Some(bar) =>
      shell_children.push(
        raw_element("footer", [text_attribute("class", "yk-bottom-bar")], [bar]),
      )
    None => ()
  }
  raw_element(
    "div",
    [
      text_attribute("class", "yk-shell"),
      text_attribute("data-has-rail", bool_name(rail is Some(_))),
      text_attribute("data-has-sidebar", bool_name(sidebar is Some(_))),
      text_attribute("data-sidebar-collapsed", bool_name(sidebar_collapsed)),
      text_attribute("data-mobile-sidebar-open", bool_name(mobile_sidebar_open)),
      text_attribute(
        "data-has-context-panel",
        bool_name(context_panel is Some(_)),
      ),
      text_attribute("data-context-panel-open", bool_name(context_panel_open)),
      text_attribute("data-has-bottom-bar", bool_name(bottom_bar is Some(_))),
    ],
    shell_children,
  )
}

///|
fn optional_children(node : Html?) -> Array[Html] {
  match node {
    Some(value) => [value]
    None => []
  }
}
