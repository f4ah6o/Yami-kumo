#!/bin/bash
# Execute only after #142, #211 and #148 exact reviews and required CI succeed.
set -eu
test "$(git -C /workspace/yami-app-live-harness-union rev-parse HEAD)" = f8022d251a52a198a5af01cc2ec9f7b757e277c1
test -z "$(git -C /workspace/yami-app-live-harness-union status --porcelain)"
source /workspace/evidence/review196-direct-ea94a3f/env.sh
export YAMI_RELEASE_OUT=/workspace/evidence/yami-148-intent-live-1
export YAMI_RELEASE_APP_TREE=/workspace/yami-intent-control-retry-union
export YAMI_RELEASE_FRAMEWORK_TREE=/workspace/gpui-geometry-intent-reserve-contract
mkdir "$YAMI_RELEASE_OUT"
export PATH="/workspace/gpui-locked-profile/prefix/usr/bin:/workspace/linux-user-apt/root/usr/bin:/workspace/yami-tools/bin:$PATH"
export LD_LIBRARY_PATH="/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu/weston:/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu:/workspace/linux-user-apt/root/usr/lib/x86_64-linux-gnu"
export XKB_CONFIG_ROOT=/workspace/gpui-locked-profile/prefix/usr/share/X11/xkb
export LIBGL_DRIVERS_PATH=/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu/dri
export WESTON_MODULE_MAP='x11-backend.so=/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu/libweston-14/x11-backend.so;gl-renderer.so=/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu/libweston-14/gl-renderer.so'
exec dbus-run-session -- xvfb-run --auto-servernum --server-args='-screen 0 960x640x24 -nolisten tcp -ac +extension GLX +render' /workspace/yami-app-live-harness-union/tests/native-ui/ime-harness/retained-release/session.sh
