///|
extern "js" fn throw_type_error(message : String) -> String =
  #| (message) => { throw new TypeError(message); }

///|
priv suberror BridgeError {
  Invalid(String)
}

///|
#export_name("render")
pub fn render(spec : String) -> String {
  try {
    let json = @json.parse(spec) catch {
      _ => raise Invalid("Invalid node JSON")
    }
    let node = decode(json)
    match @yami_kumo.render_html(node) {
      Ok(html) => html
      Err(_) => raise Invalid("Unsafe HTML rejected by MoonBit")
    }
  } catch {
    Invalid(message) => throw_type_error(message)
  }
}

///|
fn field(value : Json, key : String) -> Json? {
  match value {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn string(value : Json, key : String, fallback : String) -> String {
  match field(value, key) {
    Some(String(text)) => text
    _ => fallback
  }
}

///|
fn boolean(value : Json, key : String) -> Bool {
  field(value, key) is Some(True)
}

///|
fn optional_boolean(value : Json, key : String) -> Bool? {
  match field(value, key) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}

///|
fn optional_string(value : Json, key : String) -> String? {
  match field(value, key) {
    Some(String(text)) => Some(text)
    _ => None
  }
}

///|
fn slot(value : Json, key : String) -> @yami_kumo.Html? raise BridgeError {
  match field(value, key) {
    Some(value) => Some(decode(value))
    None => None
  }
}

///|
fn size(props : Json) -> @yami_kumo.ControlSize {
  match string(props, "size", "base") {
    "xs" => @yami_kumo.Xs
    "sm" => @yami_kumo.Sm
    "lg" => @yami_kumo.Lg
    _ => @yami_kumo.Base
  }
}

///|
fn attributes(props : Json) -> Array[@yami_kumo.Attribute] raise BridgeError {
  let result = []
  match field(props, "attrs") {
    Some(Object(attrs)) =>
      for name, value in attrs {
        let attribute = match value {
          String(text) => @yami_kumo.attr(name, text)
          True => @yami_kumo.boolean_attr(name)
          False => continue
          _ => raise Invalid("Invalid attribute: \{name}")
        }
        match attribute {
          Ok(value) => result.push(value)
          Err(_) =>
            raise Invalid("Unsafe attribute rejected by MoonBit: \{name}")
        }
      }
    _ => ()
  }
  result
}

///|
fn decode(node : Json) -> @yami_kumo.Html raise BridgeError {
  let props = field(node, "props").unwrap_or(node)
  let child_nodes = match field(node, "children") {
    Some(Array(items)) => items.map(decode)
    _ => []
  }
  let children = @yami_kumo.fragment(child_nodes)
  match string(node, "kind", "") {
    "text" => @yami_kumo.text(string(node, "value", ""))
    "fragment" => children
    "element" =>
      match
        @yami_kumo.element(
          string(props, "tag", "div"),
          attributes(props),
          child_nodes,
        ) {
        Ok(node) => node
        Err(_) => raise Invalid("Unsafe element rejected by MoonBit")
      }
    "button" => {
      let variant = match string(props, "variant", "secondary") {
        "primary" => @yami_kumo.Primary
        "ghost" => @yami_kumo.Ghost
        "destructive" => @yami_kumo.Destructive
        "secondary-destructive" => @yami_kumo.SecondaryDestructive
        "outline" => @yami_kumo.Outline
        _ => @yami_kumo.Secondary
      }
      @yami_kumo.button(
        children,
        variant~,
        size=size(props),
        disabled=boolean(props, "disabled"),
        button_type=string(props, "type", "button"),
        class_name=string(props, "className", ""),
        attrs=attributes(props),
      )
    }
    "input" => {
      let variant : @yami_kumo.InputVariant? = match
        optional_string(props, "variant") {
        Some("error") => Some(@yami_kumo.Error)
        Some(_) => Some(@yami_kumo.Default)
        None => None
      }
      @yami_kumo.input(
        id=string(props, "id", ""),
        size=size(props),
        variant?,
        label?=slot(props, "label"),
        description?=slot(props, "description"),
        error?=slot(props, "error"),
        placeholder?=optional_string(props, "placeholder"),
        disabled=boolean(props, "disabled"),
        required?=optional_boolean(props, "required"),
        class_name=string(props, "className", ""),
        attrs=attributes(props),
      )
    }
    "textComponent" => {
      let variant = match string(props, "variant", "body") {
        "heading" => @yami_kumo.Heading
        "secondary" => @yami_kumo.Secondary
        "success" => @yami_kumo.Success
        "error" => @yami_kumo.Error
        "mono" => @yami_kumo.Mono
        "mono-secondary" => @yami_kumo.MonoSecondary
        _ => @yami_kumo.Body
      }
      @yami_kumo.text_component(
        children,
        variant~,
        size=size(props),
        as_element?=optional_string(props, "as"),
        bold=boolean(props, "bold"),
        truncate=boolean(props, "truncate"),
        class_name=string(props, "className", ""),
        attrs=attributes(props),
      )
    }
    "layerCard" =>
      @yami_kumo.layer_card(
        children,
        layered=boolean(props, "layered"),
        class_name=string(props, "className", ""),
        attrs=attributes(props),
      )
    "layerCardPrimary" => @yami_kumo.layer_card_primary(children)
    "layerCardSecondary" => @yami_kumo.layer_card_secondary(children)
    "appShell" =>
      @yami_kumo.app_shell(
        decode(field(props, "brand").unwrap_or(node)),
        children,
        navigation_trigger?=slot(props, "navigationTrigger"),
        global_search?=slot(props, "globalSearch"),
        header_actions?=slot(props, "headerActions"),
        account_menu?=slot(props, "accountMenu"),
        rail?=slot(props, "rail"),
        sidebar?=slot(props, "sidebar"),
        tabs?=slot(props, "tabs"),
        context_panel?=slot(props, "contextPanel"),
        bottom_bar?=slot(props, "bottomBar"),
        context_panel_label=string(props, "contextPanelLabel", "Context panel"),
        sidebar_collapsed=boolean(props, "sidebarCollapsed"),
        mobile_sidebar_open=boolean(props, "mobileSidebarOpen"),
        context_panel_open=boolean(props, "contextPanelOpen"),
        primary_navigation_label=string(
          props, "primaryNavigationLabel", "Primary",
        ),
        workspace_navigation_label=string(
          props, "workspaceNavigationLabel", "Workspace navigation",
        ),
        close_workspace_navigation_label=string(
          props, "closeWorkspaceNavigationLabel", "Close workspace navigation",
        ),
        close_context_panel_label=string(
          props, "closeContextPanelLabel", "Close Context panel",
        ),
      )
    _ => raise Invalid("Unknown node kind")
  }
}
