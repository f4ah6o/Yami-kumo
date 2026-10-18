#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreGraphics/CGSession.h>

#include <errno.h>
#include <limits.h>
#include <math.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static void fail(const char *message, AXError error) {
  if (error == kAXErrorSuccess) {
    fprintf(stderr, "%s\n", message);
  } else {
    fprintf(stderr, "%s (AX error %d)\n", message, (int)error);
  }
  exit(1);
}

static double monotonic_seconds(void) {
  struct timespec value;
  if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) {
    perror("clock_gettime");
    exit(1);
  }
  return (double)value.tv_sec + (double)value.tv_nsec / 1000000000.0;
}

static double active_ax_deadline = 0.0;
static volatile sig_atomic_t input_cancel_requested = 0;

static void request_input_cancel(int signal_number) {
  (void)signal_number;
  input_cancel_requested = 1;
}

static bool set_ax_messaging_timeout(AXUIElementRef element) {
  if (element == NULL) return false;
  double remaining = active_ax_deadline > 0.0
                         ? active_ax_deadline - monotonic_seconds()
                         : 0.25;
  if (remaining <= 0.0) return false;
  if (remaining > 0.25) remaining = 0.25;
  return AXUIElementSetMessagingTimeout(element, (float)remaining) ==
         kAXErrorSuccess;
}

static bool query_deadline_available(double deadline) {
  return monotonic_seconds() < deadline;
}

static bool reset_unmodified_event_flags(CGEventRef event,
                                         uint64_t *out_inherited_flags,
                                         uint64_t *out_flags_before_post) {
  if (event == NULL) return false;
  uint64_t inherited = (uint64_t)CGEventGetFlags(event);
  CGEventSetFlags(event, (CGEventFlags)0);
  uint64_t before_post = (uint64_t)CGEventGetFlags(event);
  if (out_inherited_flags != NULL) *out_inherited_flags = inherited;
  if (out_flags_before_post != NULL) *out_flags_before_post = before_post;
  return before_post == 0;
}

static bool copy_string_attribute(AXUIElementRef element, CFStringRef name,
                                  char *buffer, size_t capacity,
                                  AXError *out_error) {
  if (!set_ax_messaging_timeout(element)) return false;
  CFTypeRef value = NULL;
  AXError error = AXUIElementCopyAttributeValue(element, name, &value);
  if (out_error != NULL) {
    *out_error = error;
  }
  if (error != kAXErrorSuccess || value == NULL ||
      CFGetTypeID(value) != CFStringGetTypeID()) {
    if (value != NULL) {
      CFRelease(value);
    }
    return false;
  }
  bool copied = CFStringGetCString((CFStringRef)value, buffer,
                                   (CFIndex)capacity, kCFStringEncodingUTF8);
  CFRelease(value);
  return copied;
}

typedef struct WindowSearchResult {
  AXUIElementRef window;
  CFIndex owned_windows;
  CFIndex exact_title_windows;
  bool ambiguous;
  bool title_matched;
} WindowSearchResult;

typedef struct WindowSearchDiagnostics {
  CFIndex entries;
  CFIndex accessibility_elements;
  CFIndex other_elements;
  CFIndex pid_readable;
  CFIndex matching_pid;
  CFIndex role_readable;
  CFIndex window_roles;
  CFIndex exact_titles;
  unsigned long last_type_id;
  pid_t last_pid;
  AXError attribute_error;
  AXError last_pid_error;
  AXError last_role_error;
  char last_role[128];
} WindowSearchDiagnostics;

static WindowSearchResult search_window_array(
    CFArrayRef windows, pid_t pid, const char *expected_title,
    char *last_title, size_t title_capacity,
    WindowSearchDiagnostics *diagnostics, double deadline) {
  WindowSearchResult result = {0};
  AXUIElementRef sole_owned_window = NULL;
  AXUIElementRef exact_title_window = NULL;
  diagnostics->entries = CFArrayGetCount(windows);
  for (CFIndex index = 0;
       index < CFArrayGetCount(windows) &&
       monotonic_seconds() < deadline;
       index++) {
    CFTypeRef raw_element = CFArrayGetValueAtIndex(windows, index);
    if (raw_element == NULL) {
      continue;
    }
    diagnostics->last_type_id = CFGetTypeID(raw_element);
    if (diagnostics->last_type_id != AXUIElementGetTypeID()) {
      diagnostics->other_elements += 1;
      continue;
    }
    diagnostics->accessibility_elements += 1;
    AXUIElementRef candidate = (AXUIElementRef)raw_element;
    if (!set_ax_messaging_timeout(candidate)) break;
    pid_t owner_pid = 0;
    AXError pid_error = AXUIElementGetPid(candidate, &owner_pid);
    diagnostics->last_pid_error = pid_error;
    diagnostics->last_pid = owner_pid;
    if (pid_error != kAXErrorSuccess) {
      continue;
    }
    diagnostics->pid_readable += 1;
    if (owner_pid != pid) continue;
    diagnostics->matching_pid += 1;
    CFTypeRef raw_role = NULL;
    AXError role_error = AXUIElementCopyAttributeValue(
        candidate, kAXRoleAttribute, &raw_role);
    diagnostics->last_role_error = role_error;
    bool role_string = role_error == kAXErrorSuccess && raw_role != NULL &&
                       CFGetTypeID(raw_role) == CFStringGetTypeID();
    if (role_string) {
      diagnostics->role_readable += 1;
      (void)CFStringGetCString((CFStringRef)raw_role,
                               diagnostics->last_role,
                               sizeof(diagnostics->last_role),
                               kCFStringEncodingUTF8);
    }
    bool is_window = role_string && CFEqual(raw_role, kAXWindowRole);
    if (is_window) diagnostics->window_roles += 1;
    if (raw_role != NULL) {
      CFRelease(raw_role);
    }
    if (!is_window) {
      continue;
    }

    result.owned_windows += 1;
    if (sole_owned_window == NULL) {
      sole_owned_window = (AXUIElementRef)CFRetain(candidate);
    }
    char title[512] = "";
    if (copy_string_attribute(candidate, kAXTitleAttribute, title,
                              sizeof(title), NULL)) {
      if (last_title != NULL && title_capacity > 0) {
        snprintf(last_title, title_capacity, "%s", title);
      }
      if (strcmp(title, expected_title) == 0) {
        result.exact_title_windows += 1;
        if (exact_title_window == NULL) {
          exact_title_window = (AXUIElementRef)CFRetain(candidate);
        }
      }
    }
  }

  if (result.exact_title_windows == 1) {
    result.window = exact_title_window;
    result.title_matched = true;
    if (sole_owned_window != NULL && sole_owned_window != result.window) {
      CFRelease(sole_owned_window);
    } else if (sole_owned_window == result.window) {
      CFRelease(sole_owned_window);
    }
  } else if (result.exact_title_windows > 1) {
    result.ambiguous = true;
    if (exact_title_window != NULL) {
      CFRelease(exact_title_window);
    }
    if (sole_owned_window != NULL) {
      CFRelease(sole_owned_window);
    }
  } else if (result.owned_windows == 1) {
    result.window = sole_owned_window;
    result.title_matched = false;
    if (exact_title_window != NULL) {
      CFRelease(exact_title_window);
    }
  } else {
    if (sole_owned_window != NULL) {
      CFRelease(sole_owned_window);
    }
    if (exact_title_window != NULL) {
      CFRelease(exact_title_window);
    }
    result.ambiguous = result.owned_windows > 1;
  }
  return result;
}

typedef struct WindowTreeSearch {
  WindowSearchResult result;
  AXUIElementRef sole_owned_window;
  AXUIElementRef exact_title_window;
  AXUIElementRef seen[256];
  CFIndex seen_count;
  pid_t pid;
  const char *expected_title;
  char *last_title;
  size_t title_capacity;
  WindowSearchDiagnostics *diagnostics;
  double deadline;
} WindowTreeSearch;

static bool window_tree_seen(WindowTreeSearch *search,
                             AXUIElementRef element) {
  for (CFIndex index = 0; index < search->seen_count; index++) {
    if (CFEqual(search->seen[index], element)) return true;
  }
  if (search->seen_count >= 256) return true;
  search->seen[search->seen_count++] = (AXUIElementRef)CFRetain(element);
  return false;
}

static void record_tree_window(WindowTreeSearch *search,
                               AXUIElementRef candidate) {
  search->result.owned_windows += 1;
  if (search->sole_owned_window == NULL) {
    search->sole_owned_window = (AXUIElementRef)CFRetain(candidate);
  }
  char title[512] = "";
  if (copy_string_attribute(candidate, kAXTitleAttribute, title,
                            sizeof(title), NULL)) {
    if (search->last_title != NULL && search->title_capacity > 0) {
      snprintf(search->last_title, search->title_capacity, "%s", title);
    }
    if (strcmp(title, search->expected_title) == 0) {
      search->result.exact_title_windows += 1;
      if (search->exact_title_window == NULL) {
        search->exact_title_window = (AXUIElementRef)CFRetain(candidate);
      }
    }
  }
}

static void walk_window_tree(WindowTreeSearch *search,
                             AXUIElementRef element, bool root,
                             unsigned depth) {
  if (element == NULL || depth > 12 || search->seen_count >= 256 ||
      search->diagnostics->accessibility_elements >= 256 ||
      monotonic_seconds() >= search->deadline ||
      window_tree_seen(search, element)) {
    return;
  }
  search->diagnostics->accessibility_elements += 1;
  if (!set_ax_messaging_timeout(element)) return;

  if (!root) {
    pid_t owner_pid = 0;
    AXError pid_error = AXUIElementGetPid(element, &owner_pid);
    search->diagnostics->last_pid_error = pid_error;
    search->diagnostics->last_pid = owner_pid;
    if (pid_error != kAXErrorSuccess) return;
    search->diagnostics->pid_readable += 1;
    if (owner_pid != search->pid) return;
    search->diagnostics->matching_pid += 1;
  }

  CFTypeRef raw_role = NULL;
  AXError role_error = AXUIElementCopyAttributeValue(
      element, kAXRoleAttribute, &raw_role);
  search->diagnostics->last_role_error = role_error;
  bool role_string = role_error == kAXErrorSuccess && raw_role != NULL &&
                     CFGetTypeID(raw_role) == CFStringGetTypeID();
  if (role_string) {
    search->diagnostics->role_readable += 1;
    (void)CFStringGetCString((CFStringRef)raw_role,
                             search->diagnostics->last_role,
                             sizeof(search->diagnostics->last_role),
                             kCFStringEncodingUTF8);
  }
  bool is_window = !root && role_string &&
                   CFEqual(raw_role, kAXWindowRole);
  if (raw_role != NULL) CFRelease(raw_role);
  if (is_window) {
    search->diagnostics->window_roles += 1;
    record_tree_window(search, element);
    return;
  }

  CFTypeRef raw_children = NULL;
  AXError children_error = AXUIElementCopyAttributeValue(
      element, kAXChildrenAttribute, &raw_children);
  if (children_error == kAXErrorSuccess && raw_children != NULL &&
      CFGetTypeID(raw_children) == CFArrayGetTypeID()) {
    CFArrayRef children = (CFArrayRef)raw_children;
    for (CFIndex index = 0;
         index < CFArrayGetCount(children) &&
         search->diagnostics->accessibility_elements < 256 &&
         monotonic_seconds() < search->deadline;
         index++) {
      CFTypeRef raw_child = CFArrayGetValueAtIndex(children, index);
      if (raw_child != NULL &&
          CFGetTypeID(raw_child) == AXUIElementGetTypeID()) {
        walk_window_tree(search, (AXUIElementRef)raw_child, false, depth + 1);
      }
    }
  }
  if (raw_children != NULL) CFRelease(raw_children);
}

static WindowSearchResult search_window_tree(
    AXUIElementRef root, pid_t pid, const char *expected_title,
    char *last_title, size_t title_capacity,
    WindowSearchDiagnostics *diagnostics, double deadline) {
  *diagnostics = (WindowSearchDiagnostics){0};
  WindowTreeSearch search = {
      .pid = pid,
      .expected_title = expected_title,
      .last_title = last_title,
      .title_capacity = title_capacity,
      .diagnostics = diagnostics,
      .deadline = deadline,
  };
  walk_window_tree(&search, root, true, 0);
  if (search.result.exact_title_windows == 1) {
    search.result.window = search.exact_title_window;
    search.result.title_matched = true;
    if (search.sole_owned_window != NULL) {
      CFRelease(search.sole_owned_window);
    }
  } else if (search.result.exact_title_windows > 1) {
    search.result.ambiguous = true;
    if (search.exact_title_window != NULL) {
      CFRelease(search.exact_title_window);
    }
    if (search.sole_owned_window != NULL) {
      CFRelease(search.sole_owned_window);
    }
  } else if (search.result.owned_windows == 1) {
    search.result.window = search.sole_owned_window;
  } else {
    search.result.ambiguous = search.result.owned_windows > 1;
    if (search.sole_owned_window != NULL) {
      CFRelease(search.sole_owned_window);
    }
  }
  for (CFIndex index = 0; index < search.seen_count; index++) {
    CFRelease(search.seen[index]);
  }
  return search.result;
}

static WindowSearchResult search_window_attribute(
    AXUIElementRef app, CFStringRef attribute, pid_t pid,
    const char *expected_title, char *last_title, size_t title_capacity,
    WindowSearchDiagnostics *diagnostics) {
  *diagnostics = (WindowSearchDiagnostics){0};
  if (!set_ax_messaging_timeout(app)) return (WindowSearchResult){0};
  CFTypeRef raw_window = NULL;
  AXError error = AXUIElementCopyAttributeValue(app, attribute, &raw_window);
  diagnostics->attribute_error = error;
  diagnostics->last_role_error = error;
  if (error != kAXErrorSuccess || raw_window == NULL) {
    if (raw_window != NULL) CFRelease(raw_window);
    return (WindowSearchResult){0};
  }
  diagnostics->entries = 1;
  diagnostics->last_type_id = CFGetTypeID(raw_window);
  if (diagnostics->last_type_id != AXUIElementGetTypeID()) {
    diagnostics->other_elements = 1;
    CFRelease(raw_window);
    return (WindowSearchResult){0};
  }
  diagnostics->accessibility_elements = 1;
  AXUIElementRef candidate = (AXUIElementRef)raw_window;
  if (!set_ax_messaging_timeout(candidate)) {
    CFRelease(raw_window);
    return (WindowSearchResult){0};
  }
  pid_t owner_pid = 0;
  AXError pid_error = AXUIElementGetPid(candidate, &owner_pid);
  diagnostics->last_pid_error = pid_error;
  diagnostics->last_pid = owner_pid;
  if (pid_error != kAXErrorSuccess) {
    CFRelease(raw_window);
    return (WindowSearchResult){0};
  }
  diagnostics->pid_readable = 1;
  if (owner_pid != pid) {
    CFRelease(raw_window);
    return (WindowSearchResult){0};
  }
  diagnostics->matching_pid = 1;
  CFTypeRef raw_role = NULL;
  AXError role_error = AXUIElementCopyAttributeValue(
      candidate, kAXRoleAttribute, &raw_role);
  diagnostics->last_role_error = role_error;
  bool role_string = role_error == kAXErrorSuccess && raw_role != NULL &&
                     CFGetTypeID(raw_role) == CFStringGetTypeID();
  if (role_string) {
    diagnostics->role_readable = 1;
    (void)CFStringGetCString((CFStringRef)raw_role,
                             diagnostics->last_role,
                             sizeof(diagnostics->last_role),
                             kCFStringEncodingUTF8);
  }
  bool is_window = role_string && CFEqual(raw_role, kAXWindowRole);
  if (raw_role != NULL) CFRelease(raw_role);
  if (!is_window) {
    CFRelease(raw_window);
    return (WindowSearchResult){0};
  }
  diagnostics->window_roles = 1;
  WindowSearchResult result = {
      .window = (AXUIElementRef)CFRetain(candidate),
      .owned_windows = 1,
  };
  char title[512] = "";
  if (copy_string_attribute(candidate, kAXTitleAttribute, title,
                            sizeof(title), NULL)) {
    if (last_title != NULL && title_capacity > 0) {
      snprintf(last_title, title_capacity, "%s", title);
    }
    if (strcmp(title, expected_title) == 0) {
      result.exact_title_windows = 1;
      result.title_matched = true;
      diagnostics->exact_titles = 1;
    }
  }
  CFRelease(raw_window);
  return result;
}

static AXUIElementRef find_window(
    AXUIElementRef app, pid_t pid, const char *expected_title,
    AXError *out_app_error, CFIndex *out_app_count,
    CFIndex *out_app_owned, CFIndex *out_app_exact,
    AXError *out_system_error, CFIndex *out_system_count,
    CFIndex *out_system_owned, CFIndex *out_system_exact,
    char *last_title, size_t title_capacity, bool *out_title_matched,
    WindowSearchDiagnostics *app_diagnostics,
    WindowSearchDiagnostics *system_diagnostics,
    WindowSearchDiagnostics *app_tree_diagnostics,
    WindowSearchDiagnostics *system_tree_diagnostics,
    WindowSearchDiagnostics *focused_diagnostics,
    WindowSearchDiagnostics *main_diagnostics,
    double deadline) {
  *app_diagnostics = (WindowSearchDiagnostics){0};
  *system_diagnostics = (WindowSearchDiagnostics){0};
  *app_tree_diagnostics = (WindowSearchDiagnostics){0};
  *system_tree_diagnostics = (WindowSearchDiagnostics){0};
  *focused_diagnostics = (WindowSearchDiagnostics){0};
  *main_diagnostics = (WindowSearchDiagnostics){0};
  if (out_app_count != NULL) *out_app_count = 0;
  if (out_app_owned != NULL) *out_app_owned = 0;
  if (out_app_exact != NULL) *out_app_exact = 0;
  if (out_system_error != NULL) *out_system_error = kAXErrorNoValue;
  if (out_title_matched != NULL) *out_title_matched = false;
  if (last_title != NULL && title_capacity > 0) {
    last_title[0] = '\0';
  }
  if (!set_ax_messaging_timeout(app)) return NULL;
  WindowSearchResult app_result = {0};
  CFTypeRef raw_windows = NULL;
  AXError error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute,
                                                &raw_windows);
  if (out_app_error != NULL) {
    *out_app_error = error;
  }
  if (error == kAXErrorSuccess && raw_windows != NULL &&
      CFGetTypeID(raw_windows) == CFArrayGetTypeID()) {
    CFArrayRef windows = (CFArrayRef)raw_windows;
    if (out_app_count != NULL) {
      *out_app_count = CFArrayGetCount(windows);
    }
    app_result = search_window_array(
        windows, pid, expected_title, last_title, title_capacity,
        app_diagnostics, deadline);
    if (out_app_owned != NULL) {
      *out_app_owned = app_result.owned_windows;
    }
    if (out_app_exact != NULL) {
      *out_app_exact = app_result.exact_title_windows;
    }
    CFRelease(raw_windows);
    if (app_result.title_matched) {
      if (out_title_matched != NULL) {
        *out_title_matched = true;
      }
      return app_result.window;
    }
  } else if (raw_windows != NULL) {
    CFRelease(raw_windows);
  }

  WindowSearchResult app_tree_result = search_window_tree(
      app, pid, expected_title, last_title, title_capacity,
      app_tree_diagnostics, deadline);
  if (app_tree_result.title_matched) {
    if (out_app_owned != NULL) {
      *out_app_owned = app_tree_result.owned_windows;
    }
    if (out_app_exact != NULL) {
      *out_app_exact = app_tree_result.exact_title_windows;
    }
    if (out_title_matched != NULL) {
      *out_title_matched = true;
    }
    if (app_result.window != NULL) {
      CFRelease(app_result.window);
    }
    return app_tree_result.window;
  }
  if (app_result.exact_title_windows > 1 ||
      app_tree_result.exact_title_windows > 1) {
    if (app_result.window != NULL) CFRelease(app_result.window);
    if (app_tree_result.window != NULL) CFRelease(app_tree_result.window);
    return NULL;
  }
  WindowSearchResult focused_result = search_window_attribute(
      app, kAXFocusedWindowAttribute, pid, expected_title, last_title,
      title_capacity, focused_diagnostics);
  WindowSearchResult main_result = search_window_attribute(
      app, kAXMainWindowAttribute, pid, expected_title, last_title,
      title_capacity, main_diagnostics);
  bool attributes_are_different =
      focused_result.window != NULL && main_result.window != NULL &&
      !CFEqual(focused_result.window, main_result.window);
  if (attributes_are_different && focused_result.title_matched &&
      main_result.title_matched) {
    CFRelease(focused_result.window);
    CFRelease(main_result.window);
    if (app_result.window != NULL) CFRelease(app_result.window);
    if (app_tree_result.window != NULL) CFRelease(app_tree_result.window);
    return NULL;
  }
  WindowSearchResult attribute_result = {0};
  int attribute_choice = 0;
  if (focused_result.title_matched) {
    attribute_result = focused_result;
    attribute_choice = 1;
  } else if (main_result.title_matched) {
    attribute_result = main_result;
    attribute_choice = 2;
  } else if (!app_result.ambiguous && !app_tree_result.ambiguous &&
             !attributes_are_different && focused_result.window != NULL) {
    attribute_result = focused_result;
    attribute_choice = 1;
  } else if (!app_result.ambiguous && !app_tree_result.ambiguous &&
             focused_result.window == NULL && main_result.window != NULL) {
    attribute_result = main_result;
    attribute_choice = 2;
  }
  if (attribute_result.window != NULL) {
    if (attribute_choice != 1 && focused_result.window != NULL) {
      CFRelease(focused_result.window);
    }
    if (attribute_choice != 2 && main_result.window != NULL) {
      CFRelease(main_result.window);
    }
    if (out_app_owned != NULL) *out_app_owned = 1;
    if (out_app_exact != NULL) {
      *out_app_exact = attribute_result.exact_title_windows;
    }
    if (out_title_matched != NULL) {
      *out_title_matched = attribute_result.title_matched;
    }
    if (app_result.window != NULL) CFRelease(app_result.window);
    if (app_tree_result.window != NULL) CFRelease(app_tree_result.window);
    return attribute_result.window;
  }
  if (focused_result.window != NULL) CFRelease(focused_result.window);
  if (main_result.window != NULL) CFRelease(main_result.window);
  if (!app_result.ambiguous && app_result.window != NULL) {
    if (out_title_matched != NULL) {
      *out_title_matched = false;
    }
    if (app_tree_result.window != NULL) {
      CFRelease(app_tree_result.window);
    }
    return app_result.window;
  }
  if (!app_result.ambiguous && app_tree_result.window != NULL) {
    if (out_app_owned != NULL) {
      *out_app_owned = app_tree_result.owned_windows;
    }
    if (out_app_exact != NULL) {
      *out_app_exact = app_tree_result.exact_title_windows;
    }
    if (out_title_matched != NULL) {
      *out_title_matched = false;
    }
    return app_tree_result.window;
  }
  if (app_result.ambiguous && app_result.exact_title_windows > 1) {
    return NULL;
  }

  if (out_system_count != NULL) {
    *out_system_count = 0;
  }
  if (out_system_owned != NULL) {
    *out_system_owned = 0;
  }
  if (out_system_exact != NULL) {
    *out_system_exact = 0;
  }
  AXUIElementRef system = AXUIElementCreateSystemWide();
  if (system == NULL) {
    if (out_system_error != NULL) {
      *out_system_error = kAXErrorFailure;
    }
    if (app_result.window != NULL) {
      CFRelease(app_result.window);
    }
    if (app_tree_result.window != NULL) {
      CFRelease(app_tree_result.window);
    }
    return NULL;
  }
  if (!set_ax_messaging_timeout(system)) {
    CFRelease(system);
    if (app_result.window != NULL) CFRelease(app_result.window);
    if (app_tree_result.window != NULL) CFRelease(app_tree_result.window);
    return NULL;
  }
  raw_windows = NULL;
  error = AXUIElementCopyAttributeValue(system, kAXWindowsAttribute,
                                        &raw_windows);
  if (out_system_error != NULL) {
    *out_system_error = error;
  }
  WindowSearchResult system_result = {0};
  if (error == kAXErrorSuccess && raw_windows != NULL &&
      CFGetTypeID(raw_windows) == CFArrayGetTypeID()) {
    CFArrayRef windows = (CFArrayRef)raw_windows;
    if (out_system_count != NULL) {
      *out_system_count = CFArrayGetCount(windows);
    }
    system_result = search_window_array(
        windows, pid, expected_title, last_title, title_capacity,
        system_diagnostics, deadline);
    if (out_system_owned != NULL) {
      *out_system_owned = system_result.owned_windows;
    }
    if (out_system_exact != NULL) {
      *out_system_exact = system_result.exact_title_windows;
    }
    if (system_result.title_matched) {
      if (out_title_matched != NULL) {
        *out_title_matched = true;
      }
      if (app_result.window != NULL) {
        CFRelease(app_result.window);
      }
      if (app_tree_result.window != NULL) {
        CFRelease(app_tree_result.window);
      }
      if (system != NULL) {
        CFRelease(system);
      }
      if (raw_windows != NULL) {
        CFRelease(raw_windows);
      }
      return system_result.window;
    }
  }
  if (raw_windows != NULL) {
    CFRelease(raw_windows);
  }
  WindowSearchResult system_tree_result = search_window_tree(
      system, pid, expected_title, last_title, title_capacity,
      system_tree_diagnostics, deadline);
  CFRelease(system);
  if (system_tree_result.title_matched) {
    if (out_system_owned != NULL) {
      *out_system_owned = system_tree_result.owned_windows;
    }
    if (out_system_exact != NULL) {
      *out_system_exact = system_tree_result.exact_title_windows;
    }
    if (out_title_matched != NULL) {
      *out_title_matched = true;
    }
    if (system_result.window != NULL) {
      CFRelease(system_result.window);
    }
    if (app_result.window != NULL) {
      CFRelease(app_result.window);
    }
    if (app_tree_result.window != NULL) {
      CFRelease(app_tree_result.window);
    }
    return system_tree_result.window;
  }
  if (!system_result.ambiguous && system_result.window != NULL) {
    if (out_title_matched != NULL) {
      *out_title_matched = false;
    }
    if (system_tree_result.window != NULL) {
      CFRelease(system_tree_result.window);
    }
    if (app_result.window != NULL) {
      CFRelease(app_result.window);
    }
    if (app_tree_result.window != NULL) {
      CFRelease(app_tree_result.window);
    }
    return system_result.window;
  }
  if (!system_result.ambiguous && system_tree_result.window != NULL) {
    if (out_system_owned != NULL) {
      *out_system_owned = system_tree_result.owned_windows;
    }
    if (out_system_exact != NULL) {
      *out_system_exact = system_tree_result.exact_title_windows;
    }
    if (out_title_matched != NULL) {
      *out_title_matched = false;
    }
    if (app_result.window != NULL) {
      CFRelease(app_result.window);
    }
    if (app_tree_result.window != NULL) {
      CFRelease(app_tree_result.window);
    }
    return system_tree_result.window;
  }
  if (system_result.window != NULL) {
    CFRelease(system_result.window);
  }
  if (system_tree_result.window != NULL) {
    CFRelease(system_tree_result.window);
  }
  if (app_result.window != NULL) {
    CFRelease(app_result.window);
  }
  if (app_tree_result.window != NULL) {
    CFRelease(app_tree_result.window);
  }
  return NULL;
}

static bool application_identity_matches(pid_t pid,
                                         const char *expected_bundle_id,
                                         const char *expected_bundle_path) {
  NSRunningApplication *running =
      [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
  if (running == nil || running.bundleIdentifier == nil ||
      running.bundleURL == nil) {
    return false;
  }
  NSString *expected_id =
      [NSString stringWithUTF8String:expected_bundle_id];
  NSURL *expected_url = [[NSURL fileURLWithPath:
      [NSString stringWithUTF8String:expected_bundle_path] isDirectory:YES]
      URLByResolvingSymlinksInPath];
  NSURL *actual_url = [[running.bundleURL URLByResolvingSymlinksInPath]
      URLByStandardizingPath];
  NSURL *normalized_expected = [expected_url URLByStandardizingPath];
  return expected_id != nil &&
         [running.bundleIdentifier isEqualToString:expected_id] &&
         normalized_expected != nil && actual_url != nil &&
         [actual_url.path isEqualToString:normalized_expected.path];
}

static AXUIElementRef find_button(AXUIElementRef parent,
                                  const char *expected_name, unsigned depth,
                                  unsigned *visited, double deadline) {
  if (depth > 12 || *visited >= 256 || monotonic_seconds() >= deadline) {
    return NULL;
  }
  *visited += 1;
  if (!set_ax_messaging_timeout(parent)) return NULL;
  CFTypeRef raw_role = NULL;
  AXError role_error = AXUIElementCopyAttributeValue(
      parent, kAXRoleAttribute, &raw_role);
  if (!query_deadline_available(deadline)) {
    if (raw_role != NULL) CFRelease(raw_role);
    return NULL;
  }
  if (role_error == kAXErrorSuccess && raw_role != NULL &&
      CFGetTypeID(raw_role) == CFStringGetTypeID() &&
      CFEqual(raw_role, kAXButtonRole)) {
    char name[512];
    if (copy_string_attribute(parent, kAXTitleAttribute, name, sizeof(name),
                              NULL) &&
        strcmp(name, expected_name) == 0) {
      CFRelease(raw_role);
      return (AXUIElementRef)CFRetain(parent);
    }
  }
  if (raw_role != NULL) {
    CFRelease(raw_role);
  }
  CFTypeRef raw_children = NULL;
  if (AXUIElementCopyAttributeValue(parent, kAXChildrenAttribute,
                                    &raw_children) != kAXErrorSuccess ||
      raw_children == NULL ||
      CFGetTypeID(raw_children) != CFArrayGetTypeID()) {
    if (raw_children != NULL) {
      CFRelease(raw_children);
    }
    return NULL;
  }
  if (!query_deadline_available(deadline)) {
    CFRelease(raw_children);
    return NULL;
  }
  CFArrayRef children = (CFArrayRef)raw_children;
  AXUIElementRef result = NULL;
  for (CFIndex index = 0; index < CFArrayGetCount(children) &&
                           query_deadline_available(deadline); index++) {
    CFTypeRef raw_child = CFArrayGetValueAtIndex(children, index);
    if (raw_child == NULL ||
        CFGetTypeID(raw_child) != AXUIElementGetTypeID()) {
      continue;
    }
    AXUIElementRef child = (AXUIElementRef)raw_child;
    result = find_button(child, expected_name, depth + 1, visited, deadline);
    if (result != NULL) {
      break;
    }
  }
  CFRelease(raw_children);
  return result;
}

static bool button_enabled(AXUIElementRef button, AXError *out_error) {
  if (!set_ax_messaging_timeout(button)) return false;
  CFTypeRef value = NULL;
  AXError error = AXUIElementCopyAttributeValue(
      button, kAXEnabledAttribute, &value);
  if (out_error != NULL) {
    *out_error = error;
  }
  bool enabled = error == kAXErrorSuccess && value != NULL &&
                 CFGetTypeID(value) == CFBooleanGetTypeID() &&
                 CFBooleanGetValue((CFBooleanRef)value);
  if (value != NULL) {
    CFRelease(value);
  }
  return enabled;
}

static bool button_help_count(AXUIElementRef button, int *out_count) {
  char help[512];
  if (!copy_string_attribute(button, kAXHelpAttribute, help, sizeof(help),
                             NULL)) {
    return false;
  }
  int count = -1;
  if (sscanf(help, "Activations: %d", &count) != 1 || count < 0) {
    return false;
  }
  *out_count = count;
  return true;
}

static bool has_press_action(AXUIElementRef button, AXError *out_error) {
  if (!set_ax_messaging_timeout(button)) return false;
  CFArrayRef actions = NULL;
  AXError error = AXUIElementCopyActionNames(button, &actions);
  if (out_error != NULL) {
    *out_error = error;
  }
  if (error != kAXErrorSuccess || actions == NULL) {
    if (actions != NULL) {
      CFRelease(actions);
    }
    return false;
  }
  bool found = false;
  for (CFIndex index = 0; index < CFArrayGetCount(actions); index++) {
    CFTypeRef action = CFArrayGetValueAtIndex(actions, index);
    if (CFGetTypeID(action) == CFStringGetTypeID() &&
        CFEqual(action, kAXPressAction)) {
      found = true;
      break;
    }
  }
  CFRelease(actions);
  return found;
}

static void post_escape(pid_t pid, bool key_down) {
  CGEventRef event = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)53, key_down);
  if (event == NULL) {
    fail("could not create Escape event", kAXErrorFailure);
  }
  uint64_t inherited_flags = 0, flags_before_post = UINT64_MAX;
  if (!reset_unmodified_event_flags(event, &inherited_flags,
                                   &flags_before_post)) {
    CFRelease(event);
    fprintf(stderr,
            "refusing PID-targeted Escape with nonzero pre-post flags (inherited=%llu, beforePost=%llu)\n",
            (unsigned long long)inherited_flags,
            (unsigned long long)flags_before_post);
    exit(1);
  }
  CGEventPostToPid(pid, event);
  CFRelease(event);
}

static void close_window(pid_t pid, AXUIElementRef window) {
  CFTypeRef raw_close_button = NULL;
  AXError error = AXUIElementCopyAttributeValue(
      window, kAXCloseButtonAttribute, &raw_close_button);
  if (error == kAXErrorSuccess && raw_close_button != NULL &&
      AXUIElementGetTypeID() == CFGetTypeID(raw_close_button)) {
    error = AXUIElementPerformAction((AXUIElementRef)raw_close_button,
                                     kAXPressAction);
    CFRelease(raw_close_button);
    if (error == kAXErrorSuccess) {
      return;
    }
  } else if (raw_close_button != NULL) {
    CFRelease(raw_close_button);
  }
  post_escape(pid, true);
  post_escape(pid, false);
}

static void print_json_string(const char *value) {
  putchar('"');
  for (const unsigned char *cursor = (const unsigned char *)value; *cursor;
       cursor++) {
    switch (*cursor) {
    case '"':
      fputs("\\\"", stdout);
      break;
    case '\\':
      fputs("\\\\", stdout);
      break;
    case '\b':
      fputs("\\b", stdout);
      break;
    case '\f':
      fputs("\\f", stdout);
      break;
    case '\n':
      fputs("\\n", stdout);
      break;
    case '\r':
      fputs("\\r", stdout);
      break;
    case '\t':
      fputs("\\t", stdout);
      break;
    default:
      if (*cursor < 0x20) {
        printf("\\u%04x", (unsigned int)*cursor);
      } else {
        putchar(*cursor);
      }
    }
  }
  putchar('"');
}

static bool copy_dictionary_boolean(CFDictionaryRef dictionary,
                                    CFStringRef key, bool *out_value) {
  if (dictionary == NULL) return false;
  CFTypeRef value = CFDictionaryGetValue(dictionary, key);
  if (value == NULL) return false;
  if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
    *out_value = CFBooleanGetValue((CFBooleanRef)value);
    return true;
  }
  if (CFGetTypeID(value) == CFNumberGetTypeID()) {
    int number = 0;
    if (CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, &number)) {
      *out_value = number != 0;
      return true;
    }
  }
  return false;
}

static int input_preflight(bool emit_report, double deadline) {
  bool on_console = false;
  bool session_locked = true;
  bool on_console_known = false;
  bool locked_known = false;
  CFDictionaryRef session = query_deadline_available(deadline)
                                ? CGSessionCopyCurrentDictionary()
                                : NULL;
  if (session != NULL) {
    on_console_known = copy_dictionary_boolean(
        session, CFSTR("kCGSSessionOnConsoleKey"), &on_console);
    bool lock_marker_present =
        CFDictionaryContainsKey(session, CFSTR("CGSSessionScreenIsLocked"));
    locked_known = copy_dictionary_boolean(
        session, CFSTR("CGSSessionScreenIsLocked"), &session_locked);
    if (!lock_marker_present && on_console_known && on_console) {
      // This host omits the private lock marker in an unlocked console session.
      session_locked = false;
      locked_known = true;
    }
  }
  bool accessibility = query_deadline_available(deadline) && AXIsProcessTrusted();
  if (!query_deadline_available(deadline)) {
    on_console_known = false;
    locked_known = false;
  }
  if (emit_report) {
    printf("{\"accessibility\":%s,\"on_console\":",
           accessibility ? "true" : "false");
    if (on_console_known) printf("%s", on_console ? "true" : "false");
    else printf("null");
    fputs(",\"session_locked\":", stdout);
    if (locked_known) printf("%s", session_locked ? "true" : "false");
    else printf("null");
    fputs("}\n", stdout);
  }
  if (session != NULL) CFRelease(session);
  if (!accessibility) return 77;
  if (!on_console_known || !on_console || !locked_known || session_locked) {
    return 78;
  }
  return 0;
}

static bool read_cf_number(CFDictionaryRef dictionary, CFStringRef key,
                           double *out_value) {
  if (dictionary == NULL) return false;
  CFTypeRef value = CFDictionaryGetValue(dictionary, key);
  if (value == NULL || CFGetTypeID(value) != CFNumberGetTypeID()) return false;
  return CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, out_value) &&
         isfinite(*out_value);
}

static bool copy_visible_target_window(pid_t pid, const char *title,
                                       CGWindowID *out_window_id,
                                       CGRect *out_bounds, double deadline) {
  if (!query_deadline_available(deadline)) return false;
  CFArrayRef windows = CGWindowListCopyWindowInfo(
      kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
      kCGNullWindowID);
  if (windows == NULL || !query_deadline_available(deadline)) {
    if (windows != NULL) CFRelease(windows);
    return false;
  }
  CFIndex matches = 0;
  for (CFIndex index = 0; index < CFArrayGetCount(windows) &&
                           query_deadline_available(deadline); index++) {
    CFTypeRef raw = CFArrayGetValueAtIndex(windows, index);
    if (raw == NULL || CFGetTypeID(raw) != CFDictionaryGetTypeID()) continue;
    CFDictionaryRef record = (CFDictionaryRef)raw;
    double owner = 0, layer = -1, alpha = 0, number = 0;
    bool on_screen = false;
    CFTypeRef name = CFDictionaryGetValue(record, kCGWindowName);
    if (!read_cf_number(record, kCGWindowOwnerPID, &owner) || owner != pid ||
        !read_cf_number(record, kCGWindowLayer, &layer) || layer != 0 ||
        !read_cf_number(record, kCGWindowAlpha, &alpha) || alpha <= 0 ||
        !read_cf_number(record, kCGWindowNumber, &number) || number <= 0 ||
        !copy_dictionary_boolean(record, kCGWindowIsOnscreen, &on_screen) ||
        !on_screen || name == NULL || CFGetTypeID(name) != CFStringGetTypeID()) {
      continue;
    }
    char observed[512] = "";
    if (!CFStringGetCString((CFStringRef)name, observed, sizeof(observed),
                            kCFStringEncodingUTF8) || strcmp(observed, title) != 0) {
      continue;
    }
    CFTypeRef raw_bounds = CFDictionaryGetValue(record, kCGWindowBounds);
    if (raw_bounds == NULL || CFGetTypeID(raw_bounds) != CFDictionaryGetTypeID()) {
      continue;
    }
    double x = 0, y = 0, width = 0, height = 0;
    CFDictionaryRef bounds = (CFDictionaryRef)raw_bounds;
    if (!read_cf_number(bounds, CFSTR("X"), &x) ||
        !read_cf_number(bounds, CFSTR("Y"), &y) ||
        !read_cf_number(bounds, CFSTR("Width"), &width) ||
        !read_cf_number(bounds, CFSTR("Height"), &height) ||
        width <= 0 || height <= 0 || number > UINT32_MAX) {
      continue;
    }
    matches += 1;
    *out_window_id = (CGWindowID)number;
    *out_bounds = CGRectMake(x, y, width, height);
  }
  CFRelease(windows);
  return matches == 1 && query_deadline_available(deadline);
}

static bool target_is_frontmost(pid_t pid, double deadline) {
  if (!query_deadline_available(deadline)) return false;
  NSRunningApplication *frontmost = [[NSWorkspace sharedWorkspace] frontmostApplication];
  return query_deadline_available(deadline) && frontmost != nil &&
         frontmost.processIdentifier == pid;
}

static bool copy_focused_target_window(pid_t pid, const char *title,
                                       double deadline,
                                       AXUIElementRef *out_app,
                                       AXUIElementRef *out_window) {
  if (!query_deadline_available(deadline)) return false;
  AXUIElementRef app = AXUIElementCreateApplication(pid);
  if (app == NULL) return false;
  if (!set_ax_messaging_timeout(app)) {
    CFRelease(app);
    return false;
  }
  AXError app_error = kAXErrorNoValue;
  AXError system_error = kAXErrorNoValue;
  CFIndex app_count = 0, app_owned = 0, app_exact = 0;
  CFIndex system_count = 0, system_owned = 0, system_exact = 0;
  WindowSearchDiagnostics app_diagnostics = {0};
  WindowSearchDiagnostics system_diagnostics = {0};
  WindowSearchDiagnostics app_tree_diagnostics = {0};
  WindowSearchDiagnostics system_tree_diagnostics = {0};
  WindowSearchDiagnostics focused_diagnostics = {0};
  WindowSearchDiagnostics main_diagnostics = {0};
  bool title_matched = false;
  char last_title[512] = "";
  AXUIElementRef exact = find_window(
      app, pid, title, &app_error, &app_count, &app_owned, &app_exact,
      &system_error, &system_count, &system_owned, &system_exact,
      last_title, sizeof(last_title), &title_matched,
      &app_diagnostics, &system_diagnostics, &app_tree_diagnostics,
      &system_tree_diagnostics, &focused_diagnostics, &main_diagnostics,
      deadline);
  if (exact == NULL || !title_matched || !set_ax_messaging_timeout(app)) {
    if (exact != NULL) CFRelease(exact);
    CFRelease(app);
    return false;
  }
  CFTypeRef raw_focused = NULL;
  AXError error = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute,
                                                &raw_focused);
  bool focused_matches = error == kAXErrorSuccess && raw_focused != NULL &&
                         CFGetTypeID(raw_focused) == AXUIElementGetTypeID() &&
                         CFEqual((AXUIElementRef)raw_focused, exact);
  if (raw_focused != NULL) CFRelease(raw_focused);
  if (!focused_matches || !query_deadline_available(deadline)) {
    CFRelease(exact);
    CFRelease(app);
    return false;
  }
  *out_app = app;
  *out_window = exact;
  return true;
}

static bool ax_hit_is_inside(AXUIElementRef hit, pid_t pid, double deadline,
                             AXUIElementRef button) {
  AXUIElementRef current = (AXUIElementRef)CFRetain(hit);
  bool inside = false;
  for (unsigned depth = 0; depth < 16 && current != NULL &&
                           query_deadline_available(deadline); depth++) {
    if (!set_ax_messaging_timeout(current)) break;
    pid_t owner = 0;
    if (AXUIElementGetPid(current, &owner) != kAXErrorSuccess || owner != pid) break;
    if (CFEqual(current, button)) {
      inside = true;
      break;
    }
    CFTypeRef raw_parent = NULL;
    if (!set_ax_messaging_timeout(current)) break;
    AXError error = AXUIElementCopyAttributeValue(current, kAXParentAttribute,
                                                  &raw_parent);
    CFRelease(current);
    current = NULL;
    if (error == kAXErrorSuccess && raw_parent != NULL &&
        CFGetTypeID(raw_parent) == AXUIElementGetTypeID()) {
      current = (AXUIElementRef)raw_parent;
    } else if (raw_parent != NULL) {
      CFRelease(raw_parent);
    }
  }
  if (current != NULL) CFRelease(current);
  return inside && query_deadline_available(deadline);
}

static bool topmost_window_owns_point(pid_t pid, const char *title,
                                     CGPoint point, CGWindowID expected_id,
                                     double deadline) {
  if (!query_deadline_available(deadline)) return false;
  CFArrayRef windows = CGWindowListCopyWindowInfo(
      kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
      kCGNullWindowID);
  if (windows == NULL || !query_deadline_available(deadline)) {
    if (windows != NULL) CFRelease(windows);
    return false;
  }
  bool owned = false;
  for (CFIndex index = 0; index < CFArrayGetCount(windows) &&
                           query_deadline_available(deadline); index++) {
    CFTypeRef raw = CFArrayGetValueAtIndex(windows, index);
    if (raw == NULL || CFGetTypeID(raw) != CFDictionaryGetTypeID()) continue;
    CFDictionaryRef record = (CFDictionaryRef)raw;
    double alpha = 0, number = 0;
    bool on_screen = false;
    if (!read_cf_number(record, kCGWindowAlpha, &alpha) || alpha <= 0 ||
        !read_cf_number(record, kCGWindowNumber, &number) ||
        !copy_dictionary_boolean(record, kCGWindowIsOnscreen, &on_screen) ||
        !on_screen) continue;
    CFTypeRef raw_bounds = CFDictionaryGetValue(record, kCGWindowBounds);
    if (raw_bounds == NULL || CFGetTypeID(raw_bounds) != CFDictionaryGetTypeID()) continue;
    double x = 0, y = 0, width = 0, height = 0;
    CFDictionaryRef bounds = (CFDictionaryRef)raw_bounds;
    if (!read_cf_number(bounds, CFSTR("X"), &x) ||
        !read_cf_number(bounds, CFSTR("Y"), &y) ||
        !read_cf_number(bounds, CFSTR("Width"), &width) ||
        !read_cf_number(bounds, CFSTR("Height"), &height)) continue;
    if (!CGRectContainsPoint(CGRectMake(x, y, width, height), point)) continue;
    double owner = 0;
    if (!read_cf_number(record, kCGWindowOwnerPID, &owner) || owner != pid ||
        number != expected_id) break;
    CFTypeRef name = CFDictionaryGetValue(record, kCGWindowName);
    char observed[512] = "";
    owned = name != NULL && CFGetTypeID(name) == CFStringGetTypeID() &&
            CFStringGetCString((CFStringRef)name, observed, sizeof(observed),
                               kCFStringEncodingUTF8) &&
            strcmp(observed, title) == 0;
    break;
  }
  CFRelease(windows);
  return owned && query_deadline_available(deadline);
}

static bool copy_ax_point(AXUIElementRef element, CFStringRef attribute,
                          AXValueType type, CGPoint *out_point,
                          CGSize *out_size) {
  if (!set_ax_messaging_timeout(element)) return false;
  CFTypeRef raw = NULL;
  AXError error = AXUIElementCopyAttributeValue(element, attribute, &raw);
  if (error != kAXErrorSuccess || raw == NULL ||
      CFGetTypeID(raw) != AXValueGetTypeID()) {
    if (raw != NULL) CFRelease(raw);
    return false;
  }
  bool ok = false;
  if (type == kAXValueCGPointType) {
    ok = AXValueGetValue((AXValueRef)raw, type, out_point);
  } else if (type == kAXValueCGSizeType) {
    ok = AXValueGetValue((AXValueRef)raw, type, out_size);
  }
  CFRelease(raw);
  return ok && (active_ax_deadline <= 0.0 ||
                query_deadline_available(active_ax_deadline));
}

typedef struct InputTarget {
  pid_t pid;
  const char *title;
  const char *button_name;
  bool has_button;
  AXUIElementRef window;
  AXUIElementRef button;
  CGWindowID window_id;
  CGRect window_bounds;
  CGRect button_bounds;
  CGPoint point;
  double expected_button_width;
  double expected_button_height;
} InputTarget;

typedef struct InputGuardSnapshot {
  bool deadline_available;
  bool session_ok;
  bool frontmost;
  bool focused_window_matches;
  bool visible_window_matches;
  bool button_found;
  bool button_enabled;
  bool button_identity_matches;
  bool activation_count_read;
  int activation_count;
  bool button_frame_matches;
  bool topmost_matches;
  bool ax_hit_matches;
  pid_t pid;
  CGWindowID window_id;
  CGRect window_bounds;
  CGRect button_bounds;
  uint64_t inherited_event_flags;
  uint64_t event_flags_before_post;
} InputGuardSnapshot;

typedef void (*InputPoster)(void *context);
typedef bool (*InputGuardReader)(void *context, double deadline,
                                InputGuardSnapshot *snapshot, char *reason,
                                size_t reason_capacity);

typedef struct InputPostContext {
  pid_t pid;
  CGEventRef event;
  bool target_pid;
} InputPostContext;

static bool rect_is_finite(CGRect rect) {
  return isfinite(rect.origin.x) && isfinite(rect.origin.y) &&
         isfinite(rect.size.width) && isfinite(rect.size.height);
}

static bool rect_matches(CGRect actual, CGRect expected, double tolerance) {
  return rect_is_finite(actual) && rect_is_finite(expected) &&
         fabs(actual.origin.x - expected.origin.x) <= tolerance &&
         fabs(actual.origin.y - expected.origin.y) <= tolerance &&
         fabs(actual.size.width - expected.size.width) <= tolerance &&
         fabs(actual.size.height - expected.size.height) <= tolerance;
}

static bool copy_button_frame(AXUIElementRef button, double expected_width,
                              double expected_height, CGRect *out_frame,
                              CGPoint *out_center, bool *out_enabled,
                              int *out_activation_count,
                              bool *out_activation_read, double deadline) {
  if (!query_deadline_available(deadline) || !set_ax_messaging_timeout(button)) {
    return false;
  }
  AXError enabled_error = kAXErrorSuccess;
  bool enabled = button_enabled(button, &enabled_error);
  int activation_count = -1;
  bool activation_read = button_help_count(button, &activation_count);
  CGPoint position = CGPointZero;
  CGSize size = CGSizeZero;
  bool position_read = copy_ax_point(button, kAXPositionAttribute,
                                     kAXValueCGPointType, &position, NULL);
  bool size_read = copy_ax_point(button, kAXSizeAttribute,
                                 kAXValueCGSizeType, NULL, &size);
  CGRect frame = CGRectMake(position.x, position.y, size.width, size.height);
  CGPoint center = CGPointMake(position.x + size.width / 2.0,
                                position.y + size.height / 2.0);
  if (out_frame != NULL) *out_frame = frame;
  if (out_center != NULL) *out_center = center;
  if (out_enabled != NULL) *out_enabled = enabled;
  if (out_activation_count != NULL) *out_activation_count = activation_count;
  if (out_activation_read != NULL) *out_activation_read = activation_read;
  return query_deadline_available(deadline) && enabled && position_read && size_read &&
         fabs(size.width - expected_width) <= 1.0 &&
         fabs(size.height - expected_height) <= 1.0;
}

static bool ax_point_hits_button(AXUIElementRef button, pid_t pid,
                                 CGPoint point, double deadline) {
  if (!query_deadline_available(deadline)) return false;
  AXUIElementRef system = AXUIElementCreateSystemWide();
  if (system == NULL || !set_ax_messaging_timeout(system)) {
    if (system != NULL) CFRelease(system);
    return false;
  }
  AXUIElementRef hit = NULL;
  AXError error = AXUIElementCopyElementAtPosition(
      system, (float)point.x, (float)point.y, &hit);
  bool matches = error == kAXErrorSuccess && hit != NULL &&
                 query_deadline_available(deadline) &&
                 ax_hit_is_inside(hit, pid, deadline, button);
  if (hit != NULL) CFRelease(hit);
  CFRelease(system);
  return matches && query_deadline_available(deadline);
}

static bool input_snapshot_allows(const InputTarget *target,
                                  const InputGuardSnapshot *snapshot,
                                  bool require_button,
                                  bool require_zero_activation) {
  if (target == NULL || snapshot == NULL ||
      !snapshot->deadline_available || !snapshot->session_ok ||
      !snapshot->frontmost || !snapshot->focused_window_matches ||
      !snapshot->visible_window_matches || snapshot->pid != target->pid ||
      snapshot->window_id != target->window_id ||
      !rect_matches(snapshot->window_bounds, target->window_bounds, 0.5) ||
      snapshot->event_flags_before_post != 0) {
    return false;
  }
  if (!require_button) return true;
  return target->has_button && snapshot->button_found &&
         snapshot->button_enabled && snapshot->button_identity_matches &&
         snapshot->activation_count_read &&
         (!require_zero_activation || snapshot->activation_count == 0) &&
         snapshot->button_frame_matches &&
         snapshot->topmost_matches && snapshot->ax_hit_matches &&
         rect_matches(snapshot->button_bounds, target->button_bounds, 0.5);
}

static bool guarded_post_snapshot(const InputTarget *target,
                                  InputGuardSnapshot *snapshot,
                                  bool require_button, bool is_down,
                                  bool *pending_down, InputPoster post,
                                  void *post_context) {
  if (post == NULL || pending_down == NULL ||
      (is_down && *pending_down) || (!is_down && !*pending_down) ||
      !input_snapshot_allows(target, snapshot, require_button, is_down)) {
    return false;
  }
  // Set ownership before invoking the post callback: an ACK can be lost after
  // the event has entered the WindowServer queue.
  if (is_down) *pending_down = true;
  post(post_context);
  if (!is_down) *pending_down = false;
  return true;
}

static bool dispatch_guarded_event(const InputTarget *target,
                                   bool require_button, bool is_down,
                                   bool *pending_down, uint64_t inherited_flags,
                                   uint64_t flags_before_post, double deadline,
                                   InputGuardReader read_guard,
                                   void *guard_context, InputPoster post,
                                   void *post_context,
                                   InputGuardSnapshot *out_snapshot,
                                   char *reason, size_t reason_capacity) {
  if (read_guard == NULL || out_snapshot == NULL || post == NULL) return false;
  InputGuardSnapshot snapshot = {0};
  if (!read_guard(guard_context, deadline, &snapshot, reason,
                  reason_capacity)) {
    *out_snapshot = snapshot;
    return false;
  }
  snapshot.inherited_event_flags = inherited_flags;
  snapshot.event_flags_before_post = flags_before_post;
  *out_snapshot = snapshot;
  if (!query_deadline_available(deadline) || input_cancel_requested) {
    snprintf(reason, reason_capacity,
             input_cancel_requested ? "input helper cancellation requested"
                                    : "shared input guard deadline expired before post");
    return false;
  }
  if (!guarded_post_snapshot(target, &snapshot, require_button, is_down,
                             pending_down, post, post_context)) {
    snprintf(reason, reason_capacity,
             "fresh target snapshot or modifier guard refused global post");
    return false;
  }
  *out_snapshot = snapshot;
  return true;
}

static void post_cg_event(void *opaque) {
  InputPostContext *context = (InputPostContext *)opaque;
  if (context->target_pid) {
    CGEventPostToPid(context->pid, context->event);
  } else {
    CGEventPost(kCGHIDEventTap, context->event);
  }
}

static bool capture_input_guard(const InputTarget *target, double deadline,
                                InputGuardSnapshot *snapshot,
                                char *reason, size_t reason_capacity);

typedef struct LiveGuardContext {
  const InputTarget *target;
} LiveGuardContext;

static bool read_live_guard(void *opaque, double deadline,
                            InputGuardSnapshot *snapshot, char *reason,
                            size_t reason_capacity) {
  LiveGuardContext *context = (LiveGuardContext *)opaque;
  return capture_input_guard(context->target, deadline, snapshot, reason,
                             reason_capacity);
}

static bool dispatch_live_event(const InputTarget *target,
                                bool require_button, bool is_down,
                                bool *pending_down, CGEventRef event,
                                bool target_pid, double deadline,
                                uint64_t *out_inherited_flags,
                                uint64_t *out_flags_before_post,
                                InputGuardSnapshot *out_snapshot,
                                char *reason, size_t reason_capacity) {
  uint64_t inherited_flags = UINT64_MAX;
  uint64_t flags_before_post = UINT64_MAX;
  bool flags_clear = reset_unmodified_event_flags(
      event, &inherited_flags, &flags_before_post);
  if (out_inherited_flags != NULL) *out_inherited_flags = inherited_flags;
  if (out_flags_before_post != NULL) *out_flags_before_post = flags_before_post;
  if (!flags_clear) {
    snprintf(reason, reason_capacity,
             "event retained nonzero flags after normalization");
    return false;
  }
  InputPostContext context = {
      .pid = target->pid,
      .event = event,
      .target_pid = target_pid,
  };
  LiveGuardContext guard_context = {.target = target};
  return dispatch_guarded_event(
      target, require_button, is_down, pending_down, inherited_flags,
      flags_before_post, deadline, read_live_guard, &guard_context,
      post_cg_event, &context, out_snapshot, reason, reason_capacity);
}

static bool capture_input_guard(const InputTarget *target, double deadline,
                                InputGuardSnapshot *snapshot,
                                char *reason, size_t reason_capacity) {
  *snapshot = (InputGuardSnapshot){0};
  snapshot->pid = target->pid;
  if (!query_deadline_available(deadline)) {
    snprintf(reason, reason_capacity, "shared input guard deadline expired");
    return false;
  }
  if (input_cancel_requested) {
    snprintf(reason, reason_capacity, "input helper cancellation requested");
    return false;
  }
  AXUIElementRef app = NULL;
  AXUIElementRef window = NULL;
  if (!copy_focused_target_window(target->pid, target->title, deadline,
                                 &app, &window)) {
    snprintf(reason, reason_capacity,
             "fresh exact focused AXWindow lookup failed or expired");
    return false;
  }
  snapshot->focused_window_matches = CFEqual(window, target->window);

  CGRect visible_bounds = CGRectZero;
  CGWindowID visible_id = 0;
  bool visible = copy_visible_target_window(target->pid, target->title,
                                             &visible_id, &visible_bounds,
                                             deadline);
  snapshot->window_id = visible_id;
  snapshot->window_bounds = visible_bounds;
  snapshot->visible_window_matches = visible &&
      visible_id == target->window_id &&
      rect_matches(visible_bounds, target->window_bounds, 0.5);

  if (target->has_button) {
    unsigned visited = 0;
    AXUIElementRef button = find_button(window, target->button_name,
                                        0, &visited, deadline);
    if (button != NULL) {
      CGRect button_bounds = CGRectZero;
      CGPoint point = CGPointZero;
      bool enabled = false;
      int activation_count = -1;
      bool activation_read = false;
      bool frame_read = copy_button_frame(
          button, target->expected_button_width, target->expected_button_height,
          &button_bounds, &point, &enabled, &activation_count,
          &activation_read, deadline);
      snapshot->button_found = frame_read;
      snapshot->button_enabled = enabled;
      snapshot->button_identity_matches = CFEqual(button, target->button);
      snapshot->activation_count_read = activation_read;
      snapshot->activation_count = activation_count;
      snapshot->button_bounds = button_bounds;
      snapshot->button_frame_matches = frame_read &&
          CGRectContainsPoint(target->window_bounds, point) &&
          fabs(point.x - target->point.x) <= 0.5 &&
          fabs(point.y - target->point.y) <= 0.5;
      snapshot->topmost_matches = topmost_window_owns_point(
          target->pid, target->title, target->point, target->window_id,
          deadline);
      snapshot->ax_hit_matches = ax_point_hits_button(
          button, target->pid, target->point, deadline);
      CFRelease(button);
    }
  }

  CFRelease(window);
  CFRelease(app);

  snapshot->session_ok = input_preflight(false, deadline) == 0;
  snapshot->frontmost = target_is_frontmost(target->pid, deadline);
  snapshot->deadline_available = query_deadline_available(deadline);
  if (!snapshot->deadline_available) {
    snprintf(reason, reason_capacity, "shared input guard deadline expired");
    return false;
  }
  if (!snapshot->session_ok || !snapshot->frontmost ||
      !snapshot->focused_window_matches || !snapshot->visible_window_matches ||
      (target->has_button &&
       (!snapshot->button_found || !snapshot->button_enabled ||
        !snapshot->button_identity_matches ||
        !snapshot->activation_count_read ||
        !snapshot->button_frame_matches || !snapshot->topmost_matches ||
        !snapshot->ax_hit_matches))) {
    snprintf(reason, reason_capacity,
             "fresh target ownership, session, Button, or point guard refused input");
    return false;
  }
  return true;
}

static bool input_target_is_live(pid_t pid) {
  errno = 0;
  if (kill(pid, 0) == 0) return true;
  return errno == EPERM;
}

static bool guarded_owned_release(const InputTarget *target,
                                  bool session_ok, bool target_live,
                                  uint64_t flags_before_post,
                                  bool *pending_down, InputPoster post,
                                  void *post_context, const char **outcome,
                                  char *reason, size_t reason_capacity) {
  if (pending_down == NULL || !*pending_down) {
    *outcome = "no-pending-input";
    return true;
  }
  if (target == NULL || target->pid <= 0) {
    snprintf(reason, reason_capacity, "owned release has no original target PID");
    *outcome = "refused";
    return false;
  }
  if (!target_live) {
    *pending_down = false;
    *outcome = "target-exited";
    return true;
  }
  if (!session_ok || flags_before_post != 0 || post == NULL) {
    snprintf(reason, reason_capacity,
             "owned PID-targeted release refused by session or modifier guard");
    *outcome = "refused";
    return false;
  }
  post(post_context);
  *pending_down = false;
  *outcome = "target-pid";
  return true;
}

static bool post_owned_release_to_pid(const InputTarget *target,
                                      CGEventRef event, bool *pending_down,
                                      double cleanup_deadline,
                                      uint64_t *out_inherited_flags,
                                      uint64_t *out_flags_before_post,
                                      const char **outcome,
                                      char *reason, size_t reason_capacity) {
  if (pending_down == NULL || !*pending_down) {
    *outcome = "no-pending-input";
    return true;
  }
  if (!input_target_is_live(target->pid)) {
    return guarded_owned_release(target, true, false, 0, pending_down, NULL,
                                 NULL, outcome, reason, reason_capacity);
  }
  active_ax_deadline = cleanup_deadline;
  if (input_preflight(false, cleanup_deadline) != 0 ||
      !query_deadline_available(cleanup_deadline)) {
    return guarded_owned_release(target, false, true, UINT64_MAX,
                                 pending_down, NULL, NULL, outcome, reason,
                                 reason_capacity);
  }
  uint64_t inherited_flags = UINT64_MAX;
  uint64_t flags_before_post = UINT64_MAX;
  bool flags_clear = reset_unmodified_event_flags(
      event, &inherited_flags, &flags_before_post);
  if (out_inherited_flags != NULL) *out_inherited_flags = inherited_flags;
  if (out_flags_before_post != NULL) *out_flags_before_post = flags_before_post;
  if (!flags_clear || !query_deadline_available(cleanup_deadline) ||
      input_preflight(false, cleanup_deadline) != 0) {
    return guarded_owned_release(target, false, true, flags_before_post,
                                 pending_down, NULL, NULL, outcome, reason,
                                 reason_capacity);
  }
  if (!input_target_is_live(target->pid)) {
    return guarded_owned_release(target, true, false, flags_before_post,
                                 pending_down, NULL, NULL, outcome, reason,
                                 reason_capacity);
  }
  InputPostContext context = {
      .pid = target->pid,
      .event = event,
      .target_pid = true,
  };
  return guarded_owned_release(target, true, true, flags_before_post,
                               pending_down, post_cg_event, &context, outcome,
                               reason, reason_capacity);
}

static void release_input_target(InputTarget *target) {
  if (target->button != NULL) CFRelease(target->button);
  if (target->window != NULL) CFRelease(target->window);
  target->button = NULL;
  target->window = NULL;
}

static bool initialize_input_target(InputTarget *target, pid_t pid,
                                    const char *title, bool has_button,
                                    const char *button_name,
                                    double button_width, double button_height,
                                    double deadline, char *reason,
                                    size_t reason_capacity) {
  *target = (InputTarget){
      .pid = pid,
      .title = title,
      .button_name = button_name,
      .has_button = has_button,
      .expected_button_width = button_width,
      .expected_button_height = button_height,
  };
  if (input_preflight(false, deadline) != 0 ||
      !target_is_frontmost(pid, deadline)) {
    snprintf(reason, reason_capacity,
             "refusing host input because the session is not ready or the exact sample PID is not frontmost");
    return false;
  }
  AXUIElementRef app = NULL;
  AXUIElementRef window = NULL;
  if (!copy_focused_target_window(pid, title, deadline, &app, &window)) {
    snprintf(reason, reason_capacity,
             "refusing host input because the exact titled AXWindow is not uniquely focused");
    return false;
  }
  target->window = window;
  CFRelease(app);
  if (!copy_visible_target_window(pid, title, &target->window_id,
                                  &target->window_bounds, deadline)) {
    snprintf(reason, reason_capacity,
             "refusing host input because the exact titled sample window is not uniquely visible");
    release_input_target(target);
    return false;
  }
  if (has_button) {
    unsigned visited = 0;
    AXUIElementRef button = find_button(window, button_name, 0, &visited,
                                        deadline);
    if (button == NULL) {
      snprintf(reason, reason_capacity,
               "refusing host click because the named sample AXButton is absent");
      release_input_target(target);
      return false;
    }
    CGRect button_bounds = CGRectZero;
    CGPoint point = CGPointZero;
    bool enabled = false;
    int activation_count = -1;
    bool activation_read = false;
    bool frame_read = copy_button_frame(
        button, button_width, button_height, &button_bounds, &point, &enabled,
        &activation_count, &activation_read, deadline);
    bool in_window = CGRectContainsPoint(target->window_bounds, point);
    bool topmost = topmost_window_owns_point(pid, title, point, target->window_id,
                                              deadline);
    bool ax_hit = ax_point_hits_button(button, pid, point, deadline);
    if (!frame_read || !enabled || !activation_read || activation_count != 0 ||
        !in_window || !topmost || !ax_hit) {
      CFRelease(button);
      snprintf(reason, reason_capacity,
               "refusing host click: frame_read=%d enabled=%d activation_read=%d activation_count=%d in_window=%d topmost=%d ax_hit=%d point=(%.1f,%.1f) button=(%.1f,%.1f,%.1f,%.1f) window=(%.1f,%.1f,%.1f,%.1f)",
               frame_read, enabled, activation_read, activation_count,
               in_window, topmost, ax_hit, point.x, point.y,
               button_bounds.origin.x, button_bounds.origin.y,
               button_bounds.size.width, button_bounds.size.height,
               target->window_bounds.origin.x, target->window_bounds.origin.y,
               target->window_bounds.size.width,
               target->window_bounds.size.height);
      release_input_target(target);
      return false;
    }
    target->button = button;
    target->button_bounds = button_bounds;
    target->point = point;
  }
  if (!query_deadline_available(deadline) || input_cancel_requested) {
    snprintf(reason, reason_capacity,
             "shared input setup deadline expired or helper cancellation was requested");
    release_input_target(target);
    return false;
  }
  return true;
}

static bool original_window_is_gone(const InputTarget *target,
                                    double deadline, bool *known) {
  *known = false;
  if (!query_deadline_available(deadline)) return false;
  CFArrayRef windows = CGWindowListCopyWindowInfo(kCGWindowListOptionAll,
                                                 kCGNullWindowID);
  if (windows == NULL) return false;
  bool found = false;
  for (CFIndex index = 0; index < CFArrayGetCount(windows) &&
                           query_deadline_available(deadline); index++) {
    CFTypeRef raw = CFArrayGetValueAtIndex(windows, index);
    if (raw == NULL || CFGetTypeID(raw) != CFDictionaryGetTypeID()) continue;
    CFDictionaryRef record = (CFDictionaryRef)raw;
    double owner = 0, number = 0;
    if (read_cf_number(record, kCGWindowOwnerPID, &owner) &&
        read_cf_number(record, kCGWindowNumber, &number) &&
        owner == target->pid && number == target->window_id) {
      found = true;
      break;
    }
  }
  CFRelease(windows);
  if (!query_deadline_available(deadline)) return false;
  *known = true;
  return !found;
}

static bool escape_terminal_fallback_allowed(bool click, bool target_terminal,
                                             bool cleanup_ok) {
  return !click && target_terminal && cleanup_ok;
}

typedef struct FixturePoster {
  unsigned global_posts;
  unsigned pid_posts;
  bool target_pid;
} FixturePoster;

static void fixture_post(void *opaque) {
  FixturePoster *poster = (FixturePoster *)opaque;
  if (poster->target_pid) poster->pid_posts += 1;
  else poster->global_posts += 1;
}

typedef struct FixtureGuardReader {
  InputGuardSnapshot snapshot;
  bool available;
} FixtureGuardReader;

static bool fixture_read_guard(void *opaque, double deadline,
                               InputGuardSnapshot *snapshot, char *reason,
                               size_t reason_capacity) {
  FixtureGuardReader *reader = (FixtureGuardReader *)opaque;
  if (!reader->available || !query_deadline_available(deadline)) {
    snprintf(reason, reason_capacity, "fixture guard unavailable or expired");
    return false;
  }
  *snapshot = reader->snapshot;
  return true;
}

static InputGuardSnapshot valid_fixture_snapshot(const InputTarget *target) {
  return (InputGuardSnapshot){
      .deadline_available = true,
      .session_ok = true,
      .frontmost = true,
      .focused_window_matches = true,
      .visible_window_matches = true,
      .button_found = target->has_button,
      .button_enabled = target->has_button,
      .button_identity_matches = target->has_button,
      .activation_count_read = target->has_button,
      .activation_count = 0,
      .button_frame_matches = target->has_button,
      .topmost_matches = target->has_button,
      .ax_hit_matches = target->has_button,
      .pid = target->pid,
      .window_id = target->window_id,
      .window_bounds = target->window_bounds,
      .button_bounds = target->button_bounds,
      .event_flags_before_post = 0,
  };
}

typedef enum FixtureMutation {
  kFixtureExpired,
  kFixtureLocked,
  kFixtureNotFrontmost,
  kFixtureOtherFocusedWindow,
  kFixtureOtherVisibleWindow,
  kFixtureOtherPid,
  kFixtureOtherWindowId,
  kFixtureMovedWindow,
  kFixtureMissingButton,
  kFixtureDisabledButton,
  kFixtureOtherButton,
  kFixtureMissingActivation,
  kFixtureAlreadyActivated,
  kFixtureMovedButton,
  kFixtureOverlay,
  kFixtureOtherAXHit,
  kFixtureModifierFlags,
} FixtureMutation;

static bool fixture_expect_no_post(const InputTarget *target,
                                   FixtureMutation mutation,
                                   const char *label) {
  FixtureGuardReader reader = {
      .snapshot = valid_fixture_snapshot(target),
      .available = true,
  };
  switch (mutation) {
  case kFixtureExpired: reader.snapshot.deadline_available = false; break;
  case kFixtureLocked: reader.snapshot.session_ok = false; break;
  case kFixtureNotFrontmost: reader.snapshot.frontmost = false; break;
  case kFixtureOtherFocusedWindow: reader.snapshot.focused_window_matches = false; break;
  case kFixtureOtherVisibleWindow: reader.snapshot.visible_window_matches = false; break;
  case kFixtureOtherPid: reader.snapshot.pid += 1; break;
  case kFixtureOtherWindowId: reader.snapshot.window_id += 1; break;
  case kFixtureMovedWindow: reader.snapshot.window_bounds.origin.x += 2.0; break;
  case kFixtureMissingButton: reader.snapshot.button_found = false; break;
  case kFixtureDisabledButton: reader.snapshot.button_enabled = false; break;
  case kFixtureOtherButton: reader.snapshot.button_identity_matches = false; break;
  case kFixtureMissingActivation: reader.snapshot.activation_count_read = false; break;
  case kFixtureAlreadyActivated: reader.snapshot.activation_count = 1; break;
  case kFixtureMovedButton: reader.snapshot.button_bounds.origin.y += 2.0; break;
  case kFixtureOverlay: reader.snapshot.topmost_matches = false; break;
  case kFixtureOtherAXHit: reader.snapshot.ax_hit_matches = false; break;
  case kFixtureModifierFlags: break;
  }
  FixturePoster poster = {0};
  bool pending_down = false;
  InputGuardSnapshot observed = {0};
  char reason[160] = "";
  double deadline = monotonic_seconds() + 1.0;
  uint64_t flags = mutation == kFixtureModifierFlags ? 1 : 0;
  bool posted = dispatch_guarded_event(
      target, true, true, &pending_down, 0, flags, deadline,
      fixture_read_guard, &reader, fixture_post, &poster, &observed,
      reason, sizeof(reason));
  if (posted || poster.global_posts != 0 || poster.pid_posts != 0 ||
      pending_down) {
    fprintf(stderr, "guard fixture failed to refuse %s\n", label);
    return false;
  }
  return true;
}

static bool fixture_modifier_normalization(void) {
  const CGEventFlags modifiers[] = {
      kCGEventFlagMaskCommand,
      kCGEventFlagMaskControl,
      kCGEventFlagMaskAlternate,
      kCGEventFlagMaskShift,
  };
  for (size_t index = 0; index < sizeof(modifiers) / sizeof(modifiers[0]);
       index++) {
    CGEventRef keyboard = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)53, true);
    CGEventRef keyboard_up = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)53, false);
    CGEventRef mouse_down = CGEventCreateMouseEvent(
        NULL, kCGEventLeftMouseDown, CGPointMake(20.0, 20.0),
        kCGMouseButtonLeft);
    CGEventRef mouse_up = CGEventCreateMouseEvent(
        NULL, kCGEventLeftMouseUp, CGPointMake(20.0, 20.0),
        kCGMouseButtonLeft);
    if (keyboard == NULL || keyboard_up == NULL || mouse_down == NULL ||
        mouse_up == NULL) {
      if (keyboard != NULL) CFRelease(keyboard);
      if (keyboard_up != NULL) CFRelease(keyboard_up);
      if (mouse_down != NULL) CFRelease(mouse_down);
      if (mouse_up != NULL) CFRelease(mouse_up);
      return false;
    }
    CGEventRef events[] = {keyboard, keyboard_up, mouse_down, mouse_up};
    for (size_t event_index = 0; event_index < 4; event_index++) {
      CGEventSetFlags(events[event_index], modifiers[index]);
      uint64_t inherited = UINT64_MAX, before_post = UINT64_MAX;
      bool normalized = reset_unmodified_event_flags(
          events[event_index], &inherited, &before_post);
      if (!normalized || before_post != 0 ||
          (inherited & (uint64_t)modifiers[index]) == 0) {
        CFRelease(keyboard);
        CFRelease(keyboard_up);
        CFRelease(mouse_down);
        CFRelease(mouse_up);
        return false;
      }
    }
    CFRelease(keyboard);
    CFRelease(keyboard_up);
    CFRelease(mouse_down);
    CFRelease(mouse_up);
  }
  return true;
}

static int run_guard_fixtures(void) {
  input_cancel_requested = 0;
  InputTarget target = {
      .pid = 321,
      .title = "fixture",
      .button_name = "Click me",
      .has_button = true,
      .window_id = 19,
      .window_bounds = CGRectMake(1.0, 2.0, 100.0, 60.0),
      .button_bounds = CGRectMake(20.0, 20.0, 30.0, 15.0),
      .point = CGPointMake(35.0, 27.5),
  };
  const struct {
    FixtureMutation mutation;
    const char *label;
  } cases[] = {
      {kFixtureExpired, "expired deadline"},
      {kFixtureLocked, "locked session"},
      {kFixtureNotFrontmost, "different frontmost PID"},
      {kFixtureOtherFocusedWindow, "same-PID focused AXWindow change"},
      {kFixtureOtherVisibleWindow, "visible window identity change"},
      {kFixtureOtherPid, "target PID change"},
      {kFixtureOtherWindowId, "WindowServer ID change"},
      {kFixtureMovedWindow, "window geometry change"},
      {kFixtureMissingButton, "missing AXButton"},
      {kFixtureDisabledButton, "disabled AXButton"},
      {kFixtureOtherButton, "AXButton identity change"},
      {kFixtureMissingActivation, "unreadable activation baseline"},
      {kFixtureAlreadyActivated, "already activated button"},
      {kFixtureMovedButton, "button geometry change"},
      {kFixtureOverlay, "topmost overlay"},
      {kFixtureOtherAXHit, "AX point hit outside owned Button"},
      {kFixtureModifierFlags, "nonzero pre-post modifier flags"},
  };
  for (size_t index = 0; index < sizeof(cases) / sizeof(cases[0]); index++) {
    if (!fixture_expect_no_post(&target, cases[index].mutation,
                                cases[index].label)) return 1;
  }

  FixtureGuardReader expired_reader = {
      .snapshot = valid_fixture_snapshot(&target),
      .available = false,
  };
  FixturePoster expired_poster = {0};
  bool expired_pending = false;
  InputGuardSnapshot expired_observed = {0};
  char expired_reason[128] = "";
  if (dispatch_guarded_event(&target, true, true, &expired_pending, 0, 0,
                             monotonic_seconds() + 1.0, fixture_read_guard,
                             &expired_reader, fixture_post, &expired_poster,
                             &expired_observed, expired_reason,
                             sizeof(expired_reason)) ||
      expired_poster.global_posts != 0 || expired_pending) {
    fputs("guard fixture posted after a stalled guard reader\n", stderr);
    return 1;
  }

  FixtureGuardReader down_reader = {
      .snapshot = valid_fixture_snapshot(&target),
      .available = true,
  };
  FixturePoster pair_poster = {0};
  bool pending_down = false;
  InputGuardSnapshot observed = {0};
  char reason[160] = "";
  double deadline = monotonic_seconds() + 1.0;
  if (!dispatch_guarded_event(&target, true, true, &pending_down, 0, 0,
                              deadline, fixture_read_guard, &down_reader,
                              fixture_post, &pair_poster, &observed,
                              reason, sizeof(reason)) ||
      !pending_down || pair_poster.global_posts != 1) {
    fputs("guard fixture failed to record ownership before down post\n", stderr);
    return 1;
  }
  FixtureGuardReader changed_up_reader = {
      .snapshot = valid_fixture_snapshot(&target),
      .available = true,
  };
  changed_up_reader.snapshot.topmost_matches = false;
  if (dispatch_guarded_event(&target, true, false, &pending_down, 0, 0,
                             deadline, fixture_read_guard, &changed_up_reader,
                             fixture_post, &pair_poster, &observed,
                             reason, sizeof(reason)) ||
      !pending_down || pair_poster.global_posts != 1) {
    fputs("guard fixture allowed an unguarded paired release\n", stderr);
    return 1;
  }
  FixturePoster cleanup_poster = {.target_pid = true};
  const char *outcome = NULL;
  if (!guarded_owned_release(&target, true, true, 0, &pending_down,
                             fixture_post, &cleanup_poster, &outcome,
                             reason, sizeof(reason)) ||
      pending_down || strcmp(outcome, "target-pid") != 0 ||
      cleanup_poster.pid_posts != 1 || pair_poster.global_posts != 1) {
    fputs("guard fixture failed to release owned input to original PID\n", stderr);
    return 1;
  }

  pending_down = true;
  outcome = NULL;
  cleanup_poster.pid_posts = 0;
  if (guarded_owned_release(&target, true, true, 1, &pending_down,
                            fixture_post, &cleanup_poster, &outcome,
                            reason, sizeof(reason)) ||
      !pending_down || cleanup_poster.pid_posts != 0 ||
      strcmp(outcome, "refused") != 0) {
    fputs("guard fixture allowed a modifier-bearing owned release\n", stderr);
    return 1;
  }
  outcome = NULL;
  if (guarded_owned_release(&target, false, true, 0, &pending_down,
                            fixture_post, &cleanup_poster, &outcome,
                            reason, sizeof(reason)) ||
      !pending_down || cleanup_poster.pid_posts != 0 ||
      strcmp(outcome, "refused") != 0) {
    fputs("guard fixture masked a session-refused release\n", stderr);
    return 1;
  }
  outcome = NULL;
  if (!guarded_owned_release(&target, true, false, 0, &pending_down,
                             NULL, NULL, &outcome, reason, sizeof(reason)) ||
      pending_down || strcmp(outcome, "target-exited") != 0) {
    fputs("guard fixture did not recognize an exited owned target\n", stderr);
    return 1;
  }
  if (!escape_terminal_fallback_allowed(false, true, true) ||
      escape_terminal_fallback_allowed(true, true, true) ||
      escape_terminal_fallback_allowed(false, false, true) ||
      escape_terminal_fallback_allowed(false, true, false)) {
    fputs("guard fixture accepted an unproven Escape terminal fallback\n", stderr);
    return 1;
  }
  if (!fixture_modifier_normalization()) {
    fputs("guard fixture failed to clear inherited modifiers on inert events\n", stderr);
    return 1;
  }
  puts("guard fixtures passed; no native events were posted");
  return 0;
}

static int external_input(int argc, char **argv) {
  bool click = strcmp(argv[1], "--click") == 0;
  if ((!click && (argc != 4 || strcmp(argv[1], "--escape") != 0)) ||
      (click && argc != 7)) {
    fprintf(stderr, "usage: --click PID WINDOW_TITLE BUTTON_NAME WIDTH HEIGHT | --escape PID WINDOW_TITLE\n");
    return 2;
  }
  char *end = NULL;
  long parsed_pid = strtol(argv[2], &end, 10);
  if (end == argv[2] || *end != '\0' || parsed_pid <= 0 || parsed_pid > INT_MAX) {
    fprintf(stderr, "invalid sample PID\n");
    return 2;
  }
  pid_t pid = (pid_t)parsed_pid;
  const char *title = argv[3];
  const char *button_name = click ? argv[4] : NULL;
  double expected_width = 0.0, expected_height = 0.0;
  if (click) {
    char *width_end = NULL, *height_end = NULL;
    expected_width = strtod(argv[5], &width_end);
    expected_height = strtod(argv[6], &height_end);
    if (width_end == argv[5] || *width_end != '\0' ||
        !isfinite(expected_width) || expected_width <= 0 ||
        height_end == argv[6] || *height_end != '\0' ||
        !isfinite(expected_height) || expected_height <= 0) {
      fprintf(stderr, "invalid expected Button dimensions\n");
      return 2;
    }
  }

  struct sigaction cancel_action = {0};
  cancel_action.sa_handler = request_input_cancel;
  sigemptyset(&cancel_action.sa_mask);
  (void)sigaction(SIGTERM, &cancel_action, NULL);
  (void)sigaction(SIGINT, &cancel_action, NULL);
  input_cancel_requested = 0;
  double operation_deadline = monotonic_seconds() + 18.0;
  active_ax_deadline = operation_deadline;
  char reason[256] = "";
  InputTarget target = {0};
  if (!initialize_input_target(&target, pid, title, click, button_name,
                               expected_width, expected_height,
                               operation_deadline, reason, sizeof(reason))) {
    fprintf(stderr, "%s\n", reason);
    release_input_target(&target);
    return 1;
  }

  CGEventRef down = NULL;
  CGEventRef up = NULL;
  if (click) {
    down = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, target.point,
                                   kCGMouseButtonLeft);
    up = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, target.point,
                                 kCGMouseButtonLeft);
  } else {
    down = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)53, true);
    up = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)53, false);
  }
  if (down == NULL || up == NULL) {
    if (down != NULL) CFRelease(down);
    if (up != NULL) CFRelease(up);
    release_input_target(&target);
    fprintf(stderr, "could not create host-input events\n");
    return 1;
  }

  bool pending_down = false;
  uint64_t down_inherited = UINT64_MAX, down_flags = UINT64_MAX;
  InputGuardSnapshot down_snapshot = {0};
  if (!dispatch_live_event(&target, click, true, &pending_down, down, false,
                           operation_deadline, &down_inherited, &down_flags,
                           &down_snapshot, reason, sizeof(reason))) {
    fprintf(stderr, "refusing host input before down: %s\n", reason);
    CFRelease(down);
    CFRelease(up);
    release_input_target(&target);
    return 1;
  }

  uint64_t up_inherited = UINT64_MAX, up_flags = UINT64_MAX;
  InputGuardSnapshot up_snapshot = {0};
  bool up_posted_globally = dispatch_live_event(
      &target, click, false, &pending_down, up, false, operation_deadline,
      &up_inherited, &up_flags, &up_snapshot, reason, sizeof(reason));
  const char *release_outcome = "global";
  uint64_t cleanup_inherited = UINT64_MAX, cleanup_flags = UINT64_MAX;
  bool window_gone = false;
  bool window_gone_known = false;
  if (!up_posted_globally) {
    double cleanup_deadline = monotonic_seconds() + 2.0;
    char cleanup_error[256] = "";
    bool cleanup_ok = post_owned_release_to_pid(
        &target, up, &pending_down, cleanup_deadline, &cleanup_inherited,
        &cleanup_flags, &release_outcome, cleanup_error,
        sizeof(cleanup_error));
    if (!click && cleanup_ok && strcmp(release_outcome, "target-exited") != 0) {
      window_gone = original_window_is_gone(&target, cleanup_deadline,
                                             &window_gone_known);
    }
    bool target_terminal = strcmp(release_outcome, "target-exited") == 0 ||
                           (window_gone_known && window_gone);
    bool escape_terminal = escape_terminal_fallback_allowed(
        click, target_terminal, cleanup_ok);
    if (!cleanup_ok || click || (!click && !escape_terminal)) {
      fprintf(stderr,
              "host-input release guard failed after down (guard=%s; cleanup=%s; pendingDown=%s; originalWindowGone=%s)\n",
              reason, cleanup_error[0] ? cleanup_error : release_outcome,
              pending_down ? "true" : "false",
              window_gone_known ? (window_gone ? "true" : "false") : "unknown");
      CFRelease(down);
      CFRelease(up);
      release_input_target(&target);
      return 1;
    }
  }

  printf("{\"action\":");
  print_json_string(click ? "CGEventPost(kCGHIDEventTap) left click"
                          : "CGEventPost(kCGHIDEventTap) Escape");
  printf(",\"pid\":%d,\"windowTitle\":", (int)pid);
  print_json_string(title);
  printf(",\"windowNumber\":%u,\"downPostedGlobally\":true,\"releaseOutcome\":",
         (unsigned int)target.window_id);
  print_json_string(up_posted_globally ? "global" : release_outcome);
  printf(",\"upPostedGlobally\":%s,\"originalWindowGone\":%s,\"eventFlags\":{\"downInherited\":%llu,\"downBeforePost\":%llu,\"upInherited\":%llu,\"upBeforePost\":%llu",
         up_posted_globally ? "true" : "false",
         window_gone_known ? (window_gone ? "true" : "false") : "null",
         (unsigned long long)down_inherited,
         (unsigned long long)down_flags,
         (unsigned long long)up_inherited,
         (unsigned long long)up_flags);
  if (!up_posted_globally && strcmp(release_outcome, "target-pid") == 0) {
    printf(",\"cleanupInherited\":%llu,\"cleanupBeforePost\":%llu",
           (unsigned long long)cleanup_inherited,
           (unsigned long long)cleanup_flags);
  }
  fputs("}", stdout);
  if (click) {
    fputs(",\"button\":", stdout);
    print_json_string(button_name);
    printf(",\"point\":{\"x\":%.3f,\"y\":%.3f},\"axHitWithinButton\":true",
           target.point.x, target.point.y);
  }
  fputs("}\n", stdout);
  CFRelease(down);
  CFRelease(up);
  release_input_target(&target);
  return 0;
}

int main(int argc, char **argv) {
  if (argc == 2 && strcmp(argv[1], "--preflight") == 0) {
    return input_preflight(true, monotonic_seconds() + 2.0);
  }
  if (argc == 2 && strcmp(argv[1], "--guard-fixtures") == 0) {
    return run_guard_fixtures();
  }
  if (argc >= 2 && (strcmp(argv[1], "--click") == 0 ||
                    strcmp(argv[1], "--escape") == 0)) {
    return external_input(argc, argv);
  }
  if (argc != 6) {
    fprintf(stderr, "usage: macos_ax_client PID WINDOW_TITLE BUTTON_NAME BUNDLE_ID BUNDLE_PATH\n");
    return 2;
  }
  char *end = NULL;
  long parsed_pid = strtol(argv[1], &end, 10);
  if (end == argv[1] || *end != '\0' || parsed_pid <= 0 ||
      parsed_pid > INT_MAX) {
    fprintf(stderr, "invalid app PID\n");
    return 2;
  }
  pid_t pid = (pid_t)parsed_pid;
  const char *expected_title = argv[2];
  const char *expected_button = argv[3];
  const char *expected_bundle_id = argv[4];
  const char *expected_bundle_path = argv[5];
  if (!AXIsProcessTrusted()) {
    fprintf(stderr,
            "UNSUPPORTED: AX client is not authorized by macOS Accessibility privacy settings\n");
    return 77;
  }
  if (!application_identity_matches(pid, expected_bundle_id,
                                    expected_bundle_path)) {
    fprintf(stderr,
            "launched PID does not match expected registered app bundle id=%s path=%s\n",
            expected_bundle_id, expected_bundle_path);
    return 1;
  }
  AXUIElementRef app = AXUIElementCreateApplication(pid);
  if (app == NULL) {
    fail("could not create AX application element", kAXErrorFailure);
  }
  (void)AXUIElementSetMessagingTimeout(app, 0.25f);

  AXUIElementRef window = NULL;
  AXUIElementRef button = NULL;
  AXError app_error = kAXErrorNoValue;
  AXError system_error = kAXErrorNoValue;
  CFIndex app_window_count = 0;
  CFIndex app_owned_count = 0;
  CFIndex app_exact_count = 0;
  CFIndex system_window_count = 0;
  CFIndex system_owned_count = 0;
  CFIndex system_exact_count = 0;
  WindowSearchDiagnostics app_diagnostics = {0};
  WindowSearchDiagnostics system_diagnostics = {0};
  WindowSearchDiagnostics app_tree_diagnostics = {0};
  WindowSearchDiagnostics system_tree_diagnostics = {0};
  WindowSearchDiagnostics focused_diagnostics = {0};
  WindowSearchDiagnostics main_diagnostics = {0};
  bool window_title_matched = false;
  char last_window_title[512] = "";
  double deadline = monotonic_seconds() + 15.0;
  while (monotonic_seconds() < deadline && window == NULL) {
    if (kill(pid, 0) != 0 && errno == ESRCH) {
      fail("sample process exited before its AX window appeared",
           kAXErrorNoValue);
    }
    window = find_window(
        app, pid, expected_title, &app_error, &app_window_count,
        &app_owned_count, &app_exact_count, &system_error,
        &system_window_count, &system_owned_count, &system_exact_count,
        last_window_title, sizeof(last_window_title), &window_title_matched,
        &app_diagnostics, &system_diagnostics, &app_tree_diagnostics,
        &system_tree_diagnostics, &focused_diagnostics, &main_diagnostics,
        deadline);
    if (window == NULL) {
      struct timespec pause = {.tv_sec = 0, .tv_nsec = 20000000};
      nanosleep(&pause, NULL);
    }
  }
  if (window == NULL) {
    fprintf(stderr,
            "sample AXWindow did not appear for the exact launched PID; "
            "app AXWindows error=%d count=%ld owned=%ld exact-title=%ld; "
            "system AXWindows error=%d count=%ld owned=%ld exact-title=%ld; "
            "app entries=%ld AX=%ld other=%ld PID-readable=%ld matching=%ld "
            "last-PID=%d PID-error=%d role-readable=%ld window-role=%ld "
            "last-role=%s role-error=%d type=%lu; "
            "app AXChildren visited=%ld PID-readable=%ld matching=%ld "
            "role-readable=%ld window-role=%ld last-PID=%d last-role=%s; "
            "system entries=%ld AX=%ld other=%ld PID-readable=%ld matching=%ld "
            "last-PID=%d PID-error=%d role-readable=%ld window-role=%ld "
            "last-role=%s role-error=%d type=%lu; "
            "system AXChildren visited=%ld PID-readable=%ld matching=%ld "
            "role-readable=%ld window-role=%ld last-PID=%d last-role=%s; "
            "focusedWindow error=%d AX=%ld PID=%ld role=%ld window-role=%ld exact=%ld; "
            "mainWindow error=%d AX=%ld PID=%ld role=%ld window-role=%ld exact=%ld; "
            "last readable title=%s requested=%s\n",
            (int)app_error, (long)app_window_count, (long)app_owned_count,
            (long)app_exact_count, (int)system_error,
            (long)system_window_count, (long)system_owned_count,
            (long)system_exact_count, (long)app_diagnostics.entries,
            (long)app_diagnostics.accessibility_elements,
            (long)app_diagnostics.other_elements,
            (long)app_diagnostics.pid_readable,
            (long)app_diagnostics.matching_pid,
            (int)app_diagnostics.last_pid,
            (int)app_diagnostics.last_pid_error,
            (long)app_diagnostics.role_readable,
            (long)app_diagnostics.window_roles,
            app_diagnostics.last_role[0] ? app_diagnostics.last_role : "<none>",
            (int)app_diagnostics.last_role_error,
            app_diagnostics.last_type_id,
            (long)app_tree_diagnostics.accessibility_elements,
            (long)app_tree_diagnostics.pid_readable,
            (long)app_tree_diagnostics.matching_pid,
            (long)app_tree_diagnostics.role_readable,
            (long)app_tree_diagnostics.window_roles,
            (int)app_tree_diagnostics.last_pid,
            app_tree_diagnostics.last_role[0]
                ? app_tree_diagnostics.last_role
                : "<none>",
            (long)system_diagnostics.entries,
            (long)system_diagnostics.accessibility_elements,
            (long)system_diagnostics.other_elements,
            (long)system_diagnostics.pid_readable,
            (long)system_diagnostics.matching_pid,
            (int)system_diagnostics.last_pid,
            (int)system_diagnostics.last_pid_error,
            (long)system_diagnostics.role_readable,
            (long)system_diagnostics.window_roles,
            system_diagnostics.last_role[0]
                ? system_diagnostics.last_role
                : "<none>",
            (int)system_diagnostics.last_role_error,
            system_diagnostics.last_type_id,
            (long)system_tree_diagnostics.accessibility_elements,
            (long)system_tree_diagnostics.pid_readable,
            (long)system_tree_diagnostics.matching_pid,
            (long)system_tree_diagnostics.role_readable,
            (long)system_tree_diagnostics.window_roles,
            (int)system_tree_diagnostics.last_pid,
            system_tree_diagnostics.last_role[0]
                ? system_tree_diagnostics.last_role
                : "<none>",
            (int)focused_diagnostics.attribute_error,
            (long)focused_diagnostics.accessibility_elements,
            (long)focused_diagnostics.matching_pid,
            (long)focused_diagnostics.role_readable,
            (long)focused_diagnostics.window_roles,
            (long)focused_diagnostics.exact_titles,
            (int)main_diagnostics.attribute_error,
            (long)main_diagnostics.accessibility_elements,
            (long)main_diagnostics.matching_pid,
            (long)main_diagnostics.role_readable,
            (long)main_diagnostics.window_roles,
            (long)main_diagnostics.exact_titles,
            last_window_title[0] ? last_window_title : "<none>",
            expected_title);
    return 1;
  }
  (void)AXUIElementSetMessagingTimeout(window, 0.25f);
  char observed_window_title[512] = "";
  (void)copy_string_attribute(window, kAXTitleAttribute,
                              observed_window_title,
                              sizeof(observed_window_title), NULL);

  deadline = monotonic_seconds() + 15.0;
  unsigned visited_nodes = 0;
  while (monotonic_seconds() < deadline && button == NULL) {
    visited_nodes = 0;
    button = find_button(window, expected_button, 0, &visited_nodes, deadline);
    if (button == NULL) {
      struct timespec pause = {.tv_sec = 0, .tv_nsec = 20000000};
      nanosleep(&pause, NULL);
    }
  }
  if (button == NULL) {
    fail("Yami sample Button did not appear in the AX tree", kAXErrorNoValue);
  }
  (void)AXUIElementSetMessagingTimeout(button, 0.25f);

  AXError action_error = kAXErrorSuccess;
  if (!has_press_action(button, &action_error)) {
    fail("Yami sample Button does not advertise AXPress", action_error);
  }
  AXError enabled_error = kAXErrorSuccess;
  if (!button_enabled(button, &enabled_error)) {
    fail("Yami sample Button is not enabled in its live snapshot",
         enabled_error);
  }
  int activation_count = -1;
  if (!button_help_count(button, &activation_count) || activation_count != 0) {
    fail("Yami sample Button did not publish the owner count 0",
         kAXErrorNoValue);
  }

  AXError error = AXUIElementPerformAction(button, kAXPressAction);
  if (error != kAXErrorSuccess) {
    fail("AXPress did not reach the Yami sample Button", error);
  }
  deadline = monotonic_seconds() + 5.0;
  while (monotonic_seconds() < deadline) {
    if (button_help_count(button, &activation_count) && activation_count == 1) {
      break;
    }
    struct timespec pause = {.tv_sec = 0, .tv_nsec = 20000000};
    nanosleep(&pause, NULL);
  }
  if (activation_count != 1) {
    fail("AXPress did not publish the exact Yami App Entity count 1",
         kAXErrorNoValue);
  }

  close_window(pid, window);
  printf("{\"pid\":%d,\"requestedWindowTitle\":", (int)pid);
  print_json_string(expected_title);
  fputs(",\"observedWindowTitle\":", stdout);
  print_json_string(observed_window_title);
  fputs(",\"windowTitleMatched\":", stdout);
  fputs(window_title_matched ? "true" : "false", stdout);
  fputs(",\"bundleID\":", stdout);
  print_json_string(expected_bundle_id);
  fputs(",\"bundlePath\":", stdout);
  print_json_string(expected_bundle_path);
  fputs(",\"button\":", stdout);
  print_json_string(expected_button);
  fputs(",\"initialCount\":0,\"finalCount\":1,"
        "\"action\":\"AXPress\",\"closeRequested\":true}\n",
        stdout);
  CFRelease(button);
  CFRelease(window);
  CFRelease(app);
  return 0;
}
