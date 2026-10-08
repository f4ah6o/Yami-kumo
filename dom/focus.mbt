///|
#external
priv type BrowserElement

///|
#external
priv type BrowserEvent

///|
#external
priv type BrowserWeakSet

///|
extern "js" fn document_is_available() -> Bool =
  #| () => typeof document !== "undefined" && typeof document.addEventListener === "function"

///|
extern "js" fn global_flag(name : String) -> Bool =
  #| (name) => globalThis[name] === true

///|
extern "js" fn set_global_flag(name : String, value : Bool) -> Unit =
  #| (name, value) => { globalThis[name] = value; }

///|
extern "js" fn document_add_event_listener(
  name : String,
  callback : (BrowserEvent) -> Unit,
) -> Unit =
  #| (name, callback) => document.addEventListener(name, callback)

///|
extern "js" fn event_target(event : BrowserEvent) -> BrowserElement =
  #| (event) => event.target || null

///|
extern "js" fn event_key(event : BrowserEvent) -> String =
  #| (event) => event?.key || ""

///|
extern "js" fn is_input_element(element : BrowserElement) -> Bool =
  #| (element) => element?.tagName === "INPUT"

///|
extern "js" fn is_present(element : BrowserElement) -> Bool =
  #| (element) => element !== null && element !== undefined

///|
extern "js" fn closest(
  element : BrowserElement,
  selector : String,
) -> BrowserElement =
  #| (element, selector) => element?.closest?.(selector) || null

///|
extern "js" fn child_count(element : BrowserElement) -> Int =
  #| (element) => element?.children?.length || 0

///|
extern "js" fn child_at(
  element : BrowserElement,
  index : Int,
) -> BrowserElement =
  #| (element, index) => element?.children?.[index] || null

///|
extern "js" fn set_attribute(
  element : BrowserElement,
  name : String,
  value : String,
) -> Unit =
  #| (element, name, value) => element?.setAttribute(name, value)

///|
extern "js" fn remove_attribute(
  element : BrowserElement,
  name : String,
) -> Unit =
  #| (element, name) => element?.removeAttribute(name)

///|
extern "js" fn has_attribute(element : BrowserElement, name : String) -> Bool =
  #| (element, name) => element?.hasAttribute?.(name) === true

///|
extern "js" fn contains_active_element(element : BrowserElement) -> Bool =
  #| (element) => !!element?.contains?.(document.activeElement)

///|
extern "js" fn input_value(element : BrowserElement) -> String =
  #| (element) => element?.value ?? ""

///|
extern "js" fn input_default_value(element : BrowserElement) -> String =
  #| (element) => element?.defaultValue ?? ""

///|
extern "js" fn input_will_validate(element : BrowserElement) -> Bool =
  #| (element) => element?.willValidate === true

///|
extern "js" fn input_validity_is_valid(element : BrowserElement) -> Bool =
  #| (element) => element?.validity?.valid === true

///|
extern "js" fn input_value_is_missing(element : BrowserElement) -> Bool =
  #| (element) => element?.validity?.valueMissing === true

///|
extern "js" fn weak_set_new() -> BrowserWeakSet =
  #| () => new WeakSet()

///|
extern "js" fn weak_set_has(
  set : BrowserWeakSet,
  element : BrowserElement,
) -> Bool =
  #| (set, element) => set?.has?.(element) === true

///|
extern "js" fn weak_set_add(
  set : BrowserWeakSet,
  element : BrowserElement,
) -> Unit =
  #| (set, element) => set?.add?.(element)

///|
extern "js" fn queue_microtask(callback : () -> Unit) -> Unit =
  #| (callback) => typeof queueMicrotask === "function" ? queueMicrotask(callback) : Promise.resolve().then(callback)

///|
const INSTALLATION_FLAG = "__yamiKumoInputFocusBehaviorInstalled"

///|
/// Install MoonBit-owned Kumo Input state behavior for rendered fields.
/// Repeated calls are safe, including when multiple consumers share a page.
pub fn enhance() -> Unit {
  if document_is_available() && !global_flag(INSTALLATION_FLAG) {
    let marked_dirty_inputs = weak_set_new()
    let managed_aria_invalid_inputs = weak_set_new()
    document_add_event_listener("focusin", fn(event) {
      update_from_event(event, true)
    })
    document_add_event_listener("focusout", fn(event) {
      update_from_event(event, false)
    })
    document_add_event_listener("input", fn(event) {
      update_value_from_event(event, marked_dirty_inputs)
    })
    document_add_event_listener("change", fn(event) {
      update_value_from_event(event, marked_dirty_inputs)
    })
    document_add_event_listener("keydown", fn(event) {
      update_touched_from_key_event(
        event, marked_dirty_inputs, managed_aria_invalid_inputs,
      )
    })
    set_global_flag(INSTALLATION_FLAG, true)
  }
}

///|
fn update_from_event(event : BrowserEvent, focused : Bool) -> Unit {
  let target = event_target(event)
  if is_present(target) && is_input_element(target) {
    let field = closest(target, ".yk-kumo-input-field")
    if is_present(field) {
      if focused {
        set_field_focused(field, true)
      } else {
        set_field_attribute_state(field, "data-touched", true)
        // focusout fires before the browser has moved activeElement. Defer
        // the decision so moving between controls in one field stays focused.
        queue_microtask(fn() {
          set_field_focused(field, contains_active_element(field))
        })
      }
    }
  }
}

///|
fn update_value_from_event(
  event : BrowserEvent,
  marked_dirty_inputs : BrowserWeakSet,
) -> Unit {
  let target = event_target(event)
  if is_present(target) && is_input_element(target) {
    let field = closest(target, ".yk-kumo-input-field")
    if is_present(field) {
      let value = input_value(target)
      let initial_value = input_default_value(target)
      let dirty = value != initial_value
      if dirty {
        weak_set_add(marked_dirty_inputs, target)
      }
      set_field_attribute_state(field, "data-dirty", dirty)
      set_field_attribute_state(field, "data-filled", value != "")
    }
  }
}

///|
fn update_touched_from_key_event(
  event : BrowserEvent,
  marked_dirty_inputs : BrowserWeakSet,
  managed_aria_invalid_inputs : BrowserWeakSet,
) -> Unit {
  let target = event_target(event)
  if is_present(target) &&
    is_input_element(target) &&
    event_key(event) == "Enter" {
    let field = closest(target, ".yk-kumo-input-field")
    if is_present(field) {
      set_field_attribute_state(field, "data-touched", true)
      update_field_validity(
        field, target, marked_dirty_inputs, managed_aria_invalid_inputs,
      )
    }
  }
}

///|
fn update_field_validity(
  field : BrowserElement,
  input : BrowserElement,
  marked_dirty_inputs : BrowserWeakSet,
  managed_aria_invalid_inputs : BrowserWeakSet,
) -> Unit {
  let valid = if !input_will_validate(input) || input_validity_is_valid(input) {
    true
  } else {
    input_value_is_missing(input) && !weak_set_has(marked_dirty_inputs, input)
  }
  set_field_attribute_state(field, "data-valid", valid)
  set_field_attribute_state(field, "data-invalid", !valid)
  if valid {
    if weak_set_has(managed_aria_invalid_inputs, input) {
      remove_attribute(input, "aria-invalid")
    }
  } else {
    if !has_attribute(input, "aria-invalid") {
      weak_set_add(managed_aria_invalid_inputs, input)
    }
    set_attribute(input, "aria-invalid", "true")
  }
}

///|
fn set_field_focused(field : BrowserElement, focused : Bool) -> Unit {
  set_field_attribute_state(field, "data-focused", focused)
}

///|
fn set_field_attribute_state(
  field : BrowserElement,
  name : String,
  enabled : Bool,
) -> Unit {
  set_boolean_attribute_state(field, name, enabled)
  let count = child_count(field)
  for index in 0..<count {
    let child = child_at(field, index)
    if is_present(child) {
      set_boolean_attribute_state(child, name, enabled)
    }
  }
}

///|
fn set_boolean_attribute_state(
  element : BrowserElement,
  name : String,
  enabled : Bool,
) -> Unit {
  if enabled {
    set_attribute(element, name, "")
  } else {
    remove_attribute(element, name)
  }
}
