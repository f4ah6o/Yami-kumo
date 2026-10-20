/* Test-only macOS helper for the native text-field IME proof.
 *
 * Subcommands:
 *   select-japanese          print the selected source id as JSON
 *   restore <source-id>      reselect a previously selected source
 *   activate <pid>           activate the application
 *   type <pid> <scenario>    post keycodes; scenarios: tab, romaji, enter, escape
 *   probe                    print on-screen window metadata as JSON
 *
 * The helper posts synthetic HID events with CGEventPostToPid. It does not
 * replace the live input method: the selected system input source processes the
 * keys. Accessibility authorization is required for posting and is reported.
 */
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void fail(const char *message) {
  fprintf(stderr, "%s\n", message);
  exit(1);
}

static void post_key(pid_t pid, CGKeyCode code) {
  CGEventRef down = CGEventCreateKeyboardEvent(NULL, code, true);
  CGEventRef up = CGEventCreateKeyboardEvent(NULL, code, false);
  if (!down || !up) fail("cannot create a key event");
  CGEventPostToPid(pid, down);
  usleep(30000);
  CGEventPostToPid(pid, up);
  CFRelease(down);
  CFRelease(up);
  usleep(90000);
}

static NSString *current_source_id(void) {
  TISInputSourceRef source = TISCopyCurrentKeyboardInputSource();
  if (!source) return nil;
  CFTypeRef value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
  NSString *identifier = value ? (__bridge NSString *)value : nil;
  CFRelease(source);
  return identifier;
}

static BOOL select_japanese(void) {
  NSArray *sources = CFBridgingRelease(TISCreateInputSourceList(NULL, false));
  for (id candidate in sources) {
    TISInputSourceRef source = (__bridge TISInputSourceRef)candidate;
    CFTypeRef value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
    if (!value) continue;
    NSString *identifier = (__bridge NSString *)value;
    if ([identifier containsString:@"Kotoeri"] ||
        [identifier containsString:@"Japanese"] ||
        [identifier containsString:@"mozc"] ||
        [identifier containsString:@"azooKey"] ||
        [identifier containsString:@"GoogleJapaneseInput"]) {
      if (TISSelectInputSource(source) == noErr) return YES;
    }
  }
  return NO;
}

static BOOL restore_source(NSString *identifier) {
  if (identifier.length == 0) return NO;
  NSArray *sources = CFBridgingRelease(TISCreateInputSourceList(NULL, false));
  for (id candidate in sources) {
    TISInputSourceRef source = (__bridge TISInputSourceRef)candidate;
    CFTypeRef value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
    if (!value) continue;
    if ([(__bridge NSString *)value isEqualToString:identifier]) {
      return TISSelectInputSource(source) == noErr;
    }
  }
  return NO;
}

static NSString *json_escape(NSString *value) {
  NSMutableString *out = [NSMutableString string];
  for (NSUInteger index = 0; index < value.length; index++) {
    unichar c = [value characterAtIndex:index];
    if (c == '"' || c == '\\') {
      [out appendFormat:@"\\%C", c];
    } else if (c < 0x20) {
      [out appendFormat:@"\\u%04x", c];
    } else {
      [out appendFormat:@"%C", c];
    }
  }
  return out;
}

static void command_select(void) {
  NSString *previous = current_source_id();
  if (!select_japanese()) {
    printf("{\"status\":\"no-japanese-source\",\"previous\":\"%s\"}\n",
           previous ? json_escape(previous).UTF8String : "");
    exit(2);
  }
  NSString *selected = current_source_id();
  printf("{\"status\":\"selected\",\"previous\":\"%s\",\"selected\":\"%s\"}\n",
         previous ? json_escape(previous).UTF8String : "",
         selected ? json_escape(selected).UTF8String : "");
}

static void command_activate(pid_t pid) {
  NSRunningApplication *app =
      [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
  if (!app) fail("application is not running");
  if (![app activateWithOptions:NSApplicationActivateAllWindows])
    fail("application activation was refused");
  usleep(300000);
  printf("{\"status\":\"activated\",\"pid\":%d}\n", pid);
}

static void command_type(pid_t pid, const char *scenario) {
  if (!AXIsProcessTrusted()) {
    printf("{\"status\":\"unsupported\",\"reason\":\"accessibility-not-trusted\"}\n");
    exit(77);
  }
  if (strcmp(scenario, "tab") == 0) {
    post_key(pid, 48);
  } else if (strcmp(scenario, "romaji") == 0) {
    const CGKeyCode keys[] = {45, 34, 4, 31, 45, 5, 31}; /* n i h o n g o */
    for (size_t index = 0; index < sizeof(keys) / sizeof(keys[0]); index++)
      post_key(pid, keys[index]);
  } else if (strcmp(scenario, "space") == 0) {
    post_key(pid, 49);
  } else if (strcmp(scenario, "enter") == 0) {
    post_key(pid, 36);
  } else if (strcmp(scenario, "escape") == 0) {
    post_key(pid, 53);
  } else {
    fail("unknown key scenario");
  }
  printf("{\"status\":\"typed\",\"scenario\":\"%s\"}\n", scenario);
}

static void command_probe(void) {
  CFArrayRef windows = CGWindowListCopyWindowInfo(
      kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
      kCGNullWindowID);
  if (!windows) fail("cannot enumerate windows");
  printf("{\"status\":\"windows\",\"windows\":[");
  CFIndex count = CFArrayGetCount(windows);
  bool first = true;
  for (CFIndex index = 0; index < count; index++) {
    NSDictionary *window = (__bridge NSDictionary *)CFArrayGetValueAtIndex(windows, index);
    NSNumber *pid = window[(id)kCGWindowOwnerPID];
    NSString *owner = window[(id)kCGWindowOwnerName];
    NSDictionary *bounds = window[(id)kCGWindowBounds];
    NSNumber *layer = window[(id)kCGWindowLayer];
    if (!pid || !bounds) continue;
    if (!first) printf(",");
    first = false;
    printf("{\"pid\":%d,\"owner\":\"%s\",\"layer\":%d,"
           "\"x\":%g,\"y\":%g,\"width\":%g,\"height\":%g}",
           pid.intValue, owner ? json_escape(owner).UTF8String : "",
           layer ? layer.intValue : 0,
           [bounds[@"X"] doubleValue], [bounds[@"Y"] doubleValue],
           [bounds[@"Width"] doubleValue], [bounds[@"Height"] doubleValue]);
  }
  printf("]}\n");
  CFRelease(windows);
}

int main(int argc, char **argv) {
  @autoreleasepool {
    if (argc < 2) fail("usage: macos_ime_helper <command>");
    if (strcmp(argv[1], "select-japanese") == 0) {
      command_select();
    } else if (strcmp(argv[1], "restore") == 0 && argc >= 3) {
      if (!restore_source([NSString stringWithUTF8String:argv[2]]))
        fail("cannot restore the input source");
      printf("{\"status\":\"restored\"}\n");
    } else if (strcmp(argv[1], "activate") == 0 && argc >= 3) {
      command_activate((pid_t)atoi(argv[2]));
    } else if (strcmp(argv[1], "type") == 0 && argc >= 4) {
      command_type((pid_t)atoi(argv[2]), argv[3]);
    } else if (strcmp(argv[1], "probe") == 0) {
      command_probe();
    } else {
      fail("unknown command");
    }
  }
  return 0;
}
