///|
enum HtmlNode {
  Text(String)
  Element(String, Array[Attribute], Array[Html])
  Fragment(Array[Html])
}

///|
/// A safe HTML tree. Text and attribute values are escaped by `render_html`.
pub struct Html {
  priv node : HtmlNode
}

///|
/// An escaped HTML attribute created with `attr` or `boolean_attr`.
pub struct Attribute {
  priv name : String
  priv value : String?
}

///|
/// Errors raised when a node, attribute, or URL is unsafe to serialize.
pub enum HtmlError {
  InvalidTag(String)
  InvalidAttributeName(String)
  UnsafeAttribute(String)
  UnsafeUrl(String)
  DuplicateAttribute(String)
  VoidElementHasChildren(String)
}

///|
/// Create escaped text content.
pub fn text(value : String) -> Html {
  Html::{ node: HtmlNode::Text(value), }
}

///|
/// Join several nodes without adding a wrapper element.
pub fn fragment(children : Array[Html]) -> Html {
  Html::{ node: HtmlNode::Fragment(children), }
}

///|
/// Create a text attribute after validating its name and any URL value.
pub fn attr(name : String, value : String) -> Result[Attribute, HtmlError] {
  match validate_attribute_name(name) {
    Err(error) => Err(error)
    Ok(_) =>
      if is_url_attribute(name) && !is_safe_url(value) {
        Err(HtmlError::UnsafeUrl(value))
      } else {
        Ok(Attribute::{ name, value: Some(value), })
      }
  }
}

///|
/// Create a true HTML boolean attribute such as `disabled` or `hidden`.
/// Omit the attribute entirely when its value should be false.
pub fn boolean_attr(name : String) -> Result[Attribute, HtmlError] {
  match validate_attribute_name(name) {
    Err(error) => Err(error)
    Ok(_) =>
      if is_boolean_attribute(name) {
        Ok(Attribute::{ name, value: None, })
      } else {
        Err(HtmlError::UnsafeAttribute(name))
      }
  }
}

///|
/// Create a validated HTML element. Script, embedded-document, and custom
/// elements are excluded so callers cannot turn markup into executable code.
pub fn element(
  tag : String,
  attributes : Array[Attribute],
  children : Array[Html],
) -> Result[Html, HtmlError] {
  if !is_safe_tag(tag) {
    return Err(HtmlError::InvalidTag(tag))
  }
  match validate_attributes(attributes) {
    Err(error) => Err(error)
    Ok(_) =>
      if is_void_tag(tag) && children.length() > 0 {
        Err(HtmlError::VoidElementHasChildren(tag))
      } else {
        Ok(Html::{ node: HtmlNode::Element(tag, attributes, children), })
      }
  }
}

///|
/// Serialize a safe node to deterministic, escaped HTML.
pub fn render_html(html : Html) -> Result[String, HtmlError] {
  let output = StringBuilder()
  match render_node(html, output) {
    Err(error) => Err(error)
    Ok(_) => Ok(output.to_string())
  }
}

///|
fn validate_attributes(
  attributes : Array[Attribute],
) -> Result[Unit, HtmlError] {
  let seen : Array[String] = []
  for attribute in attributes {
    match validate_attribute(attribute) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    if seen.contains(attribute.name) {
      return Err(HtmlError::DuplicateAttribute(attribute.name))
    }
    seen.push(attribute.name)
    match attribute.value {
      Some(value) =>
        if is_url_attribute(attribute.name) && !is_safe_url(value) {
          return Err(HtmlError::UnsafeUrl(value))
        }
      None =>
        if !is_boolean_attribute(attribute.name) {
          return Err(HtmlError::UnsafeAttribute(attribute.name))
        }
    }
  }
  Ok(())
}

///|
fn validate_attribute_name(name : String) -> Result[Unit, HtmlError] {
  if !is_ascii_attribute_name(name) {
    return Err(HtmlError::InvalidAttributeName(name))
  }
  if name.has_prefix("on") || name == "style" || name == "srcdoc" {
    return Err(HtmlError::UnsafeAttribute(name))
  }
  Ok(())
}

///|
fn validate_attribute(attribute : Attribute) -> Result[Unit, HtmlError] {
  validate_attribute_name(attribute.name)
}

///|
fn is_ascii_attribute_name(name : String) -> Bool {
  if name == "" {
    return false
  }
  let mut first = true
  let mut valid = true
  for character in name {
    let is_letter = (character >= 'a' && character <= 'z') ||
      character == '_' ||
      character == ':'
    let is_digit = character >= '0' && character <= '9'
    if !(is_letter ||
      is_digit ||
      (!first && (character == '-' || character == '.'))) {
      valid = false
    }
    if first && !is_letter {
      valid = false
    }
    first = false
  }
  valid
}

///|
fn is_safe_url(value : String) -> Bool {
  let lower = lowercase_ascii(value)
  !lower.contains("javascript:") &&
  !lower.contains("vbscript:") &&
  !lower.contains("data:") &&
  !value.contains("\n") &&
  !value.contains("\r") &&
  !value.contains("\t")
}

///|
fn lowercase_ascii(value : String) -> String {
  let output = StringBuilder()
  for character in value {
    match character {
      'A' => output.write_char('a')
      'B' => output.write_char('b')
      'C' => output.write_char('c')
      'D' => output.write_char('d')
      'E' => output.write_char('e')
      'F' => output.write_char('f')
      'G' => output.write_char('g')
      'H' => output.write_char('h')
      'I' => output.write_char('i')
      'J' => output.write_char('j')
      'K' => output.write_char('k')
      'L' => output.write_char('l')
      'M' => output.write_char('m')
      'N' => output.write_char('n')
      'O' => output.write_char('o')
      'P' => output.write_char('p')
      'Q' => output.write_char('q')
      'R' => output.write_char('r')
      'S' => output.write_char('s')
      'T' => output.write_char('t')
      'U' => output.write_char('u')
      'V' => output.write_char('v')
      'W' => output.write_char('w')
      'X' => output.write_char('x')
      'Y' => output.write_char('y')
      'Z' => output.write_char('z')
      _ => output.write_char(character)
    }
  }
  output.to_string()
}

///|
fn is_url_attribute(name : String) -> Bool {
  name == "href" ||
  name == "src" ||
  name == "action" ||
  name == "formaction" ||
  name == "xlink:href"
}

///|
fn is_boolean_attribute(name : String) -> Bool {
  name == "allowfullscreen" ||
  name == "async" ||
  name == "autofocus" ||
  name == "autoplay" ||
  name == "checked" ||
  name == "controls" ||
  name == "default" ||
  name == "defer" ||
  name == "disabled" ||
  name == "formnovalidate" ||
  name == "hidden" ||
  name == "inert" ||
  name == "ismap" ||
  name == "itemscope" ||
  name == "loop" ||
  name == "multiple" ||
  name == "muted" ||
  name == "nomodule" ||
  name == "novalidate" ||
  name == "open" ||
  name == "playsinline" ||
  name == "readonly" ||
  name == "required" ||
  name == "reversed" ||
  name == "selected"
}

///|
fn is_safe_tag(tag : String) -> Bool {
  let tags = [
    "a", "abbr", "address", "article", "aside", "b", "bdi", "bdo", "blockquote",
    "br", "button", "canvas", "caption", "cite", "code", "col", "colgroup", "data",
    "dd", "del", "details", "dfn", "div", "dl", "dt", "em", "fieldset", "figcaption",
    "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup",
    "hr", "i", "img", "input", "ins", "kbd", "label", "legend", "li", "main", "mark",
    "menu", "meter", "nav", "ol", "optgroup", "option", "output", "p", "picture",
    "pre", "progress", "q", "rp", "rt", "ruby", "s", "samp", "section", "select",
    "small", "span", "strong", "sub", "summary", "sup", "table", "tbody", "td", "textarea",
    "tfoot", "th", "thead", "time", "tr", "u", "ul", "var", "wbr",
  ]
  tags.contains(tag)
}

///|
fn is_void_tag(tag : String) -> Bool {
  tag == "area" ||
  tag == "base" ||
  tag == "br" ||
  tag == "col" ||
  tag == "embed" ||
  tag == "hr" ||
  tag == "img" ||
  tag == "input" ||
  tag == "link" ||
  tag == "meta" ||
  tag == "param" ||
  tag == "source" ||
  tag == "track" ||
  tag == "wbr"
}

///|
fn render_node(html : Html, output : StringBuilder) -> Result[Unit, HtmlError] {
  match html.node {
    HtmlNode::Text(value) => {
      escape_html(value, output)
      Ok(())
    }
    HtmlNode::Fragment(children) => {
      for child in children {
        match render_node(child, output) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      }
      Ok(())
    }
    HtmlNode::Element(tag, attributes, children) => {
      if !is_safe_tag(tag) {
        return Err(HtmlError::InvalidTag(tag))
      }
      match validate_attributes(attributes) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      if is_void_tag(tag) && children.length() > 0 {
        return Err(HtmlError::VoidElementHasChildren(tag))
      }
      output.write_char('<')
      output.write_view(tag[:])
      for attribute in attributes {
        output.write_char(' ')
        output.write_view(attribute.name[:])
        match attribute.value {
          None => output.write_view("=\"\""[:])
          Some(value) => {
            output.write_view("=\""[:])
            escape_html(value, output)
            output.write_char('"')
          }
        }
      }
      output.write_char('>')
      if !is_void_tag(tag) {
        for child in children {
          match render_node(child, output) {
            Err(error) => return Err(error)
            Ok(_) => ()
          }
        }
        output.write_view("</"[:])
        output.write_view(tag[:])
        output.write_char('>')
      }
      Ok(())
    }
  }
}

///|
fn escape_html(value : String, output : StringBuilder) -> Unit {
  for character in value {
    match character {
      '&' => output.write_view("&amp;"[:])
      '<' => output.write_view("&lt;"[:])
      '>' => output.write_view("&gt;"[:])
      '"' => output.write_view("&quot;"[:])
      '\'' => output.write_view("&#x27;"[:])
      _ => output.write_char(character)
    }
  }
}

///|
fn text_attribute(name : String, value : String) -> Attribute {
  Attribute::{ name, value: Some(value), }
}

///|
fn boolean_attribute(name : String) -> Attribute {
  Attribute::{ name, value: None, }
}

///|
fn raw_element(
  tag : String,
  attributes : Array[Attribute],
  children : Array[Html],
) -> Html {
  Html::{ node: HtmlNode::Element(tag, attributes, children), }
}
