/* Test-only AX observation client for the native TextField proof.
 *
 * Usage: macos_text_ax_client <pid> <expected-value>
 * Prints one JSON object with role/value/selection/focus/frame. Exit 77 when
 * AX observation is not authorized, 1 when the field is missing or mismatched.
 */
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/Foundation.h>
#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

enum { AX_UNSUPPORTED = 77, AX_MAX_DEPTH = 10 };

static void fail(const char *message) {
  fprintf(stderr, "FAIL: %s\n", message);
  exit(1);
}

static void set_timeout(AXUIElementRef element) {
  AXUIElementSetMessagingTimeout(element, 0.5f);
}

static AXUIElementRef copy_child(AXUIElementRef parent, CFStringRef attribute,
                                 CFIndex index) {
  CFTypeRef value = NULL;
  if (AXUIElementCopyAttributeValue(parent, attribute, &value) != kAXErrorSuccess ||
      value == NULL)
    return NULL;
  AXUIElementRef child = NULL;
  if (CFGetTypeID(value) == CFArrayGetTypeID()) {
    CFArrayRef array = (CFArrayRef)value;
    if (index >= 0 && index < CFArrayGetCount(array)) {
      CFTypeRef item = CFArrayGetValueAtIndex(array, index);
      if (item && CFGetTypeID(item) == AXUIElementGetTypeID()) {
        child = (AXUIElementRef)CFRetain(item);
      }
    }
  }
  CFRelease(value);
  return child;
}

static AXUIElementRef find_text_field(AXUIElementRef root, int depth) {
  if (depth > AX_MAX_DEPTH) return NULL;
  set_timeout(root);
  CFTypeRef role_value = NULL;
  if (AXUIElementCopyAttributeValue(root, kAXRoleAttribute, &role_value) ==
          kAXErrorSuccess &&
      role_value && CFGetTypeID(role_value) == CFStringGetTypeID()) {
    NSString *role = (__bridge NSString *)role_value;
    bool match = [role isEqualToString:@"AXTextField"] ||
                 [role isEqualToString:@"AXTextArea"];
    CFRelease(role_value);
    if (match) return (AXUIElementRef)CFRetain(root);
  } else if (role_value) {
    CFRelease(role_value);
  }
  CFIndex count = 0;
  CFTypeRef children_value = NULL;
  if (AXUIElementCopyAttributeValue(root, kAXChildrenAttribute, &children_value) ==
          kAXErrorSuccess &&
      children_value && CFGetTypeID(children_value) == CFArrayGetTypeID()) {
    count = CFArrayGetCount((CFArrayRef)children_value);
    for (CFIndex index = 0; index < count; index++) {
      AXUIElementRef child = copy_child(root, kAXChildrenAttribute, index);
      if (!child) continue;
      AXUIElementRef found = find_text_field(child, depth + 1);
      CFRelease(child);
      if (found) {
        CFRelease(children_value);
        return found;
      }
    }
    CFRelease(children_value);
  } else if (children_value) {
    CFRelease(children_value);
  }
  return NULL;
}

static bool copy_string(AXUIElementRef element, CFStringRef attribute,
                        char *out, size_t size) {
  CFTypeRef value = NULL;
  if (AXUIElementCopyAttributeValue(element, attribute, &value) !=
          kAXErrorSuccess ||
      !value || CFGetTypeID(value) != CFStringGetTypeID())
    return false;
  bool ok = CFStringGetCString((CFStringRef)value, out, size, kCFStringEncodingUTF8);
  CFRelease(value);
  return ok;
}

static bool copy_bool(AXUIElementRef element, CFStringRef attribute, bool *out) {
  CFTypeRef value = NULL;
  if (AXUIElementCopyAttributeValue(element, attribute, &value) !=
          kAXErrorSuccess ||
      !value || CFGetTypeID(value) != CFBooleanGetTypeID())
    return false;
  *out = CFBooleanGetValue((CFBooleanRef)value);
  CFRelease(value);
  return true;
}

static bool copy_point(AXUIElementRef element, CFStringRef attribute, CGPoint *out) {
  CFTypeRef value = NULL;
  if (AXUIElementCopyAttributeValue(element, attribute, &value) !=
          kAXErrorSuccess ||
      !value || CFGetTypeID(value) != AXValueGetTypeID())
    return false;
  bool ok = AXValueGetValue((AXValueRef)value, kAXValueCGPointType, out);
  CFRelease(value);
  return ok;
}

static bool copy_size(AXUIElementRef element, CFStringRef attribute, CGSize *out) {
  CFTypeRef value = NULL;
  if (AXUIElementCopyAttributeValue(element, attribute, &value) !=
          kAXErrorSuccess ||
      !value || CFGetTypeID(value) != AXValueGetTypeID())
    return false;
  bool ok = AXValueGetValue((AXValueRef)value, kAXValueCGSizeType, out);
  CFRelease(value);
  return ok;
}

static bool copy_range(AXUIElementRef element, CFRange *out) {
  CFTypeRef value = NULL;
  if (AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute,
                                    &value) != kAXErrorSuccess ||
      !value || CFGetTypeID(value) != AXValueGetTypeID())
    return false;
  bool ok = AXValueGetValue((AXValueRef)value, kAXValueCFRangeType, out);
  CFRelease(value);
  return ok;
}

static void json_string(const char *value) {
  putchar('"');
  for (const unsigned char *cursor = (const unsigned char *)value; *cursor;
       cursor++) {
    if (*cursor == '"' || *cursor == '\\') {
      putchar('\\');
      putchar(*cursor);
    } else if (*cursor < 0x20) {
      printf("\\u%04x", *cursor);
    } else {
      putchar(*cursor);
    }
  }
  putchar('"');
}

int main(int argc, char **argv) {
  @autoreleasepool {
    if (argc < 3) fail("usage: macos_text_ax_client <pid> <expected-value>");
    if (!AXIsProcessTrusted()) {
      printf("{\"status\":\"unsupported\",\"reason\":\"accessibility-not-trusted\"}\n");
      return AX_UNSUPPORTED;
    }
    pid_t pid = (pid_t)atoi(argv[1]);
    const char *expected = argv[2];
    AXUIElementRef app = AXUIElementCreateApplication(pid);
    AXUIElementRef field = find_text_field(app, 0);
    CFRelease(app);
    if (!field) {
      printf("{\"status\":\"not-found\"}\n");
      return 1;
    }
    char value[16384] = {0};
    bool has_value = copy_string(field, kAXValueAttribute, value, sizeof(value));
    bool focused = false;
    bool has_focus = copy_bool(field, kAXFocusedAttribute, &focused);
    CGPoint position = CGPointZero;
    CGSize size = CGSizeZero;
    bool has_position = copy_point(field, kAXPositionAttribute, &position);
    bool has_size = copy_size(field, kAXSizeAttribute, &size);
    CFRange selection = {0, 0};
    bool has_selection = copy_range(field, &selection);
    if (!has_selection) selection = (CFRange){0, 0};
    printf("{\"status\":\"observed\",\"value\":");
    json_string(has_value ? value : "");
    printf(",\"focused\":%s,\"position\":[%g,%g],\"size\":[%g,%g],"
           "\"selection\":[%ld,%ld]}\n",
           has_focus && focused ? "true" : "false", position.x, position.y,
           size.width, size.height, (long)selection.location,
           (long)selection.length);
    CFRelease(field);
    if (!has_value || strcmp(value, expected) != 0) {
      fprintf(stderr, "FAIL: AX value does not match the expected value\n");
      return 1;
    }
    if (!has_focus || !focused) {
      fprintf(stderr, "FAIL: AX field is not focused\n");
      return 1;
    }
    if (!has_position || !has_size || size.width <= 0 || size.height <= 0) {
      fprintf(stderr, "FAIL: AX frame is unavailable\n");
      return 1;
    }
  }
  return 0;
}
