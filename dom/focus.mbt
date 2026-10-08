///|
#external
priv type BrowserElement

///|
#external
priv type BrowserEvent

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
extern "js" fn contains_active_element(element : BrowserElement) -> Bool =
  #| (element) => !!element?.contains?.(document.activeElement)

///|
extern "js" fn queue_microtask(callback : () -> Unit) -> Unit =
  #| (callback) => typeof queueMicrotask === "function" ? queueMicrotask(callback) : Promise.resolve().then(callback)

///|
const INSTALLATION_FLAG = "__yamiKumoInputFocusBehaviorInstalled"

///|
/// Install Kumo Field focus state behavior for rendered Yami Input fields.
/// Repeated calls are safe, including when multiple consumers share a page.
pub fn enhance() -> Unit {
  if document_is_available() && !global_flag(INSTALLATION_FLAG) {
    document_add_event_listener("focusin", fn(event) {
      update_from_event(event, true)
    })
    document_add_event_listener("focusout", fn(event) {
      update_from_event(event, false)
    })
    set_global_flag(INSTALLATION_FLAG, true)
  }
}

///|
fn update_from_event(event : BrowserEvent, focused : Bool) -> Unit {
  let target = event_target(event)
  if is_present(target) {
    let field = closest(target, ".yk-kumo-input-field")
    if is_present(field) {
      if focused {
        set_field_focused(field, true)
      } else {
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
fn set_field_focused(field : BrowserElement, focused : Bool) -> Unit {
  set_focused_attribute(field, focused)
  let count = child_count(field)
  for index in 0..<count {
    let child = child_at(field, index)
    if is_present(child) {
      set_focused_attribute(child, focused)
    }
  }
}

///|
fn set_focused_attribute(element : BrowserElement, focused : Bool) -> Unit {
  if focused {
    set_attribute(element, "data-focused", "")
  } else {
    remove_attribute(element, "data-focused")
  }
}
