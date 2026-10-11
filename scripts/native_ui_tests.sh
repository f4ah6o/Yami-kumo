#!/bin/sh
set -eu

if [ -z "${YAMI_NATIVE_MODULE_ROOT:-}" ]; then
  echo "YAMI_NATIVE_MODULE_ROOT must be set by native_ui_workspace.sh" >&2
  exit 2
fi

python_bin=${YAMI_PYTHON_BIN:-}
if [ -z "$python_bin" ]; then
  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 &&
      "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' >/dev/null 2>&1; then
      python_bin=$candidate
      break
    fi
  done
fi
if [ -z "$python_bin" ]; then
  echo "Python 3.11 or newer is required for native frame verifier tests" >&2
  exit 2
fi

PYTHONDONTWRITEBYTECODE=1 "$python_bin" "$YAMI_NATIVE_YAMI_ROOT/tests/native-ui/test_drive_native_ui.py"

moon test "$YAMI_NATIVE_MODULE_ROOT/components" \
  --target native --deny-warn --no-parallelize
moon test "$YAMI_NATIVE_MODULE_ROOT/sample" \
  --target native --deny-warn --no-parallelize
moon test "$YAMI_NATIVE_MODULE_ROOT/examples/common" \
  --target native --deny-warn --no-parallelize
