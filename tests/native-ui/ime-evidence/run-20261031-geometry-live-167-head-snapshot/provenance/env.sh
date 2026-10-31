#!/bin/bash
# Source this file for preparation or the gated #153 live launch.
export PATH="/workspace/gpui-locked-profile/prefix/usr/bin:/workspace/linux-user-apt/root/usr/bin:/workspace/yami-tools/bin:$PATH"
export MOON_HOME=/workspace/yami-tools
export PKG_CONFIG_SYSROOT_DIR=/workspace/linux-user-apt/root
export PKG_CONFIG_LIBDIR=/workspace/linux-user-apt/root/usr/lib/x86_64-linux-gnu/pkgconfig:/workspace/linux-user-apt/root/usr/share/pkgconfig
export WAYLAND_PROTOCOLS_DIR=/workspace/linux-user-apt/root/usr/share/wayland-protocols
export LD_LIBRARY_PATH="/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu/weston:/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu:/workspace/linux-user-apt/root/usr/lib/x86_64-linux-gnu"
export XKB_CONFIG_ROOT=/workspace/gpui-locked-profile/prefix/usr/share/X11/xkb
export LIBGL_DRIVERS_PATH=/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu/dri
export WESTON_MODULE_MAP='x11-backend.so=/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu/libweston-14/x11-backend.so;gl-renderer.so=/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu/libweston-14/gl-renderer.so'
export TMPDIR=/workspace/review167-live-prep-agent/tmp
export YAMI_RELEASE_APP_TREE=/workspace/review167-live-prep-agent/app
export YAMI_RELEASE_FRAMEWORK_TREE=/workspace/review167-live-prep-agent/framework
