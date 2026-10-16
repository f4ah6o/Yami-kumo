#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>

#define COMMAND_LINE_CAPACITY 32768

static BOOL append_char(wchar_t *buffer, size_t *length, wchar_t value) {
  if (*length + 1 >= COMMAND_LINE_CAPACITY) {
    return FALSE;
  }
  buffer[(*length)++] = value;
  buffer[*length] = L'\0';
  return TRUE;
}

static BOOL append_backslashes(wchar_t *buffer, size_t *length, size_t count) {
  if (count >= COMMAND_LINE_CAPACITY - *length) {
    return FALSE;
  }
  while (count-- > 0) {
    buffer[(*length)++] = L'\\';
  }
  buffer[*length] = L'\0';
  return TRUE;
}

/* Quote one argument using the Windows C runtime command-line rules. */
static BOOL append_argument(wchar_t *buffer, size_t *length,
                            const wchar_t *argument) {
  const wchar_t *cursor = argument;
  if (!append_char(buffer, length, L'"')) {
    return FALSE;
  }
  while (*cursor != L'\0') {
    size_t backslashes = 0;
    while (*cursor == L'\\') {
      backslashes++;
      cursor++;
    }
    if (*cursor == L'"') {
      if (backslashes > (SIZE_MAX - 1) / 2 ||
          !append_backslashes(buffer, length, backslashes * 2 + 1) ||
          !append_char(buffer, length, L'"')) {
        return FALSE;
      }
      cursor++;
    } else if (*cursor == L'\0') {
      if (backslashes > SIZE_MAX / 2 ||
          !append_backslashes(buffer, length, backslashes * 2)) {
        return FALSE;
      }
    } else {
      if (!append_backslashes(buffer, length, backslashes) ||
          !append_char(buffer, length, *cursor)) {
        return FALSE;
      }
      cursor++;
    }
  }
  return append_char(buffer, length, L'"');
}

static BOOL duplicate_standard_handle(DWORD kind, HANDLE *duplicate) {
  HANDLE source = GetStdHandle(kind);
  *duplicate = NULL;
  if (source == NULL || source == INVALID_HANDLE_VALUE) {
    return TRUE;
  }
  return DuplicateHandle(GetCurrentProcess(), source, GetCurrentProcess(),
                         duplicate, 0, TRUE, DUPLICATE_SAME_ACCESS);
}

static void print_windows_error(const wchar_t *operation, DWORD error) {
  fwprintf(stderr, L"python3 forwarder: %ls failed (Windows error %lu)\n",
           operation, (unsigned long)error);
}

int wmain(void) {
  int argument_count = 0;
  LPWSTR *arguments = CommandLineToArgvW(GetCommandLineW(), &argument_count);
  if (arguments == NULL || argument_count < 1) {
    print_windows_error(L"CommandLineToArgvW", GetLastError());
    ExitProcess(2);
  }

  DWORD python_path_length =
      GetEnvironmentVariableW(L"YAMI_SELECTED_PYTHON_PATH", NULL, 0);
  if (python_path_length == 0) {
    fwprintf(stderr,
             L"python3 forwarder: YAMI_SELECTED_PYTHON_PATH is not set\n");
    LocalFree(arguments);
    ExitProcess(2);
  }
  wchar_t *python_path =
      (wchar_t *)calloc((size_t)python_path_length, sizeof(wchar_t));
  if (python_path == NULL ||
      GetEnvironmentVariableW(L"YAMI_SELECTED_PYTHON_PATH", python_path,
                              python_path_length) == 0) {
    print_windows_error(L"reading YAMI_SELECTED_PYTHON_PATH", GetLastError());
    free(python_path);
    LocalFree(arguments);
    ExitProcess(2);
  }

  wchar_t *command_line =
      (wchar_t *)calloc(COMMAND_LINE_CAPACITY, sizeof(wchar_t));
  size_t command_line_length = 0;
  BOOL command_line_ok =
      command_line != NULL && append_argument(command_line,
                                               &command_line_length,
                                               python_path);
  for (int index = 1; command_line_ok && index < argument_count; index++) {
    command_line_ok = append_char(command_line, &command_line_length, L' ') &&
                      append_argument(command_line, &command_line_length,
                                      arguments[index]);
  }
  if (!command_line_ok) {
    fwprintf(stderr, L"python3 forwarder: argument list is too long\n");
    free(command_line);
    free(python_path);
    LocalFree(arguments);
    ExitProcess(2);
  }

  HANDLE child_stdin = NULL;
  HANDLE child_stdout = NULL;
  HANDLE child_stderr = NULL;
  if (!duplicate_standard_handle(STD_INPUT_HANDLE, &child_stdin) ||
      !duplicate_standard_handle(STD_OUTPUT_HANDLE, &child_stdout) ||
      !duplicate_standard_handle(STD_ERROR_HANDLE, &child_stderr)) {
    print_windows_error(L"DuplicateHandle", GetLastError());
    if (child_stdin != NULL) {
      CloseHandle(child_stdin);
    }
    if (child_stdout != NULL) {
      CloseHandle(child_stdout);
    }
    if (child_stderr != NULL) {
      CloseHandle(child_stderr);
    }
    free(command_line);
    free(python_path);
    LocalFree(arguments);
    ExitProcess(2);
  }

  STARTUPINFOW startup;
  PROCESS_INFORMATION process;
  ZeroMemory(&startup, sizeof(startup));
  ZeroMemory(&process, sizeof(process));
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdInput = child_stdin;
  startup.hStdOutput = child_stdout;
  startup.hStdError = child_stderr;

  BOOL started = CreateProcessW(python_path, command_line, NULL, NULL, TRUE,
                                CREATE_UNICODE_ENVIRONMENT, NULL, NULL,
                                &startup, &process);
  DWORD start_error = started ? ERROR_SUCCESS : GetLastError();
  if (child_stdin != NULL) {
    CloseHandle(child_stdin);
  }
  if (child_stdout != NULL) {
    CloseHandle(child_stdout);
  }
  if (child_stderr != NULL) {
    CloseHandle(child_stderr);
  }
  free(command_line);
  free(python_path);
  LocalFree(arguments);
  if (!started) {
    print_windows_error(L"CreateProcessW", start_error);
    ExitProcess(127);
  }

  DWORD wait_result = WaitForSingleObject(process.hProcess, INFINITE);
  DWORD exit_code = 1;
  if (wait_result != WAIT_OBJECT_0 ||
      !GetExitCodeProcess(process.hProcess, &exit_code)) {
    DWORD error = GetLastError();
    print_windows_error(L"waiting for Python", error);
    TerminateProcess(process.hProcess, 1);
    WaitForSingleObject(process.hProcess, INFINITE);
    exit_code = 1;
  }
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  ExitProcess(exit_code);
}
