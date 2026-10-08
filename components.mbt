///|
/// Kumo-compatible control sizes supported by Button and Input.
pub(all) enum ControlSize {
  Xs
  Sm
  Base
  Lg
}

///|
/// The Kumo Button variants supported by this MoonBit implementation.
pub(all) enum ButtonVariant {
  Primary
  Secondary
  Ghost
  Destructive
  SecondaryDestructive
  Outline
}

///|
/// Input appearance. An error message selects `Error` automatically when the
/// caller leaves this value unspecified.
pub(all) enum InputVariant {
  Default
  Error
}

///|
/// The Kumo Text variants supported by this MoonBit implementation.
pub(all) enum TextVariant {
  Heading
  Body
  Secondary
  Success
  Error
  Mono
  MonoSecondary
}

///|
/// Render a Kumo Button as safe HTML. `attrs` adds ordinary HTML attributes
/// such as `id`, `aria-label`, or `data-*` values.
pub fn button(
  children : Html,
  variant? : ButtonVariant = Secondary,
  size? : ControlSize = Base,
  disabled? : Bool = false,
  button_type? : String = "button",
  class_name? : String = "",
  attrs? : Array[Attribute] = [],
) -> Html {
  let class_key = "\{button_variant_name(variant)}|\{size_name(size)}|\{bool_name(disabled)}"
  let classes = append_classes(
    append_classes(generated_button_classes(class_key), emphasis_class(variant)),
    class_name,
  )
  let attributes : Array[Attribute] = [
    text_attribute("data-kumo-component", "Button"),
    text_attribute("class", classes),
  ]
  if disabled {
    attributes.push(boolean_attribute("disabled"))
  }
  attributes.push(text_attribute("type", button_type))
  let final_attributes = merge_attributes(attributes, attrs)
  let content = raw_element("span", [text_attribute("class", "contents")], [
    children,
  ])
  let button_children = match variant {
    Primary | Destructive => {
      let decoration = raw_element(
        "span",
        [
          text_attribute("aria-hidden", "true"),
          text_attribute(
            "class", "absolute inset-0 rounded-[inherit] bg-linear-to-b from-(--kumo-button-emphasis-gradient-start) to-(--kumo-button-emphasis-gradient-end) shadow-[inset_0_1px_0_0_var(--kumo-button-emphasis-bg)] group-hover:from-(--kumo-button-emphasis-bg)",
          ),
        ],
        [],
      )
      let content_wrap = raw_element(
        "span",
        [text_attribute("class", "relative flex items-center gap-1.5")],
        [content],
      )
      [decoration, content_wrap]
    }
    _ => [content]
  }
  raw_element("button", final_attributes, button_children)
}

///|
/// Render a Kumo Input. Labels, descriptions, and errors are semantic nodes;
/// the field wrapper links them to the control with stable ids.
pub fn input(
  id~ : String,
  size? : ControlSize = Base,
  variant? : InputVariant,
  label? : Html,
  description? : Html,
  error? : Html,
  placeholder? : String,
  disabled? : Bool = false,
  required? : Bool,
  class_name? : String = "",
  attrs? : Array[Attribute] = [],
) -> Html {
  let resolved_variant = match variant {
    Some(value) => input_variant_name(value)
    None =>
      match error {
        Some(_) => "error"
        None => "default"
      }
  }
  let class_key = "\{resolved_variant}|\{size_name(size)}"
  let classes = append_classes(generated_input_classes(class_key), class_name)
  let input_id = match find_attribute(attrs, "id") {
    Some(value) => value
    None => id
  }
  let has_field = label is Some(_) || description is Some(_) || error is Some(_)
  let input_attributes : Array[Attribute] = [text_attribute("id", input_id)]
  match label {
    Some(_) =>
      input_attributes.push(
        text_attribute("aria-labelledby", "\{input_id}-label"),
      )
    None => ()
  }
  input_attributes.push(text_attribute("class", classes))
  if disabled {
    input_attributes.push(boolean_attribute("disabled"))
  }
  match required {
    Some(true) => input_attributes.push(boolean_attribute("required"))
    _ => ()
  }
  if has_field {
    let description_id = "\{input_id}-description"
    let error_id = "\{input_id}-error"
    // Kumo's Field gives the error message precedence over helper text. Keep
    // aria-describedby aligned with the node that is actually rendered.
    let described_by = match (description, error) {
      (_, Some(_)) => error_id
      (Some(_), None) => description_id
      (None, None) => ""
    }
    if described_by != "" {
      input_attributes.push(text_attribute("aria-describedby", described_by))
    }
  }
  match placeholder {
    Some(value) => input_attributes.push(text_attribute("placeholder", value))
    None => ()
  }
  let final_input_attributes = merge_attributes(input_attributes, attrs)
  let control = raw_element("input", final_input_attributes, [])
  if !has_field {
    return control
  }
  let field_children : Array[Html] = []
  match label {
    Some(label_node) => {
      let label_content : Array[Html] = [label_node]
      match required {
        Some(false) =>
          label_content.push(
            raw_element(
              "span",
              [text_attribute("class", "font-normal text-kumo-subtle")],
              [text("(optional)")],
            ),
          )
        _ => ()
      }
      let label_span = raw_element(
        "span",
        [text_attribute("class", "inline-flex items-center gap-1")],
        label_content,
      )
      field_children.push(
        raw_element(
          "label",
          [
            text_attribute("id", "\{input_id}-label"),
            text_attribute("for", input_id),
            text_attribute(
              "class", "m-0 text-base font-medium text-kumo-default select-none",
            ),
          ],
          [label_span],
        ),
      )
    }
    None => ()
  }
  field_children.push(control)
  match (error, description) {
    (Some(error_node), _) =>
      field_children.push(
        raw_element(
          "div",
          [
            text_attribute("id", "\{input_id}-error"),
            text_attribute(
              "class", "text-sm leading-snug text-kumo-danger col-span-full",
            ),
          ],
          [error_node],
        ),
      )
    (None, Some(description_node)) =>
      field_children.push(
        raw_element(
          "p",
          [
            text_attribute("id", "\{input_id}-description"),
            text_attribute(
              "class", "text-sm leading-snug text-kumo-subtle col-span-full",
            ),
          ],
          [description_node],
        ),
      )
    (None, None) => ()
  }
  raw_element(
    "div",
    [
      text_attribute(
        "class", "yk-kumo-input-field grid gap-2 has-[input[type=checkbox]]:grid-cols-[auto_1fr] has-[input[type=checkbox]]:items-center has-[[role=switch]]:grid-cols-[auto_1fr] has-[[role=switch]]:items-center",
      ),
    ],
    field_children,
  )
}

///|
/// Render a Kumo Text element with an optional semantic tag override.
pub fn text_component(
  children : Html,
  variant? : TextVariant = Body,
  size? : ControlSize = Base,
  as_element? : String,
  bold? : Bool = false,
  truncate? : Bool = false,
  class_name? : String = "",
  attrs? : Array[Attribute] = [],
) -> Html {
  let tag = match as_element {
    Some(value) => value
    None => default_text_tag(variant)
  }
  let class_key = "\{text_variant_name(variant)}|\{size_name(size)}"
  let classes = generated_text_classes(class_key)
  let with_bold = if is_copy_variant(variant) && bold {
    append_classes(classes, "font-medium")
  } else {
    classes
  }
  let with_truncate = if truncate {
    append_classes(with_bold, "min-w-0 truncate")
  } else {
    with_bold
  }
  let attributes = merge_attributes(
    [text_attribute("class", append_classes(with_truncate, class_name))],
    attrs,
  )
  raw_element(tag, attributes, [children])
}

///|
/// Render a simple or layered Kumo LayerCard container.
pub fn layer_card(
  children : Html,
  layered? : Bool = false,
  class_name? : String = "",
  attrs? : Array[Attribute] = [],
) -> Html {
  let variant = if layered { "layered" } else { "simple" }
  let classes = append_classes(generated_layer_card_class(variant), class_name)
  let attributes = merge_attributes([text_attribute("class", classes)], attrs)
  raw_element("div", attributes, [children])
}

///|
/// Render the secondary heading section used inside a layered LayerCard.
pub fn layer_card_secondary(
  children : Html,
  class_name? : String = "",
  attrs? : Array[Attribute] = [],
) -> Html {
  layer_card_section(children, "secondary", class_name, attrs)
}

///|
/// Render the primary content section used inside a layered LayerCard.
pub fn layer_card_primary(
  children : Html,
  class_name? : String = "",
  attrs? : Array[Attribute] = [],
) -> Html {
  layer_card_section(children, "primary", class_name, attrs)
}

///|
fn layer_card_section(
  children : Html,
  section : String,
  class_name : String,
  attrs : Array[Attribute],
) -> Html {
  let classes = append_classes(generated_layer_card_class(section), class_name)
  let attributes = merge_attributes([text_attribute("class", classes)], attrs)
  raw_element("div", attributes, [children])
}

///|
fn size_name(size : ControlSize) -> String {
  match size {
    Xs => "xs"
    Sm => "sm"
    Base => "base"
    Lg => "lg"
  }
}

///|
fn button_variant_name(variant : ButtonVariant) -> String {
  match variant {
    Primary => "primary"
    Secondary => "secondary"
    Ghost => "ghost"
    Destructive => "destructive"
    SecondaryDestructive => "secondary-destructive"
    Outline => "outline"
  }
}

///|
fn input_variant_name(variant : InputVariant) -> String {
  match variant {
    Default => "default"
    Error => "error"
  }
}

///|
fn text_variant_name(variant : TextVariant) -> String {
  match variant {
    Heading => "heading"
    Body => "body"
    Secondary => "secondary"
    Success => "success"
    Error => "error"
    Mono => "mono"
    MonoSecondary => "mono-secondary"
  }
}

///|
fn default_text_tag(variant : TextVariant) -> String {
  match variant {
    Heading | Mono | MonoSecondary => "span"
    _ => "p"
  }
}

///|
fn is_copy_variant(variant : TextVariant) -> Bool {
  match variant {
    Body | Secondary | Success | Error => true
    _ => false
  }
}

///|
fn emphasis_class(variant : ButtonVariant) -> String {
  match variant {
    Primary => "yk-kumo-button-emphasis-primary"
    Destructive => "yk-kumo-button-emphasis-destructive"
    _ => ""
  }
}

///|
fn bool_name(value : Bool) -> String {
  if value {
    "true"
  } else {
    "false"
  }
}

///|
fn append_classes(base : String, extra : String) -> String {
  if extra == "" {
    base
  } else if base == "" {
    extra
  } else {
    "\{base} \{extra}"
  }
}

///|
fn find_attribute(attributes : Array[Attribute], name : String) -> String? {
  for attribute in attributes {
    if attribute.name == name {
      return attribute.value
    }
  }
  None
}

///|
fn merge_attributes(
  base : Array[Attribute],
  extra : Array[Attribute],
) -> Array[Attribute] {
  let merged : Array[Attribute] = []
  for attribute in base {
    merged.push(attribute)
  }
  for attribute in extra {
    let mut found_index : Int? = None
    for index in 0..<merged.length() {
      if merged[index].name == attribute.name {
        found_index = Some(index)
      }
    }
    match found_index {
      Some(index) =>
        if attribute.name == "class" {
          match (merged[index].value, attribute.value) {
            (Some(base_value), Some(extra_value)) =>
              merged[index] = text_attribute(
                "class",
                append_classes(base_value, extra_value),
              )
            _ => merged[index] = attribute
          }
        } else {
          merged[index] = attribute
        }
      None => merged.push(attribute)
    }
  }
  merged
}
