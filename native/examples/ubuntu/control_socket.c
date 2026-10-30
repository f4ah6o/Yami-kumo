#define _GNU_SOURCE
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <poll.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

/* Single-threaded, opt-in control endpoint. No text or IME transport here. */
static int listener = -1;
static int client = -1;
static int64_t requested_sequence = 0;
static char control_dir[sizeof("/tmp/yami-settings-XXXXXX")];
static char control_path[sizeof(((struct sockaddr_un *)0)->sun_path)];

int gpui_settings_control_open(void) {
  if (listener >= 0) return -1;
  /* mkdtemp replaces the template in place. A later controlled session in
   * the same process must receive a fresh directory, never the prior path. */
  memcpy(control_dir, "/tmp/yami-settings-XXXXXX", sizeof(control_dir));
  control_path[0] = '\0';
  if (!mkdtemp(control_dir)) return -1;
  if (snprintf(control_path, sizeof(control_path), "%s/control.sock", control_dir) >= (int)sizeof(control_path)) {
    rmdir(control_dir); return -1;
  }
  listener = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
  if (listener < 0) { rmdir(control_dir); return -1; }
  struct sockaddr_un address = { .sun_family = AF_UNIX };
  memcpy(address.sun_path, control_path, strlen(control_path) + 1);
  if (bind(listener, (struct sockaddr *)&address, sizeof(address)) < 0 || listen(listener, 4) < 0) {
    close(listener); listener = -1; unlink(control_path); rmdir(control_dir); return -1;
  }
  printf("YAMI_SETTINGS_CONTROL {\"path\":\"%s\",\"state\":\"open\"}\n", control_path);
  fflush(stdout);
  return 0;
}

const char *gpui_settings_control_path(void) { return control_path; }

/* Return one command byte, zero on timeout, or -1 on fatal listener error. */
int gpui_settings_control_next(int timeout_ms) {
  if (listener < 0 || client >= 0 || timeout_ms < 0 || timeout_ms > 30000) return -1;
  requested_sequence = 0;
  struct pollfd p = { .fd = listener, .events = POLLIN };
  int ready = poll(&p, 1, timeout_ms);
  if (ready == 0 || (ready < 0 && errno == EINTR)) return 0;
  if (ready < 0 || !(p.revents & POLLIN)) return -1;
  client = accept4(listener, NULL, NULL, SOCK_CLOEXEC);
  if (client < 0) return errno == EINTR ? 0 : -1;
  struct ucred credentials;
  socklen_t n = sizeof(credentials);
  if (getsockopt(client, SOL_SOCKET, SO_PEERCRED, &credentials, &n) < 0 ||
      n != sizeof(credentials) || credentials.uid != geteuid()) {
    close(client); client = -1; return 0;
  }
  p.fd = client; p.events = POLLIN | POLLRDHUP; p.revents = 0;
  ready = poll(&p, 1, 1000);
  unsigned char command;
  if (ready <= 0 || (p.revents & (POLLHUP | POLLRDHUP | POLLERR | POLLNVAL)) ||
      !(p.revents & POLLIN) || read(client, &command, 1) != 1) {
    close(client); client = -1; return 0;
  }
  if (command == 'a') {
    /* Exactly one positive portable sequence prevents replay onto the next
     * record if the client loses the result and retries its request. */
    uint64_t value = 0;
    for (int i = 0; i < 8; ++i) {
      p.revents = 0;
      ready = poll(&p, 1, 1000);
      unsigned char byte;
      if (ready <= 0 || (p.revents & (POLLHUP | POLLRDHUP | POLLERR | POLLNVAL)) ||
          !(p.revents & POLLIN) || read(client, &byte, 1) != 1) {
        close(client); client = -1; return 0;
      }
      value = (value << 8) | byte;
    }
    if (value == 0 || value > INT64_MAX) { close(client); client = -1; return 0; }
    requested_sequence = (int64_t)value;
  }
  return command;
}

int64_t gpui_settings_control_sequence(void) { return requested_sequence; }

/* One byte per request. A disconnected client does not alter ownership. */
void gpui_settings_control_reply(int code) {
  if (client >= 0) {
    unsigned char value = (unsigned char)code;
    (void)send(client, &value, 1, MSG_NOSIGNAL);
    close(client); client = -1;
  }
}

void gpui_settings_control_reply_sequence(int code, int64_t sequence) {
  if (client >= 0) {
    unsigned char bytes[9] = { (unsigned char)code };
    uint64_t value = (uint64_t)sequence;
    for (int i = 8; i > 0; --i) { bytes[i] = (unsigned char)value; value >>= 8; }
    (void)send(client, bytes, sizeof(bytes), MSG_NOSIGNAL);
    close(client); client = -1;
  }
}

void gpui_settings_control_close(void) {
  if (client >= 0) { close(client); client = -1; }
  if (listener >= 0) { close(listener); listener = -1; unlink(control_path); rmdir(control_dir); }
}

/* Back off on an unexpected listener failure without destroying the owner. */
void gpui_settings_control_backoff(void) { (void)poll(NULL, 0, 1000); }
