#!/bin/sh
set -eu

if [ -z "${YAMI_NATIVE_MODULE_ROOT:-}" ]; then
  echo "YAMI_NATIVE_MODULE_ROOT must be set by native_ui_workspace.sh" >&2
  exit 2
fi

if command -v python3 >/dev/null 2>&1; then
  python_bin=python3
elif command -v python >/dev/null 2>&1; then
  python_bin=python
else
  echo "Python 3 is required for native frame verifier tests" >&2
  exit 2
fi

PYTHONDONTWRITEBYTECODE=1 "$python_bin" "$YAMI_NATIVE_YAMI_ROOT/tests/native-ui/test_drive_native_ui.py"

moon test "$YAMI_NATIVE_MODULE_ROOT/components" \
  --target native --deny-warn --no-parallelize
moon test "$YAMI_NATIVE_MODULE_ROOT/sample" \
  --target native --deny-warn --no-parallelize
