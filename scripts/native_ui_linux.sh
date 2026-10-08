#!/bin/sh
set -eu

yami_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
gpui_root=${GPUI_SOURCE:-"$yami_root/../gpui.mbt"}
if [ ! -f "$gpui_root/moon.mod" ]; then
  echo "GPUI source module not found: $gpui_root (set GPUI_SOURCE)" >&2
  exit 2
fi
for command in xvfb-run weston xdotool wayland-info; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Linux native UI E2E requires '$command'" >&2
    exit 2
  fi
done

evidence_dir=${YAMI_NATIVE_UI_EVIDENCE_DIR:-"$yami_root/_build/native-ui/linux"}
mkdir -p "$evidence_dir"
evidence_dir=$(CDPATH='' cd -- "$evidence_dir" && pwd -P)

# GPUI's Wayland backend includes generated xdg-shell and text-input bindings.
# Generate them only when none exist; never overwrite a partial or existing set.
generated_count=0
for generated in \
  "$gpui_root/ubuntu/xdg-shell-client-protocol.h" \
  "$gpui_root/ubuntu/xdg-shell-protocol.c" \
  "$gpui_root/ubuntu/text-input-v1-client-protocol.h" \
  "$gpui_root/ubuntu/text-input-v1-protocol.c"; do
  if [ -e "$generated" ]; then
    generated_count=$((generated_count + 1))
  fi
done
if [ "$generated_count" -eq 0 ]; then
  sh "$gpui_root/scripts/prepare_ubuntu.sh"
elif [ "$generated_count" -ne 4 ]; then
  echo "GPUI contains a partial generated Wayland protocol set; refusing to overwrite it." >&2
  exit 2
fi

xvfb-run --auto-servernum \
  --server-args="-screen 0 800x600x24 -nolisten tcp -ac +extension GLX +render" \
  sh "$yami_root/scripts/native_ui_linux_session.sh" \
    "$yami_root" "$gpui_root" "$evidence_dir"
