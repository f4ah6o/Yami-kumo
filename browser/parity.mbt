///|
#export_name("enhanceYamiKumo")
pub fn enhance_yami_kumo() -> Unit {
  @dom.enhance()
}

///|
/// @parity.export
/// Render one parity-manifest case through the production MoonBit components.
/// Input is the JSON object from `fixtures/kumo-cases.json`; the output is safe
/// HTML produced by the same `render_html` API used by MoonBit consumers.
#export_name("renderParityCase")
pub fn render_parity_case(case_json : String) -> String {
  let case = @json.parse(case_json) catch {
    _ => return "<!-- invalid parity case -->"
  }
  let case = Some(case)
  let component = string_field(case, "component", "")
  let props = field(case, "props")
  let content = string_field(case, "content", "")
  let node = match component {
    "button" => render_button(props, content)
    "input" => render_input(props)
    "text" => render_text(props, content)
    "layerCard" => render_layer_card(props, content)
    "appShell" => render_app_shell(props, content)
    _ => @yami_kumo.text("Unsupported parity component")
  }
  match @yami_kumo.render_html(node) {
    Ok(html) => html
    Err(_) => "<!-- unsafe parity markup rejected -->"
  }
}

///|
fn render_button(props : Json?, content : String) -> @yami_kumo.Html {
  let variant = match string_field(props, "variant", "secondary") {
    "primary" => @yami_kumo.Primary
    "ghost" => @yami_kumo.Ghost
    "destructive" => @yami_kumo.Destructive
    "secondary-destructive" => @yami_kumo.SecondaryDestructive
    "outline" => @yami_kumo.Outline
    _ => @yami_kumo.Secondary
  }
  @yami_kumo.button(
    @yami_kumo.text(content),
    variant~,
    size=control_size(string_field(props, "size", "base")),
    disabled=bool_field(props, "disabled", false),
    button_type=string_field(props, "type", "button"),
    class_name=string_field(props, "className", ""),
    attrs=target_attributes(props),
  )
}

///|
fn render_input(props : Json?) -> @yami_kumo.Html {
  if bool_field(props, "grouped", false) {
    return render_input_group(props)
  }
  let value = string_field(props, "value", "")
  let attributes = target_attributes(props)
  let aria_label = string_field(props, "ariaLabel", "")
  if aria_label != "" {
    push_attribute(attributes, "aria-label", aria_label)
  }
  if value != "" {
    push_attribute(attributes, "value", value)
  }
  let id = string_field(props, "id", "field")
  let size = control_size(string_field(props, "size", "base"))
  let required = optional_bool_field(props, "required")
  let placeholder = optional_string_field(props, "placeholder")
  let label = optional_text_node_field(props, "label")
  let description = optional_text_node_field(props, "description")
  let error = optional_text_node_field(props, "error")
  if error is None {
    @yami_kumo.input(
      id~,
      size~,
      label?,
      description?,
      placeholder?,
      disabled=bool_field(props, "disabled", false),
      required?,
      class_name=string_field(props, "className", ""),
      attrs=attributes,
    )
  } else {
    @yami_kumo.input(
      id~,
      size~,
      variant=input_variant(string_field(props, "variant", "default")),
      label?,
      description?,
      error?,
      placeholder?,
      disabled=bool_field(props, "disabled", false),
      required?,
      class_name=string_field(props, "className", ""),
      attrs=attributes,
    )
  }
}

///|
fn render_input_group(props : Json?) -> @yami_kumo.Html {
  let first_id = string_field(props, "firstId", "parity-first")
  let first = @yami_kumo.input(
    id=first_id,
    label=@yami_kumo.text(string_field(props, "firstLabel", "Account name")),
    description=@yami_kumo.text(
      string_field(props, "firstDescription", "Shown to your team"),
    ),
    attrs=target_attribute_for(props, "firstTarget"),
  )
  let second_id = string_field(props, "secondId", "parity-second")
  let second = @yami_kumo.input(
    id=second_id,
    label=@yami_kumo.text(string_field(props, "secondLabel", "Email address")),
    description=@yami_kumo.text(
      string_field(props, "secondDescription", "Helper text is superseded"),
    ),
    error=@yami_kumo.text(string_field(props, "secondError", "Invalid email")),
    attrs=target_attribute_for(props, "secondTarget"),
  )
  @yami_kumo.fragment([first, second])
}

///|
fn render_text(props : Json?, content : String) -> @yami_kumo.Html {
  let child = @yami_kumo.text(content)
  let variant = text_variant(string_field(props, "variant", "body"))
  let size = control_size(string_field(props, "size", "base"))
  let bold = bool_field(props, "bold", false)
  let truncate = bool_field(props, "truncate", false)
  let class_name = string_field(props, "className", "")
  let attrs = target_attributes(props)
  match field(props, "as") {
    Some(Json::String(tag)) =>
      @yami_kumo.text_component(
        child,
        variant~,
        size~,
        as_element=tag,
        bold~,
        truncate~,
        class_name~,
        attrs~,
      )
    _ =>
      @yami_kumo.text_component(
        child,
        variant~,
        size~,
        bold~,
        truncate~,
        class_name~,
        attrs~,
      )
  }
}

///|
fn render_layer_card(props : Json?, content : String) -> @yami_kumo.Html {
  let child = if bool_field(props, "layered", false) {
    @yami_kumo.fragment([
      @yami_kumo.layer_card_secondary(
        @yami_kumo.text(string_field(props, "secondary", "Details")),
      ),
      @yami_kumo.layer_card_primary(@yami_kumo.text(content)),
    ])
  } else {
    @yami_kumo.text(content)
  }
  @yami_kumo.layer_card(
    child,
    layered=bool_field(props, "layered", false),
    class_name=string_field(props, "className", ""),
    attrs=target_attributes(props),
  )
}

///|
fn render_app_shell(props : Json?, content : String) -> @yami_kumo.Html {
  let trigger_result = @yami_kumo.element(
    "button",
    [
      attr("type", "button"),
      attr("aria-controls", "yk-mobile-navigation"),
      attr(
        "aria-expanded",
        bool_text(bool_field(props, "mobileSidebarOpen", false)),
      ),
      attr("data-parity-target", "nav-trigger"),
    ],
    [@yami_kumo.text(string_field(props, "triggerLabel", "Open navigation"))],
  )
  let trigger = match trigger_result {
    Ok(value) => value
    Err(_) => @yami_kumo.text("Open navigation")
  }
  let brand = @yami_kumo.text(string_field(props, "brand", "Workspace"))
  let main = @yami_kumo.text(content)
  if bool_field(props, "full", false) {
    @yami_kumo.app_shell(
      brand,
      main,
      navigation_trigger=trigger,
      global_search=slot_text(props, "search"),
      header_actions=slot_text(props, "headerActions"),
      account_menu=slot_text(props, "accountMenu"),
      rail=slot_text(props, "rail"),
      sidebar=slot_text(props, "sidebar"),
      tabs=slot_text(props, "tabs"),
      context_panel=slot_text(props, "contextPanel"),
      context_panel_label=string_field(
        props, "contextPanelLabel", "Context panel",
      ),
      bottom_bar=slot_text(props, "bottomBar"),
      sidebar_collapsed=bool_field(props, "sidebarCollapsed", false),
      mobile_sidebar_open=bool_field(props, "mobileSidebarOpen", false),
      context_panel_open=bool_field(props, "contextPanelOpen", false),
      primary_navigation_label=string_field(
        props, "primaryNavigationLabel", "Primary",
      ),
      workspace_navigation_label=string_field(
        props, "workspaceNavigationLabel", "Workspace navigation",
      ),
      close_workspace_navigation_label=string_field(
        props, "closeWorkspaceNavigationLabel", "Close workspace navigation",
      ),
      close_context_panel_label=string_field(
        props, "closeContextPanelLabel", "Close Context panel",
      ),
    )
  } else {
    @yami_kumo.app_shell(brand, main)
  }
}

///|
fn slot_text(props : Json?, name : String) -> @yami_kumo.Html {
  @yami_kumo.text(string_field(props, name, ""))
}

///|
fn field(value : Json?, name : String) -> Json? {
  match value {
    Some(Json::Object(fields)) => fields.get(name)
    _ => None
  }
}

///|
fn string_field(value : Json?, name : String, fallback : String) -> String {
  match field(value, name) {
    Some(Json::String(result)) => result
    _ => fallback
  }
}

///|
fn optional_text_node_field(value : Json?, name : String) -> @yami_kumo.Html? {
  match field(value, name) {
    Some(Json::String(text_value)) => Some(@yami_kumo.text(text_value))
    _ => None
  }
}

///|
fn bool_field(value : Json?, name : String, fallback : Bool) -> Bool {
  match field(value, name) {
    Some(Json::True) => true
    Some(Json::False) => false
    _ => fallback
  }
}

///|
fn optional_bool_field(value : Json?, name : String) -> Bool? {
  match field(value, name) {
    Some(Json::True) => Some(true)
    Some(Json::False) => Some(false)
    _ => None
  }
}

///|
fn optional_string_field(value : Json?, name : String) -> String? {
  match field(value, name) {
    Some(Json::String(result)) => Some(result)
    _ => None
  }
}

///|

///|
fn control_size(value : String) -> @yami_kumo.ControlSize {
  match value {
    "xs" => @yami_kumo.Xs
    "sm" => @yami_kumo.Sm
    "lg" => @yami_kumo.Lg
    _ => @yami_kumo.Base
  }
}

///|
fn input_variant(value : String) -> @yami_kumo.InputVariant {
  match value {
    "error" => @yami_kumo.Error
    _ => @yami_kumo.Default
  }
}

///|
fn text_variant(value : String) -> @yami_kumo.TextVariant {
  match value {
    "heading" => @yami_kumo.Heading
    "secondary" => @yami_kumo.Secondary
    "success" => @yami_kumo.Success
    "error" => @yami_kumo.Error
    "mono" => @yami_kumo.Mono
    "mono-secondary" => @yami_kumo.MonoSecondary
    _ => @yami_kumo.Body
  }
}

///|
fn target_attributes(props : Json?) -> Array[@yami_kumo.Attribute] {
  target_attribute_for(props, "target")
}

///|
fn target_attribute_for(
  props : Json?,
  key : String,
) -> Array[@yami_kumo.Attribute] {
  let attributes : Array[@yami_kumo.Attribute] = []
  let target = string_field(props, key, "")
  if target != "" {
    push_attribute(attributes, "data-parity-target", target)
  }
  attributes
}

///|
fn push_attribute(
  attributes : Array[@yami_kumo.Attribute],
  name : String,
  value : String,
) -> Unit {
  match @yami_kumo.attr(name, value) {
    Ok(attribute) => attributes.push(attribute)
    Err(_) => ()
  }
}

///|
fn attr(name : String, value : String) -> @yami_kumo.Attribute {
  match @yami_kumo.attr(name, value) {
    Ok(attribute) => attribute
    Err(_) => abort("invalid trusted parity attribute")
  }
}

///|
fn bool_text(value : Bool) -> String {
  if value {
    "true"
  } else {
    "false"
  }
}
