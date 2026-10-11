#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreFoundation/CoreFoundation.h>

#include <errno.h>
#include <limits.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

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

static bool copy_string_attribute(AXUIElementRef element, CFStringRef name,
                                  char *buffer, size_t capacity,
                                  AXError *out_error) {
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
    (void)AXUIElementSetMessagingTimeout(candidate, 0.25f);
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
  (void)AXUIElementSetMessagingTimeout(element, 0.25f);

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
  (void)AXUIElementSetMessagingTimeout(candidate, 0.25f);
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
  (void)AXUIElementSetMessagingTimeout(system, 0.25f);
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
  (void)AXUIElementSetMessagingTimeout(parent, 0.25f);
  CFTypeRef raw_role = NULL;
  AXError role_error = AXUIElementCopyAttributeValue(
      parent, kAXRoleAttribute, &raw_role);
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
  CFArrayRef children = (CFArrayRef)raw_children;
  AXUIElementRef result = NULL;
  for (CFIndex index = 0; index < CFArrayGetCount(children); index++) {
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

int main(int argc, char **argv) {
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
