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

static int input_preflight(bool emit_report) {
  bool on_console = false;
  bool session_locked = true;
  bool on_console_known = false;
  bool locked_known = false;
  CFDictionaryRef session = CGSessionCopyCurrentDictionary();
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
  bool accessibility = AXIsProcessTrusted();
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
                                       CGRect *out_bounds) {
  CFArrayRef windows = CGWindowListCopyWindowInfo(
      kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
      kCGNullWindowID);
  if (windows == NULL) return false;
  CFIndex matches = 0;
  for (CFIndex index = 0; index < CFArrayGetCount(windows); index++) {
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
  return matches == 1;
}

static bool target_is_frontmost(pid_t pid) {
  NSRunningApplication *frontmost = [[NSWorkspace sharedWorkspace] frontmostApplication];
  return frontmost != nil && frontmost.processIdentifier == pid;
}

static bool copy_focused_target_window(pid_t pid, const char *title,
                                       AXUIElementRef *out_app,
                                       AXUIElementRef *out_window) {
  AXUIElementRef app = AXUIElementCreateApplication(pid);
  if (app == NULL) return false;
  (void)AXUIElementSetMessagingTimeout(app, 0.25f);
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
      monotonic_seconds() + 3.0);
  if (exact == NULL || !title_matched) {
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
  if (!focused_matches) {
    CFRelease(exact);
    CFRelease(app);
    return false;
  }
  *out_app = app;
  *out_window = exact;
  return true;
}

static bool ax_hit_is_inside(AXUIElementRef hit, pid_t pid,
                             AXUIElementRef button) {
  AXUIElementRef current = (AXUIElementRef)CFRetain(hit);
  bool inside = false;
  for (unsigned depth = 0; depth < 16 && current != NULL; depth++) {
    pid_t owner = 0;
    if (AXUIElementGetPid(current, &owner) != kAXErrorSuccess || owner != pid) break;
    if (CFEqual(current, button)) {
      inside = true;
      break;
    }
    CFTypeRef raw_parent = NULL;
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
  return inside;
}

static bool topmost_window_owns_point(pid_t pid, const char *title,
                                     CGPoint point, CGWindowID expected_id) {
  CFArrayRef windows = CGWindowListCopyWindowInfo(
      kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
      kCGNullWindowID);
  if (windows == NULL) return false;
  bool owned = false;
  for (CFIndex index = 0; index < CFArrayGetCount(windows); index++) {
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
  return owned;
}

static bool copy_ax_point(AXUIElementRef element, CFStringRef attribute,
                          AXValueType type, CGPoint *out_point,
                          CGSize *out_size) {
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
  return ok;
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
  if (input_preflight(false) != 0) return 1;
  if (!target_is_frontmost(pid)) {
    fprintf(stderr, "refusing host input because the exact sample PID is not frontmost\n");
    return 1;
  }
  AXUIElementRef app = NULL;
  AXUIElementRef window = NULL;
  if (!copy_focused_target_window(pid, title, &app, &window)) {
    fprintf(stderr, "refusing host input because the exact titled AXWindow is not uniquely focused\n");
    return 1;
  }
  CGWindowID window_id = 0;
  CGRect window_bounds = CGRectZero;
  if (!copy_visible_target_window(pid, title, &window_id, &window_bounds)) {
    CFRelease(window);
    CFRelease(app);
    fprintf(stderr, "refusing host input because the exact titled sample window is not uniquely visible\n");
    return 1;
  }
  if (!click) {
    if (input_preflight(false) != 0 || !target_is_frontmost(pid)) {
      CFRelease(window);
      CFRelease(app);
      fprintf(stderr, "refusing Escape because the session or frontmost identity changed\n");
      return 1;
    }
    CGEventRef down = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)53, true);
    CGEventRef up = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)53, false);
    if (down == NULL || up == NULL) {
      if (down != NULL) CFRelease(down);
      if (up != NULL) CFRelease(up);
      CFRelease(window);
      CFRelease(app);
      fprintf(stderr, "could not create Escape events\n");
      return 1;
    }
    CGEventPost(kCGHIDEventTap, down);
    CGEventPost(kCGHIDEventTap, up);
    CFRelease(down);
    CFRelease(up);
    printf("{\"action\":\"CGEventPost(kCGHIDEventTap) Escape\",\"pid\":%d,\"windowTitle\":",
           (int)pid);
    print_json_string(title);
    fputs("}\n", stdout);
    CFRelease(window);
    CFRelease(app);
    return 0;
  }
  const char *button_name = argv[4];
  char *width_end = NULL, *height_end = NULL;
  double expected_width = strtod(argv[5], &width_end);
  double expected_height = strtod(argv[6], &height_end);
  if (width_end == argv[5] || *width_end != '\0' || !isfinite(expected_width) ||
      expected_width <= 0 || height_end == argv[6] || *height_end != '\0' ||
      !isfinite(expected_height) || expected_height <= 0) {
    CFRelease(window);
    CFRelease(app);
    fprintf(stderr, "invalid expected Button dimensions\n");
    return 2;
  }
  unsigned visited = 0;
  AXUIElementRef button = find_button(window, button_name, 0, &visited,
                                      monotonic_seconds() + 2.0);
  if (button == NULL) {
    CFRelease(window);
    CFRelease(app);
    fprintf(stderr, "refusing host click because the named sample AXButton is absent\n");
    return 1;
  }
  CGPoint position = CGPointZero;
  CGSize size = CGSizeZero;
  int activation_count = -1;
  AXError enabled_error = kAXErrorSuccess;
  bool valid_button = button_enabled(button, &enabled_error) &&
                      button_help_count(button, &activation_count) &&
                      activation_count == 0 &&
                      copy_ax_point(button, kAXPositionAttribute,
                                    kAXValueCGPointType, &position, NULL) &&
                      copy_ax_point(button, kAXSizeAttribute,
                                    kAXValueCGSizeType, NULL, &size) &&
                      fabs(size.width - expected_width) <= 1.0 &&
                      fabs(size.height - expected_height) <= 1.0;
  CGPoint point = CGPointMake(position.x + size.width / 2.0,
                              position.y + size.height / 2.0);
  if (!valid_button || !CGRectContainsPoint(window_bounds, point) ||
      !topmost_window_owns_point(pid, title, point, window_id)) {
    CFRelease(button);
    CFRelease(window);
    CFRelease(app);
    fprintf(stderr, "refusing host click because the enabled Button frame is invalid, occluded, or not in the selected window\n");
    return 1;
  }
  AXUIElementRef system = AXUIElementCreateSystemWide();
  AXUIElementRef hit = NULL;
  AXError hit_error = system == NULL ? kAXErrorFailure :
      AXUIElementCopyElementAtPosition(system, (float)point.x, (float)point.y, &hit);
  bool point_owner_matches = hit_error == kAXErrorSuccess && hit != NULL &&
      ax_hit_is_inside(hit, pid, button);
  if (hit != NULL) CFRelease(hit);
  if (system != NULL) CFRelease(system);
  if (!point_owner_matches || !target_is_frontmost(pid)) {
    CFRelease(button);
    CFRelease(window);
    CFRelease(app);
    fprintf(stderr, "refusing host click because AX point ownership or frontmost identity changed\n");
    return 1;
  }
  CGEventRef down = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown,
                                            point, kCGMouseButtonLeft);
  CGEventRef up = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp,
                                          point, kCGMouseButtonLeft);
  if (down == NULL || up == NULL) {
    if (down != NULL) CFRelease(down);
    if (up != NULL) CFRelease(up);
    CFRelease(button);
    CFRelease(window);
    CFRelease(app);
    fprintf(stderr, "could not create mouse click events\n");
    return 1;
  }
  if (input_preflight(false) != 0 || !target_is_frontmost(pid)) {
    CFRelease(down);
    CFRelease(up);
    CFRelease(button);
    CFRelease(window);
    CFRelease(app);
    fprintf(stderr, "refusing host click because the session or frontmost identity changed\n");
    return 1;
  }
  CGEventPost(kCGHIDEventTap, down);
  CGEventPost(kCGHIDEventTap, up);
  CFRelease(down);
  CFRelease(up);
  printf("{\"action\":\"CGEventPost(kCGHIDEventTap) left click\",\"pid\":%d,\"windowTitle\":",
         (int)pid);
  print_json_string(title);
  fputs(",\"button\":", stdout);
  print_json_string(button_name);
  printf(",\"windowNumber\":%u,\"point\":{\"x\":%.3f,\"y\":%.3f},\"axHitWithinButton\":true}\n",
         (unsigned int)window_id, point.x, point.y);
  CFRelease(button);
  CFRelease(window);
  CFRelease(app);
  return 0;
}

int main(int argc, char **argv) {
  if (argc == 2 && strcmp(argv[1], "--preflight") == 0) {
    return input_preflight(true);
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
