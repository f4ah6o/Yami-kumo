#!/bin/bash
# Parent must explicitly confirm BOTH exact #160/#162 reviews and CI 7/7.
set -eu
test "${YAMI_160_162_REVIEW_CI_CONFIRMED:-}" = bc5ea9398abbdcc11147aac0a1b7cf92c90d6e92 || {
  echo 'Live launch is gated on parent confirmation of exact #160 and #162 reviews and both CI 7/7.' >&2
  exit 2
}
source /workspace/review162-live-prep-agent/env.sh
python3 /workspace/review162-live-prep-agent/verify-preparation.py
for pair in \
  '/workspace/review162-live-prep-agent/app cfa87adb6214f7ba50fa3a91075ca6e4eafddb9d' \
  '/workspace/review162-live-prep-agent/framework 35b9041dfb3642b43ca37c604834942614eb50fb' \
  '/workspace/review162-live-prep-agent/harness bc5ea9398abbdcc11147aac0a1b7cf92c90d6e92'; do
  read -r source_tree source_revision <<< "$pair"
  test "$(git -C "$source_tree" rev-parse HEAD)" = "$source_revision"
  test -z "$(git -C "$source_tree" status --porcelain)"
done
export YAMI_RELEASE_OUT=/workspace/review162-live-prep-agent/live
mkdir "$YAMI_RELEASE_OUT"
# Diagnostic only: #160 diagnostic app does not include the #154 P1 fix.
# Exact session creates a fresh build before it starts live services or app.
# No pre-existing binary is accepted by this launch path.
exec dbus-run-session -- xvfb-run --auto-servernum --server-args='-screen 0 960x640x24 -nolisten tcp -ac +extension GLX +render' \
  /workspace/review162-live-prep-agent/harness/tests/native-ui/ime-harness/retained-release/session.sh
