#!/bin/sh
set -eu
: "${YAMI_NATIVE_MODULE_ROOT:?must be invoked through native_ui_workspace.sh}"
: "${YAMI_NATIVE_YAMI_ROOT:?must be invoked through native_ui_workspace.sh}"
python_bin=${YAMI_PYTHON_BIN:-python3}
PYTHONDONTWRITEBYTECODE=1 "$python_bin" "$YAMI_NATIVE_YAMI_ROOT/tests/shared-ui/test_native_driver.py"
PYTHONDONTWRITEBYTECODE=1 "$python_bin" "$YAMI_NATIVE_YAMI_ROOT/tests/shared-ui/test_palette_oracle.py"
for package in ui examples/shared_counter examples/shared_counter_host; do
  moon test "$YAMI_NATIVE_MODULE_ROOT/$package" --target native --deny-warn --no-parallelize
done

if [ -n "${YAMI_SHARED_UI_CANDIDATE_SHA:-}" ]; then
  "$python_bin" "$YAMI_NATIVE_YAMI_ROOT/scripts/shared_native_ui_provenance.py"
fi
